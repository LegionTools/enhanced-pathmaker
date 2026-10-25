local addonName, addon = ...

addon.Navigation = {}

-------------------------------------------------
-- SETTINGS
-------------------------------------------------

local ARROW_TEXTURES = {
    BLADE = {
        ["2D"] = "Interface\\AddOns\\PathMaker\\Media\\arrow2d.tga",
        ["3D"] = "Interface\\AddOns\\PathMaker\\Media\\arrow3d.tga",
    },
    POINTER = {
        ["2D"] = "Interface\\AddOns\\PathMaker\\Media\\arrow2d_pointer.tga",
        ["3D"] = "Interface\\AddOns\\PathMaker\\Media\\arrow3d_pointer.tga",
    },
    FRAME = {
        ["2D"] = "Interface\\AddOns\\PathMaker\\Media\\arrow2d_frame.tga",
        ["3D"] = "Interface\\AddOns\\PathMaker\\Media\\arrow3d_frame.tga",
    },
}
local ARROW_DEPTH_TEXTURES = {
    BLADE = "Interface\\AddOns\\PathMaker\\Media\\arrow3d_depth.tga",
    POINTER = "Interface\\AddOns\\PathMaker\\Media\\arrow3d_pointer_depth.tga",
    FRAME = "Interface\\AddOns\\PathMaker\\Media\\arrow3d_frame_depth.tga",
}
local arrowFrame
local currentAngle = 0
local MAX_THICKNESS_LAYERS = 20
local THICKNESS_LAYER_SPACING = 1

local RABBIT_DISTANCE_YARDS = 120
local ENDPOINT_TURNAROUND_DISTANCE_YARDS = 22
local OFF_ROUTE_RECOVERY_DISTANCE_YARDS = 75
local LOCAL_SEGMENT_LOOKAHEAD = 3
local SMOOTHING_SPEED = 5.0
local DIRECTION_CHANGE_DELAY = 2.0
local DIRECTION_MOVEMENT_THRESHOLD_YARDS = 0.05
local DIRECTION_OPPOSITE_DOT_THRESHOLD = -0.35

local lastSegIndex = 1
local lastRouteGUID = nil
local stableNavigationPositionState = {}
local navigationState = {}

addon.Navigation.enabled = false

local function EnsureArrowSettings()
    PathmakerDB = PathmakerDB or {}
    PathmakerDB.settings = PathmakerDB.settings or {}
    local s = PathmakerDB.settings
    if s.navArrowWidth == nil then s.navArrowWidth = tonumber(s.navArrowSize) or 42 end
    s.navArrowWidth = math.max(20, math.min(120, tonumber(s.navArrowWidth) or 42))
    s.navArrowScale = math.max(0.5, math.min(2, tonumber(s.navArrowScale) or 1))
    s.navArrowSize = nil
    s.navArrowLength = math.max(40, math.min(220, tonumber(s.navArrowLength) or 98))
    if s.navArrow3DTransformation == nil then
        local oldStretch = tonumber(s.navArrow3DStretch)
        s.navArrow3DTransformation = oldStretch and ((oldStretch - 0.5) / 1.5) or 0.5
    end
    s.navArrow3DTransformation = math.max(0, math.min(1, tonumber(s.navArrow3DTransformation) or 0.5))
    s.navArrow3DThickness = math.max(0, math.min(20, tonumber(s.navArrow3DThickness) or 0))
    s.navArrowPerspective = nil
    s.navArrow3DStretch = nil
    if s.navArrowY == nil then s.navArrowY = tonumber(s.navArrowHeight) or 120 end
    s.navArrowHeight = nil
    if s.navArrowStyle ~= "2D" and s.navArrowStyle ~= "3D" then
        s.navArrowStyle = "3D"
    end
    if s.navArrowDesign ~= "BLADE" and s.navArrowDesign ~= "POINTER" and s.navArrowDesign ~= "FRAME" then
        s.navArrowDesign = "BLADE"
    end
    if s.navArrowColorless == nil then s.navArrowColorless = false end
    if s.navArrowLocked == nil then s.navArrowLocked = false end
    if s.navArrowClickThrough == nil then s.navArrowClickThrough = false end
    s.navArrowColorOuter = nil
    s.navArrowColorMiddle = nil
    s.navArrowColorGem = nil
    return s
end

local function GetArrowTexture(settings)
    local s = settings or EnsureArrowSettings()
    local design = ARROW_TEXTURES[s.navArrowDesign] or ARROW_TEXTURES.BLADE
    return design[s.navArrowStyle] or design["2D"]
end

local function GetArrowDepthTexture(settings)
    local s = settings or EnsureArrowSettings()
    return ARROW_DEPTH_TEXTURES[s.navArrowDesign] or ARROW_DEPTH_TEXTURES.BLADE
end

local function ApplyArrowColor(routeColor, inactive)
    if not arrowFrame then return end
    local s = EnsureArrowSettings()
    if arrowFrame.arrow.SetDesaturated then arrowFrame.arrow:SetDesaturated(false) end

    local useRouteColor = not inactive and not s.navArrowColorless and routeColor ~= nil
    local r = routeColor and (routeColor[1] or 1) or 1
    local g = routeColor and (routeColor[2] or 1) or 1
    local b = routeColor and (routeColor[3] or 1) or 1
    if useRouteColor then
        arrowFrame.arrow:SetVertexColor(r, g, b, 1)
    else
        arrowFrame.arrow:SetVertexColor(1, 1, 1, inactive and 0.72 or 1)
    end

    local activeDepthLayerCount = arrowFrame.activeDepthLayerCount or 0
    for index, depthLayer in ipairs(arrowFrame.depthLayers or {}) do
        if index > activeDepthLayerCount then break end
        if useRouteColor then
            local shade = index == 1 and 0.34 or 0.17
            depthLayer:SetVertexColor(r * shade, g * shade, b * shade, 0.98)
        else
            local shade = index == 1 and 0.28 or 0.12
            depthLayer:SetVertexColor(shade, shade, shade, inactive and 0.62 or 0.98)
        end
    end
end

local function ApplyArrowInteraction()
    if not arrowFrame then return end
    local s = EnsureArrowSettings()
    local canDrag = not s.navArrowLocked and not s.navArrowClickThrough
    arrowFrame:EnableMouse(not s.navArrowClickThrough)
    arrowFrame:SetMovable(canDrag)
end

local function SetArrowRotation(angle)
    if not arrowFrame then return end
    arrowFrame.arrow:SetRotation(angle)
    arrowFrame.trim:SetRotation(angle)
    arrowFrame.highlight:SetRotation(angle)
    for index, depthLayer in ipairs(arrowFrame.depthLayers or {}) do
        if index > (arrowFrame.activeDepthLayerCount or 0) then break end
        depthLayer:SetRotation(angle)
    end
end

local function ApplyArrowAppearance(routeColor, inactive, applyLayout)
    if not arrowFrame then return end
    local s = EnsureArrowSettings()
    local transform = s.navArrowStyle == "3D" and s.navArrow3DTransformation or 0
    local width = s.navArrowStyle == "3D" and (s.navArrowWidth * (1.25 + (transform * 0.35))) or s.navArrowWidth
    local length = s.navArrowStyle == "3D" and (s.navArrowLength * (0.85 - (transform * 0.15))) or s.navArrowLength
    width = width * s.navArrowScale
    length = length * s.navArrowScale
    local thickness = s.navArrowStyle == "3D" and s.navArrow3DThickness or 0
    local depthLayerCount = 0
    if thickness > 0 then
        depthLayerCount = math.min(MAX_THICKNESS_LAYERS, math.max(1, math.ceil(thickness / THICKNESS_LAYER_SPACING)))
    end
    arrowFrame.activeDepthLayerCount = depthLayerCount
    local faceOffsetY = thickness * 0.5
    local arrowTexture = GetArrowTexture(s)
    local depthTexture = GetArrowDepthTexture(s)

    arrowFrame:SetSize(width, length + thickness)
    arrowFrame.arrow:SetTexture(arrowTexture)
    arrowFrame.arrow:SetSize(width, length)
    arrowFrame.trim:SetSize(width, length)
    arrowFrame.highlight:SetSize(math.max(1, width - 4), math.max(1, length - 4))

    for index, depthLayer in ipairs(arrowFrame.depthLayers or {}) do
        depthLayer:SetTexture(depthTexture)
        depthLayer:SetSize(width, length)
        depthLayer:ClearAllPoints()
        if index <= depthLayerCount then
            local depthOffset = thickness * (index / depthLayerCount)
            depthLayer:SetPoint("CENTER", 0, faceOffsetY - depthOffset)
            depthLayer:Show()
        else
            depthLayer:Hide()
        end
    end

    if applyLayout then
        arrowFrame:ClearAllPoints()
        arrowFrame:SetPoint("CENTER", UIParent, "CENTER", tonumber(s.navArrowX) or 0, tonumber(s.navArrowY) or 120)
    end

    arrowFrame.trim:ClearAllPoints()
    arrowFrame.arrow:ClearAllPoints()
    arrowFrame.highlight:ClearAllPoints()
    arrowFrame.trim:SetPoint("CENTER", 0, faceOffsetY)
    arrowFrame.arrow:SetPoint("CENTER", 0, faceOffsetY)
    arrowFrame.highlight:SetPoint("CENTER", -1, faceOffsetY + 1)
    arrowFrame.trim:SetVertexColor(0.04, 0.04, 0.04, 1)
    arrowFrame.highlight:SetVertexColor(1, 1, 1, 0.06)
    arrowFrame.trim:Hide()
    arrowFrame.highlight:Hide()

    SetArrowRotation(currentAngle)
    ApplyArrowColor(routeColor, inactive)
    ApplyArrowInteraction()
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------

local function GetDistanceSq(p1, p2, scaleX, scaleY)
    local dx = (p1.x - p2.x) * (scaleX or 1)
    local dy = (p1.y - p2.y) * (scaleY or 1)
    return (dx * dx) + (dy * dy)
end

local function GetDistance(p1, p2, scaleX, scaleY)
    return math.sqrt(GetDistanceSq(p1, p2, scaleX, scaleY))
end

local function GetClosestPointOnSegment(px, py, ax, ay, bx, by, scaleX, scaleY)

    local mapDx = bx - ax
    local mapDy = by - ay
    local dx = mapDx * (scaleX or 1)
    local dy = mapDy * (scaleY or 1)

    if dx == 0 and dy == 0 then
        return {
            x = ax,
            y = ay
        }
    end

    local playerDx = (px - ax) * (scaleX or 1)
    local playerDy = (py - ay) * (scaleY or 1)
    local t = (playerDx * dx + playerDy * dy) / (dx * dx + dy * dy)

    t = math.max(0, math.min(1, t))

    return {
        x = ax + t * mapDx,
        y = ay + t * mapDy
    }
end

local function NormalizeAngle(angle)
    while angle > math.pi do angle = angle - (2 * math.pi) end
    while angle < -math.pi do angle = angle + (2 * math.pi) end
    return angle
end

local function GetSegmentCount(route)
    local pointCount = route and route.points and #route.points or 0
    if pointCount < 2 then return 0 end
    return route.connectPaths and pointCount or (pointCount - 1)
end

local function GetSegmentPoints(route, segmentIndex)
    local points = route.points
    local pointCount = #points
    if segmentIndex < 1 or segmentIndex > GetSegmentCount(route) then return nil, nil end
    if segmentIndex == pointCount then return points[pointCount], points[1] end
    return points[segmentIndex], points[segmentIndex + 1]
end

local function IsSegmentNavigable(route, segmentIndex)
    local p1, p2 = GetSegmentPoints(route, segmentIndex)
    if not p1 or not p2 then return false end
    return route.connectPaths or not p1.isGap
end

local function GetNextSegmentIndex(route, segmentIndex, direction)
    local segmentCount = GetSegmentCount(route)
    local nextIndex = segmentIndex + direction
    if nextIndex >= 1 and nextIndex <= segmentCount then return nextIndex end
    if route.connectPaths and segmentCount > 0 then
        return direction > 0 and 1 or segmentCount
    end
    return nil
end

local function ProjectToSegment(route, segmentIndex, pos, scaleX, scaleY)
    if not IsSegmentNavigable(route, segmentIndex) then return nil, nil end
    local p1, p2 = GetSegmentPoints(route, segmentIndex)
    local projection = GetClosestPointOnSegment(pos.x, pos.y, p1.x, p1.y, p2.x, p2.y, scaleX, scaleY)
    return projection, GetDistanceSq(projection, pos, scaleX, scaleY)
end

local function FindClosestSegment(route, pos, scaleX, scaleY, candidates)
    local bestIndex, bestPoint, bestDistanceSq
    if candidates then
        for segmentIndex in pairs(candidates) do
            local projection, distanceSq = ProjectToSegment(route, segmentIndex, pos, scaleX, scaleY)
            if distanceSq and (not bestDistanceSq or distanceSq < bestDistanceSq) then
                bestIndex, bestPoint, bestDistanceSq = segmentIndex, projection, distanceSq
            end
        end
    else
        for segmentIndex = 1, GetSegmentCount(route) do
            local projection, distanceSq = ProjectToSegment(route, segmentIndex, pos, scaleX, scaleY)
            if distanceSq and (not bestDistanceSq or distanceSq < bestDistanceSq) then
                bestIndex, bestPoint, bestDistanceSq = segmentIndex, projection, distanceSq
            end
        end
    end
    return bestIndex, bestPoint, bestDistanceSq
end

local function ChooseDirection(route, segmentIndex, projection, pos, scaleX, scaleY)
    local p1, p2 = GetSegmentPoints(route, segmentIndex)
    if not p1 or not p2 then return 1 end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if facing then
        local function HeadingTo(point)
            local dx = (point.x - pos.x) * scaleX
            local dy = (point.y - pos.y) * scaleY
            return math.atan2(-dx, -dy)
        end
        local forwardDifference = math.abs(NormalizeAngle(HeadingTo(p2) - facing))
        local reverseDifference = math.abs(NormalizeAngle(HeadingTo(p1) - facing))
        if math.abs(forwardDifference - reverseDifference) > 0.12 then
            return forwardDifference <= reverseDifference and 1 or -1
        end
    end

    -- When facing is unavailable or perpendicular to the route, prefer the
    -- direction with the closer endpoint on open routes.
    if not route.connectPaths then
        local startDistance = GetDistance(pos, route.points[1], scaleX, scaleY)
        local endDistance = GetDistance(pos, route.points[#route.points], scaleX, scaleY)
        return endDistance >= startDistance and 1 or -1
    end
    return 1
end

-- Detect travel along the route independently of camera/player facing. This
-- lets backpedalling or otherwise moving the route in reverse change the
-- navigation direction after a deliberate, sustained movement.
local function UpdateDirectionFromMovement(route, segmentIndex, pos, scaleX, scaleY, elapsed)
    local direction = navigationState.direction or 1
    local function AdvanceOppositeIntent()
        navigationState.oppositeMovementTime = (navigationState.oppositeMovementTime or 0) + math.max(elapsed or 0, 0)
        if navigationState.oppositeMovementTime >= DIRECTION_CHANGE_DELAY then
            direction = -direction
            navigationState.direction = direction
            navigationState.oppositeMovementTime = nil
            navigationState.endpointTurnaround = nil
        end
    end

    local previous = navigationState.movementPosition
    navigationState.movementPosition = { x = pos.x, y = pos.y }
    if not previous then return direction end

    local moveX = (pos.x - previous.x) * scaleX
    local moveY = (pos.y - previous.y) * scaleY
    local moveDistance = math.sqrt((moveX * moveX) + (moveY * moveY))
    local unitSpeed = GetUnitSpeed and GetUnitSpeed("player")
    if moveDistance < DIRECTION_MOVEMENT_THRESHOLD_YARDS then
        -- Secret speed is unavailable; retain the coordinate-based debounce.
        if addon.Compat:IsFiniteNumber(unitSpeed) and unitSpeed <= 0.1 then
            navigationState.oppositeMovementTime = nil
        elseif navigationState.oppositeMovementTime then
            -- Classic clients can return the same coarse map coordinate across
            -- several frames. Continue the debounce while the unit is moving.
            AdvanceOppositeIntent()
        end
        return direction
    end

    local p1, p2 = GetSegmentPoints(route, segmentIndex)
    if not p1 or not p2 then return direction end
    local routeX = (p2.x - p1.x) * scaleX * direction
    local routeY = (p2.y - p1.y) * scaleY * direction
    local routeLength = math.sqrt((routeX * routeX) + (routeY * routeY))
    if routeLength <= 0 then return direction end

    local alignment = ((moveX * routeX) + (moveY * routeY)) / (moveDistance * routeLength)
    if alignment <= DIRECTION_OPPOSITE_DOT_THRESHOLD then
        AdvanceOppositeIntent()
    else
        navigationState.oppositeMovementTime = nil
    end
    return direction
end

-------------------------------------------------
-- REVERSE ROUTE
-------------------------------------------------

function addon.Navigation:ReverseRoute(route)

    local points = route.points
    local n = #points

    if n < 2 then
        return
    end

    local gapAt = {}

    for i = 1, n - 1 do
        gapAt[i] = points[i].isGap
    end

    for i = 1, math.floor(n / 2) do
        points[i], points[n - i + 1] = points[n - i + 1], points[i]
    end

    for i = 1, n do
        points[i].isGap = nil
    end

    for i = 1, n - 1 do
        if gapAt[i] then
            points[n - i].isGap = true
        end
    end

    lastSegIndex = 1
    wipe(navigationState)
end

-------------------------------------------------
-- CREATE ARROW
-------------------------------------------------

function addon.Navigation:CreateArrow()

    if arrowFrame then
        return
    end

    arrowFrame = CreateFrame("Frame", "PathmakerNavArrow", UIParent)

    -------------------------------------------------
    -- SIZE
    -------------------------------------------------

    arrowFrame:SetSize(42, 98)

    arrowFrame:SetPoint("CENTER", 0, 120)

    arrowFrame:SetFrameStrata("TOOLTIP")

    arrowFrame:SetFrameLevel(9999)

    -------------------------------------------------
    -- MOVEABLE
    -------------------------------------------------

    arrowFrame:SetMovable(true)

    arrowFrame:EnableMouse(true)

    arrowFrame:RegisterForDrag("LeftButton")

    arrowFrame:SetClampedToScreen(true)

    arrowFrame:SetScript("OnDragStart", function(self)
        local s = EnsureArrowSettings()
        if not s.navArrowLocked and not s.navArrowClickThrough then
            self:StartMoving()
        end
    end)

    arrowFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local s = EnsureArrowSettings()
        if s.navArrowLocked or s.navArrowClickThrough then return end
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            s.navArrowX = cx - ux
            s.navArrowY = cy - uy
        end
    end)

    -------------------------------------------------
    -- OPTIONAL 3D THICKNESS
    -------------------------------------------------

    arrowFrame.depthLayers = {}
    arrowFrame.activeDepthLayerCount = 0
    for index = MAX_THICKNESS_LAYERS, 1, -1 do
        local depthLayer = arrowFrame:CreateTexture(nil, "BORDER")
        depthLayer:SetTexture(ARROW_DEPTH_TEXTURES.BLADE)
        depthLayer:SetSize(42, 98)
        depthLayer:SetPoint("CENTER")
        depthLayer:SetVertexColor(0.2, 0.2, 0.2, 0.98)
        depthLayer:Hide()
        arrowFrame.depthLayers[index] = depthLayer
    end

    -------------------------------------------------
    -- TRIM
    -------------------------------------------------

    arrowFrame.trim = arrowFrame:CreateTexture(nil, "BORDER")

    arrowFrame.trim:SetTexture(ARROW_TEXTURES.BLADE["2D"])

    arrowFrame.trim:SetSize(42, 98)

    arrowFrame.trim:SetPoint("CENTER")

    arrowFrame.trim:SetVertexColor(0.15, 0.15, 0.15, 1)

    -------------------------------------------------
    -- MAIN ARROW
    -------------------------------------------------

    arrowFrame.arrow = arrowFrame:CreateTexture(nil, "ARTWORK")

    arrowFrame.arrow:SetTexture(ARROW_TEXTURES.BLADE["2D"])

    arrowFrame.arrow:SetSize(42, 98)

    arrowFrame.arrow:SetPoint("CENTER")

    arrowFrame.arrow:SetVertexColor(0.35, 0.35, 0.35, 0.9)

    -------------------------------------------------
    -- HIGHLIGHT
    -------------------------------------------------

    arrowFrame.highlight = arrowFrame:CreateTexture(nil, "OVERLAY")

    arrowFrame.highlight:SetTexture(ARROW_TEXTURES.BLADE["2D"])

    arrowFrame.highlight:SetSize(38, 94)

    arrowFrame.highlight:SetPoint("CENTER", -1, 1)

    arrowFrame.highlight:SetBlendMode("ADD")

    arrowFrame.highlight:SetVertexColor(1, 1, 1, 0.04)

    -------------------------------------------------
    -- START HIDDEN
    -------------------------------------------------

    arrowFrame:SetAlpha(1)

    arrowFrame:Hide()
    ApplyArrowAppearance(nil, true, true)
end

function addon.Navigation:ApplySettings()
    if not arrowFrame then self:CreateArrow() end
    ApplyArrowAppearance(nil, not addon.selectedRouteGUID, true)
end

-------------------------------------------------
-- TOGGLE
-------------------------------------------------

function addon.Navigation:Toggle()

    if not arrowFrame then
        self:CreateArrow()
    end

    addon.Navigation.enabled = not addon.Navigation.enabled

    if addon.Navigation.enabled then

        wipe(navigationState)

        arrowFrame:Show()

        addon.Compat:SetGuardedUpdate(arrowFrame, "Navigation arrow", function(_, elapsed)
            addon.Navigation:OnUpdate(elapsed)
        end)

    else

        arrowFrame:Hide()

        arrowFrame:SetScript("OnUpdate", nil)
    end
end

-------------------------------------------------
-- HIDE
-------------------------------------------------

function addon.Navigation:HideArrow()

    if arrowFrame then

        arrowFrame:Hide()

        arrowFrame:SetScript("OnUpdate", nil)
    end
end

-------------------------------------------------
-- UPDATE
-------------------------------------------------

function addon.Navigation:OnUpdate(elapsed)

    if not arrowFrame then
        return
    end

    -------------------------------------------------
    -- NO ACTIVE ROUTE
    -------------------------------------------------

    if not addon.selectedRouteGUID then

        wipe(navigationState)

        ApplyArrowColor(nil, true)

        SetArrowRotation(0)

        return
    end

    -------------------------------------------------
    -- MAP
    -------------------------------------------------

    local mapID = addon.Routes and addon.Routes:GetRouteMapID(
        addon.selectedRouteGUID,
        addon.selectedRouteMapID
    ) or C_Map.GetBestMapForUnit("player")

    if not mapID then
        return
    end

    if not PathmakerDB
    or not PathmakerDB.routes
    or not PathmakerDB.routes[mapID] then
        return
    end

    -------------------------------------------------
    -- ROUTE
    -------------------------------------------------

    local route = PathmakerDB.routes[mapID][addon.selectedRouteGUID]

    if not route
    or not route.points
    or #route.points < 2 then
        return
    end

    local scaleX, scaleY = route.mapScaleX, route.mapScaleY
    if (not scaleX or not scaleY) and addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
    end
    local calibration = PathmakerDB and PathmakerDB.calibration and PathmakerDB.calibration[mapID]
    if type(calibration) == "table" then
        scaleX, scaleY = scaleX or calibration.x, scaleY or calibration.y
    end
    scaleX, scaleY = scaleX or 6000, scaleY or 6000

    -------------------------------------------------
    -- PLAYER POSITION
    -------------------------------------------------

    local pos
    if addon.Compat and addon.Compat.GetStableUnitMapPosition then
        pos = addon.Compat:GetStableUnitMapPosition(mapID, "player", stableNavigationPositionState)
    elseif addon.Compat and addon.Compat.GetUnitMapPosition then
        pos = addon.Compat:GetUnitMapPosition(mapID, "player")
    else
        pos = C_Map.GetPlayerMapPosition(mapID, "player")
    end

    if not pos then
        return
    end

    -------------------------------------------------
    -- SMART ROUTE ATTACHMENT AND RECOVERY
    -------------------------------------------------

    local routeChanged = navigationState.routeGUID ~= addon.selectedRouteGUID
        or navigationState.mapID ~= mapID
        or navigationState.points ~= route.points
        or navigationState.pointCount ~= #route.points
        or navigationState.connectPaths ~= route.connectPaths

    local foundSegIndex, bestPoint, bestDistSq
    if routeChanged or not navigationState.segmentIndex then
        foundSegIndex, bestPoint, bestDistSq = FindClosestSegment(route, pos, scaleX, scaleY)
        if not foundSegIndex then return end
        navigationState.routeGUID = addon.selectedRouteGUID
        navigationState.mapID = mapID
        navigationState.points = route.points
        navigationState.pointCount = #route.points
        navigationState.connectPaths = route.connectPaths
        navigationState.segmentIndex = foundSegIndex
        navigationState.direction = ChooseDirection(route, foundSegIndex, bestPoint, pos, scaleX, scaleY)
        navigationState.endpointTurnaround = nil
        navigationState.movementPosition = nil
        navigationState.oppositeMovementTime = nil
    else
        -- Prefer the current segment and a small window ahead. This prevents
        -- parallel or crossing route sections from stealing the arrow while
        -- still allowing ordinary corner and waypoint advancement.
        local localCandidates = {}
        local segmentIndex = navigationState.segmentIndex
        localCandidates[segmentIndex] = true
        local previous = GetNextSegmentIndex(route, segmentIndex, -navigationState.direction)
        if previous then localCandidates[previous] = true end
        for _ = 1, LOCAL_SEGMENT_LOOKAHEAD do
            segmentIndex = GetNextSegmentIndex(route, segmentIndex, navigationState.direction)
            if not segmentIndex then break end
            localCandidates[segmentIndex] = true
        end

        foundSegIndex, bestPoint, bestDistSq = FindClosestSegment(route, pos, scaleX, scaleY, localCandidates)
        local recoveryDistanceSq = OFF_ROUTE_RECOVERY_DISTANCE_YARDS * OFF_ROUTE_RECOVERY_DISTANCE_YARDS
        if not foundSegIndex or not bestDistSq or bestDistSq > recoveryDistanceSq then
            local recoveredIndex, recoveredPoint, recoveredDistanceSq = FindClosestSegment(route, pos, scaleX, scaleY)
            if not recoveredIndex then return end
            navigationState.direction = ChooseDirection(route, recoveredIndex, recoveredPoint, pos, scaleX, scaleY)
            navigationState.endpointTurnaround = nil
            navigationState.movementPosition = nil
            navigationState.oppositeMovementTime = nil
            foundSegIndex, bestPoint, bestDistSq = recoveredIndex, recoveredPoint, recoveredDistanceSq
        end
        navigationState.segmentIndex = foundSegIndex
    end

    lastRouteGUID = addon.selectedRouteGUID
    lastSegIndex = foundSegIndex

    -------------------------------------------------
    -- NON-DESTRUCTIVE ENDPOINT TURNAROUND
    -------------------------------------------------

    local direction = navigationState.direction or 1
    if not route.connectPaths then
        local endpoint = direction > 0 and route.points[#route.points] or route.points[1]
        local endpointDistance = GetDistance(pos, endpoint, scaleX, scaleY)
        if endpointDistance <= ENDPOINT_TURNAROUND_DISTANCE_YARDS and not navigationState.endpointTurnaround then
            direction = -direction
            navigationState.direction = direction
            navigationState.endpointTurnaround = true
        elseif endpointDistance > (ENDPOINT_TURNAROUND_DISTANCE_YARDS + 12) then
            navigationState.endpointTurnaround = nil
        end
    else
        navigationState.endpointTurnaround = nil
    end

    direction = UpdateDirectionFromMovement(route, foundSegIndex, pos, scaleX, scaleY, elapsed)

    -------------------------------------------------
    -- FORWARD-LOOKING TARGET (SKIPS PASSED WAYPOINTS)
    -------------------------------------------------

    local target = bestPoint
    local remaining = RABBIT_DISTANCE_YARDS
    local currentIdx = foundSegIndex
    local walker = bestPoint
    local guard = 0
    local maxSteps = math.max(4, GetSegmentCount(route) * 2)

    while remaining > 0 and currentIdx and guard < maxSteps do
        guard = guard + 1
        if not IsSegmentNavigable(route, currentIdx) then
            currentIdx = GetNextSegmentIndex(route, currentIdx, direction)
            if currentIdx then
                local nextP1, nextP2 = GetSegmentPoints(route, currentIdx)
                walker = direction > 0 and nextP1 or nextP2
                target = walker
            end
        else
            local p1, p2 = GetSegmentPoints(route, currentIdx)
            local nextPoint = direction > 0 and p2 or p1
            local segmentLength = GetDistance(walker, nextPoint, scaleX, scaleY)

            if segmentLength > remaining and segmentLength > 0 then
                local ratio = remaining / segmentLength
                target = {
                    x = walker.x + ((nextPoint.x - walker.x) * ratio),
                    y = walker.y + ((nextPoint.y - walker.y) * ratio),
                }
                remaining = 0
            else
                target = nextPoint
                remaining = remaining - segmentLength
                currentIdx = GetNextSegmentIndex(route, currentIdx, direction)
                if currentIdx then
                    local nextP1, nextP2 = GetSegmentPoints(route, currentIdx)
                    walker = direction > 0 and nextP1 or nextP2
                end
            end
        end
    end

    navigationState.closestSegment = foundSegIndex
    navigationState.distanceToRoute = bestDistSq and math.sqrt(bestDistSq) or nil
    navigationState.currentPointIndex = direction > 0
        and ((foundSegIndex % #route.points) + 1) or foundSegIndex
    if currentIdx then
        navigationState.targetIndex = direction > 0
            and ((currentIdx % #route.points) + 1) or currentIdx
    else
        navigationState.targetIndex = direction > 0 and #route.points or 1
    end

    -------------------------------------------------
    -- ROTATION
    -------------------------------------------------

    local dx = (target.x - pos.x) * scaleX
    local dy = (target.y - pos.y) * scaleY

    local targetAngle = math.atan2(-dx, -dy)

    local playerFacing = GetPlayerFacing() or 0

    local rotation = targetAngle - playerFacing

    while rotation > math.pi do
        rotation = rotation - (2 * math.pi)
    end

    while rotation < -math.pi do
        rotation = rotation + (2 * math.pi)
    end

    local angleDelta = NormalizeAngle(rotation - currentAngle)
    currentAngle = NormalizeAngle(currentAngle + (
        angleDelta * math.min(elapsed * SMOOTHING_SPEED, 1)
    ))

    -------------------------------------------------
    -- APPLY ROTATION
    -------------------------------------------------

    SetArrowRotation(currentAngle)

    -------------------------------------------------
    -- ROUTE COLOR
    -------------------------------------------------

    local c = route.color or {1, 1, 1, 1}

    ApplyArrowColor(c, false)

end


-- Read-only snapshot used by /pmdebug. Recompute the closest segment so the
-- diagnostic remains useful even when the navigation arrow is disabled.
function addon.Navigation:GetDebugState(route, mapID)
    local result = {
        enabled = self.enabled == true,
        direction = nil,
        closestSegment = nil,
        currentPointIndex = nil,
        targetIndex = nil,
        distanceToRoute = nil,
    }
    if not route or not route.points or #route.points < 2 or not mapID then return result end

    local scaleX, scaleY = route.mapScaleX, route.mapScaleY
    if (not scaleX or not scaleY) and addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
    end
    local calibration = PathmakerDB and PathmakerDB.calibration and PathmakerDB.calibration[mapID]
    if type(calibration) == "table" then
        scaleX, scaleY = scaleX or calibration.x, scaleY or calibration.y
    end
    scaleX, scaleY = scaleX or 6000, scaleY or 6000

    local pos
    if addon.Compat and addon.Compat.GetStableUnitMapPosition then
        pos = addon.Compat:GetStableUnitMapPosition(mapID, "player", stableNavigationPositionState)
    elseif addon.Compat and addon.Compat.GetUnitMapPosition then
        pos = addon.Compat:GetUnitMapPosition(mapID, "player")
    elseif C_Map and C_Map.GetPlayerMapPosition then
        pos = C_Map.GetPlayerMapPosition(mapID, "player")
    end
    if pos then
        local segmentIndex, _, distanceSq = FindClosestSegment(route, pos, scaleX, scaleY)
        result.closestSegment = segmentIndex
        result.distanceToRoute = distanceSq and math.sqrt(distanceSq) or nil
        if segmentIndex then result.currentPointIndex = math.min(#route.points, segmentIndex + 1) end
    end

    local stateMatches = self.enabled == true
        and navigationState.routeGUID == addon.selectedRouteGUID
        and navigationState.mapID == mapID and navigationState.points == route.points
    if stateMatches then
        result.direction = navigationState.direction
        result.closestSegment = navigationState.closestSegment or result.closestSegment
        result.currentPointIndex = navigationState.currentPointIndex or result.currentPointIndex
        result.targetIndex = navigationState.targetIndex
        result.distanceToRoute = navigationState.distanceToRoute or result.distanceToRoute
    end
    return result
end

-------------------------------------------------
-- START
-------------------------------------------------
