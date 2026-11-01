local addonName, addon = ...
_G["Pathmaker"] = addon
_G["PathMaker"] = addon -- Double-registration for case-insensitivity

-- Keep message categories consistent across slash commands and UI panels.
function addon:PrintMessage(setting, message)
    local settings = PathmakerDB and PathmakerDB.settings
    if not settings or not settings[setting] then print(message) end
end

local IMPORT_SAFETY_YARDS = 3
local IMPORT_FALLBACK_MAP_YARDS = 6000

local function GetImportMapScales(mapID)
    if addon.UI and addon.UI.GetMapWorldScale then
        local scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
        if scaleX and scaleY then return scaleX, scaleY end
    end
    return IMPORT_FALLBACK_MAP_YARDS, IMPORT_FALLBACK_MAP_YARDS
end

local function IsSameNodeImportSpot(mapID, existing, x, y)
    local scaleX, scaleY = GetImportMapScales(mapID)
    local dx = (existing.x - x) * scaleX
    local dy = (existing.y - y) * scaleY
    return ((dx * dx) + (dy * dy)) <= (IMPORT_SAFETY_YARDS * IMPORT_SAFETY_YARDS)
end

-- ============================================================================
-- UNIVERSAL NODE TRANSLATOR (ERA & TBC)
-- Guarantees that node IDs are always translated to their real names.
-- EXACT CORRECTED MAPPING TO USER'S CUSTOM DATABASE
-- ============================================================================
addon.NODE_TRANSLATOR = addon.NODE_TRANSLATOR or {}
local MasterNodeDictionary = {
    -- Era Herbs
    [401]="Silverleaf", [402]="Peacebloom", [403]="Earthroot", [404]="Mageroyal", [405]="Briarthorn", 
    [407]="Stranglekelp", [408]="Bruiseweed", [410]="Wild Steelbloom", [411]="Kingsblood", 
    [412]="Liferoot", [413]="Goldthorn", [414]="Fadeleaf", [415]="Khadgar's Whisker", [416]="Wintersbite", 
    [417]="Firebloom", [418]="Purple Lotus", [420]="Arthas' Tears", [421]="Sungrass", [422]="Blindweed", 
    [423]="Ghost Mushroom", [424]="Gromsblood", [425]="Golden Sansam", [426]="Dreamfoil", [427]="Mountain Silversage", 
    [428]="Plaguebloom", [429]="Icecap", [431]="Black Lotus",
    
    -- TBC Herbs
    [432]="Felweed", [433]="Dreaming Glory", [434]="Terocone", [435]="Ragveil", 
    [437]="Mana Thistle", [438]="Netherbloom", [439]="Nightmare Vine", [440]="Flame Cap",
    
    -- Era Mining
    [201]="Copper Vein", [202]="Tin Vein", [203]="Iron Deposit", [204]="Silver Vein", 
    [205]="Gold Vein", [206]="Mithril Deposit", [208]="Truesilver Deposit", 
    [214]="Small Thorium Vein", [215]="Rich Thorium Vein", [217]="Dark Iron Deposit",
    
    -- TBC Mining
    [221]="Fel Iron Deposit", [222]="Adamantite Deposit", [223]="Rich Adamantite Deposit", 
    [224]="Khorium Vein"
}

for id, name in pairs(MasterNodeDictionary) do
    addon.NODE_TRANSLATOR[id] = name
    addon.NODE_TRANSLATOR[name] = name -- Allow string to string mapping
end

-- ============================================================================
-- ZONE ID TRANSLATOR
-- ============================================================================
local ZONE_TRANSLATOR = {
    -- Kalimdor
    [14] = 1411, [15] = 1412, [17] = 1413, [141] = 1438, [148] = 1439, [331] = 1440,
    [400] = 1441, [144] = 1442, [405] = 1443, [406] = 1444, [440] = 1445, [16] = 1446,
    [361] = 1447, [490] = 1448, [493] = 1449, [618] = 1450, [1377] = 1451,

    -- Eastern Kingdoms
    [12] = 1429, [10] = 1431, [11] = 1436, [36] = 1416, [47] = 1425, [85] = 1420,
    [130] = 1421, [139] = 1423, [28] = 1422, [8] = 1435, [33] = 1434, [41] = 1433,
    [4] = 1419, [38] = 1437, [40] = 1430, [44] = 1432, [1] = 1426, [51] = 1427,
    [46] = 1428, [267] = 1424, [45] = 1417, [3] = 1418,

    -- TBC Outland
    [3483] = 1944, [3521] = 1945, [3519] = 1946, [3518] = 1947, 
    [3522] = 1948, [3523] = 1949, [3520] = 1950,

    -- TBC Azeroth Additions
    [3430] = 1953, [3433] = 1952, [3524] = 1957, [3525] = 1958,
}

-- ============================================================================
-- CORE VISUAL REFRESH 
-- ============================================================================
function addon:RefreshAllVisuals()
    if self.drawConfig then self.drawConfig.heatEnabled = true end

    if WorldMapFrame and WorldMapFrame:IsShown() then
        if type(WorldMapFrame.RefreshAllDataProviders) == "function" then
            WorldMapFrame:RefreshAllDataProviders()
        elseif type(WorldMapFrame.OnMapChanged) == "function" then
            WorldMapFrame:OnMapChanged()
        elseif type(_G.WorldMapFrame_Update) == "function" then
            WorldMapFrame_Update()
        end
    end

    if self.MapFrame then
        if type(self.MapFrame.ManageOverlays) == "function" then self.MapFrame.ManageOverlays(true) end
        if type(self.MapFrame.UpdateCanvas) == "function" then self.MapFrame:UpdateCanvas() end
        if type(self.MapFrame.UpdateNodes) == "function" then self.MapFrame:UpdateNodes() end
        if type(self.MapFrame.Refresh) == "function" then self.MapFrame:Refresh() end
    end

    if self.Heatmap then
        if type(self.Heatmap.ForceUpdate) == "function" then self.Heatmap:ForceUpdate() end
        if type(self.Heatmap.RefreshAll) == "function" then self.Heatmap:RefreshAll() end
        if type(self.Heatmap.UpdateWorldMap) == "function" then self.Heatmap:UpdateWorldMap() end
    end
end

-- ============================================================================
-- INJECT NODE INTO DATABASE
-- ============================================================================
function addon:InjectNode(zoneID, coord, nodeType, nodeID)
    if not PathmakerDB then PathmakerDB = {} end
    if not PathmakerDB.nodes then PathmakerDB.nodes = {} end
    
    local mapID = tonumber(zoneID)
    if ZONE_TRANSLATOR[mapID] then mapID = ZONE_TRANSLATOR[mapID] end
    
    if not PathmakerDB.nodes[mapID] then PathmakerDB.nodes[mapID] = {} end

    local coordStr = tostring(coord)
    while #coordStr < 10 do coordStr = "0" .. coordStr end

    local xStr = string.sub(coordStr, 1, 4)
    local yStr = string.sub(coordStr, 5, 8)

    local x = tonumber(xStr) / 10000
    local y = tonumber(yStr) / 10000

    local trueName = addon.NODE_TRANSLATOR[nodeID] or nodeID
    local fallbackName = (nodeType == "Mining" and "Mining Node")
        or (nodeType == "Treasure" and "Treasure Node")
        or "Herb Node"
    local nodeName = (type(trueName) == "string" and trueName) or fallbackName

    for _, existing in ipairs(PathmakerDB.nodes[mapID]) do
        if (existing.id == trueName or existing.name == nodeName) and existing.x and existing.y then
            if IsSameNodeImportSpot(mapID, existing, x, y) then
                return 
            end
        end
    end

    table.insert(PathmakerDB.nodes[mapID], {
        x = x,
        y = y,
        id = trueName,
        type = nodeType,
        name = nodeName,
        source = "PathMaker_Nodes",
        verified = false,
    })
end

function addon:ClearDB(nodeType)
    if not PathmakerDB or not PathmakerDB.nodes then return end
    for mapID, nodes in pairs(PathmakerDB.nodes) do
        local newNodes = {}
        for _, node in ipairs(nodes) do
            if node.type ~= nodeType then
                table.insert(newNodes, node)
            end
        end
        PathmakerDB.nodes[mapID] = newNodes
    end
end

function addon:GetAllNodesForZone(zoneID)
    local allNodes = {}
    if not PathmakerDB or not PathmakerDB.importedNodes then return allNodes end
    for nType, zones in pairs(PathmakerDB.importedNodes) do
        if zones[zoneID] then
            for coord, nodeID in pairs(zones[zoneID]) do
                allNodes[coord] = { type = nType, id = nodeID }
            end
        end
    end
    return allNodes
end

-- ============================================================================
-- MANUAL CHAT COMMAND IMPORT (/pmimport)
-- ============================================================================
SLASH_PATHMAKERIMPORT1 = "/pmimport"
SlashCmdList["PATHMAKERIMPORT"] = function(msg)
    addon:PrintMessage("disableMsgNodeImport", "|cffffff00PathMaker:|r Attempting to load PathMaker_Nodes Addon Data...")
    
    if addon.Compat then addon.Compat:LoadAddOn("PathMaker_Nodes") end
    
    local PMNodes = _G["PathMakerNodes"] or _G["PathMaker_Nodes"]
    
    if PMNodes and PMNodes.ImportNodes then
        PMNodes:CaptureAll()
        
        local success = PMNodes:ImportNodes("All", nil)
        
        if success then
            addon:PrintMessage("disableMsgNodeImport", "|cff00ff00PathMaker:|r Import routine completed. Type /reload if nodes do not appear.")
            if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
        end
    else
        addon:PrintMessage("disableMsgError", "|cffff0000PathMaker:|r Node data module not found. Make sure PathMaker_Nodes addon is enabled!")
    end
end

-- ============================================================================
-- BUG FIXES: Unread Mail Bug
-- ============================================================================
local function CheckMail()
    if PathmakerDB and PathmakerDB.isEnabled == false then return end
    if MiniMapMailFrame and not HasNewMail() then MiniMapMailFrame:Hide() end
end

if MiniMapMailFrame then MiniMapMailFrame:HookScript("OnShow", CheckMail) end
addon.mailListener = CreateFrame("Frame")
addon.mailListener:SetScript("OnEvent", CheckMail)

function addon:ToggleMailEvents(shouldEnable)
    if shouldEnable then
        addon.mailListener:RegisterEvent("UPDATE_PENDING_MAIL")
        addon.mailListener:RegisterEvent("MAIL_INBOX_UPDATE")
        addon.mailListener:RegisterEvent("PLAYER_ENTERING_WORLD")
        addon.mailListener:RegisterEvent("MAIL_CLOSED")
        CheckMail()
    else
        addon.mailListener:UnregisterAllEvents()
    end
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================
SLASH_PATHMAKER1 = "/pm"
SLASH_PATHMAKER2 = "/pathmaker"
SlashCmdList["PATHMAKER"] = function(msg)
    local cmd, arg = msg:lower():match("^%s*(%w+)%s*(.*)")
    
    if cmd == "help" then SlashCmdList["PATHMAKERHELP"]("")
    elseif cmd == "filter" then SlashCmdList["PATHMAKERFILTER"]("")
    elseif cmd == "tools" then
        print("PathMaker: Import/export tools moved to /pmtoolimport and /pmtoolexport")
    elseif cmd == "settings" then SlashCmdList["PATHMAKERSETTINGS"]("")
    elseif cmd == "debug" then
        if addon.Debug then addon.Debug:HandleCommand(arg) end
    elseif cmd == "minimap" then
        if addon.MapFrame then
            local current = not PathmakerDB or not PathmakerDB.settings or PathmakerDB.settings.usePathmakerMinimap ~= false
            if arg ~= "" and arg ~= "on" and arg ~= "off" then
                print("PathMaker: /pm minimap [on|off] - change minimap UI without disabling route tools.")
                return
            end
            local enabled = not current
            if arg == "on" then enabled = true elseif arg == "off" then enabled = false end
            addon.MapFrame:SetMinimapEnabled(enabled)
        end
    elseif cmd == "controls" then
        SlashCmdList["PATHMAKERCONTROLS"]("")
    elseif cmd == "farm" then SlashCmdList["PATHMAKERFARM"]("")
    elseif cmd == "on" then SlashCmdList["PATHMAKERON"]("")
    elseif cmd == "off" then SlashCmdList["PATHMAKEROFF"]("")
    else
        if addon.MapFrame then addon.MapFrame:Toggle() end
    end
end

SLASH_PATHMAKERCONTROLS1 = "/pmcontrols"
SlashCmdList["PATHMAKERCONTROLS"] = function()
    if addon.MapFrame and PathmakerDB and PathmakerDB.isEnabled then
        addon.MapFrame:ShowStandaloneControls()
    else
        addon:PrintMessage("disableMsgError", "PathMaker: Enable the addon first (/pmon).")
    end
end

SLASH_PATHMAKERRESETCONTROLS1 = "/pmresetcontrols"
SlashCmdList["PATHMAKERRESETCONTROLS"] = function()
    if addon.MapFrame then
        addon.MapFrame:ResetStandaloneControls()
        addon:PrintMessage("disableMsgControls", "PathMaker: Controls window position and opacity reset.")
    end
end

SLASH_PATHMAKERMINIMAPON1 = "/pmminimapon"
SlashCmdList["PATHMAKERMINIMAPON"] = function()
    if addon.MapFrame then addon.MapFrame:SetMinimapEnabled(true) end
end

SLASH_PATHMAKERMINIMAPOFF1 = "/pmminimapoff"
SlashCmdList["PATHMAKERMINIMAPOFF"] = function()
    if addon.MapFrame then addon.MapFrame:SetMinimapEnabled(false) end
end

SLASH_PATHMAKERON1 = "/pmon"
SlashCmdList["PATHMAKERON"] = function()
    if addon.MapFrame then addon.MapFrame:Enable() end
end

SLASH_PATHMAKEROFF1 = "/pmoff"
SlashCmdList["PATHMAKEROFF"] = function()
    if addon.MapFrame then addon.MapFrame:Disable() end
end

SLASH_PATHMAKERFARM1 = "/pmfarm"
SlashCmdList["PATHMAKERFARM"] = function()
    if not addon.MapFrame then return end
    if not PathmakerDB.isEnabled then
        addon:PrintMessage("disableMsgError", "|cffff0000PathMaker:|r Cannot toggle Farm Mode. Addon is disabled. Use /pm first.")
        return
    end
    addon.MapFrame:ToggleFarmMode()
end

SLASH_PATHMAKERTOOLIMPORT1 = "/pmtoolimport"
SLASH_PATHMAKERTOOLIMPORT2 = "/PMTOOLIMPORT"
SLASH_PATHMAKERTOOLIMPORT3 = "/Pmtoolimport"
SLASH_PATHMAKERTOOLIMPORT4 = "/PmToolImport"
SlashCmdList["PATHMAKERTOOLIMPORT"] = function()
    if addon.ImportExport then addon.ImportExport:ShowImport() end
end

SLASH_PATHMAKERTOOLEXPORT1 = "/pmtoolexport"
SLASH_PATHMAKERTOOLEXPORT2 = "/PMTOOLEXPORT"
SLASH_PATHMAKERTOOLEXPORT3 = "/Pmtoolexport"
SLASH_PATHMAKERTOOLEXPORT4 = "/PmToolExport"
SlashCmdList["PATHMAKERTOOLEXPORT"] = function()
    if addon.ImportExport then
        addon.ImportExport:ShowExport(addon.selectedRouteGUID, addon.selectedRouteMapID)
    end
end

SLASH_PATHMAKERSETTINGS1 = "/pmsettings"
SlashCmdList["PATHMAKERSETTINGS"] = function()
    if addon.MapFrame then addon.MapFrame:ToggleSettings() end
end

SLASH_PATHMAKERFILTER1 = "/pmfilter"
SlashCmdList["PATHMAKERFILTER"] = function()
    if addon.MapFrame then
        if not PathmakerDB.isEnabled then
            addon:PrintMessage("disableMsgError", "|cffff0000PathMaker:|r Enable addon first to use the filter (/pm).")
            return
        end
        addon.MapFrame:ToggleNodeFilter()
    end
end

SLASH_PATHMAKERHELP1 = "/pmhelp"
SlashCmdList["PATHMAKERHELP"] = function()
    print("|cff00ff00PathMaker:|r Command List:")
    print("  |cffFFFF00/pm|r or |cffFFFF00/pathmaker|r - Toggle Addon On/Off")
    print("  |cffFFFF00/pm help|r or |cffFFFF00/pmhelp|r - Show this help list")
    print("  |cffFFFF00/pm filter|r or |cffFFFF00/pmfilter|r - Toggle the Node Filter")
    print("  |cffFFFF00/pm farm|r or |cffFFFF00/pmfarm|r - Toggle Farm Mode")
    print("  |cffFFFF00/pm settings|r or |cffFFFF00/pmsettings|r - Open Settings")
    print("  |cffFFFF00/pm minimap [on|off]|r - Toggle only the custom minimap; keep route tools active")
    print("  |cffFFFF00/pm controls|r or |cffFFFF00/pmcontrols|r - Show the standalone route controls")
    print("  |cffFFFF00/pmresetcontrols|r - Reset controls window position and opacity")
    print("  |cffFFFF00/pmminimapon|r / |cffFFFF00/pmminimapoff|r - Turn the custom minimap on/off")
    print("  |cffFFFF00/pmtoolimport|r - Open Route Import")
    print("  |cffFFFF00/pmtoolexport|r - Export the selected Route")
    print("  |cffFFFF00/pmdebug [copy|route]|r - Show compact support diagnostics")
end
-- =====================================================
-- NAVIGATION SYSTEM BOOT
-- =====================================================

C_Timer.After(1, function()
    if addon.Navigation and addon.Navigation.CreateArrow then
        addon.Navigation:CreateArrow()
    end
end)
