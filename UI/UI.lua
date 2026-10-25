local addonName, addon = ...
addon.UI = {}

local linePool = {}
local activeLines = {} 
local activeMarkerLines = {}
local activeMarkerChains = {}
local canvas

-- CALIBRATION STATE
local currentMapID = nil
local lastCalibPos = nil
local smoothedMapID = nil
local smoothedPlayerX = nil
local smoothedPlayerY = nil
local smoothedFacing = nil
local smoothedFrameTime = nil
local markerInteractionTimer = 0
local calibrationTimer = 0
local markerColorTimer = 0
local lastRenderMapID = nil
local lastRenderX = nil
local lastRenderY = nil
local lastRenderFacing = nil
local lastRenderRadius = nil
local lastRenderWidth = nil
local lastRenderHeight = nil
local lastRenderShape = nil
local renderedRouteMapID = nil
local renderedRoutePlayerX = nil
local renderedRoutePlayerY = nil
local renderedRouteRadius = nil
local hasRenderedRoutes = false
local MARKER_INTERACTION_INTERVAL = 0.10
local MARKER_COLOR_INTERVAL = 0.10
local CALIBRATION_INTERVAL = 0.25
local ROUTE_RENDER_INTERVAL = 1 / 60
local ROUTE_SEGMENT_CACHE_MARGIN_YARDS = 60
local ROUTE_SEGMENT_REBUILD_DISTANCE_YARDS = 24
local mapWorldScaleCache = {}
local stableDisplayPositionState = {}

-- EXPOSED for Routes.lua and MapFrame.lua
addon.UI.scaleX = nil 
addon.UI.scaleY = nil 
local isCalibrated = false   

-- MINIMAP ZOOM CONSTANTS
local ZOOM_RANGES = {
    [0] = 230, [1] = 190, [2] = 150, [3] = 110, [4] = 80, [5] = 50,
}

local function ReadVectorXY(vector)
    if not vector then return nil, nil end
    if vector.GetXY then return vector:GetXY() end
    return vector.x, vector.y
end

function addon.UI:GetMapWorldScale(mapID)
    if not mapID then return nil, nil end
    local cached = mapWorldScaleCache[mapID]
    if cached then return cached.x, cached.y end

    local width, height
    if C_Map and C_Map.GetMapWorldSize then
        local ok, first, second = pcall(C_Map.GetMapWorldSize, mapID)
        if ok then
            if type(first) == "number" and type(second) == "number" then
                width, height = first, second
            elseif first then
                width, height = ReadVectorXY(first)
            end
        end
    end

    -- Retail exposes world positions even where GetMapWorldSize is absent.
    -- Measuring the two normalized map axes also handles non-square zones.
    if (not width or not height or width <= 0 or height <= 0)
        and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D
    then
        local ok0, _, origin = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 0))
        local okX, _, xEdge = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(1, 0))
        local okY, _, yEdge = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0, 1))
        if ok0 and okX and okY and origin and xEdge and yEdge then
            local ox, oy = ReadVectorXY(origin)
            local xx, xy = ReadVectorXY(xEdge)
            local yx, yy = ReadVectorXY(yEdge)
            if ox and oy and xx and xy and yx and yy then
                width = math.sqrt(((xx - ox) ^ 2) + ((xy - oy) ^ 2))
                height = math.sqrt(((yx - ox) ^ 2) + ((yy - oy) ^ 2))
            end
        end
    end

    if width and height and width > 100 and height > 100 then
        mapWorldScaleCache[mapID] = { x = width, y = height }
        return width, height
    end
    return nil, nil
end

function addon.UI:GetMinimapViewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, yards = pcall(C_Minimap.GetViewRadius)
        yards = ok and tonumber(yards) or nil
        if yards and yards > 0 then return yards end
    end
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    return ZOOM_RANGES[zoom] or 100
end

local function SnapCanvasPixel(value, frame)
    if not value then return value end
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    if (not scale or scale <= 0) and UIParent and UIParent.GetEffectiveScale then
        scale = UIParent:GetEffectiveScale()
    end
    if scale and scale > 0 then
        return math.floor((value * scale) + 0.5) / scale
    end
    return math.floor(value + 0.5)
end

local function SmoothValue(current, target, elapsed, speed)
    if current == nil then return target end
    local factor = 1 - math.exp(-(speed or 18) * math.max(elapsed or 0, 0))
    return current + ((target - current) * factor)
end

local function SmoothAngle(current, target, elapsed, speed)
    if current == nil then return target end
    local delta = math.atan2(math.sin(target - current), math.cos(target - current))
    local factor = 1 - math.exp(-(speed or 22) * math.max(elapsed or 0, 0))
    return current + (delta * factor)
end

local function GetSmoothedRenderState(mapID, rawPos, elapsed)
    if not mapID or not rawPos then return rawPos, GetPlayerFacing and GetPlayerFacing() or 0 end
    if addon.Compat and addon.Compat.isRetail then
        return rawPos, GetPlayerFacing and GetPlayerFacing() or 0
    end

    local now = GetTime and GetTime() or 0
    local dt = elapsed
    if not dt and smoothedFrameTime then dt = now - smoothedFrameTime end
    smoothedFrameTime = now
    dt = math.max(0, math.min(dt or 0, 0.05))

    local reset = smoothedMapID ~= mapID or not smoothedPlayerX or not smoothedPlayerY
    local jump = false
    if not reset then
        local dx = rawPos.x - smoothedPlayerX
        local dy = rawPos.y - smoothedPlayerY
        jump = ((dx * dx) + (dy * dy)) > 0.0004
    end

    if reset or jump then
        smoothedMapID = mapID
        smoothedPlayerX = rawPos.x
        smoothedPlayerY = rawPos.y
    else
        smoothedPlayerX = SmoothValue(smoothedPlayerX, rawPos.x, dt, 24)
        smoothedPlayerY = SmoothValue(smoothedPlayerY, rawPos.y, dt, 24)
    end

    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    smoothedFacing = SmoothAngle(smoothedFacing, facing, dt, 28)
    return { x = smoothedPlayerX, y = smoothedPlayerY }, smoothedFacing or facing
end

local function GetDisplayMapAndPosition()
    local mapID, pos, moving
    if addon.Routes and addon.Routes.GetRecordingMapID then
        mapID = addon.Routes:GetRecordingMapID()
    end
    if not mapID and addon.selectedRouteGUID and addon.Routes and addon.Routes.GetRouteMapID then
        mapID = addon.Routes:GetRouteMapID(addon.selectedRouteGUID, addon.selectedRouteMapID)
    end
    local playerMapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        if addon.Compat and addon.Compat.GetStableUnitMapPosition then
            pos, moving = addon.Compat:GetStableUnitMapPosition(mapID, "player", stableDisplayPositionState)
        elseif addon.Compat and addon.Compat.GetUnitMapPosition then
            pos, moving = addon.Compat:GetUnitMapPosition(mapID, "player"), true
        else
            pos, moving = C_Map.GetPlayerMapPosition(mapID, "player"), true
        end
        if pos then
            return mapID, pos, moving
        end
        if addon.Routes and addon.Routes:GetRecordingMapID() then
            return mapID, nil, false
        end
    end

    mapID = playerMapID
    if not mapID then return nil, nil end
    if addon.Compat and addon.Compat.GetStableUnitMapPosition then
        pos, moving = addon.Compat:GetStableUnitMapPosition(mapID, "player", stableDisplayPositionState)
    elseif addon.Compat and addon.Compat.GetUnitMapPosition then
        pos, moving = addon.Compat:GetUnitMapPosition(mapID, "player"), true
    else
        pos, moving = C_Map.GetPlayerMapPosition(mapID, "player"), true
    end
    return mapID, pos, moving
end

function addon.UI:Initialize()
    if canvas then return end
    
    -- PARENT TO MINIMAP
    canvas = CreateFrame("Frame", "PathmakerCanvas", Minimap)
    canvas:SetAllPoints(Minimap)
    
    -- [FIX] Drop to FrameLevel + 1 so we are just above the map terrain 
    -- but solidly underneath the default WoW tracking blips/icons.
    canvas:SetFrameLevel(Minimap:GetFrameLevel() + 1) 
    canvas:SetClipsChildren(true)
    
    addon.Compat:SetGuardedUpdate(canvas, "Minimap route", function(self, elapsed)
        addon.UI:OnUpdate(elapsed)
    end)
end

function addon.UI:ClearLines()
    -- AcquireLine removes from the end of the pool. Pool in reverse so each
    -- route segment receives the same Line region after a rebuild; otherwise
    -- active/ghost draw order flips back and forth at overlaps.
    for index = #activeLines, 1, -1 do
        local line = activeLines[index]
        line:Hide()
        table.insert(linePool, line) 
    end
    activeLines = {}
    activeMarkerLines = {}
    activeMarkerChains = {}
    lastRenderMapID = nil
    hasRenderedRoutes = false
end

function addon.UI:Calibrate(elapsed)
    local mapID = GetDisplayMapAndPosition()
    if not mapID then return end
    
    if mapID ~= currentMapID then
        currentMapID = mapID
        self:ClearLines() 
        
        local loaded = false
        local worldScaleX, worldScaleY = self:GetMapWorldScale(mapID)
        if worldScaleX and worldScaleY then
            addon.UI.scaleX = worldScaleX
            addon.UI.scaleY = worldScaleY
            isCalibrated = true
            loaded = true
            if PathmakerDB then
                PathmakerDB.calibration = PathmakerDB.calibration or {}
                PathmakerDB.calibration[mapID] = { x = worldScaleX, y = worldScaleY }
            end
        elseif PathmakerDB and PathmakerDB.calibration and PathmakerDB.calibration[mapID] then
            local cal = PathmakerDB.calibration[mapID]
            if type(cal) == "table" and cal.x and cal.y then
                addon.UI.scaleX = cal.x
                addon.UI.scaleY = cal.y
                isCalibrated = true
                loaded = true
            end
        end
        
        if not loaded then
            addon.UI.scaleX = nil
            addon.UI.scaleY = nil
            isCalibrated = false
            if PathmakerDB and PathmakerDB.calibration then PathmakerDB.calibration[mapID] = nil end
        end
        
        lastCalibPos = nil
        self:RefreshRendering()
    end
    
    if isCalibrated then return end
    
    local y, x, _, instanceID = UnitPosition("player")
    local _, mapPos = GetDisplayMapAndPosition()
    
    if not x or not y or not mapPos then return end
    
    if not lastCalibPos then
        lastCalibPos = { wx = x, wy = y, mx = mapPos.x, my = mapPos.y, time = GetTime() }
        return
    end
    
    local dWx = math.abs(x - lastCalibPos.wx)
    local dWy = math.abs(y - lastCalibPos.wy)
    local dMx = math.abs(mapPos.x - lastCalibPos.mx)
    local dMy = math.abs(mapPos.y - lastCalibPos.my)
    
    if dWx > 20 and dMx > 0.002 then addon.UI.scaleX = dWx / dMx end
    if dWy > 20 and dMy > 0.002 then addon.UI.scaleY = dWy / dMy end
    
    if addon.UI.scaleX and addon.UI.scaleY then
        isCalibrated = true 
        if not PathmakerDB.calibration then PathmakerDB.calibration = {} end
        PathmakerDB.calibration[mapID] = { x = addon.UI.scaleX, y = addon.UI.scaleY }
        self:RefreshRendering() 
    elseif (GetTime() - lastCalibPos.time) > 30 then
        lastCalibPos = { wx = x, wy = y, mx = mapPos.x, my = mapPos.y, time = GetTime() }
    end
end

local function AcquireLine()
    local line = table.remove(linePool)
    if not line then
        -- Use the same native Line regions as Farm Mode. They retain fractional
        -- endpoints and do not shimmer when continuously repositioned/rotated.
        if canvas.CreateLine then
            line = canvas:CreateLine(nil, "BACKGROUND", nil, -8)
            line.pmNativeLine = true
        else
            line = canvas:CreateTexture(nil, "BACKGROUND", nil, -8)
            line:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
        if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
        if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
    end
    return line
end

function addon.UI:AddLine(x1, y1, x2, y2, color, thickness, markerData, baseColor, isSelected)
    if x1 < 0.001 and y1 < 0.001 then return end
    if x2 < 0.001 and y2 < 0.001 then return end

    local line = AcquireLine()
    
    line.x1, line.y1 = x1, y1
    line.x2, line.y2 = x2, y2
    line:SetColorTexture(unpack(color))
    line.thickness = thickness or 2
    if line.SetDrawLayer then
        line:SetDrawLayer("BACKGROUND", isSelected == false and -8 or -7)
    end
    line.markerData = markerData 
    line.baseColor = baseColor or color 
    
    table.insert(activeLines, line)
    if markerData then table.insert(activeMarkerLines, line) end
end

local function UpdateMarkerLineColors(owner)
    for _, line in ipairs(activeMarkerLines) do
        local newColor = owner:GetMarkerColor(line.markerData, line.baseColor)
        line:SetColorTexture(unpack(newColor))
    end
end

local function AppendMarkerChains(route)
    local currentChain = {}
    for i, point in ipairs(route.points or {}) do
        if point.isMarker and point.duration then
            local previous = route.points[i - 1]
            local lastInChain = currentChain[#currentChain]
            local continues = lastInChain and lastInChain == previous
                and not previous.isGap and point.duration == previous.duration
            if continues then
                table.insert(currentChain, point)
            else
                if #currentChain > 0 then table.insert(activeMarkerChains, currentChain) end
                currentChain = {point}
            end
        else
            if #currentChain > 0 then table.insert(activeMarkerChains, currentChain) end
            currentChain = {}
        end
    end
    if #currentChain > 0 then table.insert(activeMarkerChains, currentChain) end
end

-- COLOR SYSTEM: 
-- Standing (Green) -> Countdown (Gradient Red->Yellow->Green) -> Ready (RouteColor)
function addon.UI:GetMarkerColor(markerData, baseColor)
    local idleColor = baseColor or {0, 0, 0, 1}
    
    if not markerData or not markerData.duration then return idleColor end 
    
    -- 1. Standing On -> Green (Instant Feedback)
    if markerData.isStanding then
        return {0, 1, 0, 1} 
    end
    
    -- 2. Timer Active (Stepped Off)
    if markerData.countdownStart then
        local elapsed = GetTime() - markerData.countdownStart
        local duration = markerData.duration
        local remaining = duration - elapsed
        
        if remaining > 0 then
             -- Timer Running: GRADIENT (Red -> Yellow -> Green)
             -- We want 15 distinct steps of fading
             local pct = remaining / duration -- 1.0 (start) to 0.0 (end)
             
             -- Convert continuous percent to 15 discrete steps
             -- We map 1.0 -> step 0 (Red), 0.0 -> step 15 (Green)
             local steps = 15
             local val = 1.0 - pct -- Now 0.0 (Start/Red) to 1.0 (End/Green)
             val = math.floor(val * steps) / steps
             
             local r, g, b = 0, 0, 0
             
             if val < 0.5 then
                 -- Red (1,0,0) -> Yellow (1,1,0)
                 -- R stays 1, G goes 0 -> 1
                 r = 1
                 g = val * 2
             else
                 -- Yellow (1,1,0) -> Green (0,1,0)
                 -- R goes 1 -> 0, G stays 1
                 r = 1 - (val - 0.5) * 2
                 g = 1
             end
             
             return {r, g, b, 1}
        else
             -- Timer Finished: Hold Green for 1s then back to Route Color
             if (elapsed - duration) < 1.0 then
                 return {0, 1, 0, 1} -- Success Flash
             end
             return idleColor 
        end
    end
    
    -- 3. Default Idle -> Back to Route Color
    return idleColor 
end

function addon.UI:RefreshRendering()
    self:ClearLines()
    
    local mapID, playerPos = GetDisplayMapAndPosition()
    if not addon.UI.scaleX or not addon.UI.scaleY then return end
    
    if not mapID or not PathmakerDB.routes or not PathmakerDB.routes[mapID] then return end
    
    local visibleRadius = tonumber(self:GetMinimapViewRadius()) or 100
    local cacheRadius = visibleRadius + ROUTE_SEGMENT_CACHE_MARGIN_YARDS
    local cacheRadiusX = cacheRadius / addon.UI.scaleX
    local cacheRadiusY = cacheRadius / addon.UI.scaleY
    renderedRouteMapID = mapID
    renderedRoutePlayerX = playerPos and playerPos.x or nil
    renderedRoutePlayerY = playerPos and playerPos.y or nil
    renderedRouteRadius = visibleRadius

    local function SegmentCouldBeVisible(point1, point2)
        if not playerPos or not point1 or not point2 then return true end
        local minX, maxX = math.min(point1.x, point2.x), math.max(point1.x, point2.x)
        local minY, maxY = math.min(point1.y, point2.y), math.max(point1.y, point2.y)
        return maxX >= playerPos.x - cacheRadiusX and minX <= playerPos.x + cacheRadiusX
            and maxY >= playerPos.y - cacheRadiusY and minY <= playerPos.y + cacheRadiusY
    end

    local function RenderRoute(route, isSelected)
        if not route or not route.points or #route.points < 2 then return end
        hasRenderedRoutes = true
        AppendMarkerChains(route)
        local color = route.color or {1, 1, 1, 1}
        local activeRouteAlpha = PathmakerDB.settings and tonumber(PathmakerDB.settings.activeRouteAlpha) or 1
        activeRouteAlpha = math.max(0, math.min(1, activeRouteAlpha))
        local alpha = isSelected and activeRouteAlpha or 0.35
        -- The regular minimap is much smaller than Farm Mode. Its original
        -- widths remain crisper here than Farm Mode's large-canvas widths.
        local thickness = isSelected and 2 or 1
        local drawColor = {color[1], color[2], color[3], alpha}

        for i = 1, #route.points - 1 do
            local p1 = route.points[i]
            local p2 = route.points[i + 1]
            if not p1.isGap and SegmentCouldBeVisible(p1, p2) then
                local segColor = drawColor
                local markerData
                local distSq = (p1.x - p2.x)^2 + (p1.y - p2.y)^2
                if p1.isMarker and p2.isMarker and p1.duration == p2.duration and distSq < 0.0002 then
                    markerData = p1
                    segColor = self:GetMarkerColor(markerData, drawColor)
                end
                self:AddLine(p1.x, p1.y, p2.x, p2.y, segColor, thickness, markerData, drawColor, isSelected)
            end
        end

        if route.connectPaths then
            local pLast = route.points[#route.points]
            local pFirst = route.points[1]
            if not pLast.isGap and SegmentCouldBeVisible(pLast, pFirst) then
                local segColor = drawColor
                local markerData
                local distSq = (pLast.x - pFirst.x)^2 + (pLast.y - pFirst.y)^2
                if pLast.isMarker and pFirst.isMarker and pLast.duration == pFirst.duration and distSq < 0.0002 then
                    markerData = pLast
                    segColor = self:GetMarkerColor(markerData, drawColor)
                end
                self:AddLine(pLast.x, pLast.y, pFirst.x, pFirst.y, segColor, thickness, markerData, drawColor, isSelected)
            end
        end
    end

    local routes = PathmakerDB.routes[mapID]
    if addon.drawConfig and addon.drawConfig.ghostView then
        for guid, route in pairs(routes) do
            if guid ~= addon.selectedRouteGUID then RenderRoute(route, false) end
        end
    end
    -- Farm Mode deliberately renders the selected route last so it stays above
    -- ghost intersections. Keep the normal minimap's layer order identical.
    if addon.selectedRouteGUID then
        RenderRoute(routes[addon.selectedRouteGUID], true)
    end
end

function addon.UI:OnUpdate(elapsed)
    calibrationTimer = calibrationTimer + elapsed
    if not currentMapID or calibrationTimer >= CALIBRATION_INTERVAL then
        addon.UI:Calibrate(calibrationTimer)
        calibrationTimer = 0
    end
    if addon.isFarmMode then return end
    if not hasRenderedRoutes then return end

    markerColorTimer = markerColorTimer + elapsed
    markerInteractionTimer = markerInteractionTimer + elapsed
    -- Bound high-refresh clients to a stable 60 Hz route sample. On displays
    -- below 60 FPS this still updates once per rendered frame.
    self.routeRenderTimer = (self.routeRenderTimer or 0) + elapsed
    if self.routeRenderTimer < ROUTE_RENDER_INTERVAL then return end
    local renderElapsed = self.routeRenderTimer
    self.routeRenderTimer = self.routeRenderTimer % ROUTE_RENDER_INTERVAL
    local mapID, mapPos, moving = GetDisplayMapAndPosition()
    if not mapID or mapID ~= currentMapID then return end

    if not mapPos then return end
    if not addon.UI.scaleX or not addon.UI.scaleY then
        if #activeLines > 0 then self:ClearLines() end
        return
    end
    local sampledViewRadius = tonumber(self:GetMinimapViewRadius()) or 100
    local rebuildSegments = renderedRouteMapID ~= mapID
        or renderedRouteRadius ~= sampledViewRadius
        or renderedRoutePlayerX == nil or renderedRoutePlayerY == nil
    if not rebuildSegments then
        local dx = (mapPos.x - renderedRoutePlayerX) * addon.UI.scaleX
        local dy = (mapPos.y - renderedRoutePlayerY) * addon.UI.scaleY
        rebuildSegments = ((dx * dx) + (dy * dy)) >=
            (ROUTE_SEGMENT_REBUILD_DISTANCE_YARDS * ROUTE_SEGMENT_REBUILD_DISTANCE_YARDS)
    end
    if rebuildSegments then
        self:RefreshRendering()
        if not hasRenderedRoutes then return end
    end
    -- 2. INTERACTION LOGIC: CHAIN PROPAGATION
    if markerInteractionTimer >= MARKER_INTERACTION_INTERVAL
        and #activeMarkerChains > 0
    then
        markerInteractionTimer = 0
        for _, chain in ipairs(activeMarkerChains) do
            local anyStanding = false
            for _, point in ipairs(chain) do
                local distX = math.abs(point.x - mapPos.x)
                local distY = math.abs(point.y - mapPos.y)
                if distX < 0.004 and distY < 0.004 then
                    anyStanding = true
                    break
                end
            end

            local now = GetTime()
            if anyStanding then
                for _, point in ipairs(chain) do
                    point.isStanding = true
                    point.countdownStart = nil
                end
            else
                local wasStanding = false
                for _, point in ipairs(chain) do
                    if point.isStanding then wasStanding = true break end
                end
                for _, point in ipairs(chain) do
                    point.isStanding = false
                    if wasStanding then point.countdownStart = now end
                end
            end
        end
    end

    -- 3. RENDERING
    if not canvas:IsShown() then return end
    if not addon.UI.scaleX or not addon.UI.scaleY then 
        if #activeLines > 0 then self:ClearLines() end
        return 
    end

    -- Match Farm Mode's rendered-frame motion and native line endpoint path.
    local renderPos, renderFacing
    if moving then
        renderPos, renderFacing = GetSmoothedRenderState(mapID, mapPos, renderElapsed)
    else
        smoothedMapID = mapID
        smoothedPlayerX, smoothedPlayerY = mapPos.x, mapPos.y
        smoothedFacing = GetPlayerFacing and GetPlayerFacing() or 0
        renderPos, renderFacing = mapPos, smoothedFacing
    end

    local px, py = renderPos.x, renderPos.y
    local visibleRadiusYards = sampledViewRadius
    
    local canvasWidth = canvas:GetWidth()
    local canvasHeight = canvas:GetHeight()
    local isRotating = GetCVar and GetCVar("rotateMinimap") == "1"
    local effectiveFacing = isRotating and (renderFacing or 0) or 0
    local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local geometryChanged = lastRenderMapID ~= mapID
        or lastRenderX ~= px or lastRenderY ~= py
        or lastRenderFacing ~= effectiveFacing
        or lastRenderRadius ~= visibleRadiusYards
        or lastRenderWidth ~= canvasWidth or lastRenderHeight ~= canvasHeight
        or lastRenderShape ~= minimapShape

    if not geometryChanged then
        if markerColorTimer >= MARKER_COLOR_INTERVAL then
            markerColorTimer = 0
            UpdateMarkerLineColors(self)
        end
        return
    end

    lastRenderMapID = mapID
    lastRenderX, lastRenderY = px, py
    lastRenderFacing = effectiveFacing
    lastRenderRadius = visibleRadiusYards
    lastRenderWidth, lastRenderHeight = canvasWidth, canvasHeight
    lastRenderShape = minimapShape
    markerColorTimer = 0

    local pixelsPerYard = (canvasWidth / 2) / visibleRadiusYards
    
    local scaleFactorX = pixelsPerYard * addon.UI.scaleX
    local scaleFactorY = pixelsPerYard * addon.UI.scaleY

    local rotation = isRotating and -(renderFacing or 0) or 0
    local cosR, sinR = math.cos(rotation), math.sin(rotation)

    local function GetCanvasOffset(mapX, mapY)
        local dx = (mapX - px) * scaleFactorX
        local dy = -((mapY - py) * scaleFactorY)
        if rotation ~= 0 then
            return (dx * cosR) - (dy * sinR), (dx * sinR) + (dy * cosR)
        end
        return dx, dy
    end

    for _, line in ipairs(activeLines) do
        -- DYNAMIC COLOR UPDATE
        if line.markerData then
            local newColor = self:GetMarkerColor(line.markerData, line.baseColor)
            line:SetColorTexture(unpack(newColor))
        end

        local x1, y1 = GetCanvasOffset(line.x1, line.y1)
        local x2, y2 = GetCanvasOffset(line.x2, line.y2)
        -- Texture children do not inherit the native minimap's round mask.
        if addon.MapFrame and not addon.MapFrame.ownsMinimap and addon.MapFrame.ClipNativeMinimapLine
            and (not GetMinimapShape or GetMinimapShape() == "ROUND") then
            local radius = math.max(0, math.min(canvas:GetWidth(), canvas:GetHeight()) / 2 - line.thickness)
            x1, y1, x2, y2 = addon.MapFrame:ClipNativeMinimapLine(x1, y1, x2, y2, radius)
        end
        local baseDx = x1 and (x2 - x1) or 0
        local baseDy = y1 and (y2 - y1) or 0
        local len = math.sqrt(baseDx^2 + baseDy^2)
        
        -- Filter out microscopic duplicate/broken nodes that cause rotation math to flip out
        if len < 0.5 then
            line:Hide()
        else
            line:Show()
            
            local angle = math.atan2(baseDy, baseDx)
            local centerX = (x1 + x2) / 2
            local centerY = (y1 + y2) / 2
            local drawLength = math.max(1, len)

            if line.pmNativeLine then
                if line.pmThickness ~= line.thickness then
                    line:SetThickness(line.thickness)
                    line.pmThickness = line.thickness
                end
                line:SetStartPoint("CENTER", canvas, x1, y1)
                line:SetEndPoint("CENTER", canvas, x2, y2)
            else
                line:SetSize(drawLength, line.thickness)
                line:ClearAllPoints()
                line:SetPoint("CENTER", canvas, "CENTER", centerX, centerY)
                line:SetRotation(angle)
            end
        end
    end
end
-- =====================================================
-- FORCE NAVIGATION VISIBILITY
-- =====================================================

function addon.UI:RefreshNavigationArrow()
    if addon.arrowFrame then
        addon.arrowFrame:SetFrameStrata("HIGH")
        addon.arrowFrame:SetFrameLevel(9999)
        addon.arrowFrame:Show()
    end
end
