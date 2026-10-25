local addonName, addon = ...
addon.Planner = {}

-- ----------------------------------------------------------------------------
-- CONSTANTS & VARIABLES
-- ----------------------------------------------------------------------------
local PANEL_WIDTH = 220
local PANEL_HEIGHT = 685

local PALETTE = addon.Routes and addon.Routes.Palette or {}

local currentDraft = {
    points = {},
    color = {1, 1, 1, 1},
    thickness = 2
}

-- State History
local undoStack = {}
local redoStack = {}
local routeHistory = {} 

local currentTool = "PENCIL" 
local currentAvoidDraft = {}
local currentTimerDuration = 1 
local eraserRadius = 14
local isDrawing = false
local isEditMode = false
local ghostMode = false 
local lastAction = nil 

-- Object Pools
local linePool = {}
local activeLines = {}
local dotPool = {}   
local activeDots = {}

-- Dropdown Tracking for exclusivity
local activeDropdowns = {}

-- Map State
addon.Planner.currentMapID = nil 
local currentMapID = nil

-- CONTINENT IDS (Compatible with Interface 20505 TBC & 11505 Classic Era)
local CONTINENT_EK = addon.Compat and addon.Compat.isRetail and 13 or 1415
local CONTINENT_KALIMDOR = addon.Compat and addon.Compat.isRetail and 12 or 1414
local CONTINENT_OUTLAND = addon.Compat and addon.Compat.isTBC and C_Map.GetMapInfo(1945) and 1945 or nil
local CONTINENT_AZEROTH = 947 -- World Map
local selectedContinent = CONTINENT_EK 

-- ----------------------------------------------------------------------------
-- [[ IMPORT DATA HERE ]] --
-- Strictly TBC/Classic Era UiMapIDs to prevent collisions (Retail/Legacy IDs stripped)
-- ----------------------------------------------------------------------------
local ZONE_DATA = {
    [CONTINENT_AZEROTH] = {
         -- World Map placeholder
    },
    [CONTINENT_EK] = {
        -- TBC Cities/Zones
        {name="Silvermoon City", id=1954},
        {name="Eversong Woods", id=1941},
        {name="Ghostlands", id=1942},
        {name="Isle of Quel'Danas", id=1957},

        -- Classic Cities
        {name="Stormwind City", id=1453}, {name="Ironforge", id=1455}, {name="Undercity", id=1458},
        
        -- Classic Zones
        {name="Elwynn Forest", id=1429}, {name="Westfall", id=1436}, {name="Redridge Mountains", id=1433},
        {name="Duskwood", id=1431}, {name="Loch Modan", id=1432}, {name="Wetlands", id=1437},
        {name="Dun Morogh", id=1426}, {name="Tirisfal Glades", id=1420}, {name="Silverpine Forest", id=1421},
        {name="Hillsbrad Foothills", id=1424}, {name="Arathi Highlands", id=1417}, {name="Alterac Mountains", id=1416},
        {name="The Hinterlands", id=1425}, {name="Stranglethorn Vale", id=1434}, {name="Badlands", id=1418},
        {name="Searing Gorge", id=1427}, {name="Burning Steppes", id=1428}, {name="Swamp of Sorrows", id=1435},
        {name="Blasted Lands", id=1419}, {name="Western Plaguelands", id=1422}, {name="Eastern Plaguelands", id=1423},
        {name="Deadwind Pass", id=1430}
    },
    [CONTINENT_KALIMDOR] = {
        -- TBC Cities/Zones
        {name="The Exodar", id=1947},
        {name="Azuremyst Isle", id=1943},
        {name="Bloodmyst Isle", id=1950},

        -- Classic Cities
        {name="Orgrimmar", id=1454}, {name="Thunder Bluff", id=1456}, {name="Darnassus", id=1457},
        
        -- Classic Zones
        {name="Durotar", id=1411}, {name="Mulgore", id=1412}, {name="The Barrens", id=1413},
        {name="Darkshore", id=1439}, {name="Teldrassil", id=1438}, {name="Ashenvale", id=1440},
        {name="Stonetalon Mountains", id=1442}, {name="Desolace", id=1443}, {name="Feralas", id=1444},
        {name="Thousand Needles", id=1441}, {name="Dustwallow Marsh", id=1445}, {name="Tanaris", id=1446},
        {name="Un'Goro Crater", id=1449}, {name="Silithus", id=1451}, {name="Felwood", id=1448},
        {name="Winterspring", id=1452}, {name="Moonglade", id=1450}, {name="Azshara", id=1447}
    }
}

if addon.Compat and addon.Compat.isRetail then
    ZONE_DATA[CONTINENT_EK] = {}
    ZONE_DATA[CONTINENT_KALIMDOR] = {}
end

if CONTINENT_OUTLAND then
    ZONE_DATA[CONTINENT_OUTLAND] = {
        {name="Shattrath City", id=1955},
        {name="Hellfire Peninsula", id=1944},
        {name="Zangarmarsh", id=1946},
        {name="Terokkar Forest", id=1952},
        {name="Nagrand", id=1951},
        {name="Blade's Edge Mountains", id=1949},
        {name="Netherstorm", id=1953},
        {name="Shadowmoon Valley", id=1948},
    }
end
-- [[ END IMPORT DATA ]] --

local CONTINENT_LABELS = {
    [CONTINENT_AZEROTH] = "Azeroth",
    [CONTINENT_EK] = "Eastern Kingdoms",
    [CONTINENT_KALIMDOR] = "Kalimdor",
}
if CONTINENT_OUTLAND then CONTINENT_LABELS[CONTINENT_OUTLAND] = "Outland" end

local CONTINENT_ORDER = {CONTINENT_AZEROTH, CONTINENT_EK, CONTINENT_KALIMDOR}
if CONTINENT_OUTLAND then CONTINENT_ORDER[#CONTINENT_ORDER + 1] = CONTINENT_OUTLAND end

-- Retail has many more continents and zones. Merge both the live map tree and
-- maps carrying PathMaker node data into the curated Classic list.
local function MergeMapCatalog()
    if not addon.Compat then return end
    local catalog = addon.Compat:GetMapCatalog()
    local knownContinents = {}
    for _, continentID in ipairs(CONTINENT_ORDER) do knownContinents[continentID] = true end
    for _, continentID in ipairs(catalog.order) do
        CONTINENT_LABELS[continentID] = catalog.labels[continentID]
        ZONE_DATA[continentID] = ZONE_DATA[continentID] or {}
        local seenZones = {}
        for _, zone in ipairs(ZONE_DATA[continentID]) do seenZones[zone.id] = true end
        for _, zone in ipairs(catalog.zones[continentID] or {}) do
            if not seenZones[zone.id] then
                ZONE_DATA[continentID][#ZONE_DATA[continentID] + 1] = {name = zone.name, id = zone.id}
                seenZones[zone.id] = true
            end
        end
        if not knownContinents[continentID] then
            CONTINENT_ORDER[#CONTINENT_ORDER + 1] = continentID
            knownContinents[continentID] = true
        end
    end
end

MergeMapCatalog()

local function IsMapVisibleForExpansion(mapID)
    return not addon.Compat or addon.Compat:IsMapExpansionVisible(mapID)
end

local function GetVisibleContinentOrder()
    local result, seenLabels = {}, {}
    for _, continentID in ipairs(CONTINENT_ORDER) do
        local hasVisibleZone = false
        for _, zone in ipairs(ZONE_DATA[continentID] or {}) do
            if IsMapVisibleForExpansion(zone.id) then hasVisibleZone = true break end
        end
        local normalizedLabel = string.lower(CONTINENT_LABELS[continentID] or tostring(continentID))
        if hasVisibleZone and not seenLabels[normalizedLabel] then
            seenLabels[normalizedLabel] = true
            result[#result + 1] = continentID
        end
    end
    return result
end

function addon.Planner:RefreshMapCatalog()
    MergeMapCatalog()
    if self.dropCont and self.LoadContinentList then self:LoadContinentList(self.dropCont) end
    if self.dropZone and self.LoadZoneList then self:LoadZoneList(self.dropZone) end
end

-- ----------------------------------------------------------------------------
-- SAFE MAP SWITCHING (CRASH PREVENTION)
-- ----------------------------------------------------------------------------
local function SafeSetMapID(mapID)
    if not mapID then return end
    
    local info = C_Map.GetMapInfo(mapID)
    if not info then
        -- Silent fail or print error if client doesn't support the map
        addon:PrintMessage("disableMsgError", "|cffff0000Pathmaker:|r Cannot switch map. Game client returned no info for MapID: " .. mapID)
        return
    end
    
    local success, err = pcall(function()
        WorldMapFrame:SetMapID(mapID)
    end)

    if not success then
         -- Fallback to the parent map if the current map doesn't have a valid World Map canvas
         local parentID = info.parentMapID
         if parentID and parentID > 0 then
             local pSuccess = pcall(function() WorldMapFrame:SetMapID(parentID) end)
             if not pSuccess then
                 addon:PrintMessage("disableMsgError", "|cffff0000Pathmaker:|r Failed to set Map ID " .. mapID .. " and its parent.")
             end
         else
             addon:PrintMessage("disableMsgError", "|cffff0000Pathmaker:|r Failed to set Map ID " .. mapID)
         end
    end
end

-- ----------------------------------------------------------------------------
-- HELPER: AUTO-DETECT LOCATION & SYNC
-- ----------------------------------------------------------------------------
local function UpdateDropdownsToMatchMap(mapID)
    if not mapID then return end
    if not addon.Planner.panel then return end
    if not IsMapVisibleForExpansion(mapID) then return end
    
    currentMapID = mapID
    addon.Planner.currentMapID = mapID
    
    local foundContinent = nil

    -- 1. Try Reverse Lookup in ZONE_DATA (Prioritize explicit data)
    for contID, zones in pairs(ZONE_DATA) do
        for _, z in ipairs(zones) do
            if z.id == mapID then
                foundContinent = contID
                break
            end
        end
        if foundContinent then break end
    end
    
    -- 2. If not found, try traversing API Parent Hierarchy
    if not foundContinent then
        local info = C_Map.GetMapInfo(mapID)
        local safety = 0
        while info and info.parentMapID and safety < 10 do
            if CONTINENT_LABELS[info.parentMapID] then foundContinent = info.parentMapID; break end
            
            if info.parentMapID == 0 then break end -- Root
            info = C_Map.GetMapInfo(info.parentMapID)
            safety = safety + 1
        end
    end
    
    -- 3. Check if the map itself is a continent
    if not foundContinent then
         if CONTINENT_LABELS[mapID] then foundContinent = mapID end
    end

    if foundContinent then
        selectedContinent = foundContinent
    end

    -- Update Continent Dropdown Text
    if addon.Planner.dropCont then
        if CONTINENT_LABELS[selectedContinent] then
             addon.Planner.dropCont.text:SetText(CONTINENT_LABELS[selectedContinent])
             addon.Planner.dropCont.text:SetTextColor(1, 1, 1)
        end
    end
    
    -- Update Zone Dropdown List & Text
    if addon.Planner.dropZone then
        -- RELOAD LIST based on new continent
        if addon.Planner.LoadZoneList then
            addon.Planner:LoadZoneList(addon.Planner.dropZone)
        end
        
        -- Set Zone Text
        local zoneName = nil
        if ZONE_DATA[selectedContinent] then
             for _, z in ipairs(ZONE_DATA[selectedContinent]) do
                  if z.id == mapID then zoneName = z.name; break end
             end
        end
        
        if not zoneName then
             local info = C_Map.GetMapInfo(mapID)
             if info then zoneName = info.name end
        end
        
        if zoneName then
            addon.Planner.dropZone.text:SetText(zoneName)
            addon.Planner.dropZone.text:SetTextColor(1, 1, 1)
        end
    end
end

local function DetectPlayerLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        UpdateDropdownsToMatchMap(mapID)
    end
end

local plannerEvent = CreateFrame("Frame")
plannerEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
plannerEvent:RegisterEvent("ZONE_CHANGED")
plannerEvent:RegisterEvent("ZONE_CHANGED_NEW_AREA")
plannerEvent:RegisterEvent("ZONE_CHANGED_INDOORS")
plannerEvent:SetScript("OnEvent", function()
    if not isEditMode then 
        DetectPlayerLocation()
    end
end)

-- ----------------------------------------------------------------------------
-- HELPER: UTILS
-- ----------------------------------------------------------------------------
local function DeepCopyPoints(points)
    local copy = {}
    if not points then return copy end
    for _, p in ipairs(points) do
        table.insert(copy, {
            x = p.x, 
            y = p.y, 
            isGap = p.isGap,
            isMarker = p.isMarker,   
            duration = p.duration,   
            name = p.name,           
            countdownStart = p.countdownStart, 
            isStanding = p.isStanding 
        })
    end
    return copy
end

local function PushUndoState()
    if #undoStack > 50 then table.remove(undoStack, 1) end
    table.insert(undoStack, DeepCopyPoints(currentDraft.points))
    wipe(redoStack)
end

local function ReverseDraft()
    local pts = currentDraft.points
    local n = #pts
    if n < 2 then return end
    
    local oldMeta = {}
    for i=1, n do 
        oldMeta[i] = {
            isGap = pts[i].isGap,
            isMarker = pts[i].isMarker,
            duration = pts[i].duration,
            name = pts[i].name
        } 
    end
    
    for i = 1, math.floor(n / 2) do
        local temp = pts[i]
        pts[i] = pts[n - i + 1]
        pts[n - i + 1] = temp
    end
    
    for i=1, n-1 do
        pts[i].isGap = oldMeta[n-i].isGap
        pts[i].isMarker = oldMeta[n-i].isMarker
        pts[i].duration = oldMeta[n-i].duration
        pts[i].name = oldMeta[n-i].name
    end
    pts[n].isGap = true 
end

function addon:GetMapIDForRoute(guid)
    if not PathmakerDB or not PathmakerDB.routes then return nil end
    for mapID, routes in pairs(PathmakerDB.routes) do
        if type(routes) == "table" and routes[guid] then 
            return mapID 
        end
    end
    return nil
end
local GetMapIDForRoute = addon.GetMapIDForRoute

-- ----------------------------------------------------------------------------
-- HELPER: UI COMPONENTS
-- ----------------------------------------------------------------------------
local function CreateMinimalButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    btn.text = fs
    
    btn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropColor(0.3, 0.3, 0.3, 1)
        if self.pmActive then
            self:SetBackdropBorderColor(0, 1, 0, 1)
        else
            self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        if self.pmActive then
            self:SetBackdropBorderColor(0, 1, 0, 1)
            self.text:SetTextColor(0, 1, 0)
        else
            self:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end)
    return btn
end

local function StyleCloseButton(btn)
    if not btn or not btn.text then return btn end
    btn.text:SetText("X")
    btn.text:SetTextColor(1, 1, 1)
    btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    btn:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.32, 0.05, 0.05, 1)
        self:SetBackdropBorderColor(1, 0.22, 0.22, 1)
        if self.text then self.text:SetTextColor(1, 1, 1) end
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        self:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
        if self.text then self.text:SetTextColor(1, 1, 1) end
    end)
    return btn
end

local function SetTooltip(frame, title, body)
    if not frame or not title then return end
    frame:HookScript("OnEnter", function(self)
        if self.IsEnabled and not self:IsEnabled() then return end
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetFrameStrata("TOOLTIP")
        GameTooltip:SetFrameLevel(10000)
        GameTooltip:SetText(title, 1, 0.82, 0)
        if body and body ~= "" then
            GameTooltip:AddLine(body, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function(self)
        if GameTooltip and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == self) then
            GameTooltip:Hide()
        end
    end)
end

local function CreateDarkScrollArea(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:EnableMouse(true)
    sf:EnableMouseWheel(true)
    sf:SetSize(width, height)
    
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width, height) 
    sf:SetScrollChild(content)
    
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("VERTICAL")
    slider:SetSize(6, height)
    slider:SetPoint("TOPLEFT", sf, "TOPRIGHT", 2, 0)
    slider:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    slider:SetBackdropColor(0.1, 0.1, 0.1, 1) 
    
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.4, 0.4, 0.4, 1) 
    thumb:SetSize(6, 20)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetScript("OnValueChanged", function(self, value) sf:SetVerticalScroll(value) end)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = slider:GetValue()
        local min, max = slider:GetMinMaxValues()
        local step = 20
        local new = cur - (delta * step)
        if new < min then new = min elseif new > max then new = max end
        slider:SetValue(new)
    end)
    return sf, content, slider 
end

local function CreateCustomDropdown(parent, width, defaultText)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate") 
    f:SetSize(width, 20)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 1)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 5, 0)
    text:SetPoint("RIGHT", -20, 0)
    text:SetText(defaultText or "")
    text:SetJustifyH("LEFT")
    f.text = text
    
    local arrow = f:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -2, 0)
    
    local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    list:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
    list:SetWidth(width)
    list:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    list:SetBackdropColor(0, 0, 0, 1) 
    list:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    list:SetFrameStrata("TOOLTIP") -- Keep dropdowns highly visible
    list:SetFrameLevel(math.max(f:GetFrameLevel() + 100, 9600))
    if list.SetToplevel then list:SetToplevel(true) end
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:Hide()
    f.list = list
    
    local scroll = CreateFrame("ScrollFrame", nil, list)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 10)
    scroll:SetScrollChild(content)
    f.content = content
    f.scroll = scroll
    
    table.insert(activeDropdowns, f)
    
    f:SetScript("OnClick", function()
        local wasShown = list:IsShown()
        -- Close all other registered dropdowns
        for _, dd in ipairs(activeDropdowns) do
            if dd.list then dd.list:Hide() end
        end
        -- Toggle this one
        if not wasShown then 
            list:Show()
            list:Raise()
        end
    end)
    
    f.items = {}
    f.AddItem = function(self, label, func)
        local idx = #self.items + 1
        local b = CreateFrame("Button", nil, self.content)
        b:SetSize(width, 18)
        b:SetPoint("TOPLEFT", 0, -((idx-1)*18))
        local bt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bt:SetPoint("LEFT", 5, 0)
        bt:SetText(label)
        b:SetScript("OnEnter", function() b.bg:Show() end)
        b:SetScript("OnLeave", function() b.bg:Hide() end)
        b:SetScript("OnClick", function()
            func()
            self.text:SetText(label)
            self.text:SetTextColor(1, 1, 1) 
            self.list:Hide()
        end)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        b.bg:Hide()
        
        table.insert(self.items, b)
        self.content:SetHeight(idx * 18)
        
        local maxH = math.min(600, idx * 18)
        self.list:SetHeight(maxH)
        self.scroll:SetHeight(maxH)
    end
    
    f.ClearItems = function(self)
        for _, b in ipairs(self.items) do b:Hide(); b:SetParent(nil) end
        self.items = {}
        self.content:SetHeight(1)
        self.list:SetHeight(1)
    end
    
    return f
end

-- ----------------------------------------------------------------------------
-- HELPER: DRAWING (Improved for Realism)
-- ----------------------------------------------------------------------------
local function AcquireLine(canvas)
    local line = table.remove(linePool)
    if not line then
        line = canvas:CreateTexture(nil, "OVERLAY")
        line:SetTexture("Interface\\Buttons\\WHITE8x8")
    end
    line:Show()
    table.insert(activeLines, line)
    return line
end

local function AcquireDot(canvas)
    local dot = table.remove(dotPool)
    if not dot then
        dot = canvas:CreateTexture(nil, "OVERLAY")
        dot:SetTexture("Interface\\Buttons\\WHITE8x8") 
    end
    dot:Show()
    table.insert(activeDots, dot)
    return dot
end

local function DrawLine(canvas, startX, startY, endX, endY, width, color)
    local w, h = canvas:GetSize()
    
    local sx1, sy1 = startX * w, -startY * h
    local sx2, sy2 = endX * w, -endY * h
    
    local line = AcquireLine(canvas)
    line:SetColorTexture(unpack(color))
    
    local dx = sx2 - sx1
    local dy = sy2 - sy1
    local length = math.sqrt(dx*dx + dy*dy)
    local angle = math.atan2(dy, dx)
    
    line:SetSize(length, width) 
    line:ClearAllPoints()
    line:SetPoint("CENTER", canvas, "TOPLEFT", (sx1 + sx2) / 2, (sy1 + sy2) / 2)
    line:SetRotation(angle)

    local dot = AcquireDot(canvas)
    dot:SetColorTexture(unpack(color))
    dot:SetSize(width, width)
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", canvas, "TOPLEFT", sx2, sy2)
end

-- ----------------------------------------------------------------------------
-- PLANNER CONTROL PANEL (The "Box")
-- ----------------------------------------------------------------------------
function addon.Planner:CreateControlPanel()
    if self.panel then return end

    -- Parented to UIParent instead of WorldMapFrame so it isn't affected by map scaling/stratifying
    local f = CreateFrame("Frame", "PathmakerControlPanel", UIParent, "BackdropTemplate")
    f:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    f:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 10, -30)
    f:SetFrameStrata("TOOLTIP") -- Force to stay on top
    f:SetFrameLevel(9500)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Make entire panel background draggable
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
    end)
    
    -- DRAG HEADER
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(PANEL_WIDTH, 24)
    header:SetPoint("TOP", 0, 0)
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then f:StartMoving() end end)
    header:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    
    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", 0, 0)
    title:SetText("PathMaker - Draw Mode")
    title:SetTextColor(1, 0.82, 0)
    
    local coords = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.coordDisplay = coords
    
    local btnClose = StyleCloseButton(CreateMinimalButton(header, "X", 20, 20))
    btnClose:SetPoint("RIGHT", -2, 0)
    btnClose:SetScript("OnClick", function() self:Toggle() end)
    SetTooltip(btnClose, "Close", "Close draw mode and return to the normal map.")
    
    self.LoadZoneList = function(self, dropdown)
        dropdown:ClearItems()
        dropdown.text:SetText("Select Zone")
        dropdown.text:SetTextColor(1, 1, 1) 
        
        local zones = {}
        local seenIDs = {} 
        
        local apiZones = C_Map.GetMapChildren and C_Map.GetMapChildren(selectedContinent) or {}
        for _, z in ipairs(apiZones) do
            if z.mapID and z.name and IsMapVisibleForExpansion(z.mapID) then
                if not seenIDs[z.mapID] then
                    table.insert(zones, {name=z.name, mapID=z.mapID})
                    seenIDs[z.mapID] = true
                end
            end
        end
        
        if ZONE_DATA[selectedContinent] then
            for _, zData in ipairs(ZONE_DATA[selectedContinent]) do
                -- Check if map exists in the client before adding (CRASH FIX)
                if not seenIDs[zData.id] and C_Map.GetMapInfo(zData.id) and IsMapVisibleForExpansion(zData.id) then
                    table.insert(zones, {name=zData.name, mapID=zData.id})
                    seenIDs[zData.id] = true
                end
            end
        end
        
        table.sort(zones, function(a,b) return a.name < b.name end)
        
        for _, zone in ipairs(zones) do
            dropdown:AddItem(zone.name, function()
                currentMapID = zone.mapID
                addon.Planner.currentMapID = zone.mapID
                SafeSetMapID(zone.mapID) 
                self:LoadZone()
            end)
        end
    end

    local yOffset = -30
    
    local defaultContText = CONTINENT_LABELS[selectedContinent] or "Select Continent"
    
    local dropCont = CreateCustomDropdown(f, PANEL_WIDTH - 20, defaultContText)
    if CONTINENT_LABELS[selectedContinent] then
        dropCont.text:SetTextColor(1, 1, 1) 
    end
    dropCont:SetPoint("TOP", 0, yOffset)
    self.dropCont = dropCont
    yOffset = yOffset - 25
    
    local dropZone = CreateCustomDropdown(f, PANEL_WIDTH - 20, "Select Zone")
    dropZone:SetPoint("TOP", 0, yOffset - 10) 
    self.dropZone = dropZone
    yOffset = yOffset - 40 

    self.LoadContinentList = function(self, dropdown)
        dropdown:ClearItems()
        local visibleContinents = GetVisibleContinentOrder()
        local selectedStillVisible = false
        for _, continentID in ipairs(visibleContinents) do
            if continentID == selectedContinent then selectedStillVisible = true end
        end
        if not selectedStillVisible and visibleContinents[1] then selectedContinent = visibleContinents[1] end
        dropdown.text:SetText(CONTINENT_LABELS[selectedContinent] or "Select Continent")

        for _, continentID in ipairs(visibleContinents) do
            local selectedID = continentID
            local label = CONTINENT_LABELS[selectedID] or tostring(selectedID)
            dropdown:AddItem(label, function()
                selectedContinent = selectedID
                dropdown.text:SetText(label)
                dropdown.text:SetTextColor(1, 1, 1)
                SafeSetMapID(selectedContinent)
                self:LoadZoneList(dropZone)
                if dropZone.list:IsShown() then dropZone.list:Hide() end
            end)
        end
    end
    self:LoadContinentList(dropCont)
    
    local tTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tTitle:SetPoint("TOP", 0, yOffset)
    tTitle:SetText("Tools")
    tTitle:SetTextColor(1, 0.82, 0)
    self.drawStatus = tTitle
    yOffset = yOffset - 15
    
    local btnW = (PANEL_WIDTH - 30) / 3
    
    local function SetTool(mode, btnObj)
        currentTool = mode
        self.btnPencil.pmActive = false; self.btnPencil:SetBackdropBorderColor(0,0,0,1); self.btnPencil.text:SetTextColor(1,1,1)
        self.btnEraser.pmActive = false; self.btnEraser:SetBackdropBorderColor(0,0,0,1); self.btnEraser.text:SetTextColor(1,1,1)
        self.btnDrag.pmActive = false; self.btnDrag:SetBackdropBorderColor(0,0,0,1); self.btnDrag.text:SetTextColor(1,1,1)
        self.btnMarker.pmActive = false; self.btnMarker:SetBackdropBorderColor(0,0,0,1); self.btnMarker.text:SetTextColor(1,1,1)
        if self.btnAvoidMode then self.btnAvoidMode.pmActive = false; self.btnAvoidMode:SetBackdropBorderColor(0,0,0,1); self.btnAvoidMode.text:SetTextColor(1,1,1) end
        
        btnObj.pmActive = true
        btnObj:SetBackdropBorderColor(0,1,0,1)
        btnObj.text:SetTextColor(0,1,0)
        
        if self.overlay then
            if mode == "DRAG" then
                self.overlay:EnableMouse(false) 
            else
                self.overlay:EnableMouse(true)  
            end
        end

        if mode == "MARKER" or mode == "AVOID" then
            self.btnFill:Disable()
            self.btnFill.text:SetTextColor(0.3, 0.3, 0.3)
            self.btnConnect:Disable()
            self.btnConnect.text:SetTextColor(0.3, 0.3, 0.3)
        else
            self.btnFill:Enable()
            self.btnFill.text:SetTextColor(1, 1, 1)
            self.btnConnect:Enable()
            self.btnConnect.text:SetTextColor(1, 1, 1)
        end
        if self.drawStatus then
            local labels = {PENCIL="Drawing Route", ERASER="Erasing", DRAG="Moving", MARKER="Marking", AVOID="Drawing Avoid Area"}
            local pointCount = mode == "AVOID" and #currentAvoidDraft or #currentDraft.points
            self.drawStatus:SetText(string.format("%s - %d points", labels[mode] or "Draw Mode", pointCount))
        end
    end

    self.btnAvoidMode = CreateMinimalButton(f, "Draw Avoid Area", PANEL_WIDTH - 20, 20)
    self.btnAvoidMode:SetPoint("TOP", 0, yOffset)
    self.btnAvoidMode:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self.btnAvoidMode:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local areas = currentMapID and PathmakerDB and PathmakerDB.avoidAreas and PathmakerDB.avoidAreas[currentMapID]
            if areas and #areas > 0 then
                table.remove(areas)
                local remaining = #areas
                if remaining == 0 then PathmakerDB.avoidAreas[currentMapID] = nil end
                addon:PrintMessage("disableMsgRouteEditing", string.format("PathMaker: Removed the latest avoid area. %d remaining.", remaining))
            else
                addon:PrintMessage("disableMsgRouteEditing", "PathMaker: There are no avoid areas to remove on this map.")
            end
            currentAvoidDraft = {}
            self:RefreshCanvas()
        else
            currentAvoidDraft = {}
            SetTool("AVOID", self.btnAvoidMode)
            self:RefreshCanvas()
        end
    end)
    SetTooltip(self.btnAvoidMode, "Draw Avoid Area", "Left-click to draw and show avoid areas. Right-click removes only the most recently drawn area; repeat to remove more.")
    -- Keep the avoid-area action on its own row with a clear gap before the
    -- regular drawing tools so its hit box never crowds the Draw/Erase row.
    yOffset = yOffset - 26

    self.btnPencil = CreateMinimalButton(f, "Draw", btnW, 20)
    self.btnPencil:SetPoint("TOPLEFT", 10, yOffset)
    self.btnPencil:SetScript("OnClick", function() SetTool("PENCIL", self.btnPencil) end)
    SetTooltip(self.btnPencil, "Draw", "Click and drag on the map to draw a route. Start near an endpoint to continue an existing line.")
    
    self.btnEraser = CreateMinimalButton(f, "Erase", btnW, 20)
    self.btnEraser:SetPoint("LEFT", self.btnPencil, "RIGHT", 5, 0)
    self.btnEraser:SetScript("OnClick", function() SetTool("ERASER", self.btnEraser) end)
    SetTooltip(self.btnEraser, "Erase", "Click and drag over route points to remove them. The remaining route is split cleanly.")
    
    self.btnDrag = CreateMinimalButton(f, "Move", btnW, 20)
    self.btnDrag:SetPoint("LEFT", self.btnEraser, "RIGHT", 5, 0)
    self.btnDrag.text:SetScale(0.9) 
    self.btnDrag:SetScript("OnClick", function() SetTool("DRAG", self.btnDrag) end)
    SetTooltip(self.btnDrag, "Move", "Temporarily releases drawing input so you can pan and move the world map.")
    
    self.btnFill = CreateMinimalButton(f, "Stitch", btnW, 20)
    self.btnFill:SetPoint("TOP", self.btnPencil, "BOTTOM", 0, -2)
    SetTooltip(self.btnFill, "Stitch", "Join separated route segments in the closest order and leave one final break.")
    self.btnFill:SetScript("OnClick", function()
        local pts = currentDraft.points
        if #pts < 2 then return end
        PushUndoState()
        lastAction = "FILL_GAPS"
        local segments = {}
        local currentSeg = {}
        for i, p in ipairs(pts) do
            table.insert(currentSeg, p)
            if p.isGap or i == #pts then
                table.insert(segments, currentSeg)
                currentSeg = {}
            end
        end
        local stitched = segments[1]
        table.remove(segments, 1)
        while #segments > 0 do
            local tip = stitched[#stitched]
            local bestIdx = -1
            local bestDist = math.huge
            local shouldReverse = false
            for i, seg in ipairs(segments) do
                local startP = seg[1]
                local endP = seg[#seg]
                local dStart = (tip.x - startP.x)^2 + (tip.y - startP.y)^2
                if dStart < bestDist then bestDist = dStart; bestIdx = i; shouldReverse = false end
                local dEnd = (tip.x - endP.x)^2 + (tip.y - endP.y)^2
                if dEnd < bestDist then bestDist = dEnd; bestIdx = i; shouldReverse = true end
            end
            if bestIdx ~= -1 then
                local bestSeg = table.remove(segments, bestIdx)
                local connectingTo = shouldReverse and bestSeg[#bestSeg] or bestSeg[1]
                if stitched[#stitched].isMarker and connectingTo.isMarker then
                     table.insert(stitched, {x=stitched[#stitched].x, y=stitched[#stitched].y, isGap=false}) 
                end
                
                stitched[#stitched].isGap = false
                if shouldReverse then
                    local n = #bestSeg
                    for k = 1, math.floor(n/2) do bestSeg[k], bestSeg[n-k+1] = bestSeg[n-k+1], bestSeg[k] end
                end
                for _, p in ipairs(bestSeg) do table.insert(stitched, p) end
            else break end
        end
        local finalPts = stitched
        local maxDistSq = -1
        local splitIndex = -1 
        for i = 1, #finalPts do
            local p1 = finalPts[i]
            local p2 = finalPts[(i % #finalPts) + 1] 
            local d = (p1.x - p2.x)^2 + (p1.y - p2.y)^2
            if d > maxDistSq then maxDistSq = d; splitIndex = i end
        end
        if splitIndex ~= -1 then
            local rotated = {}
            for i = splitIndex + 1, #finalPts do table.insert(rotated, finalPts[i]) end
            for i = 1, splitIndex do table.insert(rotated, finalPts[i]) end
            finalPts = rotated
        end
        for i = 1, #finalPts - 1 do finalPts[i].isGap = false end
        finalPts[#finalPts].isGap = true
        currentDraft.points = finalPts
        addon:PrintMessage("disableMsgRouteEditing", "Pathmaker: Route stitched.")
        self:RefreshCanvas()
        self:Save(true) 
    end)
    
    self.btnMarker = CreateMinimalButton(f, "Mark", btnW, 20)
    self.btnMarker:SetPoint("TOP", self.btnFill, "BOTTOM", 0, -2)
    self.btnMarker:SetScript("OnClick", function() SetTool("MARKER", self.btnMarker) end)
    SetTooltip(self.btnMarker, "Mark", "Draw marker segments on the route. Marker names and timer values can be edited below.")

    self.btnConnect = CreateMinimalButton(f, "Close", btnW, 20)
    self.btnConnect:SetPoint("TOP", self.btnEraser, "BOTTOM", 0, -2)
    SetTooltip(self.btnConnect, "Close", "Connect the last route point back to the first point.")
    self.btnConnect:SetScript("OnClick", function()
        local pts = currentDraft.points
        if #pts < 2 then return end
        local first = pts[1]
        local last = pts[#pts]
        local d = (first.x - last.x)^2 + (first.y - last.y)^2
        if d < 0.00000001 then 
             if not last.isGap then 
                last.isGap = true; 
                self:RefreshCanvas(); 
                self:Save(true) 
             end
             return 
        end
        PushUndoState()
        if last.isGap then last.isGap = false end
        
        if last.isMarker and first.isMarker then
             table.insert(pts, {x=last.x, y=last.y, isGap=false})
        end
        
        table.insert(pts, {x=first.x, y=first.y, isGap=true})
        self:RefreshCanvas()
        self:Save(true) 
    end)
    
    self.btnTimer = CreateMinimalButton(f, "Timer", btnW, 20)
    self.btnTimer:SetPoint("TOP", self.btnConnect, "BOTTOM", 0, -2)
    self.btnTimer:SetScript("OnClick", function()
        if self.timerDisplay then self.timerDisplay:SetFocus() end
    end)
    SetTooltip(self.btnTimer, "Timer", "Set the timer duration used by new marker segments.")
    
    local timerBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    timerBox:SetSize(btnW, 20) 
    timerBox:SetPoint("LEFT", self.btnTimer, "RIGHT", 5, 0)
    timerBox:SetAutoFocus(false)
    timerBox:SetFontObject("GameFontHighlightSmall")
    timerBox:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    timerBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    timerBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    timerBox:SetTextInsets(4,4,0,0)
    timerBox:SetJustifyH("CENTER")
    timerBox:SetText(tostring(currentTimerDuration) .. "s")
    SetTooltip(timerBox, "Marker Timer", "Type a duration in seconds, then press Enter.")
    
    timerBox:SetScript("OnEnterPressed", function(self)
        local text = self:GetText():gsub("s", "") 
        local val = tonumber(text)
        if val and val > 0 then
            currentTimerDuration = val
            addon:PrintMessage("disableMsgRouteEditing", "Pathmaker: Marker timer set to " .. val .. "s")
        end
        self:SetText(tostring(currentTimerDuration) .. "s")
        self:ClearFocus()
        addon.Planner:Save(true) 
    end)
    timerBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(currentTimerDuration) .. "s")
        self:ClearFocus()
    end)
    timerBox:SetScript("OnEditFocusGained", function(self)
        self:SetText(tostring(currentTimerDuration))
        self:HighlightText()
    end)
    timerBox:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(currentTimerDuration) .. "s")
        self:HighlightText(0, 0)
    end)
    
    self.timerDisplay = timerBox

    local coordRow = CreateFrame("Frame", nil, f)
    coordRow:SetSize(PANEL_WIDTH - 20, 14)
    coordRow:SetPoint("TOPLEFT", self.btnTimer, "BOTTOMLEFT", -(btnW + 5), -7)

    local coordLabel = coordRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coordLabel:SetPoint("LEFT", coordRow, "LEFT", 0, 0)
    coordLabel:SetText("Coordinates")
    coordLabel:SetTextColor(0.72, 0.72, 0.72)
    self.coordDisplay:ClearAllPoints()
    self.coordDisplay:SetPoint("RIGHT", coordRow, "RIGHT", 0, 0)
    self.coordDisplay:SetWidth(90)
    self.coordDisplay:SetJustifyH("RIGHT")
    self.coordDisplay:SetText("--, --")

    yOffset = yOffset - 25 
    
    local btnGhost = CreateMinimalButton(f, "%", 20, 20)
    btnGhost:SetPoint("TOPRIGHT", self.btnDrag, "BOTTOMRIGHT", 0, -2)
    
    self.btnGhost = btnGhost
    SetTooltip(btnGhost, "Ghost Preview", "Toggle faint preview lines for the current route while drawing.")
    
    btnGhost:SetScript("OnClick", function()
        ghostMode = not ghostMode
        if ghostMode then
            btnGhost:SetBackdropBorderColor(0,0,0,1)
            btnGhost.text:SetTextColor(1,1,1) 
        else
            btnGhost:SetBackdropBorderColor(0,0,0,1)
            btnGhost.text:SetTextColor(0.5, 0.5, 1) 
        end
        self:RefreshCanvas()
    end)
    yOffset = yOffset - 50 
    
    local palFrame = CreateFrame("Frame", nil, f)
    palFrame:SetSize(PANEL_WIDTH - 20, 60)
    palFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, yOffset - 15)
    local swatchS, gap, cols = 15, 3, 11
    self.paletteButtons = {}

    local function SamePaletteColor(a, b)
        if not a or not b then return false end
        return math.abs((a[1] or 0) - (b[1] or 0)) < 0.001
            and math.abs((a[2] or 0) - (b[2] or 0)) < 0.001
            and math.abs((a[3] or 0) - (b[3] or 0)) < 0.001
    end

    local function PaintColorButton(btn, active)
        btn.pmColorActive = active == true
        if btn.pmColorActive then
            btn:SetBackdropBorderColor(0, 1, 0, 1)
        else
            btn:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
        end
    end

    self.UpdatePaletteSelection = function(planner)
        if not planner.paletteButtons then return end
        for _, btn in ipairs(planner.paletteButtons) do
            PaintColorButton(btn, SamePaletteColor(currentDraft.color, btn.pmColor))
        end
    end

    for i, color in ipairs(PALETTE) do
        if i > 22 then break end 
        local b = CreateFrame("Button", nil, palFrame, "BackdropTemplate")
        b:SetSize(swatchS, swatchS)
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        b:SetBackdropColor(0.03, 0.03, 0.03, 1)
        b:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
        b.pmColor = color
        local row = math.floor((i-1) / cols) 
        local col = (i-1) % cols 
        b:SetPoint("TOPLEFT", col * (swatchS+gap), -row * (swatchS+gap))
        local bg = b:CreateTexture(nil, "OVERLAY")
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
        bg:SetColorTexture(unpack(color))
        b:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0, 1, 0, 1)
        end)
        b:SetScript("OnLeave", function(self)
            PaintColorButton(self, self.pmColorActive)
        end)
        SetTooltip(b, "Route Color", "Set the color for the current route.")
        b:SetScript("OnClick", function() 
            currentDraft.color = color 
            self:UpdatePaletteSelection()
            self:RefreshCanvas()
            addon.Planner:Save(true) 
            if addon.Routes and addon.Routes.NotifyRouteColorChanged then
                addon.Routes:NotifyRouteColorChanged(addon.selectedRouteGUID, addon.selectedRouteMapID or currentMapID, color)
            end
        end)
        table.insert(self.paletteButtons, b)
    end
    self:UpdatePaletteSelection()
    yOffset = yOffset - 80 
    
    local actionW = (PANEL_WIDTH - 30) / 4
    local btnUndo = CreateMinimalButton(f, "Undo", actionW, 24)
    btnUndo:SetPoint("TOPLEFT", 10, yOffset)
    btnUndo:SetScript("OnClick", function() self:Undo() end)
    SetTooltip(btnUndo, "Undo", "Revert the last drawing edit.")
    
    local btnRedo = CreateMinimalButton(f, "Redo", actionW, 24)
    btnRedo:SetPoint("LEFT", btnUndo, "RIGHT", 3, 0)
    btnRedo:SetScript("OnClick", function() self:Redo() end)
    SetTooltip(btnRedo, "Redo", "Restore the last undone drawing edit.")
    
    local btnClear = CreateMinimalButton(f, "Clear", actionW, 24)
    btnClear:SetPoint("LEFT", btnRedo, "RIGHT", 3, 0)
    btnClear:SetScript("OnClick", function() self:Clear() end)
    SetTooltip(btnClear, "Clear", "Remove all points from the current draft route.")
    
    local btnSave = CreateMinimalButton(f, "Save", actionW, 24)
    btnSave:SetPoint("LEFT", btnClear, "RIGHT", 3, 0)
    btnSave.text:SetTextColor(0, 1, 0)
    SetTooltip(btnSave, "Save", "Save the current route and any route name changes.")
    
    yOffset = yOffset - 35

    local rmTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rmTitle:SetPoint("TOP", 0, yOffset)
    rmTitle:SetText("Route Manager")
    rmTitle:SetTextColor(1, 0.82, 0)
    yOffset = yOffset - 15
    
    local btnImport = CreateMinimalButton(f, "Import", (PANEL_WIDTH-30)/3, 20)
    btnImport:SetPoint("TOPLEFT", 10, yOffset)
    btnImport:SetScript("OnClick", function() if addon.ImportExport then addon.ImportExport:ShowImport() end end)
    SetTooltip(btnImport, "Import", "Open the route import window.")
    
    local btnExport = CreateMinimalButton(f, "Export", (PANEL_WIDTH-30)/3, 20)
    btnExport:SetPoint("LEFT", btnImport, "RIGHT", 5, 0)
    btnExport:SetScript("OnClick", function() 
        if addon.ImportExport and addon.selectedRouteGUID then
            local routeMapID = GetMapIDForRoute(addon.selectedRouteGUID)
            local savedMapID = addon.Planner.currentMapID
            if routeMapID then addon.Planner.currentMapID = routeMapID end
            addon.ImportExport:ShowExport(addon.selectedRouteGUID) 
            addon.Planner.currentMapID = savedMapID
        end 
    end)
    btnExport:Disable()
    f.btnExport = btnExport
    SetTooltip(btnExport, "Export", "Export the selected route.")
    
    local btnUndoDel = CreateMinimalButton(f, "Restore", (PANEL_WIDTH-30)/3, 20)
    btnUndoDel:SetPoint("LEFT", btnExport, "RIGHT", 5, 0)
    SetTooltip(btnUndoDel, "Restore", "Restore the most recently deleted route.")
    btnUndoDel:SetScript("OnClick", function()
        if #routeHistory > 0 then
            local restore = table.remove(routeHistory)
            if restore.mapID and restore.guid and restore.data then
                if not PathmakerDB.routes[restore.mapID] then PathmakerDB.routes[restore.mapID] = {} end
                PathmakerDB.routes[restore.mapID][restore.guid] = restore.data
                self.panel:UpdateList(nil)
                if addon.MapFrame then addon.MapFrame:UpdateRouteList() end
                if addon.UI then addon.UI:RefreshRendering() end
                addon:PrintMessage("disableMsgRouteEditing", "Pathmaker: Route restored.")
            end
        end
    end)
    yOffset = yOffset - 25

    local searchBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    searchBox:SetSize(PANEL_WIDTH - 20, 20)
    searchBox:SetPoint("TOP", 0, yOffset)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    searchBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    searchBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    searchBox:SetTextInsets(4,4,0,0)
    local ph = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 4, 0); ph:SetText("Search...")
    searchBox:SetScript("OnTextChanged", function(self) if self:GetText()=="" then ph:Show() else ph:Hide() end; f:UpdateList(self:GetText()) end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    SetTooltip(searchBox, "Search Routes", "Filter the route list across all saved maps.")
    yOffset = yOffset - 25
    f.searchBox = searchBox 
    
    local renameBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    renameBox:SetSize(PANEL_WIDTH - 20, 20)
    renameBox:SetPoint("TOP", 0, yOffset)
    renameBox:SetAutoFocus(false)
    renameBox:SetFontObject("GameFontHighlightSmall")
    renameBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    renameBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    renameBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    renameBox:SetTextInsets(4,4,0,0)
    renameBox:SetMaxLetters(12)
    local rph = renameBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    rph:SetPoint("LEFT", 4, 0); rph:SetText("Rename...")
    f.renameBox = renameBox
    SetTooltip(renameBox, "Rename Route", "Type a new name for the selected route and press Enter.")
    
    renameBox:SetScript("OnTextChanged", function(self) 
        if self:GetText()=="" then rph:Show() else rph:Hide() end 
    end)
    
    renameBox:SetScript("OnEscapePressed", function(self) 
        local rMapID = GetMapIDForRoute(addon.selectedRouteGUID)
        if rMapID and PathmakerDB.routes[rMapID] and PathmakerDB.routes[rMapID][addon.selectedRouteGUID] then
             self:SetText(PathmakerDB.routes[rMapID][addon.selectedRouteGUID].name)
        end
        self:ClearFocus()
    end)
    
    local function CommitRename()
        local guid = addon.selectedRouteGUID
        local newName = f.renameBox:GetText()
        
        if guid and newName and newName ~= "" then
            local mapID = GetMapIDForRoute(guid)
            if not mapID then mapID = addon.Planner.currentMapID end 
            
            if mapID and PathmakerDB.routes[mapID] and PathmakerDB.routes[mapID][guid] then
                local currentName = PathmakerDB.routes[mapID][guid].name
                if currentName ~= newName then
                    PathmakerDB.routes[mapID][guid].name = newName
                    addon.Planner:Save(true) 
                    f:UpdateList(f.searchBox:GetText()) 
                end
            end
        end
    end
    
    renameBox:SetScript("OnEnterPressed", function(self) 
        CommitRename()
        self:ClearFocus() 
    end)
    
    renameBox:SetScript("OnEditFocusLost", function(self)
        CommitRename()
    end)

    btnSave:SetScript("OnClick", function() 
        CommitRename()
        self:Save(false) 
    end)

    yOffset = yOffset - 25
    
    local listHeight = 140 
    local scrollFrame, scrollChild, slider = CreateDarkScrollArea(f, PANEL_WIDTH - 30, listHeight)
    scrollFrame:SetPoint("TOP", 0, yOffset)
    f.scrollFrame = scrollFrame; f.scrollChild = scrollChild; f.slider = slider; f.buttons = {} 
    
    f.UpdateList = function(self, filter)
        for _, btn in pairs(self.buttons) do btn:Hide() end
        
        if addon.selectedRouteGUID then 
            f.btnExport:Enable(); f.btnExport.text:SetTextColor(1,1,1)
            local r = nil
            if currentMapID and PathmakerDB.routes[currentMapID] and PathmakerDB.routes[currentMapID][addon.selectedRouteGUID] then
                r = PathmakerDB.routes[currentMapID][addon.selectedRouteGUID]
            else
                local mID = GetMapIDForRoute(addon.selectedRouteGUID)
                if mID then r = PathmakerDB.routes[mID][addon.selectedRouteGUID] end
            end
            if r and not f.renameBox:HasFocus() then f.renameBox:SetText(r.name) end
        else 
            f.btnExport:Disable(); f.btnExport.text:SetTextColor(0.5,0.5,0.5)
            f.renameBox:SetText("")
        end
        
        local items = {}
        local function CollectRoutes(mID, zoneNameSuffix)
            if PathmakerDB.routes[mID] then
                for guid, data in pairs(PathmakerDB.routes[mID]) do
                    if type(data) == "table" and (not addon.Routes or not addon.Routes.IsRouteData or addon.Routes:IsRouteData(data)) then
                        local name = data.name or "Unnamed"
                        local displayName = name
                        if zoneNameSuffix then displayName = name .. " (" .. zoneNameSuffix .. ")" end
                        if filter and filter ~= "" then
                            if string.find(string.lower(name), string.lower(filter)) then
                                table.insert(items, {guid=guid, data=data, mapID=mID, displayName=displayName})
                            end
                        else
                            if mID == currentMapID then
                                table.insert(items, {guid=guid, data=data, mapID=mID, displayName=name})
                            end
                        end
                    end
                end
            end
        end
        
        if filter and filter ~= "" then
            for mID, _ in pairs(PathmakerDB.routes) do
                local info = C_Map.GetMapInfo(mID)
                local zName = info and info.name or ("Map " .. mID)
                CollectRoutes(mID, zName)
            end
        else
            CollectRoutes(currentMapID, nil)
        end
        if addon.selectedRouteGUID then
            local alreadyListed = false
            for _, item in ipairs(items) do
                if item.guid == addon.selectedRouteGUID then alreadyListed = true break end
            end
            if not alreadyListed then
                local selectedMapID = GetMapIDForRoute(addon.selectedRouteGUID)
                local selectedRoute = selectedMapID and PathmakerDB.routes[selectedMapID] and PathmakerDB.routes[selectedMapID][addon.selectedRouteGUID]
                if selectedRoute then
                    local info = C_Map.GetMapInfo(selectedMapID)
                    local displayName = selectedRoute.name or "Unnamed"
                    if selectedMapID ~= currentMapID then displayName = displayName .. " (" .. (info and info.name or ("Map " .. selectedMapID)) .. ")" end
                    table.insert(items, {guid=addon.selectedRouteGUID, data=selectedRoute, mapID=selectedMapID, displayName=displayName})
                end
            end
        end
        table.sort(items, function(a,b) return a.displayName < b.displayName end)
        
        local idx = 0
        for i, item in ipairs(items) do
            idx = idx + 1
            local btn = self.buttons[idx]
            if not btn then
                btn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
                btn:SetSize(PANEL_WIDTH - 35, 20)
                btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                btn.color = CreateFrame("Button", nil, btn, "BackdropTemplate")
                btn.color:SetSize(12,12); btn.color:SetPoint("LEFT", 2, 0)
                btn.color:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
                btn.color:SetBackdropBorderColor(0,0,0,1)
                btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.name:SetPoint("LEFT", 18, 0); btn.name:SetWidth(PANEL_WIDTH - 75); btn.name:SetJustifyH("LEFT")
                btn.del = CreateFrame("Button", nil, btn)
                btn.del:SetSize(16,16); btn.del:SetPoint("RIGHT", -2, 0)
                btn.del.t = btn.del:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.del.t:SetPoint("CENTER"); btn.del.t:SetText("X"); btn.del.t:SetTextColor(1,1,0)
                SetTooltip(btn.del, "Delete Route", "Delete this route. Restore can bring back the most recently deleted route.")
                
                btn.del:SetScript("OnClick", function()
                    local rMID = btn.mapID
                    if rMID and PathmakerDB.routes[rMID] and PathmakerDB.routes[rMID][btn.guid] then
                        local d = PathmakerDB.routes[rMID][btn.guid]
                        if #routeHistory >= 25 then table.remove(routeHistory, 1) end
                        table.insert(routeHistory, {mapID=rMID, guid=btn.guid, data=d})
                        PathmakerDB.routes[rMID][btn.guid] = nil
                        if addon.selectedRouteGUID == btn.guid then addon.selectedRouteGUID = nil end
                        f:UpdateList(searchBox:GetText())
                    end
                end)
                
                btn:SetScript("OnClick", function()
                    if addon.selectedRouteGUID == btn.guid then
                        addon.selectedRouteGUID = nil
                        currentDraft.points = {} 
                        addon.Planner:RefreshCanvas()
                    else
                        addon.selectedRouteGUID = btn.guid
                        addon.selectedRouteMapID = btn.mapID
                        if btn.mapID ~= currentMapID then
                             currentMapID = btn.mapID
                             addon.Planner.currentMapID = btn.mapID
                             SafeSetMapID(btn.mapID) 
                             addon.Planner.currentMapID = btn.mapID
                             addon.Planner:LoadZone()

                        end
                         local r = PathmakerDB.routes[btn.mapID][btn.guid]
                         if r then
                            currentDraft.points = DeepCopyPoints(r.points)
                            currentDraft.color = r.color
                            addon.Planner:RefreshCanvas()
                         end
                    end
                    f:UpdateList(searchBox:GetText())
                end)
                self.buttons[idx] = btn
            end
            btn.guid = item.guid; btn.mapID = item.mapID; btn.routeName = item.data.name
            btn:SetPoint("TOPLEFT", 0, -((idx-1)*22))
            btn.name:SetText(item.displayName)
            if item.data and item.data.color then btn.color:SetBackdropColor(unpack(item.data.color)) else btn.color:SetBackdropColor(1,1,1,1) end
            if item.guid == addon.selectedRouteGUID then btn:SetBackdropColor(0.2, 0.4, 0.8, 0.4) else btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5) end
            btn:Show()
        end
        local totalHeight = math.max(1, idx * 22)
        scrollChild:SetHeight(totalHeight + 50) 
        slider:SetMinMaxValues(0, math.max(0, totalHeight - listHeight + 20)) 
    end
    
    yOffset = yOffset - (listHeight + 10)

    local lblMarkers = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lblMarkers:SetPoint("TOP", 0, yOffset)
    lblMarkers:SetText("Route Markers")
    lblMarkers:SetTextColor(1, 0.82, 0)
    yOffset = yOffset - 15

    local markerHeight = 125 
    local markerScroll, markerChild, markerSlider = CreateDarkScrollArea(f, PANEL_WIDTH - 30, markerHeight)
    markerScroll:SetPoint("TOP", 0, yOffset)
    
    self.markerList = {
        scroll = markerScroll,
        child = markerChild,
        slider = markerSlider,
        rows = {}
    }

    f.UpdateMarkerList = function(self)
        local frame = addon.Planner.markerList
        for _, row in pairs(frame.rows) do row:Hide() end

        local markers = {}
        local pts = currentDraft.points
        
        for i, p in ipairs(pts) do
            if p.isMarker then
                local isStart = true
                if i > 1 then
                    local prev = pts[i-1]
                    if prev.isMarker and not prev.isGap and (prev.duration == p.duration) then
                        isStart = false
                    end
                end
                
                if isStart then
                    table.insert(markers, {index=i, data=p})
                end
            end
        end

        local rowH = 24
        for i, item in ipairs(markers) do
            local row = frame.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, frame.child, "BackdropTemplate")
                row:SetSize(PANEL_WIDTH - 35, rowH)
                row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)

                local editName = CreateFrame("EditBox", nil, row, "BackdropTemplate")
                editName:SetSize(PANEL_WIDTH - 110, 18) 
                editName:SetPoint("LEFT", 2, 0)
                editName:SetAutoFocus(false)
                editName:SetFontObject("GameFontHighlightSmall")
                editName:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
                editName:SetBackdropColor(0,0,0,0.5)
                editName:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                editName:SetTextInsets(4,4,0,0)
                editName:SetMaxLetters(6) 
                
                editName:SetScript("OnEnterPressed", function(self) 
                    local newName = self:GetText() 
                    if row.data and row.markerIndex then 
                        PushUndoState() 
                        local pts = currentDraft.points
                        for k = row.markerIndex, #pts do
                             local p = pts[k]
                             if k > row.markerIndex and (p.isGap or not p.isMarker or p.duration ~= row.data.duration) then
                                  break
                             end
                             p.name = newName
                        end
                    end
                    self:ClearFocus() 
                    addon.Planner:RefreshCanvas()
                    addon.Planner:Save(true) 
                end)
                
                editName:SetScript("OnEscapePressed", function(self) 
                    self:ClearFocus()
                    self:SetText(row.data.name or "Marker")
                end)
                
                editName:SetScript("OnEditFocusLost", function(self)
                    if row.data then
                        self:SetText(row.data.name or "Marker")
                    end
                end)
                
                row.editName = editName

                local btnDel = CreateMinimalButton(row, "X", 18, 18)
                btnDel:SetPoint("RIGHT", -2, 0)
                btnDel:SetScript("OnClick", function()
                    if row.data and row.markerIndex then
                        PushUndoState() 
                        local pts = currentDraft.points
                        local startIndex = row.markerIndex
                        local endIndex = startIndex
                        
                        for k = startIndex, #pts do
                             local p = pts[k]
                             if k > startIndex and (p.isGap or not p.isMarker or p.duration ~= row.data.duration) then
                                  break 
                             end
                             endIndex = k
                        end
                        
                        for k = endIndex, startIndex, -1 do
                            table.remove(pts, k)
                        end
                        
                        addon.Planner:RefreshCanvas()
                        f:UpdateMarkerList() 
                        addon.Planner:Save(true) 
                    end
                end)
                row.btnDel = btnDel

                local editTime = CreateFrame("EditBox", nil, row, "BackdropTemplate")
                editTime:SetSize(35, 18)
                editTime:SetPoint("RIGHT", btnDel, "LEFT", -2, 0)
                editTime:SetAutoFocus(false)
                editTime:SetFontObject("GameFontHighlightSmall")
                editTime:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
                editTime:SetBackdropColor(0,0,0,0.5)
                editTime:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                editTime:SetTextInsets(0,0,0,0)
                editTime:SetJustifyH("CENTER")
                
                editTime:SetScript("OnEnterPressed", function(self) 
                    local text = self:GetText():gsub("s", "") 
                    local val = tonumber(text)
                    if row.data and row.markerIndex and val and val > 0 then
                        PushUndoState() 
                        local pts = currentDraft.points
                        for k = row.markerIndex, #pts do
                                local p = pts[k]
                                if k > row.markerIndex and (p.isGap or not p.isMarker) then
                                    break 
                                end
                                p.duration = val
                        end
                    end
                    self:ClearFocus() 
                    addon.Planner:RefreshCanvas()
                    addon.Planner:Save(true) 
                end)
                
                editTime:SetScript("OnEscapePressed", function(self) 
                    self:ClearFocus()
                    self:SetText(tostring(row.data.duration).."s")
                end)
                
                editTime:SetScript("OnEditFocusGained", function(self) self:SetText(tostring(row.data.duration)); self:HighlightText() end)
                
                editTime:SetScript("OnEditFocusLost", function(self)
                     if row.data then
                        self:SetText(tostring(row.data.duration).."s")
                     end
                end)
                
                row.editTime = editTime

                frame.rows[i] = row
            end

            row.data = item.data
            row.markerIndex = item.index 
            row.editName:SetText(item.data.name or "Marker")
            row.editTime:SetText(tostring(item.data.duration) .. "s")
            
            row:SetPoint("TOPLEFT", 0, -((i-1)*rowH))
            row:Show()
        end

        local totalH = math.max(1, #markers * rowH)
        frame.child:SetHeight(totalH)
        frame.slider:SetMinMaxValues(0, math.max(0, totalH - markerHeight))
    end

    self:LoadZoneList(self.dropZone)
    
    if currentMapID and self.dropZone then
        local info = C_Map.GetMapInfo(currentMapID)
        if info then
            self.dropZone.text:SetText(info.name)
            self.dropZone.text:SetTextColor(1, 1, 1)
        end
    end
    
    SetTool("PENCIL", self.btnPencil) 
    self.panel = f
    self.routeManager = f 
end

function addon.Planner:Create()
    self:CreateControlPanel()
    
    local overlay = CreateFrame("Frame", "PathmakerDrawingOverlay", WorldMapFrame)
    overlay:SetFrameLevel(9000)
    overlay:EnableMouse(false) 
    overlay:SetScript("OnMouseDown", function(_, button) self:OnOverlayClick(button, true) end)
    overlay:SetScript("OnMouseUp", function(_, button) self:OnOverlayClick(button, false) end)
    self.overlay = overlay

    self.drawingCanvas = CreateFrame("Frame", "PathmakerLines", UIParent)
    self.drawingCanvas:SetSize(100,100)
    self.drawingCanvas:Hide()
    
    WorldMapFrame:HookScript("OnHide", function()
        if isEditMode then self:Toggle() end
    end)
    
    self.panel:Hide()
end

function addon.Planner:Toggle()
    if not self.panel then self:Create() end
    
    isEditMode = not isEditMode
    
    if isEditMode then
        if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end

        local selectedMapID = addon.selectedRouteMapID
            or (addon.selectedRouteGUID and GetMapIDForRoute(addon.selectedRouteGUID))
        local selectedRoute = selectedMapID and addon.selectedRouteGUID
            and PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[selectedMapID]
            and PathmakerDB.routes[selectedMapID][addon.selectedRouteGUID]
        if selectedRoute then
            currentMapID = selectedMapID
            self.currentMapID = selectedMapID
        else
            DetectPlayerLocation()
        end
        if currentMapID then
            SafeSetMapID(currentMapID) 
        end

        local scrollChild = WorldMapFrame.ScrollContainer.Child or WorldMapFrame:GetCanvas()
        if scrollChild then
            self.drawingCanvas:SetParent(scrollChild)
            self.drawingCanvas:SetAllPoints(scrollChild)
            self.drawingCanvas:SetFrameLevel(2500)
            self.drawingCanvas:Show()
            
            self.overlay:SetParent(WorldMapFrame.ScrollContainer)
            self.overlay:ClearAllPoints()
            self.overlay:SetAllPoints(WorldMapFrame.ScrollContainer)
            self.overlay:Show()
            self.overlay:EnableMouse(currentTool ~= "DRAG")
        end
        
        self.panel:Show()
        
        self.panel:SetScript("OnUpdate", function(self, elapsed) 
            addon.Planner:OnOverlayUpdate(elapsed) 
            
            local actualMapID = WorldMapFrame:GetMapID()
            if actualMapID and actualMapID ~= currentMapID then
                UpdateDropdownsToMatchMap(actualMapID)
                self:UpdateList(self.searchBox and self.searchBox:GetText() or "")
                addon.Planner:LoadZone()
            end
        end)
        
        if not currentMapID then
             currentMapID = WorldMapFrame:GetMapID()
             addon.Planner.currentMapID = currentMapID
        end
        self:LoadZone()
    else
        self.panel:Hide()
        self.panel:SetScript("OnUpdate", nil)
        self.drawingCanvas:Hide()
        self.overlay:Hide()
        isDrawing = false
    end
end

function addon.Planner:LoadZone(overrideMapID)
    if currentMapID then
        local wMap = WorldMapFrame:GetMapID()
        if wMap ~= currentMapID then
            SafeSetMapID(currentMapID) 
        end
    else
        currentMapID = WorldMapFrame:GetMapID()
    end
    
    self.currentMapID = currentMapID

    if self.btnGhost then
        if ghostMode then
            self.btnGhost:SetBackdropBorderColor(0,0,0,1)
            self.btnGhost.text:SetTextColor(1,1,1)
        else
            self.btnGhost:SetBackdropBorderColor(0,0,0,1)
            self.btnGhost.text:SetTextColor(0.5, 0.5, 1)
        end
    end

    currentDraft.points = {}
    
    if PathmakerDB and PathmakerDB.routes and self.currentMapID then
        if addon.selectedRouteGUID and PathmakerDB.routes[self.currentMapID] then
            local r = PathmakerDB.routes[self.currentMapID][addon.selectedRouteGUID]
            if r then
                currentDraft.points = DeepCopyPoints(r.points)
                currentDraft.color = r.color
            end
        end
    end
    if self.UpdatePaletteSelection then self:UpdatePaletteSelection() end
    
    self:RefreshCanvas()
    local searchText = (self.panel and self.panel.searchBox) and self.panel.searchBox:GetText() or ""
    if self.panel then 
        self.panel:UpdateList(searchText) 
        self.panel:UpdateMarkerList() 
    end
    if self.dropZone then self:UpdateDropdowns() end
end

function addon.Planner:ShowGeneratedRoute(guid, mapID)
    if not guid or not mapID then return end
    addon.selectedRouteGUID = guid
    addon.selectedRouteMapID = mapID
    if self.panel and self.panel:IsShown() then
        currentMapID = mapID
        self.currentMapID = mapID
        SafeSetMapID(mapID)
        self:LoadZone(mapID)
    end
    if self.panel and self.panel.UpdateList then
        self.panel:UpdateList(self.panel.searchBox and self.panel.searchBox:GetText() or "")
    end
end

function addon.Planner:ClearExternalRouteSelection()
    currentDraft.points = {}
    if self.panel and self.panel:IsShown() then
        self:RefreshCanvas()
        self.panel:UpdateList(self.panel.searchBox and self.panel.searchBox:GetText() or "")
        self.panel:UpdateMarkerList()
    end
end

function addon.Planner:UpdateDropdowns()
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local info = C_Map.GetMapInfo(mapID)
    if info and self.dropZone then 
        self.dropZone.text:SetText(info.name) 
        self.dropZone.text:SetTextColor(1,1,1)
    end
end

function addon.Planner:Undo()
    if #undoStack > 0 then
        table.insert(redoStack, DeepCopyPoints(currentDraft.points))
        currentDraft.points = table.remove(undoStack)
        self:RefreshCanvas()
        self:Save(true) 
    end
end

function addon.Planner:Redo()
    if #redoStack > 0 then
        table.insert(undoStack, DeepCopyPoints(currentDraft.points))
        currentDraft.points = table.remove(redoStack)
        self:RefreshCanvas()
        self:Save(true) 
    end
end

function addon.Planner:Clear()
    PushUndoState()
    currentDraft.points = {}
    self:RefreshCanvas()
    self:Save(true) 
end

function addon.Planner:Save(silent)
    local targetMapID = self.currentMapID
    local guid = addon.selectedRouteGUID
    
    if guid then
        local existingMapID = GetMapIDForRoute(guid)
        if existingMapID then targetMapID = existingMapID end
    end
    
    if not targetMapID then return end
    
    if not guid then
        guid = "Route_" .. date("%Y%m%d%H%M%S")
    end
    
    if not PathmakerDB.routes[targetMapID] then PathmakerDB.routes[targetMapID] = {} end
    
    local name = "Drawn Route"
    if self.panel and self.panel.renameBox then
        local txt = self.panel.renameBox:GetText()
        if txt and txt ~= "" then name = txt end
    elseif guid and PathmakerDB.routes[targetMapID][guid] then
        name = PathmakerDB.routes[targetMapID][guid].name
    end

    PathmakerDB.routes[targetMapID][guid] = {
        name = name,
        color = currentDraft.color,
        thickness = 2,
        visible = true,
        connectPaths = false,
        points = DeepCopyPoints(currentDraft.points),
    }
    
    addon.selectedRouteGUID = guid 
    addon.selectedRouteMapID = targetMapID
    if addon.MapFrame then addon.MapFrame:UpdateRouteList() end
    if addon.UI then addon.UI:RefreshRendering() end
    
    if not silent then
        addon:PrintMessage("disableMsgRouteEditing", "Pathmaker: Saved.")
    end
    
    if self.panel then self.panel:UpdateList(self.panel.searchBox and self.panel.searchBox:GetText() or "") end
end

function addon.Planner:OnRouteColorChanged(guid, mapID, color)
    if not guid or type(color) ~= "table" then return end

    if addon.selectedRouteGUID == guid then
        local selectedMapID = addon.selectedRouteMapID or GetMapIDForRoute(guid)
        if not mapID or not selectedMapID or mapID == selectedMapID then
            currentDraft.color = color
            if self.UpdatePaletteSelection then self:UpdatePaletteSelection() end
        end
    end

    -- Other routes can be drawn as ghost lines in this editor as well.
    if self.RefreshCanvas then self:RefreshCanvas() end

    if self.panel and self.panel.UpdateList then
        self.panel:UpdateList(self.panel.searchBox and self.panel.searchBox:GetText() or "")
    end
end

function addon.Planner:OnOverlayClick(button, isDown)
    if not isEditMode then return end
    
    if button == "LeftButton" then
        if isDown then
            isDrawing = true
            if currentTool ~= "AVOID" then PushUndoState() end
            lastAction = "DRAW" 
            if currentTool == "AVOID" then currentAvoidDraft = {} end
            
            if (currentTool == "PENCIL" or currentTool == "MARKER") and #currentDraft.points > 0 then
                 local mx, my = GetCursorPosition()
                 local s = self.drawingCanvas:GetEffectiveScale()
                 local cx, cy = self.drawingCanvas:GetLeft(), self.drawingCanvas:GetTop()
                 local w, h = self.drawingCanvas:GetSize()
                 
                 local rx = (mx/s) - cx
                 local ry = cy - (my/s) 
                 local nx, ny = rx / w, ry / h
                 
                 local pts = currentDraft.points
                 local pFirst = pts[1]
                 local pLast = pts[#pts]
                 
                 local dFirst = math.sqrt((pFirst.x - nx)^2 + (pFirst.y - ny)^2)
                 local dLast = math.sqrt((pLast.x - nx)^2 + (pLast.y - ny)^2)
                 
                 local THRESHOLD = 0.03 
                 
                 if currentTool == "MARKER" then
                     local lastP = pts[#pts]
                     if lastP then
                          local isSameMarkerType = lastP.isMarker and (lastP.duration == currentTimerDuration)
                          if not isSameMarkerType then
                               lastP.isGap = true
                          end
                     end
                 else
                     if dFirst < THRESHOLD and dFirst < dLast then
                         ReverseDraft()
                         currentDraft.points[#currentDraft.points].isGap = false
                     elseif dLast < THRESHOLD then
                         currentDraft.points[#currentDraft.points].isGap = false
                     else
                         if currentDraft.points[#currentDraft.points] then
                             currentDraft.points[#currentDraft.points].isGap = true
                         end
                     end
                 end

            elseif currentTool == "ERASER" and #currentDraft.points > 0 then
                 local mx, my = GetCursorPosition()
                 local s = self.drawingCanvas:GetEffectiveScale()
                 local cx, cy = self.drawingCanvas:GetLeft(), self.drawingCanvas:GetTop()
                 local w, h = self.drawingCanvas:GetSize()
                 local rx = (mx/s) - cx
                 local ry = cy - (my/s) 
                 local nx, ny = rx / w, ry / h
                 
                 local pts = currentDraft.points
                 local pFirst = pts[1]
                 local pLast = pts[#pts]
                 
                 local dFirst = math.sqrt((pFirst.x - nx)^2 + (pFirst.y - ny)^2)
                 local dLast = math.sqrt((pLast.x - nx)^2 + (pLast.y - ny)^2)
                 
                 if dFirst < dLast then
                     ReverseDraft()
                 end
            end
            
            self:ProcessInput()
        else
            isDrawing = false
            if currentTool == "AVOID" then
                if #currentAvoidDraft >= 3 and currentMapID then
                    PathmakerDB = PathmakerDB or {}
                    PathmakerDB.avoidAreas = PathmakerDB.avoidAreas or {}
                    PathmakerDB.avoidAreas[currentMapID] = PathmakerDB.avoidAreas[currentMapID] or {}
                    table.insert(PathmakerDB.avoidAreas[currentMapID], DeepCopyPoints(currentAvoidDraft))
                    addon:PrintMessage("disableMsgRouteEditing", "PathMaker: Avoid area saved. New generated routes will go around it.")
                end
                currentAvoidDraft = {}
                self:RefreshCanvas()
            elseif currentTool == "PENCIL" or currentTool == "ERASER" or currentTool == "MARKER" then
                local last = currentDraft.points[#currentDraft.points]
                if last then last.isGap = true end
                self:Save(true)
            end
        end
    end
end

function addon.Planner:OnOverlayUpdate(elapsed)
    if not isEditMode then return end
    
    local mx, my = GetCursorPosition()
    local s = self.drawingCanvas:GetEffectiveScale()
    local cx, cy = self.drawingCanvas:GetLeft(), self.drawingCanvas:GetTop()
    
    if not cx or not cy then return end

    local rx = (mx/s) - cx
    local ry = cy - (my/s) 
    local w, h = self.drawingCanvas:GetSize()
    
    local nx, ny = rx / w, ry / h
    
    if self.coordDisplay then
        if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
            self.coordDisplay:SetText(string.format("%.1f, %.1f", nx*100, ny*100))
        else
            self.coordDisplay:SetText("--, --")
        end
    end

    local hoveredMarker = nil
    for i, p in ipairs(currentDraft.points) do
        if p.isMarker then
            local px, py = p.x * w, p.y * h
            local dist = math.sqrt((px - rx)^2 + (py - ry)^2)
            if dist < 10 then 
                hoveredMarker = p
                break 
            end
        end
    end

    if hoveredMarker then
        GameTooltip:SetOwner(self.drawingCanvas, "ANCHOR_CURSOR")
        GameTooltip:SetText(hoveredMarker.name or "Marker")
        GameTooltip:AddLine("Time: " .. (hoveredMarker.duration or "?") .. "s", 1, 1, 1)
        GameTooltip:Show()
    else
        if GameTooltip:GetOwner() == self.drawingCanvas then
            GameTooltip:Hide()
        end
    end
    
    if isDrawing and currentTool == "AVOID" then
        local lastP = currentAvoidDraft[#currentAvoidDraft]
        if not lastP or math.sqrt(((lastP.x * w) - rx)^2 + ((lastP.y * h) - ry)^2) > 5 then
            if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                currentAvoidDraft[#currentAvoidDraft + 1] = {x=nx, y=ny}
                self:RefreshCanvas()
            end
        end
    elseif isDrawing and (currentTool == "PENCIL" or currentTool == "MARKER") then
        local lastP = currentDraft.points[#currentDraft.points]
        if lastP then
             local px, py = lastP.x * w, lastP.y * h
             local dist = math.sqrt((px - rx)^2 + (py - ry)^2)
             if dist > 5 then
                self:AddPoint(nx, ny)
             end
        else
            self:AddPoint(nx, ny)
        end
    elseif isDrawing and currentTool == "ERASER" then
        self:EraseAt(rx, ry, w, h)
    end
end

function addon.Planner:ProcessInput()
    local mx, my = GetCursorPosition()
    local s = self.drawingCanvas:GetEffectiveScale()
    local cx, cy = self.drawingCanvas:GetLeft(), self.drawingCanvas:GetTop()
    local rx = (mx/s) - cx
    local ry = cy - (my/s) 
    local w, h = self.drawingCanvas:GetSize()
    local nx, ny = rx / w, ry / h
    
    if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
        if currentTool == "AVOID" then
            currentAvoidDraft[#currentAvoidDraft + 1] = {x=nx, y=ny}
            self:RefreshCanvas()
        elseif currentTool == "PENCIL" or currentTool == "MARKER" then
            self:AddPoint(nx, ny)
        elseif currentTool == "ERASER" then
            self:EraseAt(rx, ry, w, h)
        end
    end
end

function addon.Planner:AddPoint(nx, ny)
    if nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
    
    local pointData = {x = nx, y = ny, isGap = false}
    
    if currentTool == "MARKER" then
        pointData.isMarker = true
        pointData.duration = currentTimerDuration
        pointData.name = "Marker"
    end
    
    table.insert(currentDraft.points, pointData)
    self:RefreshCanvas()
end

function addon.Planner:EraseAt(rx, ry, w, h)
    local toRemove = {}
    for i, p in ipairs(currentDraft.points) do
        local px, py = p.x * w, p.y * h
        local dist = math.sqrt((px - rx)^2 + (py - ry)^2)
        if dist <= eraserRadius then 
            table.insert(toRemove, i) 
        end
    end

    if #toRemove == 0 then return end
    
    local removeSet = {}
    for _, idx in ipairs(toRemove) do removeSet[idx] = true end
    
    for _, idx in ipairs(toRemove) do
        local prev = idx - 1
        if prev > 0 and not removeSet[prev] then
            currentDraft.points[prev].isGap = true
        end
    end
    
    table.sort(toRemove, function(a,b) return a > b end)
    for _, idx in ipairs(toRemove) do
        table.remove(currentDraft.points, idx)
    end
    
    self:RefreshCanvas()
end

function addon.Planner:RefreshCanvas()
    if not self.drawingCanvas then return end
    if self.drawStatus then
        local labels = {PENCIL="Drawing Route", ERASER="Erasing", DRAG="Moving", MARKER="Marking", AVOID="Drawing Avoid Area"}
        local pointCount = currentTool == "AVOID" and #currentAvoidDraft or #currentDraft.points
        self.drawStatus:SetText(string.format("%s - %d points", labels[currentTool] or "Draw Mode", pointCount))
    end
    
    for _, line in ipairs(activeLines) do
        line:Hide()
        table.insert(linePool, line)
    end
    wipe(activeLines)
    
    for _, dot in ipairs(activeDots) do
        dot:Hide()
        table.insert(dotPool, dot)
    end
    wipe(activeDots)

    if currentTool == "AVOID" then
        local avoidColor = {1, 0.18, 0.12, 0.9}
        local areas = currentMapID and PathmakerDB and PathmakerDB.avoidAreas and PathmakerDB.avoidAreas[currentMapID] or {}
        for _, area in ipairs(areas) do
            for i = 1, #area do
                local a, b = area[i], area[(i % #area) + 1]
                DrawLine(self.drawingCanvas, a.x, a.y, b.x, b.y, 3, avoidColor)
            end
        end
        if #currentAvoidDraft > 1 then
            for i = 1, #currentAvoidDraft - 1 do
                DrawLine(self.drawingCanvas, currentAvoidDraft[i].x, currentAvoidDraft[i].y, currentAvoidDraft[i + 1].x, currentAvoidDraft[i + 1].y, 3, avoidColor)
            end
        end
    end
    
    if not ghostMode and currentMapID and PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[currentMapID] then
        for guid, r in pairs(PathmakerDB.routes[currentMapID]) do
            if guid ~= addon.selectedRouteGUID and r.points and #r.points > 1 then
                local rCol = r.color or {1, 1, 1, 1}
                local fadedCol = {rCol[1], rCol[2], rCol[3], 0.4} 
                for i = 1, #r.points - 1 do
                    local p1 = r.points[i]
                    local p2 = r.points[i+1]
                    if not p1.isGap then
                        DrawLine(self.drawingCanvas, p1.x, p1.y, p2.x, p2.y, 1, fadedCol)
                    end
                end
            end
        end
    end
    
    local pts = currentDraft.points
    local col = currentDraft.color
    local th = currentDraft.thickness
    
    for i = 1, #pts - 1 do
        local p1 = pts[i]
        local p2 = pts[i+1]
        
        local segCol = col
        local isMarkerSeg = false
        if p1.isMarker and p2.isMarker then
             local d = (p1.x - p2.x)^2 + (p1.y - p2.y)^2
             if d < 0.0002 then isMarkerSeg = true end
        end
        
        if isMarkerSeg then segCol = {0, 0, 0, 1} end 
        
        if not p1.isGap then
            DrawLine(self.drawingCanvas, p1.x, p1.y, p2.x, p2.y, th, segCol)
        end
    end

    if self.panel and self.panel.UpdateMarkerList then
        self.panel:UpdateMarkerList()
    end
end
