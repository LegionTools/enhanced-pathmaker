local addonName, addon = ...

addon.Debug = addon.Debug or {}
local Debug = addon.Debug

local function OnOff(value)
    return value and "Enabled" or "Disabled"
end

local function GetMetadata(field)
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or _G.GetAddOnMetadata
    if not getter then return "Unknown" end
    return getter(addonName, field) or "Unknown"
end

local function GetClientLabel()
    if addon.Compat and addon.Compat.isTBC then return "TBC Anniversary" end
    if addon.Compat and addon.Compat.isClassicEra then return "Classic Era" end
    if addon.Compat and addon.Compat.isRetail then return "Retail" end
    return addon.Compat and addon.Compat.flavor or "Unknown"
end

local function GetPlayerMap()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return mapID, info and info.name or "Unknown"
end

local function GetSelectedRoute()
    if not addon.selectedRouteGUID or not PathmakerDB or not PathmakerDB.routes then return nil, nil end
    local mapID = addon.Routes and addon.Routes.GetRouteMapID
        and addon.Routes:GetRouteMapID(addon.selectedRouteGUID, addon.selectedRouteMapID)
    local route = mapID and PathmakerDB.routes[mapID] and PathmakerDB.routes[mapID][addon.selectedRouteGUID]
    return mapID, route
end

local function CountTableEntries(value)
    if type(value) ~= "table" then return nil end
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
end

local function GetRecordedErrorCount()
    local frame = _G.ScriptErrorsFrame
    if frame then
        local count = CountTableEntries(frame.errors or frame.errorList)
        if count ~= nil then return tostring(count) end
    end
    local bugGrabber = _G.BugGrabberDB
    if type(bugGrabber) == "table" then
        local count = CountTableEntries(bugGrabber.session or bugGrabber.errors)
        if count ~= nil then return tostring(count) end
    end
    local swatter = _G.SwatterData
    if type(swatter) == "table" then
        local count = CountTableEntries(swatter.errors)
        if count ~= nil then return tostring(count) end
    end
    return "Unavailable (no error collector)"
end

local function NodesLoaded()
    local checker = C_AddOns and C_AddOns.IsAddOnLoaded or _G.IsAddOnLoaded
    if checker then return not not checker("PathMaker_Nodes") end
    return _G.PathMakerNodes ~= nil or _G.PathMaker_Nodes ~= nil
end

local function Add(lines, label, value)
    lines[#lines + 1] = label .. ": " .. tostring(value)
end

local function GetNavigationDebugState(route, mapID)
    if addon.Navigation and addon.Navigation.GetDebugState then
        local ok, state = pcall(addon.Navigation.GetDebugState, addon.Navigation, route, mapID)
        if ok and type(state) == "table" then return state end
    end
    return {}
end

function Debug:BuildSummary()
    local lines = {"PathMaker Debug Info"}
    local _, build, _, interfaceVersion = GetBuildInfo()
    local playerMapID, zoneName = GetPlayerMap()
    local routeMapID, route = GetSelectedRoute()
    local settings = PathmakerDB and PathmakerDB.settings or {}
    local nav = GetNavigationDebugState(route, routeMapID)

    Add(lines, "Version", GetMetadata("Version"))
    Add(lines, "WoW Version", GetClientLabel())
    Add(lines, "Build", build or "Unknown")
    Add(lines, "Interface", tonumber(interfaceVersion) or (addon.Compat and addon.Compat.interfaceVersion) or "Unknown")
    Add(lines, "Zone", zoneName .. (playerMapID and (" (" .. playerMapID .. ")") or ""))
    lines[#lines + 1] = ""
    Add(lines, "Active Route", route and (route.name or "Unnamed Route") or "None")
    Add(lines, "Route Points", route and route.points and #route.points or 0)
    Add(lines, "Current Route Index", nav.currentPointIndex or "Not tracking")
    Add(lines, "Route Direction", nav.direction and (nav.direction > 0 and "Forward" or "Reverse") or "Not tracking")
    lines[#lines + 1] = ""
    Add(lines, "PathMaker", OnOff(PathmakerDB and PathmakerDB.isEnabled == true))
    Add(lines, "Farm Mode", OnOff(addon.isFarmMode == true))
    Add(lines, "Custom Minimap", OnOff(settings.usePathmakerMinimap ~= false))
    Add(lines, "Navigation", OnOff(addon.Navigation and addon.Navigation.enabled == true))
    Add(lines, "PathMaker Nodes", NodesLoaded() and "Loaded" or "Not loaded")
    lines[#lines + 1] = ""
    Add(lines, "Recorded Lua Errors", GetRecordedErrorCount())
    local errors = addon.Compat and addon.Compat.updateErrors or {}
    local labels = {}
    for label in pairs(errors) do labels[#labels + 1] = label end
    table.sort(labels)
    for _, label in ipairs(labels) do
        lines[#lines + 1] = ""
        Add(lines, "Paused updates", label)
        lines[#lines + 1] = errors[label]
    end
    return lines
end

function Debug:BuildRouteDetails()
    local lines = {"PathMaker Route Debug Info"}
    local mapID, route = GetSelectedRoute()
    if not route then
        lines[#lines + 1] = "Route: None selected"
        return lines
    end
    local nav = GetNavigationDebugState(route, mapID)
    local segment = nav.closestSegment
    local direction = nav.direction and (nav.direction > 0 and "Forward" or "Reverse") or "Not tracking"
    Add(lines, "Route", route.name or "Unnamed Route")
    Add(lines, "Map ID", mapID or "Unknown")
    Add(lines, "Points", route.points and #route.points or 0)
    Add(lines, "Current Point", nav.currentPointIndex or "Not tracking")
    Add(lines, "Direction", direction)
    Add(lines, "Distance to Route", nav.distanceToRoute and (string.format("%.0f yd", nav.distanceToRoute)) or "Unavailable")
    Add(lines, "Closest Segment", segment and (segment .. " -> " .. ((segment % #route.points) + 1)) or "Unavailable")
    Add(lines, "Navigation Target", nav.targetIndex or "Not tracking")
    Add(lines, "Route Style", route.routeStyle or "Manual/Legacy")
    Add(lines, "Node Density", route.nodeDensity or "Manual/Legacy")
    local avoidCount = PathmakerDB and PathmakerDB.avoidAreas and PathmakerDB.avoidAreas[mapID]
    Add(lines, "Avoid Areas", type(avoidCount) == "table" and #avoidCount or 0)
    return lines
end

function Debug:Print(lines)
    for index, line in ipairs(lines) do
        if index == 1 then print("|cff44ff44" .. line .. "|r") else print(line) end
    end
end

function Debug:ShowCopyBox(lines)
    if not self.copyFrame then
        local frame = CreateFrame("Frame", "PathMakerDebugCopyFrame", UIParent, "BackdropTemplate")
        frame:SetSize(520, 390)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:SetMovable(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24, insets={left=7,right=7,top=7,bottom=7}})

        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("PathMaker Debug Info - Press Ctrl+C")

        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 20, -48)
        scroll:SetPoint("BOTTOMRIGHT", -38, 48)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject("ChatFontNormal")
        edit:SetWidth(445)
        edit:SetTextInsets(4, 4, 4, 4)
        edit:SetScript("OnEscapePressed", function() frame:Hide() end)
        edit:SetScript("OnTextChanged", function(self)
            local _, newlineCount = (self:GetText() or ""):gsub("\n", "\n")
            self:SetHeight(math.max(280, (newlineCount + 1) * 16 + 12))
            if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        end)
        scroll:SetScrollChild(edit)
        frame.editBox = edit

        local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        close:SetSize(90, 24)
        close:SetPoint("BOTTOM", 0, 16)
        close:SetText("Close")
        close:SetScript("OnClick", function() frame:Hide() end)
        self.copyFrame = frame
    end
    self.copyFrame.editBox:SetText(table.concat(lines, "\n"))
    self.copyFrame:Show()
    self.copyFrame:Raise()
    self.copyFrame.editBox:SetFocus()
    self.copyFrame.editBox:HighlightText()
end

function Debug:HandleCommand(message)
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "copy" then
        self:ShowCopyBox(self:BuildSummary())
    elseif command == "route" then
        self:Print(self:BuildRouteDetails())
    elseif command == "" then
        self:Print(self:BuildSummary())
    else
        print("PathMaker: /pmdebug [copy|route]")
    end
end

SLASH_PATHMAKERDEBUG1 = "/pmdebug"
SlashCmdList["PATHMAKERDEBUG"] = function(message) Debug:HandleCommand(message) end
