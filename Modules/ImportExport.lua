local addonName, addon = ...
addon.ImportExport = {}

-- ----------------------------------------------------------------------------
-- CONSTANTS & CONFIG
-- ----------------------------------------------------------------------------
local COMM_PREFIX = "PM_ROUTE"
local LINK_PROTOCOL = "pathmaker"
local LINK_COLOR = "d6b3ff" -- Distinct Purple (WeakAuras-ish style)
local CHUNK_SIZE = 240      -- Safe chunk size for addon messages

-- Classic TBC clients use a separate UiMapID range for Outland and the
-- blood-elf/draenei starting zones. On Retail those numeric IDs can identify
-- unrelated maps, so translate the destination by zone before storing it.
local CLASSIC_TBC_TO_RETAIL_MAP = {
    [1941] = 94,  -- Eversong Woods
    [1942] = 95,  -- Ghostlands
    [1943] = 97,  -- Azuremyst Isle
    [1944] = 100, -- Hellfire Peninsula
    [1946] = 102, -- Zangarmarsh
    [1948] = 104, -- Shadowmoon Valley
    [1949] = 105, -- Blade's Edge Mountains
    [1950] = 106, -- Bloodmyst Isle
    [1951] = 107, -- Nagrand
    [1952] = 108, -- Terokkar Forest
    [1953] = 109, -- Netherstorm
    [1957] = 122, -- Isle of Quel'Danas
}

local CLASSIC_ERA_TO_RETAIL_MAP = {
    [1416] = 25, -- Alterac Mountains -> Hillsbrad Foothills
    [1417] = 14, [1418] = 15, [1419] = 17, [1420] = 18,
    [1421] = 21, [1422] = 22, [1423] = 23, [1424] = 25,
    [1425] = 26, [1426] = 27, [1427] = 32, [1428] = 36,
    [1429] = 37, [1430] = 42, [1431] = 47, [1432] = 48,
    [1433] = 49, [1434] = 50, -- Stranglethorn Vale -> Northern Stranglethorn
    [1435] = 51, [1436] = 52, [1437] = 56,
    [1411] = 1, [1412] = 7, [1413] = 10, -- The Barrens -> Northern Barrens
    [1438] = 57, [1439] = 62, [1440] = 63, [1441] = 64,
    [1442] = 65, [1443] = 66, [1444] = 69, [1445] = 70,
    [1446] = 71, [1447] = 76, [1448] = 77, [1449] = 78,
    [1450] = 80, [1451] = 81, [1452] = 83,
}

-- Most zone maps retain the same normalized canvas between clients. Start
-- from that neutral conversion, then use a measured override only for maps
-- whose artwork bounds demonstrably differ. This prevents one zone's crop
-- from distorting every other Classic Era/TBC import.
local LEGACY_PICTURE_TO_RETAIL_COORDS = {
    xScale = 1,
    xOffset = 0,
    yScale = 1,
    yOffset = 0,
}

local LEGACY_ZONE_COORD_OVERRIDES = {
    [1417] = { -- Arathi Highlands, Classic Era artwork -> Retail artwork
        xScale = 1.000062,
        xOffset = 0.004842,
        yScale = 1.000117,
        yOffset = 0.001683,
    },
    [1951] = { -- Nagrand, measured from Classic TBC and Retail landmarks
        xScale = 0.780994,
        xOffset = 0.057349,
        yScale = 0.919201,
        yOffset = 0.052913,
    },
    [1439] = { -- Darkshore retains its normalized canvas across the versions
        xScale = 1,
        xOffset = 0,
        yScale = 1,
        yOffset = 0,
    },
}

local function GetRetailMapForLegacyMap(mapID)
    return CLASSIC_TBC_TO_RETAIL_MAP[mapID] or CLASSIC_ERA_TO_RETAIL_MAP[mapID]
end

local function ResolveImportMapID(mapID)
    mapID = tonumber(mapID)
    if addon.Compat and addon.Compat.isRetail then
        return GetRetailMapForLegacyMap(mapID) or mapID
    end
    return mapID
end

local function ClampCoordinate(value)
    return math.max(0, math.min(1, value or 0))
end

local function ConvertCrossClientCoordinates(route, sourceMapID, targetMapID)
    if not addon.Compat or not addon.Compat.isRetail or not route or not route.points then return false end
    sourceMapID = tonumber(sourceMapID)
    targetMapID = tonumber(targetMapID)
    if GetRetailMapForLegacyMap(sourceMapID) ~= targetMapID then return false end
    local transform = LEGACY_ZONE_COORD_OVERRIDES[sourceMapID] or LEGACY_PICTURE_TO_RETAIL_COORDS

    for _, point in ipairs(route.points) do
        point.x = ClampCoordinate((point.x or 0) * transform.xScale + transform.xOffset)
        point.y = ClampCoordinate((point.y or 0) * transform.yScale + transform.yOffset)
    end
    return true
end

-- Register the Prefix so WoW allows the traffic
if C_ChatInfo then
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
end

-- ----------------------------------------------------------------------------
-- STATE MANAGEMENT
-- ----------------------------------------------------------------------------
local sentRoutesCache = {} -- Stores routes we are willing to share
local incomingBuffers = {} -- Stores chunks of routes we are receiving

-- ----------------------------------------------------------------------------
-- UTILITY FUNCTIONS
-- ----------------------------------------------------------------------------

local function printIO(msg)
    local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgRouteIO
    if not hideMsg then print(msg) end
end

local function printErr(msg)
    local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
    if not hideMsg then print(msg) end
end

local function GetMyFullName()
    local name, realm = UnitFullName("player")
    if not realm or realm == "" then realm = GetRealmName() end
    realm = string.gsub(realm or "", "%s+", "") 
    return name .. "-" .. realm
end

-- Clean names to prevent chat link breakage (removes colons and brackets)
local function SanitizeNameForChat(str)
    if not str then return "Route" end
    -- Remove characters that would break the parsing pattern
    return string.gsub(str, "[%[%]:%^]", "")
end

local function Sanitize(str)
    if not str then return "" end
    return string.gsub(str, "[^a-zA-Z0-9%s%-%_]", "")
end

-- ----------------------------------------------------------------------------
-- SERIALIZATION (The Data Format)
-- ----------------------------------------------------------------------------
-- Format: Name^MapID^ConnectPaths^Color^Points
local function SerializeRoute(route, mapID)
    if not route or not route.points then return nil end
    
    local parts = {}
    for _, p in ipairs(route.points) do
        local flags = 0
        if p.isGap then flags = flags + 1 end
        if p.isMarker then flags = flags + 2 end
        
        -- Compact Point: x,y,flags
        local pStr = string.format("%.4f,%.4f,%d", p.x, p.y, flags)
        
        -- Append Marker Data if needed
        if p.isMarker then
            local dur = p.duration or 0
            local pName = Sanitize(p.name or "M")
            pStr = pStr .. "," .. dur .. "," .. pName
        end
        table.insert(parts, pStr)
    end
    
    local safeName = string.gsub(route.name or "Route", "%^", "")
    local c = route.color or {1, 1, 1}
    local colorStr = string.format("%.2f,%.2f,%.2f", c[1], c[2], c[3])
    local connectStr = route.connectPaths and "1" or "0"
    
    -- Combine into one string
    return string.format("%s^%d^%s^%s^%s", safeName, mapID or 0, connectStr, colorStr, table.concat(parts, ";"))
end

local function DeserializeRoute(dataString)
    if not dataString or dataString == "" then return nil end
    
    -- Try New Format
    local name, mapID, connect, colorStr, pointsStr = string.match(dataString, "^(.-)%^(%d+)%^([01])%^([%d%.,]+)%^(.*)$")
    
    -- Try Old Format (Fallback)
    if not connect then
         name, mapID, pointsStr = string.match(dataString, "^(.-)%^(%d+)%^(.*)$")
         connect = "0"
         colorStr = "1,1,1"
    end
    
    if not name or not mapID or not pointsStr then return nil end
    
    local r, g, b = string.match(colorStr, "([%d%.]+),([%d%.]+),([%d%.]+)")
    
    local route = {
        name = name,
        points = {},
        color = {tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1, 1},
        thickness = 2,
        visible = true,
        connectPaths = (connect == "1")
    }
    
    for pStr in string.gmatch(pointsStr, "([^;]+)") do
        local x, y, flags, dur, pName = string.match(pStr, "([%d%.]+),([%d%.]+),?(%d*),?(%d*),?(.*)")
        if x and y then
            flags = tonumber(flags) or 0
            local newP = {
                x = tonumber(x), 
                y = tonumber(y),
                isGap = (bit.band(flags, 1) == 1),
                isMarker = (bit.band(flags, 2) == 2)
            }
            if newP.isMarker then
                newP.duration = tonumber(dur) or 0
                newP.name = pName or "Marker"
            end
            table.insert(route.points, newP)
        end
    end
    
    return route, tonumber(mapID)
end

-- ----------------------------------------------------------------------------
-- NETWORK: SENDING & RECEIVING
-- ----------------------------------------------------------------------------
local function SendDataToPlayer(target, serializedData)
    if not target or not serializedData then return end
    
    local transferID = string.format("%x", math.random(1, 1000000))
    local len = #serializedData
    local numChunks = math.ceil(len / CHUNK_SIZE)
    local safeTarget = Ambiguate(target, "none")
    
    -- Split into chunks and send via AddonChannel
    for i = 1, numChunks do
        local startIdx = (i - 1) * CHUNK_SIZE + 1
        local endIdx = math.min(i * CHUNK_SIZE, len)
        local chunk = serializedData:sub(startIdx, endIdx)
        -- Protocol: D:ID:Index:Total:Content
        local msg = string.format("D:%s:%d:%d:%s", transferID, i, numChunks, chunk)
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, msg, "WHISPER", safeTarget)
    end
end

local function HandleRequest(sender, guid)
    -- Check cache first, then DB
    local route = sentRoutesCache[guid]
    if not route and PathmakerDB and PathmakerDB.routes then
        for mapID, routes in pairs(PathmakerDB.routes) do
            if routes[guid] then
                route = routes[guid]
                route.mapID = mapID
                sentRoutesCache[guid] = route
                break
            end
        end
    end
    
    if route then
        local data = SerializeRoute(route, route.mapID or 0)
        if data then
            printIO("|cFF"..LINK_COLOR.."PathMaker:|r Uploading route to " .. sender .. "...")
            SendDataToPlayer(sender, data)
        end
    else
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, "ERR:RouteNotFound", "WHISPER", sender)
    end
end

local function HandleDataChunk(sender, payload)
    local id, idxStr, totalStr, content = strsplit(":", payload, 4)
    local idx = tonumber(idxStr)
    local total = tonumber(totalStr)
    
    if not id or not idx or not total then return end
    
    if not incomingBuffers[id] then
        incomingBuffers[id] = { parts = {}, count = 0, total = total }
    end
    
    local buf = incomingBuffers[id]
    if not buf.parts[idx] then
        buf.parts[idx] = content
        buf.count = buf.count + 1
    end
    
    -- If Reassembly Complete
    if buf.count >= buf.total then
        local fullData = table.concat(buf.parts)
        incomingBuffers[id] = nil
        addon.ImportExport:ShowImportWindow(fullData)
        printIO("|cFF"..LINK_COLOR.."PathMaker:|r Route received from " .. sender)
    end
end

-- ----------------------------------------------------------------------------
-- COMM LISTENER
-- ----------------------------------------------------------------------------
local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")
commFrame:SetScript("OnEvent", function(self, event, prefix, msg, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    
    local cmd, payload = strsplit(":", msg, 2)
    local cleanSender = Ambiguate(sender, "none")
    
    if cmd == "REQ" then
        HandleRequest(cleanSender, payload)
    elseif cmd == "D" then
        HandleDataChunk(cleanSender, payload)
    elseif cmd == "ERR" then
        printErr("|cFFFF0000PathMaker:|r Sender says this route is no longer available.")
    end
end)

-- ----------------------------------------------------------------------------
-- CHAT FILTER SYSTEM (The "WeakAura Link" Magic)
-- ----------------------------------------------------------------------------
-- This function looks at incoming chat messages. If it sees our tag [PathMaker:Name:ID],
-- it transforms it into a clickable |H hyperlink.

local function PathMakerChatFilter(self, event, msg, sender, ...)
    if msg and string.find(msg, "%[PathMaker:") then
        -- Match Pattern: [PathMaker : Name : GUID : MapID]
        -- Note: We capture spaces around separators just in case
        local newMsg = string.gsub(msg, "%[PathMaker%s*:%s*(.-)%s*:%s*(.-)%s*:%s*(%d+)%s*%]", 
        function(rName, rGUID, rMapID)
            local cleanSender = Ambiguate(sender, "none")
            
            -- Construct the Hyperlink
            -- |Hpathmaker:SENDER:GUID:MAPID|h[TEXT]|h
            return string.format("|cFF%s|H%s:%s:%s:%s|h[PathMaker: %s]|h|r", 
                LINK_COLOR, LINK_PROTOCOL, cleanSender, rGUID, rMapID, rName)
        end)
        
        return false, newMsg, sender, ...
    end
    return false, msg, sender, ...
end

-- Register filter for all chat types where players talk
local chatEvents = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER"
}
for _, event in ipairs(chatEvents) do
    ChatFrame_AddMessageEventFilter(event, PathMakerChatFilter)
end

-- ----------------------------------------------------------------------------
-- CLICK HANDLER (SetItemRef)
-- ----------------------------------------------------------------------------
hooksecurefunc("SetItemRef", function(link, text, button, chatFrame)
    if string.sub(link, 1, #LINK_PROTOCOL) == LINK_PROTOCOL then
        -- link = pathmaker:Sender:GUID:MapID
        local _, sender, guid, mapID = strsplit(":", link)
        mapID = tonumber(mapID)
        
        if sender and guid then
            local me = GetMyFullName()
            local isMine = Ambiguate(sender, "none") == Ambiguate(me, "none")
            
            -- 1. CHECK IF WE ALREADY HAVE THIS ROUTE LOCALLY
            local existingRoute = nil
            if PathmakerDB and PathmakerDB.routes and mapID and PathmakerDB.routes[mapID] then
                existingRoute = PathmakerDB.routes[mapID][guid]
            end
            
            -- 2. IF LOCAL MATCH FOUND, OPEN IT IMMEDIATELY
            if existingRoute then
                printIO("|cFF"..LINK_COLOR.."PathMaker:|r Opening route from your library...")
                local data = SerializeRoute(existingRoute, mapID)
                addon.ImportExport:ShowImportWindow(data)
                return
            end
            
            -- 3. IF NO LOCAL MATCH, BUT IT'S "MINE", ERROR
            if isMine then
                printErr("|cFF"..LINK_COLOR.."PathMaker:|r You linked this, but the route data is missing from your database.")
                return
            end
            
            -- 4. ELSE, REQUEST FROM SENDER
            printIO("|cFF"..LINK_COLOR.."PathMaker:|r Requesting route data from "..sender.."...")
            C_ChatInfo.SendAddonMessage(COMM_PREFIX, "REQ:"..guid, "WHISPER", sender)
        end
    end
end)

-- ----------------------------------------------------------------------------
-- FIX: Prevent "Unknown link type" Lua Error
-- ----------------------------------------------------------------------------
-- When SetItemRef is called, WoW also tries to display a tooltip for the link.
-- Since "pathmaker" isn't a valid item/quest/spell, it errors.
-- We must intercept the tooltip call to prevent this.
if ItemRefTooltip then
    local oldSetHyperlink = ItemRefTooltip.SetHyperlink
    function ItemRefTooltip:SetHyperlink(link, ...)
        if link and string.sub(link, 1, #LINK_PROTOCOL) == LINK_PROTOCOL then
            return -- Silently ignore our custom link type
        end
        return oldSetHyperlink(self, link, ...)
    end
end

-- ----------------------------------------------------------------------------
-- UI FRAMES (Export/Import Windows)
-- ----------------------------------------------------------------------------
local function CreateImportExportFrame()
    if addon.ImportExportFrame then return addon.ImportExportFrame end
    
    local f = CreateFrame("Frame", "PathMakerIOFrame", UIParent, "BackdropTemplate")
    f:SetSize(450, 266)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    -- A muted matte panel remains readable without the previous pitch-black
    -- block. The 0.75 opacity leaves roughly 25% of the world visible.
    f:SetBackdropColor(0.14, 0.16, 0.18, 0.75)
    f:SetBackdropBorderColor(0.48, 0.53, 0.58, 0.9)
    
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -16)
    
    f.textLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.textLabel:SetPoint("TOPLEFT", 34, -38)

    local function StyleInset(frame)
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
            insets = {left=2, right=2, top=2, bottom=2},
        })
        frame:SetBackdropColor(0.16, 0.18, 0.20, 0.75)
        frame:SetBackdropBorderColor(0.46, 0.52, 0.56, 0.9)
    end

    local textPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    textPanel:SetPoint("TOPLEFT", 28, -54)
    textPanel:SetSize(394, 88)
    textPanel:EnableMouse(true)
    StyleInset(textPanel)

    local sf = CreateFrame("ScrollFrame", nil, textPanel, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 7, -6)
    sf:SetPoint("BOTTOMRIGHT", -27, 6)
    f.scrollFrame = sf
    
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetWidth(360)
    eb:SetHeight(76)
    eb:SetAutoFocus(false)
    sf:SetScrollChild(eb)
    f.editBox = eb

    local function FocusImportText()
        if f.mode ~= "import" then return end
        eb:SetFocus()
        eb:HighlightText()
    end
    textPanel:SetScript("OnMouseUp", FocusImportText)
    sf:SetScript("OnMouseUp", FocusImportText)
    eb:SetScript("OnMouseUp", FocusImportText)

    f.placeholder = textPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.placeholder:SetPoint("TOPLEFT", 8, -7)
    f.placeholder:SetText("Paste route code here")

    f.nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.nameLabel:SetPoint("TOPLEFT", 34, -164)
    local nameBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    nameBox:SetPoint("TOPLEFT", 28, -180)
    nameBox:SetSize(394, 22)
    StyleInset(nameBox)
    nameBox:SetFontObject("GameFontHighlightSmall")
    nameBox:SetTextInsets(7, 7, 2, 2)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(100)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    nameBox:SetScript("OnTabPressed", function(self) self:ClearFocus(); eb:SetFocus() end)
    eb:SetScript("OnTabPressed", function(self)
        if f.mode == "import" then self:ClearFocus(); nameBox:SetFocus() end
    end)
    f.nameBox = nameBox
    
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    local btnImport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnImport:SetSize(116, 22)
    btnImport:SetPoint("BOTTOM", -65, 20)
    btnImport:SetText("Import")
    f.btnImport = btnImport
    
    local btnLink = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnLink:SetSize(116, 22)
    btnLink:SetPoint("BOTTOM", -65, 20)
    btnLink:SetText("Link to Chat")
    f.btnLink = btnLink

    local btnCopy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCopy:SetSize(116, 22)
    btnCopy:SetPoint("BOTTOM", -130, 20)
    btnCopy:SetText("Copy Text")
    f.btnCopy = btnCopy

    f.btnClose = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btnClose:SetSize(116, 22)
    f.btnClose:SetPoint("BOTTOM", 65, 20)
    f.btnClose:SetText("Cancel")
    f.btnClose:SetScript("OnClick", function() f:Hide() end)

    eb:SetScript("OnTextChanged", function(self)
        if f.mode == "export" and f.exportText and self:GetText() ~= f.exportText then
            self:SetText(f.exportText)
            self:HighlightText()
            return
        end
        local hasText = self:GetText():find("%S") ~= nil
        if hasText then f.placeholder:Hide() else f.placeholder:Show() end
        if f.mode == "import" then
            if hasText then f.btnImport:Enable() else f.btnImport:Disable() end
        end
    end)
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        eb:ClearFocus()
        nameBox:ClearFocus()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        self:HighlightText(0, 0)
        if f.mode == "export" then self:EnableKeyboard(false) end
    end)
    UISpecialFrames = UISpecialFrames or {}
    table.insert(UISpecialFrames, "PathMakerIOFrame")
    
    addon.ImportExportFrame = f
    return f
end

-- ----------------------------------------------------------------------------
-- UI: EXPORT ACTION
-- ----------------------------------------------------------------------------
function addon.ImportExport:ShowExport(guid)
    if not guid then 
        printErr("Pathmaker: No route selected.")
        return 
    end

    local mapID = addon.Planner and addon.Planner.currentMapID or C_Map.GetBestMapForUnit("player")
    local route = PathmakerDB.routes[mapID] and PathmakerDB.routes[mapID][guid]
    
    -- Fallback search if current map is wrong
    if not route then
        for mID, routes in pairs(PathmakerDB.routes) do
            if routes[guid] then mapID = mID; route = routes[guid]; break end
        end
    end
    
    if not route then
        printErr("PathMaker: Route not found.")
        return
    end

    local f = CreateImportExportFrame()
    f.mode = "export"
    f:Show()
    f.title:SetText("Export Route")
    f.textLabel:SetText("Export Text (read-only; use Link to Chat)")
    f.nameLabel:SetText("Route Name")
    f.nameBox:SetText(route.name or "Unnamed")
    f.nameBox:ClearFocus()
    f.nameBox:EnableMouse(false)
    f.nameBox:EnableKeyboard(false)
    f.btnClose:SetText("Close")
    f.btnClose:ClearAllPoints()
    f.btnClose:SetPoint("BOTTOM", 130, 20)
    f.editBox:ClearFocus()
    f.editBox:EnableMouse(false)
    f.editBox:EnableKeyboard(false)
    f.exportText = SerializeRoute(route, mapID)
    f.editBox:SetText(f.exportText)
    f.scrollFrame:SetVerticalScroll(0)
    
    f.btnImport:Hide()
    f.btnCopy:Show()
    f.btnLink:Show()
    f.btnLink:Enable()
    f.btnLink:ClearAllPoints()
    f.btnLink:SetPoint("BOTTOM", 0, 20)

    f.btnCopy:SetScript("OnClick", function()
        -- WoW cannot write directly to the operating-system clipboard. Give
        -- keyboard focus only through this button, keep the field read-only,
        -- and select everything so Ctrl+C is the only remaining step.
        f.editBox:EnableKeyboard(true)
        f.editBox:SetFocus()
        f.editBox:HighlightText()
        f.textLabel:SetText("Export Text selected - press Ctrl+C")
    end)
    
    -- Cache for link sharing
    route.mapID = mapID
    sentRoutesCache[guid] = route
    
    f.btnLink:SetScript("OnClick", function()
        local cleanName = SanitizeNameForChat(route.name)
        
        -- Create the text tag: [PathMaker: Name : GUID : MapID]
        -- The ChatFilter will turn this into a link when it is seen in chat.
        local tag = string.format("[PathMaker: %s : %s : %s]", cleanName, guid, mapID or 0)
        
        local editBox = ChatEdit_GetActiveWindow()
        if editBox and editBox:IsVisible() then
            editBox:Insert(tag)
        else
            -- Open default chat if none open
            local defaultEb = ChatFrame1EditBox
            if defaultEb then
                defaultEb:Show()
                defaultEb:SetFocus()
                defaultEb:Insert(tag)
            else
                printIO("|cFF"..LINK_COLOR.."PathMaker:|r Copy this to chat:")
                printIO(tag)
            end
        end
    end)
end

-- ----------------------------------------------------------------------------
-- UI: IMPORT ACTION
-- ----------------------------------------------------------------------------
function addon.ImportExport:ShowImportWindow(data)
    local f = CreateImportExportFrame()
    f.mode = "import"
    f:Show()
    f.title:SetText("Import Route")
    f.textLabel:SetText("Import Text")
    f.nameLabel:SetText("New Route Name (optional)")
    f.nameBox:SetText("")
    f.nameBox:ClearFocus()
    f.nameBox:EnableMouse(true)
    f.nameBox:EnableKeyboard(true)
    f.btnClose:SetText("Cancel")
    f.btnClose:ClearAllPoints()
    f.btnClose:SetPoint("BOTTOM", 65, 20)
    f.exportText = nil
    f.editBox:EnableMouse(true)
    f.editBox:EnableKeyboard(true)
    f.editBox:SetText(data or "")
    f.scrollFrame:SetVerticalScroll(0)
    if not data then f.editBox:SetFocus() end
    
    f.btnLink:Hide()
    f.btnCopy:Hide()
    f.btnImport:Show()
    if f.editBox:GetText():find("%S") then f.btnImport:Enable() else f.btnImport:Disable() end
    
    f.btnImport:SetScript("OnClick", function()
        local str = f.editBox:GetText()
        local route, mapID = DeserializeRoute(str)
        local sourceMapID = mapID

        -- Image-converter routes can defer their destination to the zone that
        -- is already selected in PathMaker. This avoids numeric UiMapIDs.
        if route and mapID == 0 then
            local selectedMapID = (addon.Planner and addon.Planner.currentMapID)
                or (WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID())
                or addon.selectedRouteMapID
                or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
            if selectedMapID and selectedMapID > 0 then mapID = selectedMapID end
        end

        -- Cross-client destinations are accepted. When Retail is running, a
        -- Classic TBC UiMapID is stored under the equivalent Retail zone.
        mapID = ResolveImportMapID(mapID)
        local convertedCoordinates = ConvertCrossClientCoordinates(route, sourceMapID, mapID)
        
        if route and mapID and mapID > 0 and route.points then
            local newName = f.nameBox:GetText():match("^%s*(.-)%s*$")
            if newName ~= "" then route.name = newName end
            if not PathmakerDB.routes[mapID] then PathmakerDB.routes[mapID] = {} end
            
            local newGUID = "imported-" .. math.random(100000) .. "-" .. GetTime()
            PathmakerDB.routes[mapID][newGUID] = route
            
            printIO("|cFF00FF00PathMaker:|r Imported route: " .. route.name)
            if sourceMapID and sourceMapID ~= 0 and sourceMapID ~= mapID then
                printIO("|cFF80E86APathMaker:|r Legacy destination mapped to this client's equivalent zone (" .. mapID .. ").")
            end
            if convertedCoordinates then
                printIO("|cFF80E86APathMaker:|r Route coordinates adjusted to the Retail version of this map.")
            end
            f:Hide()
            
            -- Refresh UI
            if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
            if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
            if addon.Planner and addon.Planner.panel and addon.Planner.panel:IsShown() then
                addon.Planner.panel:UpdateList(nil)
            end
        else
            local looksLikeWebAddress = string.match(str or "", "^%s*https?://") ~= nil
            if looksLikeWebAddress then
                printErr("|cFFFF0000PathMaker:|r Convert route pictures at https://pathmaker.pages.dev/tools/image-route-importer/ then paste the generated route text here or use /pmtoolimport. The website is optional; existing route text can be imported offline.")
            else
                printErr("|cFFFF0000PathMaker:|r Error: Invalid route data. Convert route pictures at https://pathmaker.pages.dev/tools/image-route-importer/ and paste the generated PathMaker route text.")
            end
        end
    end)
end

function addon.ImportExport:ShowImport()
    self:ShowImportWindow(nil)
end
