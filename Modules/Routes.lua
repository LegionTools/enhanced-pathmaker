local addonName, addon = ...
if not addon.Routes then addon.Routes = {} end

addon.Routes.isRecording = false 
addon.Routes.isEditing = false 

local currentRouteGUID = nil
local recordingMapID = nil 
local lastWorldPos = nil 
local forceGap = false 
local recordTimer = 0 

local function GetPlayerMapPosition(mapID)
    if addon.Compat and addon.Compat.GetUnitMapPosition then
        return addon.Compat:GetUnitMapPosition(mapID, "player")
    end
    return mapID and C_Map.GetPlayerMapPosition(mapID, "player") or nil
end

-- ----------------------------------------------------------------------------
-- MESSAGE HELPERS
-- ----------------------------------------------------------------------------
local function printMsg(msg)
    local hide = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgRecording
    if not hide then print(msg) end
end

local function printErr(msg)
    local hide = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
    if not hide then print(msg) end
end

-- 24 Unique Colors Palette
addon.Routes.Palette = {
    {1, 0, 0, 1}, {0, 0, 1, 1}, {0, 1, 0, 1}, {1, 1, 0, 1}, {1, 0, 1, 1},
    {0, 1, 1, 1}, {1, 0.5, 0, 1}, {0.5, 0, 1, 1}, {0, 0.5, 0, 1}, {0.5, 0, 0, 1},
    {0, 0, 0.5, 1}, {0.5, 0.5, 0.5, 1}, {1, 1, 1, 1}, {1, 0.4, 0.7, 1}, {0.2, 1, 0.5, 1},
    {0.5, 0.2, 0, 1}, {0.5, 0.8, 1, 1}, {1, 0.8, 0.5, 1}, {0.7, 0, 0.3, 1}, {0.3, 0.3, 0.3, 1},
    {0.8, 1, 0, 1}, {0, 0.5, 0.5, 1}, {0.6, 0.4, 0.8, 1}, {0.8, 0.4, 0, 1}, {0.9, 0.9, 0.7, 1}
}

function addon.Routes:IsRouteData(route)
    if type(route) ~= "table" then return false end
    return type(route.points) == "table" or type(route.route) == "table" or type(route.nodes) == "table"
end

function addon.Routes:GetRecordingMapID()
    return self.isRecording and recordingMapID or nil
end

function addon.Routes:GetRouteMapID(guid, preferredMapID)
    if not guid or not PathmakerDB or not PathmakerDB.routes then return nil end
    if preferredMapID and PathmakerDB.routes[preferredMapID]
        and PathmakerDB.routes[preferredMapID][guid]
    then
        return preferredMapID
    end
    for mapID, routes in pairs(PathmakerDB.routes) do
        if routes and routes[guid] then return mapID end
    end
    return nil
end

function addon.Routes:ColorsMatch(c1, c2)
    if type(c1) ~= "table" or type(c2) ~= "table" then return false end
    local tol = 0.01
    return math.abs(c1[1]-c2[1]) < tol and math.abs(c1[2]-c2[2]) < tol and math.abs(c1[3]-c2[3]) < tol
end

function addon.Routes:GetNextAvailableColor(mapID)
    if not PathmakerDB.routes or not PathmakerDB.routes[mapID] then return self.Palette[1] end
    local count = 0
    for _ in pairs(PathmakerDB.routes[mapID]) do count = count + 1 end
    if count >= 24 then return nil end 
    for _, pColor in ipairs(self.Palette) do
        local taken = false
        for _, route in pairs(PathmakerDB.routes[mapID]) do
            if self:IsRouteData(route) and self:ColorsMatch(route.color, pColor) then 
                taken = true
                break
            end
        end
        if not taken then return pColor end
    end
    return nil
end

function addon.Routes:FindClosestPoint(route)
    local mapID = self:GetRouteMapID(addon.selectedRouteGUID, addon.selectedRouteMapID)
        or C_Map.GetBestMapForUnit("player")
    local pos = GetPlayerMapPosition(mapID)
    if not pos then return nil end
    local px, py = pos.x, pos.y
    local scaleX, scaleY = route and route.mapScaleX, route and route.mapScaleY
    if (not scaleX or not scaleY) and addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
    end
    local calibration = PathmakerDB and PathmakerDB.calibration and PathmakerDB.calibration[mapID]
    if type(calibration) == "table" then
        scaleX, scaleY = scaleX or calibration.x, scaleY or calibration.y
    end
    scaleX, scaleY = scaleX or 6000, scaleY or 6000
    local closestIndex = nil
    local closestDist = 999999
    if not route.points then return nil end
    for i, p in ipairs(route.points) do
        local dx = (px - p.x) * scaleX
        local dy = (py - p.y) * scaleY
        local d = math.sqrt((dx * dx) + (dy * dy))
        if d < closestDist then closestDist = d; closestIndex = i end
    end
    return closestIndex
end

function addon.Routes:FollowRouteByColor(targetColor)
    local mapID = C_Map.GetBestMapForUnit("player")
    if not PathmakerDB.routes or not PathmakerDB.routes[mapID] then return end
    for guid, route in pairs(PathmakerDB.routes[mapID]) do
        if self:IsRouteData(route) and route.color and targetColor and self:ColorsMatch(route.color, targetColor) then
            local idx = self:FindClosestPoint(route)
            if idx then
                addon.selectedRouteGUID = guid
                addon.selectedRouteMapID = mapID
                if addon.Navigation then if addon.Navigation then
    if addon.Navigation.CreateArrow then
        addon.Navigation:CreateArrow()
    end

    if addon.arrowFrame then
        addon.arrowFrame:Show()
    end

    if addon.Navigation.Toggle then
        addon.Navigation:Toggle()
    end
end end
                if addon.MapFrame and addon.MapFrame.RefreshTactical then addon.MapFrame:RefreshTactical() end
                if addon.UI then addon.UI:RefreshRendering() end
                printMsg("Pathmaker: Following Route (" .. (route.name or "Unnamed") .. ")")
                return
            end
        end
    end
    printErr("Pathmaker: No route found with that color.")
end

function addon.Routes:ReverseCurrentRoute()
    local mapID = self:GetRouteMapID(addon.selectedRouteGUID, addon.selectedRouteMapID)
        or C_Map.GetBestMapForUnit("player")
    if not mapID or not addon.selectedRouteGUID then 
        printErr("Pathmaker: No route selected to reverse.")
        return 
    end
    
    local route = PathmakerDB.routes[mapID][addon.selectedRouteGUID]
    if not route or not route.points or #route.points == 0 then return end
    
    -- FIXED: Robust Reversal that preserves Markers and Timers
    local points = route.points
    local n = #points
    local newPoints = {}
    
    -- 1. Create a reversed copy of points
    -- We MUST copy all data (isMarker, duration, name) to preserve markers
    for i = n, 1, -1 do
        local p = points[i]
        local newP = {
            x = p.x, 
            y = p.y, 
            isGap = false, -- Will be set in step 2
            
            -- Preserve Marker Data
            isMarker = p.isMarker,
            duration = p.duration,
            name = p.name
        }
        table.insert(newPoints, newP)
    end
    
    -- 2. Map gaps correctly
    -- If there was a gap at 'i' (meaning break between point i and i+1),
    -- in the reversed list, the break should be between point (n-i) and (n-i)+1.
    for i = 1, n - 1 do
        if points[i].isGap then
            local newIdx = n - i
            if newPoints[newIdx] then
                newPoints[newIdx].isGap = true
            end
        end
    end
    
    route.points = newPoints
    route.isReversed = not route.isReversed
    
    if addon.UI then addon.UI:RefreshRendering() end
    if addon.MapFrame and addon.MapFrame.RefreshTactical then addon.MapFrame:RefreshTactical() end
end

function addon.Routes:ToggleRecording()
    if self.isRecording then self:StopRecording() else self:StartRecording() end
end

function addon.Routes:StartRecording(existingGUID)
    if self.isRecording then return end
    local mapID = existingGUID and self:GetRouteMapID(existingGUID, addon.selectedRouteMapID)
        or C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    
    recordingMapID = mapID
    
    if existingGUID then
        -- EDIT MODE
        if not PathmakerDB.routes[mapID] or not PathmakerDB.routes[mapID][existingGUID] then
            printErr("Pathmaker Error: Route not found.")
            return
        end
        
        currentRouteGUID = existingGUID
        local route = PathmakerDB.routes[mapID][existingGUID]
        
        -- DISTANCE LOGIC CHECK
        if addon.UI and addon.UI.yardsPerCoord and route.points and #route.points > 1 then
            local mapPos = GetPlayerMapPosition(mapID)
            if not mapPos then
                printErr("|cffff0000Pathmaker:|r Player position is unavailable on this map.")
                return
            end
            local startP = route.points[1]
            local endP = route.points[#route.points]
            
            -- Calculate Distances in Yards
            local distStart = math.sqrt((mapPos.x - startP.x)^2 + (mapPos.y - startP.y)^2) * addon.UI.yardsPerCoord
            local distEnd = math.sqrt((mapPos.x - endP.x)^2 + (mapPos.y - endP.y)^2) * addon.UI.yardsPerCoord
            
            local tooCloseThreshold = 10 -- 0-10 Yards
            
            -- RULE 1: If TOO CLOSE (<= 10y) -> BLOCK EDITING
            if distStart <= tooCloseThreshold or distEnd <= tooCloseThreshold then
                printErr("|cffff0000Pathmaker:|r Too close to start/end point (< 10y). Move further to edit.")
                return -- EXIT FUNCTION, DO NOT START RECORDING
            end
            
            -- RULE 2: If > 10y -> ALLOW EDITING
            self.isEditing = true
            
            if distStart < distEnd then
                -- Closer to START: Reverse so we append to "new end"
                self:ReverseCurrentRoute()
                printMsg("|cff00ff00Pathmaker:|r Editing from Start (Reversed). (> 10y)")
            else
                -- Closer to END
                printMsg("|cff00ff00Pathmaker:|r Editing from End. (> 10y)")
            end
            
            -- Force a GAP (Jump) initially because we are > 10 yards away
            forceGap = true 
        else
             -- Fallback if no calibration (unlikely)
             self.isEditing = true
             forceGap = true 
        end
        
        -- Disable Navigation Arrow when editing
        if addon.Navigation then addon.Navigation:HideArrow() end
        
    else
        -- NEW RECORDING MODE
        local color = self:GetNextAvailableColor(mapID)
        if not color then
            printErr("|cffff0000Pathmaker Error:|r This zone has reached the limit of 24 routes.")
            return
        end
        
        local guid = "Route_" .. date("%Y%m%d%H%M%S")
        if not PathmakerDB.routes then PathmakerDB.routes = {} end
        if not PathmakerDB.routes[mapID] then PathmakerDB.routes[mapID] = {} end
        
        PathmakerDB.routes[mapID][guid] = {
            name = "New Route",
            color = color,
            thickness = 2,
            visible = true,
            connectPaths = false,
            isReversed = false,
            points = {}
        }
        currentRouteGUID = guid
        forceGap = false 
        self.isEditing = false
        printMsg("|cff00ff00Pathmaker:|r Recording Started...")
    end
    
    self.isRecording = true
    lastWorldPos = nil 
    
    if addon.UI and addon.UI.Initialize then addon.UI:Initialize() end
    
    self.frame = self.frame or CreateFrame("Frame")
    addon.Compat:SetGuardedUpdate(self.frame, "Route recording", function(self, elapsed) addon.Routes:OnUpdate(elapsed) end)
end

function addon.Routes:StopRecording()
    if not self.isRecording then return end

    -- WHEN STOPPING EDIT: We connect the path
    if self.isEditing and currentRouteGUID and recordingMapID then
        local route = PathmakerDB.routes[recordingMapID][currentRouteGUID]
        
        -- Since we forced a gap at start (>10y), the user has drawn a new line segment.
        -- When stopping, we just let it be. The user effectively extended the route 
        -- from a distance.
        -- If they want to close a loop, they would have walked back to the start.
        
        printMsg("|cff00ff00Pathmaker:|r Editing Finished. Path extended.")
    end

    self.isRecording = false
    self.isEditing = false
    currentRouteGUID = nil
    recordingMapID = nil
    forceGap = false
    if self.frame then self.frame:SetScript("OnUpdate", nil) end
    printMsg("|cffff0000Pathmaker:|r Stopped.")
    
    if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
    if addon.UI then addon.UI:RefreshRendering() end
end

function addon.Routes:OnUpdate(elapsed)
    if not self.isRecording or not recordingMapID then return end
    recordTimer = recordTimer + elapsed
    if recordTimer < 0.1 then return end 
    recordTimer = 0

    local y, x, _, instanceID = UnitPosition("player")
    if not x or not y then return end
    
    local mapPos = GetPlayerMapPosition(recordingMapID)
    if not mapPos then return end
    
    if not lastWorldPos then
        lastWorldPos = {x=x, y=y, instanceID=instanceID}
        self:AddPoint(recordingMapID, mapPos)
        return
    end

    -- Indoor portals and some cave/city boundaries can change the world-space
    -- coordinate system. Never join positions from two instances with one long
    -- diagonal trace; begin a fresh segment in the same route instead.
    if lastWorldPos.instanceID ~= instanceID then
        forceGap = true
        self:AddPoint(recordingMapID, mapPos)
        lastWorldPos = {x=x, y=y, instanceID=instanceID}
        return
    end
    
    local distYards = math.sqrt((x - lastWorldPos.x)^2 + (y - lastWorldPos.y)^2)
    
    if distYards >= 5 then 
        self:AddPoint(recordingMapID, mapPos)
        if addon.UI then
             local route = PathmakerDB.routes[recordingMapID][currentRouteGUID]
             local pts = route.points
             local prev = pts[#pts-1]
             if #pts >= 2 and prev and not prev.isGap then
                addon.UI:AddLine(prev.x, prev.y, mapPos.x, mapPos.y, route.color, 2)
             end
        end
        lastWorldPos = {x=x, y=y, instanceID=instanceID}
    end
end

function addon.Routes:AddPoint(mapID, pos)
    if not currentRouteGUID or not PathmakerDB.routes[mapID] then return end
    local route = PathmakerDB.routes[mapID][currentRouteGUID]
    if not route then self:StopRecording() return end
    
    local newPoint = {x = pos.x, y = pos.y}

    -- isGap describes the edge from a point to the following point, so the
    -- existing tail (not the new point) owns a requested break.
    if forceGap then
        local previousPoint = route.points[#route.points]
        if previousPoint then previousPoint.isGap = true end
        forceGap = false
    end
    
    table.insert(route.points, newPoint)
end

-- Keep every route editor synchronized when a color is changed from any route
-- list or from inside either Draw Mode. Editors only update their local draft;
-- the caller remains responsible for saving the route before notifying them.
function addon.Routes:NotifyRouteColorChanged(guid, mapID, color)
    if not guid or type(color) ~= "table" then return end
    if addon.Planner and addon.Planner.OnRouteColorChanged then
        addon.Planner:OnRouteColorChanged(guid, mapID, color)
    end
    local optionsPanel = addon.Options and addon.Options.panel
    if optionsPanel and optionsPanel.SyncOptionsDrawModeRouteColor then
        optionsPanel.SyncOptionsDrawModeRouteColor(guid, mapID, color)
    end
end
