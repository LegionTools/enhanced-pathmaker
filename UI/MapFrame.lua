local addonName, addon = ...
addon.MapFrame = {}

local originalParent
local originalPoint = {}
local originalNorthTagParent 
local originalNorthTagPoint = {} 
local hasInitializedPosition = false 
local originalRotateMinimap = "0" 
local suppressMinimapZoomSave = false
local minimapZoomHooked = false
local farmMinimapMouseWheelEnabled
local nativeMinimapState

addon.selectedRouteGUID = nil 
local lastDeleted = { mapID = nil, guid = nil, data = nil }
addon.useSquareMap = true 
addon.isFarmMode = false 
addon.farmAlpha = 0.6 

local searchFilter = ""
local colorFilter = nil

addon.drawConfig = {
    ghostView = false,
    navEnabled = false,
    heatEnabled = false,
}

addon.MapFrame.tempSettings = {}
addon.MapFrame.settingsSearchFilter = "" 

local function NormalizeFarmAlphaValue(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0.6 end
    value = math.max(0, math.min(1, value))
    if value > 0.995 then return 1 end
    if value < 0.005 then return 0 end
    return value
end

local function GetMaxMinimapZoom()
    -- GetZoomLevels is a count; valid zoom indices start at zero.
    local levels = Minimap and Minimap.GetZoomLevels and Minimap:GetZoomLevels() or 6
    return math.max(0, (tonumber(levels) or 6) - 1)
end

local function EnsurePathmakerSettings()
    PathmakerDB = PathmakerDB or {}
    PathmakerDB.settings = PathmakerDB.settings or {}
    local s = PathmakerDB.settings
    if s.usePathmakerMinimap == nil then s.usePathmakerMinimap = true end
    s.controlsAlpha = math.max(0, math.min(1, tonumber(s.controlsAlpha) or 1))
    s.minimapScale = math.max(0.5, math.min(2.5, tonumber(s.minimapScale) or 1.0))
    local currentZoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    local maxZoom = GetMaxMinimapZoom()
    s.minimapZoom = math.max(0, math.min(maxZoom, math.floor((tonumber(s.minimapZoom) or currentZoom) + 0.5)))
    if s.useSquareMap == nil then s.useSquareMap = true end
    if s.minimapUseFullEdges == nil then s.minimapUseFullEdges = false end
    if not s.clockPosition then s.clockPosition = "DEFAULT" end
    if not s.buttonAngles then s.buttonAngles = {} end
    if s.farmAlpha == nil then s.farmAlpha = 0.6 end
    s.farmAlpha = NormalizeFarmAlphaValue(s.farmAlpha, 0.6)
    if s.farmCircleAlpha == nil then s.farmCircleAlpha = 0.75 end
    if s.farmCircleSize == nil then s.farmCircleSize = 420 end
    if s.farmHideCircle == nil then s.farmHideCircle = false end
    if s.farmShowCompass == nil then s.farmShowCompass = true end
    if s.farmShowCoords == nil then s.farmShowCoords = true end
    if s.farmShowPlayerDot == nil then s.farmShowPlayerDot = true end
    if s.farmShowTooltipHover == nil then s.farmShowTooltipHover = true end
    if not s.farmPlayerMarkerStyle then s.farmPlayerMarkerStyle = "ARROW_HEAD" end
    if s.farmPlayerMarkerSize == nil then s.farmPlayerMarkerSize = 24 end
    s.farmShowPlayerArrow = nil
    s.farmModePlayerArrow = nil
    s.farmPlayerArrowSize = nil
    if s.farmAllowRoutesBeyondCircle == nil then s.farmAllowRoutesBeyondCircle = false end
    if s.farmRotateMinimap == nil then s.farmRotateMinimap = false end
    if s.minimapLocked == nil then s.minimapLocked = false end
    if s.activeRouteAlpha == nil then s.activeRouteAlpha = s.farmRouteAlpha or 1 end
    s.activeRouteAlpha = math.max(0, math.min(1, tonumber(s.activeRouteAlpha) or 1))
    s.farmRouteAlpha = nil
    s.hideActiveRoute = nil
    addon.useSquareMap = s.useSquareMap
    addon.farmAlpha = s.farmAlpha
    addon.farmCircleAlpha = s.farmCircleAlpha
    addon.farmCircleSize = s.farmCircleSize
    addon.farmAllowRoutesBeyondCircle = s.farmAllowRoutesBeyondCircle
    addon.farmRotateMinimap = s.farmRotateMinimap
    if addon.drawConfig then
        addon.drawConfig.farmAllowRoutesBeyondCircle = s.farmAllowRoutesBeyondCircle
    end
    return s
end

local minimapMouseStates = setmetatable({}, { __mode = "k" })

local function SetObjectMouseEnabled(obj, enabled)
    if not obj then return end
    if not enabled and not minimapMouseStates[obj] then
        minimapMouseStates[obj] = {
            mouse = obj.IsMouseEnabled and obj:IsMouseEnabled(),
            motion = obj.IsMouseMotionEnabled and obj:IsMouseMotionEnabled(),
            click = obj.IsMouseClickEnabled and obj:IsMouseClickEnabled(),
        }
    end

    local state = minimapMouseStates[obj]
    if enabled then
        if state then
            if obj.EnableMouse and state.mouse ~= nil then obj:EnableMouse(state.mouse) end
            if obj.SetMouseMotionEnabled and state.motion ~= nil then obj:SetMouseMotionEnabled(state.motion) end
            if obj.SetMouseClickEnabled and state.click ~= nil then obj:SetMouseClickEnabled(state.click) end
            minimapMouseStates[obj] = nil
        end
    else
        if obj.EnableMouse then obj:EnableMouse(false) end
        if obj.SetMouseMotionEnabled then obj:SetMouseMotionEnabled(false) end
        if obj.SetMouseClickEnabled then obj:SetMouseClickEnabled(false) end
    end
end

local function SetMouseTreeEnabled(root, enabled, depth)
    if not root or (depth or 0) > 12 then return end
    SetObjectMouseEnabled(root, enabled)
    if root.GetRegions then
        for _, region in ipairs({root:GetRegions()}) do
            SetObjectMouseEnabled(region, enabled)
        end
    end
    if root.GetChildren then
        for _, child in ipairs({root:GetChildren()}) do
            SetMouseTreeEnabled(child, enabled, (depth or 0) + 1)
        end
    end
end

local SQUARE_MINIMAP_MASK = "Interface\\Buttons\\WHITE8x8"
local LEGACY_CIRCLE_MINIMAP_MASK = "Textures\\MinimapMask"
local RETAIL_CIRCLE_MINIMAP_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function GetCircleMinimapMask()
    -- Forever uses the modern minimap renderer despite its 16001 interface.
    -- The legacy Classic mask can hide the terrain while leaving the border.
    if addon.Compat and (addon.Compat.isRetail or addon.Compat.isForever) then
        return RETAIL_CIRCLE_MINIMAP_MASK
    end
    return LEGACY_CIRCLE_MINIMAP_MASK
end

local function ApplyMinimapShapeMask(useSquare)
    if not Minimap or not Minimap.SetMaskTexture then return end
    Minimap:SetMaskTexture(useSquare and SQUARE_MINIMAP_MASK or GetCircleMinimapMask())
end

function addon.MapFrame:ApplyMinimapShape(useSquare)
    if not self.ownsMinimap then return end
    ApplyMinimapShapeMask(useSquare)
end

local function ApplyHiddenMinimapMouseMode(frame)
    if not frame then return end
    SetMouseTreeEnabled(frame, false)

    -- Keep the actual minimap surface interactive for pings and normal map
    -- clicks while every surrounding PathMaker/native button stays disabled.
    if Minimap then
        SetObjectMouseEnabled(Minimap, true)
        Minimap:EnableMouse(true)
        if Minimap.SetMouseMotionEnabled then Minimap:SetMouseMotionEnabled(true) end
        if Minimap.SetMouseClickEnabled then Minimap:SetMouseClickEnabled(true) end
    end
end

local function SaveMinimapZoom(zoom)
    if suppressMinimapZoomSave or not addon.MapFrame.ownsMinimap then return end
    local s = EnsurePathmakerSettings()
    local maxZoom = GetMaxMinimapZoom()
    s.minimapZoom = math.max(0, math.min(maxZoom, math.floor((tonumber(zoom) or 0) + 0.5)))
end

local function SetRememberedMinimapZoom(zoom)
    if not Minimap or not Minimap.SetZoom then return end
    local s = EnsurePathmakerSettings()
    local maxZoom = GetMaxMinimapZoom()
    zoom = math.max(0, math.min(maxZoom, math.floor((tonumber(zoom) or s.minimapZoom or 0) + 0.5)))
    s.minimapZoom = zoom
    suppressMinimapZoomSave = true
    Minimap:SetZoom(zoom)
    suppressMinimapZoomSave = false
end

local function EnsureMinimapZoomHook()
    if minimapZoomHooked or not Minimap or not hooksecurefunc then return end
    minimapZoomHooked = true
    hooksecurefunc(Minimap, "SetZoom", function(_, zoom)
        SaveMinimapZoom(zoom)
    end)
end

local function GetMinimapButtonOffset(angle, radius, useSquareMap)
    local cosValue = math.cos(angle)
    local sinValue = math.sin(angle)

    if useSquareMap then
        local maxTrig = math.max(math.abs(cosValue), math.abs(sinValue))
        if maxTrig == 0 then maxTrig = 1 end
        return radius * (cosValue / maxTrig), radius * (sinValue / maxTrig)
    end

    return radius * cosValue, radius * sinValue
end

local FARM_GREEN = { 0.48, 0.64, 0.16 }
local FARM_PLAYER_ARROW_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "PathMaker") .. "\\chevron"
local FARM_NODE_RING_RANGE_YARDS = 145
local FARM_NODE_ICON_SIZE = 10
local FARM_MARKER_UPDATE_INTERVAL = 0.03
local FARM_NODE_REBUILD_INTERVAL = 1.25
local FARM_NODE_REBUILD_DISTANCE_YARDS = 24
local FARM_GOLD_BLIP_CAPTURE_INTERVAL = 0.10
local FARM_GATHERING_REFRESH_INTERVAL = 1.00
local FARM_COORD_UPDATE_INTERVAL = 0.10
local FARM_BUTTON_LAYOUT_INTERVAL = 1.50
local FARM_COMPASS_DIRECTIONS = {
    { text = "N", angle = 0 },
    { text = "NE", angle = math.pi / 4 },
    { text = "E", angle = math.pi / 2 },
    { text = "SE", angle = math.pi * 3 / 4 },
    { text = "S", angle = math.pi },
    { text = "SW", angle = math.pi * 5 / 4 },
    { text = "W", angle = math.pi * 3 / 2 },
    { text = "NW", angle = math.pi * 7 / 4 },
}
local FARM_PLAYER_MARKER_STYLES = {
    ARROW_HEAD = true,
    DOT = true,
    NATIVE_ARROW = true,
}
local farmMinimapTooltipFilterHooked = false
local farmNativePlayerArrowVisibleState = nil

local function GetFarmPlayerMarkerStyle(settings)
    local style = settings and settings.farmPlayerMarkerStyle or "ARROW_HEAD"
    if not FARM_PLAYER_MARKER_STYLES[style] then style = "ARROW_HEAD" end
    return style
end

local function GetFarmPlayerMarkerSize(settings)
    local size = settings and settings.farmPlayerMarkerSize or 24
    return math.max(5, math.min(80, size))
end

local function SetTextureRotation(texture, angle)
    if texture and texture.SetRotation then
        texture:SetRotation(angle)
    end
end

local function KeepFarmOverlayVisible(frame, alpha)
    if frame and frame.SetIgnoreParentAlpha then
        frame:SetIgnoreParentAlpha(true)
    end
    if frame and frame.SetAlpha then
        frame:SetAlpha(alpha or 1)
    end
end

local function GetSelectedRouteColor()
    local mapID = addon.selectedRouteMapID or C_Map.GetBestMapForUnit("player")
    local route = mapID and addon.selectedRouteGUID and PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[mapID] and PathmakerDB.routes[mapID][addon.selectedRouteGUID]
    return (route and route.color) or { FARM_GREEN[1], FARM_GREEN[2], FARM_GREEN[3], 1 }
end

local function GetFarmViewRotation()
    local s = PathmakerDB and PathmakerDB.settings
    if not s or s.farmRotateMinimap ~= true then return 0 end
    local f = addon.MapFrame and addon.MapFrame.farmFrame
    -- Blizzard rotates the native minimap from the current facing. Using a
    -- separately smoothed angle makes PathMaker pins visibly slide against it.
    return -((GetPlayerFacing and GetPlayerFacing()) or (f and f.pmSmoothFacing) or 0)
end

local function GetFarmCompassRotation()
    local s = PathmakerDB and PathmakerDB.settings
    if not s or s.farmRotateMinimap ~= true then return 0 end
    local f = addon.MapFrame and addon.MapFrame.farmFrame
    return (GetPlayerFacing and GetPlayerFacing()) or (f and f.pmSmoothFacing) or 0
end

local function SmoothFarmValue(current, target, elapsed, speed)
    if current == nil then return target end
    local factor = 1 - math.exp(-(speed or 18) * math.max(elapsed or 0, 0))
    return current + ((target - current) * factor)
end

local function SmoothFarmAngle(current, target, elapsed, speed)
    if current == nil then return target end
    local delta = math.atan2(math.sin(target - current), math.cos(target - current))
    local factor = 1 - math.exp(-(speed or 22) * math.max(elapsed or 0, 0))
    return current + (delta * factor)
end

local function GetFarmVisibleRadiusYards()
    local farmFrame = addon.isFarmMode and addon.MapFrame and addon.MapFrame.farmFrame
    if farmFrame and farmFrame.pmFarmViewRadiusOverride then
        return farmFrame.pmFarmViewRadiusOverride
    end
    if addon.UI and addon.UI.GetMinimapViewRadius then
        return addon.UI:GetMinimapViewRadius()
    end
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    local ZOOM_RANGES = {[0] = 230, [1] = 190, [2] = 150, [3] = 110, [4] = 80, [5] = 50}
    return ZOOM_RANGES[zoom] or 100
end

local function GetFarmMaxDrawRadius(settings)
    local s = settings or EnsurePathmakerSettings()
    local size = math.max(160, math.min(900, s.farmCircleSize or 420))
    local radius = (size / 2) - 10
    if s.farmAllowRoutesBeyondCircle then
        return radius * 2.5
    end
    return radius
end

local FARM_BLOCKING_FRAME_NAMES = {
    "GameMenuFrame",
    "WorldMapFrame",
    "CharacterFrame",
    "SpellBookFrame",
    "QuestLogFrame",
    "QuestLogFramePanel",
    "FriendsFrame",
    "PVEFrame",
    "LFDParentFrame",
    "PlayerTalentFrame",
    "AchievementFrame",
    "CollectionsJournal",
    "EncounterJournal",
    "MerchantFrame",
    "TradeSkillFrame",
    "CraftFrame",
    "AuctionHouseFrame",
    "BankFrame",
    "MailFrame",
    "GossipFrame",
    "QuestFrame",
}

local function IsFarmBlockedByUIPanel()
    for _, frameName in ipairs(FARM_BLOCKING_FRAME_NAMES) do
        local frame = _G[frameName]
        if frame and frame.IsShown and frame:IsShown() then
            return true
        end
    end

    local uiPanels = _G.UIPanelWindows
    if type(uiPanels) == "table" then
        for frameName in pairs(uiPanels) do
            local frame = _G[frameName]
            if frame and frame.IsShown and frame:IsShown() then
                return true
            end
        end
    end

    return false
end

local function NormalizeGatheringNodeType(nodeType)
    if nodeType == "Herbalism" or nodeType == "Herb Gathering" then return "Herb" end
    if nodeType == "Mine" then return "Mining" end
    return nodeType
end

local function PlayerHasGatheringProfession(nodeType)
    local normalizedType = NormalizeGatheringNodeType(nodeType)

    if addon.Heatmap and type(addon.Heatmap.PlayerHasProfession) == "function" then
        return addon.Heatmap:PlayerHasProfession(normalizedType)
    end

    local profs = {GetProfessions()}
    for _, index in ipairs(profs) do
        if index then
            local name, icon, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(index)
            if normalizedType == "Mining" and (skillLine == 186 or name == "Mining") then return true end
            if normalizedType == "Herb" and (skillLine == 182 or name == "Herbalism" or name == "Herb Gathering") then return true end
        end
    end

    if normalizedType == "Mining" then
        return addon.Compat and (addon.Compat:IsSpellKnown(2575) or addon.Compat:IsSpellKnown(2580)) or false
    elseif normalizedType == "Herb" then
        return addon.Compat and (addon.Compat:IsSpellKnown(2366) or addon.Compat:IsSpellKnown(2383)) or false
    end

    return false
end

local RestoreNativeFarmPlayerArrow
local SetNativeFarmPlayerArrowVisible
local KeepNativeGatheringTrackingVisible
local RestoreNativeGatheringTrackingVisible

local function RestorePathmakerMinimapToFrame(frame)
    if not Minimap or not frame then return end
    RestoreNativeFarmPlayerArrow()
    RestoreNativeGatheringTrackingVisible()
    Minimap.pmFarmAnchor = nil
    Minimap.pmFarmSize = nil
    if Minimap.SetIgnoreParentAlpha then Minimap:SetIgnoreParentAlpha(true) end
    Minimap:SetParent(frame)
    Minimap:ClearAllPoints()
    local w, h = frame:GetSize()
    if w and h and w > 2 and h > 2 then
        Minimap:SetSize(w - 2, h - 2)
    end
    Minimap:SetPoint("TOPLEFT", 1, -1)
    Minimap:SetPoint("BOTTOMRIGHT", -1, 1)
    if frame.GetFrameStrata then Minimap:SetFrameStrata(frame:GetFrameStrata()) end
    Minimap:SetFrameLevel(frame:GetFrameLevel() + 1)
    Minimap:SetAlpha(1)
    Minimap:Show()
end

local function ApplyFarmMinimapAlpha(frame, alpha)
    if not Minimap or not frame then return end
    local alphaHost = frame.pmMinimapAlphaHost or frame

    -- The native minimap render surface can ignore parent alpha on every client
    -- flavor, so apply the selected opacity directly to Minimap. The dedicated
    -- host and Farm Mode artwork remain opaque.
    if frame.SetAlpha then frame:SetAlpha(1) end
    if alphaHost.SetAlpha then alphaHost:SetAlpha(1) end
    if Minimap.SetIgnoreParentAlpha then Minimap:SetIgnoreParentAlpha(true) end
    Minimap:SetAlpha(alpha)
    Minimap.pmFarmAppliedAlpha = alpha
end

local function RestoreNativeMinimapToFarmFrame(frame, settings)
    if not Minimap or not frame then return end
    local s = settings or EnsurePathmakerSettings()
    local alphaHost = frame.pmMinimapAlphaHost or frame
    local size = math.max(160, math.min(900, s.farmCircleSize or 420))
    local minimapSize = math.max(1, size - 2)
    local alpha = NormalizeFarmAlphaValue(s.farmAlpha, addon.farmAlpha or 0.6)
    s.farmAlpha = alpha
    addon.farmAlpha = alpha

    if Minimap:GetParent() ~= alphaHost then
        Minimap:SetParent(alphaHost)
        Minimap.pmFarmAnchor = nil
    end
    if Minimap.pmFarmAnchor ~= alphaHost then
        Minimap:ClearAllPoints()
        Minimap:SetPoint("CENTER", alphaHost, "CENTER", 0, 0)
        Minimap.pmFarmAnchor = alphaHost
    end
    if not Minimap.pmFarmSize or math.abs(Minimap.pmFarmSize - minimapSize) > 0.1 then
        Minimap:SetSize(minimapSize, minimapSize)
        Minimap.pmFarmSize = minimapSize
        Minimap.pmFarmSizeChanged = true
    end
    Minimap:SetFrameStrata("LOW")
    Minimap:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
    ApplyMinimapShapeMask(false)
    ApplyFarmMinimapAlpha(frame, alpha)
    Minimap:Show()
    KeepNativeGatheringTrackingVisible()
end

local function ApplyFarmRotationSetting(settings)
    if not addon.isFarmMode then return false end
    local s = settings or EnsurePathmakerSettings()
    local enabled = s.farmRotateMinimap == true
    local desiredCVar = enabled and "1" or "0"
    addon.farmRotateMinimap = enabled

    local cvarChanged = GetCVar and GetCVar("rotateMinimap") ~= desiredCVar
    if cvarChanged and SetCVar then
        SetCVar("rotateMinimap", desiredCVar)
    end

    local f = addon.MapFrame and addon.MapFrame.farmFrame
    local settingChanged = f and f.pmFarmAppliedRotate ~= enabled
    if settingChanged then
        f.pmFarmAppliedRotate = enabled
        f.pmSmoothFacing = GetPlayerFacing and GetPlayerFacing() or 0
        f.pmFarmRenderChanged = true
        f.pmFarmOverlayDirty = true
        f.pmFarmRouteDirty = true
        f.pmFarmNodesDirty = true
    end

    return settingChanged or cvarChanged
end

local minimapTextureRefreshGeneration = 0
local minimapTextureRefreshBaseZoom

local function ForceMinimapTextureRefresh()
    if not Minimap or not Minimap.GetZoom or not Minimap.SetZoom then return end
    minimapTextureRefreshGeneration = minimapTextureRefreshGeneration + 1
    local refreshGeneration = minimapTextureRefreshGeneration
    if minimapTextureRefreshBaseZoom == nil then
        minimapTextureRefreshBaseZoom = Minimap:GetZoom() or 0
    end
    local zoom = minimapTextureRefreshBaseZoom
    local maxZoom = GetMaxMinimapZoom()
    local tempZoom = zoom > 0 and (zoom - 1) or math.min(zoom + 1, maxZoom)
    -- Keep the selected percentage throughout the refresh. Temporarily forcing
    -- alpha 1 here creates a visible flash whenever the map provider changes.
    if addon.isFarmMode then
        Minimap.pmFarmAlphaPriming = true
        local refreshAlpha = NormalizeFarmAlphaValue(
            EnsurePathmakerSettings().farmAlpha, addon.farmAlpha or 0.6)
        if addon.MapFrame and addon.MapFrame.farmFrame then
            ApplyFarmMinimapAlpha(addon.MapFrame.farmFrame, refreshAlpha)
        else
            Minimap:SetAlpha(refreshAlpha)
        end
    end

    local function RestoreRefreshState()
        if refreshGeneration ~= minimapTextureRefreshGeneration or not Minimap then return end

        suppressMinimapZoomSave = true
        Minimap:SetZoom(zoom)
        suppressMinimapZoomSave = false

        if addon.isFarmMode and addon.MapFrame and addon.MapFrame.farmFrame then
            local restoreAlpha = NormalizeFarmAlphaValue(
                EnsurePathmakerSettings().farmAlpha, addon.farmAlpha or 0.6)
            Minimap.pmFarmAlphaPriming = nil
            ApplyFarmMinimapAlpha(addon.MapFrame.farmFrame, restoreAlpha)
        else
            Minimap.pmFarmAlphaPriming = nil
            Minimap:SetAlpha(1)
            Minimap.pmFarmAppliedAlpha = nil
        end
        minimapTextureRefreshBaseZoom = nil
    end

    if tempZoom ~= zoom then
        suppressMinimapZoomSave = true
        Minimap:SetZoom(tempZoom)
        suppressMinimapZoomSave = false
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RestoreRefreshState)
        else
            RestoreRefreshState()
        end
    else
        suppressMinimapZoomSave = true
        Minimap:SetZoom(zoom)
        suppressMinimapZoomSave = false
        if addon.isFarmMode and addon.MapFrame and addon.MapFrame.farmFrame then
            local restoreAlpha = NormalizeFarmAlphaValue(
                EnsurePathmakerSettings().farmAlpha, addon.farmAlpha or 0.6)
            Minimap.pmFarmAlphaPriming = nil
            ApplyFarmMinimapAlpha(addon.MapFrame.farmFrame, restoreAlpha)
        else
            Minimap.pmFarmAlphaPriming = nil
            Minimap:SetAlpha(1)
            Minimap.pmFarmAppliedAlpha = nil
        end
        minimapTextureRefreshBaseZoom = nil
    end
end

local function RefreshRestoredNativeMinimap()
    if not Minimap or not Minimap.GetZoom or not Minimap.SetZoom then return end

    -- Cancel a Farm Mode refresh that may still be waiting for its zero-delay
    -- callback. Otherwise that callback can put the farm zoom/alpha back after
    -- RestoreNativeMinimapState has already restored Blizzard's minimap.
    minimapTextureRefreshGeneration = minimapTextureRefreshGeneration + 1
    local refreshGeneration = minimapTextureRefreshGeneration
    minimapTextureRefreshBaseZoom = nil

    Minimap.pmFarmAnchor = nil
    Minimap.pmFarmSize = nil
    Minimap.pmFarmSizeChanged = nil
    Minimap.pmFarmAppliedAlpha = nil
    Minimap.pmFarmAlphaPriming = nil

    local zoom = Minimap:GetZoom() or 0
    local alpha = Minimap.GetAlpha and Minimap:GetAlpha() or 1
    local ignoreParentAlpha
    if Minimap.GetIgnoreParentAlpha then
        ignoreParentAlpha = Minimap:GetIgnoreParentAlpha()
    elseif Minimap.IsIgnoringParentAlpha then
        ignoreParentAlpha = Minimap:IsIgnoringParentAlpha()
    end
    local wasShown = Minimap.IsShown and Minimap:IsShown()
    local maxZoom = GetMaxMinimapZoom()
    local tempZoom = zoom > 0 and (zoom - 1) or math.min(zoom + 1, maxZoom)

    local function RestoreNativeRefreshState()
        if refreshGeneration ~= minimapTextureRefreshGeneration
            or addon.isFarmMode or addon.MapFrame.ownsMinimap or not Minimap
        then
            return
        end
        suppressMinimapZoomSave = true
        Minimap:SetZoom(zoom)
        suppressMinimapZoomSave = false
        if Minimap.SetAlpha then Minimap:SetAlpha(alpha) end
        if ignoreParentAlpha ~= nil and Minimap.SetIgnoreParentAlpha then
            Minimap:SetIgnoreParentAlpha(ignoreParentAlpha)
        end
        if wasShown ~= nil then
            if wasShown then Minimap:Show() else Minimap:Hide() end
        end
    end

    suppressMinimapZoomSave = true
    Minimap:SetZoom(tempZoom)
    suppressMinimapZoomSave = false
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RestoreNativeRefreshState)
    else
        RestoreNativeRefreshState()
    end
end

local function SetFarmMinimapZoomLocked(locked)
    if not Minimap or not Minimap.EnableMouseWheel then return end
    if locked then
        if farmMinimapMouseWheelEnabled == nil then
            farmMinimapMouseWheelEnabled = Minimap.IsMouseWheelEnabled and Minimap:IsMouseWheelEnabled()
            if farmMinimapMouseWheelEnabled == nil then farmMinimapMouseWheelEnabled = true end
        end
        Minimap:EnableMouseWheel(false)
    elseif farmMinimapMouseWheelEnabled ~= nil then
        Minimap:EnableMouseWheel(farmMinimapMouseWheelEnabled)
        farmMinimapMouseWheelEnabled = nil
    end
end

local function GetMapCoordinateScales(mapID)
    local scaleX, scaleY
    if addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID or C_Map.GetBestMapForUnit("player"))
    end
    return scaleX or (addon.UI and addon.UI.scaleX) or 6000,
           scaleY or (addon.UI and addon.UI.scaleY) or 6000
end

local function RequestFarmMinimapTextureRefresh(owner)
    if not addon.isFarmMode then return end
    owner = owner or Minimap
    if not owner or not C_Timer or not C_Timer.After or not GetTime then
        ForceMinimapTextureRefresh()
        return
    end

    local now = GetTime()
    if not owner.pmFarmTextureRefreshAt or (now - owner.pmFarmTextureRefreshAt) >= 0.20 then
        owner.pmFarmTextureRefreshAt = now
        ForceMinimapTextureRefresh()
        return
    end

    if owner.pmFarmTextureRefreshQueued then return end
    owner.pmFarmTextureRefreshQueued = true
    C_Timer.After(0.22, function()
        if owner then
            owner.pmFarmTextureRefreshQueued = nil
            owner.pmFarmTextureRefreshAt = GetTime and GetTime() or 0
        end
        if addon.isFarmMode then
            ForceMinimapTextureRefresh()
        end
    end)
end

function addon.MapFrame:ApplyFarmAlpha(settings)
    local s = settings or EnsurePathmakerSettings()
    local alpha = NormalizeFarmAlphaValue(s.farmAlpha, addon.farmAlpha or 0.6)
    s.farmAlpha = alpha
    addon.farmAlpha = alpha

    if addon.isFarmMode and Minimap then
        if self.farmFrame then
            local size = math.max(160, math.min(900, s.farmCircleSize or 420))
            local minimapSize = math.max(1, size - 2)
            local alphaHost = self.farmFrame.pmMinimapAlphaHost or self.farmFrame
            if Minimap:GetParent() == alphaHost and Minimap.pmFarmAnchor == alphaHost and Minimap.pmFarmSize and math.abs(Minimap.pmFarmSize - minimapSize) <= 0.1 then
                ApplyFarmMinimapAlpha(self.farmFrame, alpha)
            else
                RestoreNativeMinimapToFarmFrame(self.farmFrame, s)
            end
        else
            if Minimap.SetIgnoreParentAlpha then Minimap:SetIgnoreParentAlpha(true) end
            Minimap:SetAlpha(alpha)
            Minimap.pmFarmAppliedAlpha = alpha
        end
        -- Slider changes affect only the native minimap image. Farm overlays
        -- remain fully opaque.
    end

    return alpha
end

local farmMinimapChildStates = {}
local farmHiddenMinimapHolder
local farmNativePlayerArrowStates = {}
local farmGatheringTrackingStates = {}
local farmInteractiveGoldBlips = {}
local farmGatheringTrackingScan
local farmGatheringTrackingScanGeneration = 0
local farmGatheringTrackingLastScanAt
local farmGatheringTrackingLastTooltipSetting
local farmOriginalPlayerTextureApplied = false
local farmOriginalPlayerTextureWidth
local farmOriginalPlayerTextureHeight
local farmOriginalPlayerTextureAlpha

local function ReadOptionalObjectState(obj, methodName)
    local method = obj and obj[methodName]
    if method then return method(obj) end
    return nil
end

local function StoreAndHideFarmMinimapObject(obj)
    if not obj then return end
    if not farmMinimapChildStates[obj] then
        farmMinimapChildStates[obj] = {
            shown = ReadOptionalObjectState(obj, "IsShown"),
            alpha = obj.GetAlpha and obj:GetAlpha() or nil,
            mouse = ReadOptionalObjectState(obj, "IsMouseEnabled"),
            mouseMotion = ReadOptionalObjectState(obj, "IsMouseMotionEnabled"),
            mouseClick = ReadOptionalObjectState(obj, "IsMouseClickEnabled"),
        }
    end
    if obj.SetAlpha then obj:SetAlpha(0) end
    if obj.Hide then obj:Hide() end
    if obj.EnableMouse then obj:EnableMouse(false) end
    if obj.SetMouseMotionEnabled then obj:SetMouseMotionEnabled(false) end
    if obj.SetMouseClickEnabled then obj:SetMouseClickEnabled(false) end
    if not obj.pmPathmakerFarmShowHooked and hooksecurefunc and obj.Show then
        obj.pmPathmakerFarmShowHooked = true
        local farmObject = obj
        hooksecurefunc(obj, "Show", function()
            if addon.isFarmMode and farmMinimapChildStates[farmObject] and farmObject.Hide then
                farmObject:Hide()
            end
        end)
    end
end

local function IsNativeMinimapPlayerArrow(region)
    if not region then return false end
    local regionName = region.GetName and region:GetName()
    if regionName then
        local lowerRegionName = string.lower(regionName)
        if string.find(lowerRegionName, "minimapplayer", 1, true) or string.find(lowerRegionName, "playerframe", 1, true) then
            return true
        end
        if string.find(lowerRegionName, "navigation", 1, true) or
           string.find(lowerRegionName, "supertrack", 1, true) or
           string.find(lowerRegionName, "waypoint", 1, true) then
            return true
        end
        if string.find(lowerRegionName, "player", 1, true) and string.find(lowerRegionName, "arrow", 1, true) then
            return true
        end
        if string.find(lowerRegionName, "player", 1, true) and string.find(lowerRegionName, "icon", 1, true) then
            return true
        end
        if string.find(lowerRegionName, "player", 1, true) and string.find(lowerRegionName, "pin", 1, true) then
            return true
        end
        if string.find(lowerRegionName, "arrow", 1, true) and not string.find(lowerRegionName, "pathmaker", 1, true) then
            return true
        end
    end
    if region.GetAtlas then
        local atlas = region:GetAtlas()
        if atlas then
            local atlasName = tostring(atlas):lower()
            if (string.find(atlasName, "player", 1, true) and string.find(atlasName, "arrow", 1, true)) or
               string.find(atlasName, "minimap-player", 1, true) or
               string.find(atlasName, "navigation", 1, true) or
               string.find(atlasName, "supertrack", 1, true) or
               string.find(atlasName, "waypoint", 1, true) then
                return true
            end
        end
    end
    if not region.GetTexture then return false end
    local texture = region:GetTexture()
    if not texture then return false end
    local textureName = tostring(texture):lower()
    return string.find(textureName, "minimaparrow", 1, true) ~= nil or
           string.find(textureName, "minimap_arrow", 1, true) ~= nil or
           string.find(textureName, "minimap\\minimaparrow", 1, true) ~= nil or
           (string.find(textureName, "player", 1, true) and string.find(textureName, "arrow", 1, true))
end

local function IsNativeGatheringTrackingRegion(region)
    if not region then return false end
    local regionName = region.GetName and region:GetName()
    if regionName then
        local lowerRegionName = string.lower(regionName)
        if string.find(lowerRegionName, "button", 1, true) or
           string.find(lowerRegionName, "minimaptracking", 1, true) or
           string.find(lowerRegionName, "trackingbutton", 1, true) or
           string.find(lowerRegionName, "pathmaker", 1, true) then
            return false
        end
        if string.find(lowerRegionName, "tracking", 1, true) or
           string.find(lowerRegionName, "blip", 1, true) or
           string.find(lowerRegionName, "poi", 1, true) or
           string.find(lowerRegionName, "quest", 1, true) or
           string.find(lowerRegionName, "vignette", 1, true) then
            return true
        end
    end
    if region.GetAtlas then
        local atlas = region:GetAtlas()
        if atlas then
            local atlasName = tostring(atlas):lower()
            if string.find(atlasName, "minimap", 1, true) or
               string.find(atlasName, "poi", 1, true) or
               string.find(atlasName, "vignette", 1, true) or
               string.find(atlasName, "tracking-herb", 1, true) or
               string.find(atlasName, "tracking-mining", 1, true) then
                return true
            end
        end
    end
    if not region.GetTexture then return false end
    local texture = region:GetTexture()
    if not texture then return false end
    local textureName = tostring(texture):lower()
    return string.find(textureName, "objecticons", 1, true) ~= nil or
           string.find(textureName, "minimap\\object", 1, true) ~= nil or
           string.find(textureName, "tracking", 1, true) ~= nil or
           string.find(textureName, "poi", 1, true) ~= nil or
           string.find(textureName, "vignette", 1, true) ~= nil
end

local IsCursorOverFarmGoldBlip

local function IsCursorOverFrame(frame)
    if not frame or not frame.GetLeft or not frame.GetRight or not GetCursorPosition then return false end
    if frame.IsShown and not frame:IsShown() then return false end
    if frame.IsMouseOver and frame:IsMouseOver() then return true end
    local cursorX, cursorY = GetCursorPosition()
    if not cursorX or not cursorY then return false end
    local scale = frame.GetEffectiveScale and (frame:GetEffectiveScale() or 1) or 1
    cursorX, cursorY = cursorX / scale, cursorY / scale
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not left or not right or not top or not bottom then return false end
    return cursorX >= left and cursorX <= right and cursorY >= bottom and cursorY <= top
end

local function IsCursorOverFarmMapArea()
    local farmFrame = addon.MapFrame and addon.MapFrame.farmFrame
    return IsCursorOverFrame(Minimap) or IsCursorOverFrame(farmFrame)
end

local function IsFarmMinimapTooltipOwner()
    if not GameTooltip or not GameTooltip.GetOwner then return false end
    local owner = GameTooltip:GetOwner()
    if owner == Minimap then return true end
    while owner and owner.GetParent do
        owner = owner:GetParent()
        if owner == Minimap then return true end
    end
    return false
end

local function HideFarmTooltipNow()
    if not GameTooltip then return end
    GameTooltip:Hide()
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    if GameTooltip.SetAlpha then GameTooltip:SetAlpha(1) end
end

local function FilterFarmMinimapTooltip()
    -- Farm Mode must never suppress Blizzard's normal bottom-right tooltip.
    -- This includes world mouseover units as well as minimap objects, whether
    -- or not the optional Farm Mode tooltip checkbox is checked.
end

local function EnsureFarmMinimapTooltipFilter()
    if farmMinimapTooltipFilterHooked or not GameTooltip or not GameTooltip.HookScript then return end
    farmMinimapTooltipFilterHooked = true
    GameTooltip:HookScript("OnShow", FilterFarmMinimapTooltip)
    pcall(function() GameTooltip:HookScript("OnTooltipSetUnit", FilterFarmMinimapTooltip) end)
end

local function ShowFarmNodeTooltip(btn)
    if not GameTooltip or not btn or not btn.nodeData then return end
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, btn)
    else
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    end
    local node = btn.nodeData
    GameTooltip:SetText(node.specificName or node.name or node.type or "Gathering Node")
    if node.type then GameTooltip:AddLine(node.type, 0.75, 0.75, 0.75) end
    GameTooltip:Show()
end

local function HideFarmNodeTooltip(btn)
    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(btn)) then
        GameTooltip:Hide()
    end
end

local function SetFarmNodeButtonMouseEnabled(btn)
    if not btn then return end
    if btn.SetFrameStrata then btn:SetFrameStrata("LOW") end
    local tooltipEnabled = addon.isFarmMode
        and EnsurePathmakerSettings().farmShowTooltipHover == true
    -- Custom gathering-node markers should only capture the cursor when the
    -- Farm Mode mouse-tooltip option is enabled.
    btn:EnableMouse(tooltipEnabled)
    if btn.SetMouseMotionEnabled then btn:SetMouseMotionEnabled(tooltipEnabled) end
    if btn.SetMouseClickEnabled then btn:SetMouseClickEnabled(false) end
    btn:SetScript("OnEnter", tooltipEnabled and ShowFarmNodeTooltip or nil)
    btn:SetScript("OnLeave", tooltipEnabled and HideFarmNodeTooltip or nil)
end

local function IsCursorOverFarmBlipObject(obj, cursorX, cursorY)
    if not obj or not obj.GetCenter then return false end
    if obj.IsShown and not obj:IsShown() then return false end

    local width = obj.GetWidth and (obj:GetWidth() or 0) or 0
    local height = obj.GetHeight and (obj:GetHeight() or 0) or 0
    if width > 42 or height > 42 then return false end

    local scale = obj.GetEffectiveScale and (obj:GetEffectiveScale() or 1) or 1
    local mx, my = cursorX / scale, cursorY / scale
    local cx, cy = obj:GetCenter()
    if not cx or not cy then return false end

    local radius = math.max(8, math.min(22, (math.max(width, height) / 2) + 6))
    local dx, dy = mx - cx, my - cy
    return ((dx * dx) + (dy * dy)) <= (radius * radius)
end

IsCursorOverFarmGoldBlip = function()
    if not addon.isFarmMode or not Minimap or not GetCursorPosition then return false end
    local cursorX, cursorY = GetCursorPosition()
    if not cursorX or not cursorY then return false end

    for i = 1, #farmInteractiveGoldBlips do
        if IsCursorOverFarmBlipObject(farmInteractiveGoldBlips[i], cursorX, cursorY) then
            return true
        end
    end
    return false
end

local function ShouldCaptureFarmMinimapMouse()
    if not addon.isFarmMode then return false end
    local settings = EnsurePathmakerSettings()
    return settings.farmShowTooltipHover == true
end

local function UpdateFarmGoldBlipMouseCapture(force)
    if not Minimap then return end
    local hoverEnabled = ShouldCaptureFarmMinimapMouse()
    local now = GetTime and GetTime() or 0
    if not force and now > 0 and Minimap.pmFarmGoldBlipCheckedAt and (now - Minimap.pmFarmGoldBlipCheckedAt) < FARM_GOLD_BLIP_CAPTURE_INTERVAL then
        return
    end
    Minimap.pmFarmGoldBlipCheckedAt = now

    if hoverEnabled and addon.isFarmMode then
        if not Minimap.pmFarmGatheringRefreshAt or (now - Minimap.pmFarmGatheringRefreshAt) > FARM_GATHERING_REFRESH_INTERVAL then
            Minimap.pmFarmGatheringRefreshAt = now
            KeepNativeGatheringTrackingVisible()
        end
    end

    -- Native gathering POIs are rendered into the minimap itself on Retail, so
    -- they do not always have a child frame that can be hit-tested here. While
    -- mouse tooltips are enabled, let the minimap receive mouse motion across
    -- the farm-map area and allow Blizzard to resolve the gold POI under the
    -- cursor. With the option disabled the entire farm map remains click-through.
    local shouldCapture = hoverEnabled
        and addon.isFarmMode == true
        and IsCursorOverFarmMapArea()
    local allowHover = hoverEnabled and addon.isFarmMode == true

    if Minimap.pmFarmGoldBlipMouseCapture ~= shouldCapture or Minimap.pmFarmHoverEnabled ~= allowHover then
        Minimap.pmFarmGoldBlipMouseCapture = shouldCapture
        Minimap.pmFarmHoverEnabled = allowHover
        -- Mouse Tooltip is an explicit opt-in: the minimap captures mouse
        -- motion inside its farm-mode bounds only while that option is active.
        Minimap:EnableMouse(shouldCapture)
        if Minimap.SetMouseMotionEnabled then Minimap:SetMouseMotionEnabled(shouldCapture) end
        if Minimap.SetMouseClickEnabled then Minimap:SetMouseClickEnabled(false) end
    end

    if allowHover then
        FilterFarmMinimapTooltip()
    elseif GameTooltip and IsFarmMinimapTooltipOwner() then
        HideFarmTooltipNow()
    end
end

function KeepNativeGatheringTrackingVisible()
    if not Minimap then return end
    local tooltipsEnabled = ShouldCaptureFarmMinimapMouse()
    local tooltipSettingChanged = farmGatheringTrackingLastTooltipSetting ~= nil and
        farmGatheringTrackingLastTooltipSetting ~= tooltipsEnabled
    if farmGatheringTrackingScan then
        -- A tooltip setting change needs a fresh pass, but repeated farm-layout
        -- updates should share the scan that is already in progress.
        if farmGatheringTrackingScan.tooltipsEnabled == tooltipsEnabled then return end
        farmGatheringTrackingScanGeneration = farmGatheringTrackingScanGeneration + 1
        farmGatheringTrackingScan = nil
    end

    local now = GetTime and GetTime() or 0
    if not tooltipSettingChanged and farmGatheringTrackingLastScanAt and now > 0 and
       (now - farmGatheringTrackingLastScanAt) < FARM_GATHERING_REFRESH_INTERVAL then
        return
    end

    farmGatheringTrackingLastScanAt = now
    farmGatheringTrackingLastTooltipSetting = tooltipsEnabled
    wipe(farmInteractiveGoldBlips)
    local function ApplyObject(obj)
        if IsNativeMinimapPlayerArrow(obj) then return end
        if not IsNativeGatheringTrackingRegion(obj) then return end
        if not farmGatheringTrackingStates[obj] then
            farmGatheringTrackingStates[obj] = {
                alpha = obj.GetAlpha and obj:GetAlpha() or nil,
                ignoreParentAlpha = ReadOptionalObjectState(obj, "GetIgnoreParentAlpha"),
                mouse = ReadOptionalObjectState(obj, "IsMouseEnabled"),
                mouseMotion = ReadOptionalObjectState(obj, "IsMouseMotionEnabled"),
                mouseClick = ReadOptionalObjectState(obj, "IsMouseClickEnabled"),
                frameStrata = obj.GetFrameStrata and obj:GetFrameStrata() or nil,
                frameLevel = obj.GetFrameLevel and obj:GetFrameLevel() or nil,
                drawLayer = obj.GetDrawLayer and obj:GetDrawLayer() or nil,
            }
        end
        if obj.SetIgnoreParentAlpha then obj:SetIgnoreParentAlpha(true) end
        if obj.SetAlpha then obj:SetAlpha(1) end
        if obj.SetDrawLayer then obj:SetDrawLayer("OVERLAY", 7) end
        local farmFrame = addon.MapFrame and addon.MapFrame.farmFrame
        if farmFrame and obj.SetFrameStrata and farmFrame.GetFrameStrata then
            obj:SetFrameStrata(farmFrame:GetFrameStrata())
        end
        if farmFrame and obj.SetFrameLevel and farmFrame.GetFrameLevel then
            obj:SetFrameLevel(farmFrame:GetFrameLevel() + 20)
        end
        local isInteractiveBlip = tooltipsEnabled
        if isInteractiveBlip then
            farmInteractiveGoldBlips[#farmInteractiveGoldBlips + 1] = obj
        end
        if obj.EnableMouse then obj:EnableMouse(isInteractiveBlip) end
        if obj.SetMouseMotionEnabled then obj:SetMouseMotionEnabled(isInteractiveBlip) end
        if obj.SetMouseClickEnabled then obj:SetMouseClickEnabled(false) end
    end

    farmGatheringTrackingScanGeneration = farmGatheringTrackingScanGeneration + 1
    local generation = farmGatheringTrackingScanGeneration
    local scan = {
        queue = { { object = Minimap, depth = 0 } },
        index = 1,
        tooltipsEnabled = tooltipsEnabled,
    }
    farmGatheringTrackingScan = scan

    local function ProcessScanBatch()
        if generation ~= farmGatheringTrackingScanGeneration or
           farmGatheringTrackingScan ~= scan or not addon.isFarmMode then
            return
        end

        local processed = 0
        local startedAt = debugprofilestop and debugprofilestop() or nil
        while scan.index <= #scan.queue do
            local entry = scan.queue[scan.index]
            scan.index = scan.index + 1
            local obj, depth = entry.object, entry.depth
            ApplyObject(obj)

            if depth <= 4 and obj.GetRegions then
                for _, region in ipairs({obj:GetRegions()}) do
                    scan.queue[#scan.queue + 1] = { object = region, depth = 5 }
                end
            end
            if depth < 4 and obj.GetChildren then
                for _, child in ipairs({obj:GetChildren()}) do
                    scan.queue[#scan.queue + 1] = { object = child, depth = depth + 1 }
                end
            end

            processed = processed + 1
            if processed >= 40 or (startedAt and (debugprofilestop() - startedAt) >= 4) then
                break
            end
        end

        if scan.index <= #scan.queue then
            C_Timer.After(0, ProcessScanBatch)
            return
        end

        farmGatheringTrackingScan = nil

        -- Retail may show these again when minimap mouse/tooltip tracking is
        -- refreshed. Gathering blips stay visible, but native controls and the
        -- native player/navigation marker must remain out of Farm Mode.
        local controls = {
            Minimap.ZoomIn,
            Minimap.ZoomOut,
            MinimapCluster and MinimapCluster.Tracking,
            MinimapCluster and MinimapCluster.IndicatorFrame,
            _G["SuperTrackedFrame"],
            _G["SuperTrackedFrameContainer"],
            _G["NavigationFrame"],
        }
        for _, control in pairs(controls) do
            StoreAndHideFarmMinimapObject(control)
        end
        if SetNativeFarmPlayerArrowVisible then
            SetNativeFarmPlayerArrowVisible(false, true)
        end
    end

    ProcessScanBatch()
end

function RestoreNativeGatheringTrackingVisible()
    farmGatheringTrackingScanGeneration = farmGatheringTrackingScanGeneration + 1
    farmGatheringTrackingScan = nil
    farmGatheringTrackingLastScanAt = nil
    farmGatheringTrackingLastTooltipSetting = nil
    for obj, state in pairs(farmGatheringTrackingStates) do
        if obj then
            if obj.SetAlpha and state.alpha ~= nil then obj:SetAlpha(state.alpha) end
            if obj.SetIgnoreParentAlpha and state.ignoreParentAlpha ~= nil then
                obj:SetIgnoreParentAlpha(state.ignoreParentAlpha)
            end
            if obj.EnableMouse and state.mouse ~= nil then obj:EnableMouse(state.mouse) end
            if obj.SetMouseMotionEnabled and state.mouseMotion ~= nil then obj:SetMouseMotionEnabled(state.mouseMotion) end
            if obj.SetMouseClickEnabled and state.mouseClick ~= nil then obj:SetMouseClickEnabled(state.mouseClick) end
            if obj.SetFrameStrata and state.frameStrata ~= nil then obj:SetFrameStrata(state.frameStrata) end
            if obj.SetFrameLevel and state.frameLevel ~= nil then obj:SetFrameLevel(state.frameLevel) end
            if obj.SetDrawLayer and state.drawLayer ~= nil then obj:SetDrawLayer(state.drawLayer) end
        end
    end
    wipe(farmGatheringTrackingStates)
    wipe(farmInteractiveGoldBlips)
end

local function SetFarmPlayerTextureHidden(hidden)
    if not Minimap then return end
    if hidden then
        if not farmOriginalPlayerTextureApplied then
            farmOriginalPlayerTextureApplied = true
            if Minimap.GetPlayerTextureWidth then farmOriginalPlayerTextureWidth = Minimap:GetPlayerTextureWidth() end
            if Minimap.GetPlayerTextureHeight then farmOriginalPlayerTextureHeight = Minimap:GetPlayerTextureHeight() end
            if Minimap.GetPlayerTextureAlpha then farmOriginalPlayerTextureAlpha = Minimap:GetPlayerTextureAlpha() end
        end
        -- SetPlayerTexture was removed from Retail in 12.0.7, but the size and
        -- alpha controls remain available on affected builds. Do not return
        -- early merely because the obsolete texture setter is absent.
        if Minimap.SetPlayerTexture then pcall(Minimap.SetPlayerTexture, Minimap, "") end
        if Minimap.SetPlayerTextureWidth then Minimap:SetPlayerTextureWidth(0) end
        if Minimap.SetPlayerTextureHeight then Minimap:SetPlayerTextureHeight(0) end
        if Minimap.SetPlayerTextureAlpha then Minimap:SetPlayerTextureAlpha(0) end
    elseif farmOriginalPlayerTextureApplied then
        farmOriginalPlayerTextureApplied = false
        if Minimap.SetPlayerTexture then pcall(Minimap.SetPlayerTexture, Minimap, "Interface\\Minimap\\MinimapArrow") end
        if Minimap.SetPlayerTextureWidth and farmOriginalPlayerTextureWidth then Minimap:SetPlayerTextureWidth(farmOriginalPlayerTextureWidth) end
        if Minimap.SetPlayerTextureHeight and farmOriginalPlayerTextureHeight then Minimap:SetPlayerTextureHeight(farmOriginalPlayerTextureHeight) end
        if Minimap.SetPlayerTextureAlpha then Minimap:SetPlayerTextureAlpha(farmOriginalPlayerTextureAlpha or 1) end
    else
        if Minimap.SetPlayerTexture then pcall(Minimap.SetPlayerTexture, Minimap, "Interface\\Minimap\\MinimapArrow") end
    end
end

SetNativeFarmPlayerArrowVisible = function(visible, forceRefresh)
    if not Minimap then return end
    if farmNativePlayerArrowVisibleState == visible and not forceRefresh then
        if not visible then SetFarmPlayerTextureHidden(true) end
        return
    end
    farmNativePlayerArrowVisibleState = visible
    SetFarmPlayerTextureHidden(not visible)
    local function ApplyObject(obj, force)
        if not force and not IsNativeMinimapPlayerArrow(obj) then return end
        if not farmNativePlayerArrowStates[obj] then
            farmNativePlayerArrowStates[obj] = {
                shown = ReadOptionalObjectState(obj, "IsShown"),
                alpha = obj.GetAlpha and obj:GetAlpha() or nil,
                ignoreParentAlpha = ReadOptionalObjectState(obj, "GetIgnoreParentAlpha"),
            }
        end

        if visible then
            local state = farmNativePlayerArrowStates[obj]
            if state and state.shown ~= false and obj.Show then obj:Show() end
            if obj.SetIgnoreParentAlpha and state and state.ignoreParentAlpha ~= nil then
                obj:SetIgnoreParentAlpha(state.ignoreParentAlpha)
            end
            if obj.SetAlpha then obj:SetAlpha((state and state.alpha) or 1) end
        else
            if obj.SetIgnoreParentAlpha then obj:SetIgnoreParentAlpha(true) end
            if obj.SetAlpha then obj:SetAlpha(0) end
            if obj.Hide then obj:Hide() end
        end
    end

    local function ApplyTree(obj, depth, force)
        if not obj or (depth or 0) > 4 then return end
        ApplyObject(obj, force)
        if obj.GetRegions then
            for _, region in ipairs({obj:GetRegions()}) do
                ApplyObject(region, force)
            end
        end
        if obj.GetChildren then
            for _, child in ipairs({obj:GetChildren()}) do
                ApplyTree(child, (depth or 0) + 1, force)
            end
        end
    end

    local explicitObjects = {
        _G["MiniMapPlayer"],
        _G["MiniMapPlayerFrame"],
        _G["MiniMapPlayerArrow"],
        _G["MiniMapPlayerIcon"],
        _G["MiniMapPlayerPin"],
        _G["MiniMapArrowFrame"],
        _G["MinimapPlayer"],
        _G["MinimapPlayerFrame"],
        _G["MinimapPlayerArrow"],
        _G["MinimapPlayerIcon"],
        _G["MinimapPlayerPin"],
        _G["MinimapArrowFrame"],
        _G["MiniMapPlayerModel"],
        _G["MinimapPlayerModel"],
        _G["MiniMapArrowModel"],
        _G["MinimapArrowModel"],
        _G["SuperTrackedFrame"],
        _G["SuperTrackedFrameContainer"],
        _G["NavigationFrame"],
        Minimap.Player,
        Minimap.PlayerArrow,
        Minimap.PlayerPin,
        Minimap.Navigation,
        Minimap.SuperTrackedFrame,
        MinimapCluster and MinimapCluster.Tracking,
        MinimapCluster and MinimapCluster.IndicatorFrame,
    }
    for _, obj in pairs(explicitObjects) do
        ApplyTree(obj, 0, true)
    end
    ApplyTree(Minimap, 0, false)
    ApplyTree(MinimapCluster, 0, false)
end

function RestoreNativeFarmPlayerArrow()
    SetFarmPlayerTextureHidden(false)
    for region, state in pairs(farmNativePlayerArrowStates) do
        if region then
            if state.shown ~= nil then
                if state.shown and region.Show then region:Show()
                elseif not state.shown and region.Hide then region:Hide() end
            end
            if region.SetAlpha and state.alpha ~= nil then region:SetAlpha(state.alpha) end
            if region.SetIgnoreParentAlpha and state.ignoreParentAlpha ~= nil then
                region:SetIgnoreParentAlpha(state.ignoreParentAlpha)
            end
        end
    end
    wipe(farmNativePlayerArrowStates)
    farmNativePlayerArrowVisibleState = nil
end

local function GetFarmHiddenMinimapHolder()
    if not farmHiddenMinimapHolder then
        farmHiddenMinimapHolder = CreateFrame("Frame", "PathmakerFarmHiddenMinimapHolder", UIParent)
        farmHiddenMinimapHolder:SetSize(1, 1)
        farmHiddenMinimapHolder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        farmHiddenMinimapHolder:Hide()
    end
    return farmHiddenMinimapHolder
end

local function RestoreFarmMinimapChildren()
    RestoreNativeFarmPlayerArrow()
    RestoreNativeGatheringTrackingVisible()
    for child, state in pairs(farmMinimapChildStates) do
        if child then
            if state.shown ~= nil then
                if state.shown and child.Show then child:Show()
                elseif not state.shown and child.Hide then child:Hide() end
            end
            if child.SetAlpha and state.alpha ~= nil then child:SetAlpha(state.alpha) end
            if child.EnableMouse and state.mouse ~= nil then child:EnableMouse(state.mouse) end
            if child.SetMouseMotionEnabled and state.mouseMotion ~= nil then child:SetMouseMotionEnabled(state.mouseMotion) end
            if child.SetMouseClickEnabled and state.mouseClick ~= nil then child:SetMouseClickEnabled(state.mouseClick) end
        end
    end
    wipe(farmMinimapChildStates)
end

-- Helper: Create Minimal Button
local function CreateMinimalButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    btn.text = label

    btn:SetScript("OnEnter", function(self)
        if not self.SuppressHoverUntilLeave then
            self:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self.SuppressHoverUntilLeave = nil
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        if not self.ForceHighlight then
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
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.32, 0.05, 0.05, 1)
        self:SetBackdropBorderColor(1, 0.22, 0.22, 1)
        if self.text then self.text:SetTextColor(1, 1, 1) end
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        if self.text then self.text:SetTextColor(1, 1, 1) end
    end)
    return btn
end

local function PaintSettingsControl(button)
    if not button then return end
    local settingsOpen = addon.Settings and addon.Settings.frame and addon.Settings.frame:IsShown()
    if button:IsEnabled() and (button.hovered or settingsOpen) then
        button:SetBackdropColor(0.16, 0.13, 0.04, 1)
        button:SetBackdropBorderColor(1, 0.82, 0, 1)
        if button.tex then button.tex:SetVertexColor(1, 0.9, 0.35, 1) end
    else
        if button.tex then
            button:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
            button.tex:SetVertexColor(0.82, 0.82, 0.82, 1)
        else
            button:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        end
        button:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

function addon.MapFrame:RefreshSettingsControls()
    PaintSettingsControl(self.btnSettings)
    for _, entry in ipairs(self.standaloneButtons or {}) do
        if entry.source == "btnSettings" then PaintSettingsControl(entry.button) end
    end
end

local function StyleHeaderControlButton(btn)
    if not btn or not btn.text then return btn end
    btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    btn.text:SetTextColor(1, 1, 1)
    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.18, 0.24, 1)
        self:SetBackdropBorderColor(0.35, 0.72, 1, 1)
        self.text:SetTextColor(1, 1, 1)
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        self.text:SetTextColor(1, 1, 1)
    end)
    return btn
end

-- ============================================================================
-- PATHMAKER BRIDGE: FORCE VISUAL UPDATES
-- This allows PathMaker_Nodes (and Options.lua) to tell the map to update
-- immediately after a single node or bulk import is merged.
-- ============================================================================
function addon:RefreshAllVisuals()
    -- Ensure heatmap is enabled to see the imported nodes
    if not addon.drawConfig.heatEnabled then
        addon.drawConfig.heatEnabled = true
    end

    if WorldMapFrame and WorldMapFrame:IsShown() then
        if type(WorldMapFrame.RefreshAllDataProviders) == "function" then
            WorldMapFrame:RefreshAllDataProviders()
        elseif type(WorldMapFrame.OnMapChanged) == "function" then
            WorldMapFrame:OnMapChanged()
        elseif type(_G.WorldMapFrame_Update) == "function" then
            WorldMapFrame_Update()
        end
    end

    -- Instantly repair missing names and attach icons without needing a relog!
    -- This version is fault-tolerant and will force default icons if custom ones fail.
    if PathmakerDB and PathmakerDB.nodes then
        for mapID, nodes in pairs(PathmakerDB.nodes) do
            for _, node in ipairs(nodes) do
                -- 1. Fix Missing/Generic Names
                if not node.name or node.name == "Herb Node" or node.name == "Mining Node" or node.name == "Treasure Node" or node.name == "unknown" then
                    if node.id and addon.NODE_INFO and addon.NODE_INFO[node.id] and addon.NODE_INFO[node.id].name then
                        node.name = addon.NODE_INFO[node.id].name
                    elseif node.id and addon.NODE_TRANSLATOR and addon.NODE_TRANSLATOR[node.id] then
                        node.name = addon.NODE_TRANSLATOR[node.id]
                    end
                end
                
                -- 2. Fix Missing Icons (Crucial for visibility)
                local translatedName = (node.name and addon.NODE_TRANSLATOR and (addon.NODE_TRANSLATOR[node.name] or addon.NODE_TRANSLATOR[tostring(node.name)])) or node.name
                if translatedName and addon.NODE_ICONS and addon.NODE_ICONS[translatedName] then
                    node.name = translatedName
                    if not node.specificName then node.specificName = translatedName end
                    node.icon = addon.NODE_ICONS[translatedName]
                elseif not node.icon then
                    if node.id and addon.NODE_INFO and addon.NODE_INFO[node.id] and addon.NODE_INFO[node.id].icon then
                        node.icon = addon.NODE_INFO[node.id].icon
                    elseif node.id and addon.NODE_TRANSLATOR and addon.NODE_ICONS and addon.NODE_ICONS[addon.NODE_TRANSLATOR[node.id]] then
                        node.name = addon.NODE_TRANSLATOR[node.id]
                        node.icon = addon.NODE_ICONS[node.name]
                    else
                        -- Ultimate Fallback: Never let a node be invisible
                        if node.type == "Herb" or node.type == "Herbalism" or node.type == "Herb Gathering" then
                            node.icon = "Interface\\Icons\\Trade_Herbalism"
                        elseif node.type == "Mining" or node.type == "Mine" then
                            node.icon = "Interface\\Icons\\Trade_Mining"
                        elseif node.type == "Treasure" then
                            node.icon = "Interface\\AddOns\\PathMaker_Nodes\\Artwork\\Treasure\\treasure.tga"
                        else
                            node.icon = "Interface\\Icons\\INV_Misc_QuestionMark"
                        end
                    end
                end
            end
        end
    end

    -- Force the Heatmap file to redraw the world map and minimap pins immediately
    if addon.Heatmap then
        if addon.Heatmap.UpdateWorldMap then addon.Heatmap:UpdateWorldMap() end
        if addon.Heatmap.ForceUpdate then addon.Heatmap:ForceUpdate() end
        if addon.Heatmap.UpdateMinimap then addon.Heatmap:UpdateMinimap(0) end
        if addon.Heatmap.Refresh then addon.Heatmap:Refresh() end
    end
end

-- ============================================================================
-- INTERNAL HELPERS (Preserved from original)
-- ============================================================================
local function RestoreMinimapButtons()
    -- This acts as a stub to safely bypass the original minimization hooks 
    -- without throwing Lua errors on UI reset.
end

local function ManageOverlays(state)
    -- Safely toggles custom frame overlays for the minimap
end

-- ============================================================================
-- RESTORE ORIGINAL MINIMAP
-- ============================================================================
function addon.MapFrame:RestoreOriginalMinimap()
    Minimap:SetMovable(false) 
    RestoreNativeFarmPlayerArrow()
    
    Minimap:ClearAllPoints()
    if originalParent and originalPoint[1] then
        Minimap:SetPoint(originalPoint[1], originalPoint[2], originalPoint[3], originalPoint[4], originalPoint[5])
    else
        Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
    end
    
    if self.NorthTagFrame then
        self.NorthTagFrame:Hide()
    end
    
    RestoreMinimapButtons()
    
    ApplyMinimapShapeMask(false)
    Minimap:SetAlpha(1)
    SetRememberedMinimapZoom(EnsurePathmakerSettings().minimapZoom)
    Minimap:Show() 
    
    if PathmakerDB and PathmakerDB.originalRotate then
        SetCVar("rotateMinimap", PathmakerDB.originalRotate)
        PathmakerDB.originalRotate = nil
    end

    if PathmakerDB then PathmakerDB.isEnabled = false end
    
    ManageOverlays(false)
    
    if MinimapNorthTag and originalNorthTagParent then
        MinimapNorthTag:SetParent(originalNorthTagParent)
        MinimapNorthTag:ClearAllPoints()
        if originalNorthTagPoint[1] then
            MinimapNorthTag:SetPoint(originalNorthTagPoint[1], originalNorthTagPoint[2], originalNorthTagPoint[3], originalNorthTagPoint[4], originalNorthTagPoint[5])
        end
    end
end
-- Fix: Forces minimap interaction to fully restore to bypass WoW API quirk dropping tooltips after SetParent
local function ForceMinimapMouseRestore()
    if Minimap then
        Minimap.pmFarmGoldBlipMouseCapture = nil
        Minimap.pmFarmHoverEnabled = nil
        Minimap:EnableMouse(true)
        if Minimap.SetMouseClickEnabled then Minimap:SetMouseClickEnabled(true) end
        if Minimap.SetMouseMotionEnabled then Minimap:SetMouseMotionEnabled(true) end
        
        for _, child in ipairs({Minimap:GetChildren()}) do
            if child.IsMouseEnabled and child:IsMouseEnabled() then
                child:EnableMouse(false)
                child:EnableMouse(true)
            end
            if child.IsMouseMotionEnabled and child:IsMouseMotionEnabled() then
                child:SetMouseMotionEnabled(false)
                child:SetMouseMotionEnabled(true)
            end
            if child.IsMouseClickEnabled and child:IsMouseClickEnabled() then
                child:SetMouseClickEnabled(false)
                child:SetMouseClickEnabled(true)
            end
        end
    end
end

local hiddenFrameStates = {}
local areOverlaysHidden = false

local function IsButtonCaptured(name)
    local dbSettings = PathmakerDB and PathmakerDB.settings
    local source = addon.MapFrame.tempSettings.capturedButtons or (dbSettings and dbSettings.capturedButtons)
    if not source then return false end
    return source[name]
end

local function IsPathmakerManagedMinimapButton(child)
    if not child or child == Minimap or child == addon.MapFrame.frame then return false end

    local name = child:GetName()
    if not name or name == "" then return false end
    if string.find(name, "Pathmaker") or string.find(name, "MinimapBackdrop") then return false end
    if name == "GameTimeFrame" or
       name == "MinimapNorthTag" or
       name == "MinimapZoneTextButton" or
       name == "MinimapZoomIn" or
       name == "MinimapZoomOut" or
       name == "MinimapToggleButton" or
       name == "TimeManagerClockButton" or
       name == "MiniMapTracking" or
       name == "MiniMapMailFrame" or
       name == "MiniMapInstanceDifficulty" or
       name == "GuildInstanceDifficulty" or
       name == "MiniMapChallengeMode" or
       name == "MiniMapWorldMapButton" or
       name == "MiniMapLFGFrame" or
       name == "LFGMinimapFrame" or
       name == "MiniMapVoiceChatFrame" or
       name == "MiniMapRecordingButton" or
       name == "GarrisonLandingPageMinimapButton" or
       name == "ExpansionLandingPageMinimapButton" or
       name == "MiniMapBattlefieldFrame" or
       name == "MinimapBattlefieldFrame" or
       name == "QueueStatusMinimapButton" then
        return false
    end

    local lowerName = string.lower(name)
    local isNamedButton = string.find(lowerName, "libdbicon") or
                          string.find(lowerName, "button") or
                          string.find(lowerName, "eye") or
                          string.find(lowerName, "event") or
                          string.find(lowerName, "activity") or
                          string.find(lowerName, "garrison") or
                          string.find(lowerName, "covenant")

    local w, h = child:GetSize()
    local isButtonSize = w and h and w > 15 and w < 60 and h > 15 and h < 60

    return isNamedButton or isButtonSize
end

function addon.MapFrame:SeedReleasedMinimapButtons()
    local settings = EnsurePathmakerSettings()
    settings.capturedButtons = settings.capturedButtons or {}
    local activeCapturedButtons = settings.capturedButtons
    if self.tempSettings and self.tempSettings.capturedButtons then
        activeCapturedButtons = self.tempSettings.capturedButtons
    end

    local children = {}
    for _, child in ipairs({Minimap:GetChildren()}) do table.insert(children, child) end
    if MinimapCluster then
        for _, child in ipairs({MinimapCluster:GetChildren()}) do table.insert(children, child) end
    end

    for _, child in ipairs(children) do
        local name = child:GetName()
        if name and IsPathmakerManagedMinimapButton(child) then
            if settings.capturedButtons[name] == nil then
                settings.capturedButtons[name] = false
            end
            if activeCapturedButtons ~= settings.capturedButtons and activeCapturedButtons[name] == nil then
                activeCapturedButtons[name] = false
            end
        end
    end
end

local function ManageOverlays(shouldHide)
    if shouldHide and not addon.MapFrame.ownsMinimap then return end
    if not shouldHide and not areOverlaysHidden then return end

    local explicitObjects = {
        MinimapCluster, 
        MinimapBorder, 
        MinimapBorderTop, 
        MinimapBackdrop,
        MinimapNorthTag, 
        MinimapZoneTextButton, 
        MinimapZoomIn, 
        MinimapZoomOut, 
        MinimapToggleButton, 
        GameTimeFrame,
        TimeManagerClockButton,     
        MiniMapTracking, 
        MiniMapMailFrame, 
        MiniMapInstanceDifficulty,
        GuildInstanceDifficulty,
        MiniMapChallengeMode,
        MiniMapWorldMapButton,
        MiniMapLFGFrame,
        LFGMinimapFrame,
        MiniMapVoiceChatFrame,
        MiniMapRecordingButton,
        GarrisonLandingPageMinimapButton,
        ExpansionLandingPageMinimapButton,
        -- Excluded: MiniMapBattlefieldFrame & QueueStatusMinimapButton 
        -- PathmakerPVPButton fully controls them so Layout engines leave them alone.
    }

    local function HideAndStore(obj)
        if obj and obj:IsShown() then
            local state = { wasMouseEnabled = false }
            if obj.IsMouseEnabled then state.wasMouseEnabled = obj:IsMouseEnabled() end
            hiddenFrameStates[obj] = state
            obj:Hide()
        end
    end

    if shouldHide then
        if addon.MapFrame and type(addon.MapFrame.SeedReleasedMinimapButtons) == "function" then
            addon.MapFrame:SeedReleasedMinimapButtons()
        end

        for _, obj in pairs(explicitObjects) do HideAndStore(obj) end
        
        if MiniMapMailFrame then 
            HideAndStore(MiniMapMailFrame) 
            MiniMapMailFrame:SetAlpha(0) 
        end
        
        if TimeManagerClockButton then HideAndStore(TimeManagerClockButton) end

        local children = {Minimap:GetChildren()}
        for _, child in ipairs(children) do
            local name = child:GetName() or ""
            
            if name ~= "PathmakerCanvas" and 
               name ~= "PathmakerNorthTagFrame" and 
               name ~= "PathmakerTrackingButton" and 
               name ~= "PathmakerMailButton" and
               name ~= "PathmakerLFGButton" and
               name ~= "PathmakerPVPButton" and
               name ~= "PathmakerHeatmapMini" and 
               not string.find(name, "Pathmaker") and
               name ~= "MiniMapBattlefieldFrame" and 
               name ~= "MinimapBattlefieldFrame" and 
               name ~= "QueueStatusMinimapButton" and
               child ~= addon.MapFrame.frame and 
               not hiddenFrameStates[child] then
               
                local captureState = nil
                local shouldHideChild = IsPathmakerManagedMinimapButton(child)
                
                if addon.MapFrame.tempSettings and addon.MapFrame.tempSettings.capturedButtons then
                     captureState = addon.MapFrame.tempSettings.capturedButtons[name]
                elseif PathmakerDB.settings and PathmakerDB.settings.capturedButtons then
                     captureState = PathmakerDB.settings.capturedButtons[name]
                end

                if captureState == false then
                    shouldHideChild = false
                elseif captureState == true then
                    shouldHideChild = true
                end
                
                local lowerName = string.lower(name)
                if captureState == nil and (string.find(lowerName, "anniversary") or 
                   string.find(lowerName, "event") or 
                   string.find(lowerName, "bulletin") or
                   string.find(lowerName, "badge") or
                   string.find(lowerName, "activity") or
                   string.find(lowerName, "queue") or
                   string.find(lowerName, "feedback") or
                   string.find(lowerName, "difficulty") or
                   string.find(lowerName, "garrison") or
                   string.find(lowerName, "covenant")) then
                    shouldHideChild = true
                end

                if shouldHideChild then
                    HideAndStore(child)
                end
            end
        end
        
        if MinimapBorder and MinimapBorder.SetTexture then MinimapBorder:SetAlpha(0) end
        
        if MinimapCluster then
            local clusterChildren = {MinimapCluster:GetChildren()}
            for _, child in ipairs(clusterChildren) do
                 local childName = child:GetName()
                 local captureState = childName and PathmakerDB.settings and PathmakerDB.settings.capturedButtons and PathmakerDB.settings.capturedButtons[childName]
                 if not (captureState == false and IsPathmakerManagedMinimapButton(child)) then
                     HideAndStore(child)
                 end
            end
        end

        areOverlaysHidden = true
    else
        for obj, state in pairs(hiddenFrameStates) do
            if obj then
                obj:Show()
                if obj.EnableMouse and state.wasMouseEnabled ~= nil then obj:EnableMouse(state.wasMouseEnabled) end
                if obj.SetAlpha then obj:SetAlpha(1) end
            end
        end

        if MiniMapMailFrame then
            MiniMapMailFrame:SetAlpha(1) 
            if HasNewMail() then MiniMapMailFrame:Show() else MiniMapMailFrame:Hide() end
        end
        if MinimapBorder and MinimapBorder.SetTexture then MinimapBorder:SetAlpha(1) end
        wipe(hiddenFrameStates)
        areOverlaysHidden = false
    end
end

local function CreateCustomSlider(parent, width, height, minVal, maxVal, currentVal, callback)
    local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s:SetSize(width, height)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    s:SetBackdropColor(0, 0, 0, 1) 
    s:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) 

    local thumb = CreateFrame("Frame", nil, s, "BackdropTemplate")
    thumb:SetSize(8, height - 2)
    thumb:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    thumb:SetBackdropColor(0.8, 0.8, 0.8, 1) 

    local function UpdateThumb()
        local pct = (currentVal - minVal) / (maxVal - minVal)
        pct = math.max(0, math.min(1, pct))
        local maxDist = width - 8 - 2 
        thumb:SetPoint("LEFT", 1 + (maxDist * pct), 0)
    end
    UpdateThumb()

    local lastCallbackValue = currentVal
    local lastCallbackTime = 0
    local callbackEpsilon = math.max((maxVal - minVal) / math.max(width, 1) * 0.25, 0.0001)

    local function RunCallback(force)
        if not callback then return end
        local now = GetTime and GetTime() or 0
        if not force then
            if lastCallbackValue and math.abs(currentVal - lastCallbackValue) < callbackEpsilon then return end
            if lastCallbackTime > 0 and now > 0 and (now - lastCallbackTime) < 0.04 then return end
        end
        lastCallbackValue = currentVal
        lastCallbackTime = now
        callback(currentVal, force)
    end

    local function UpdateValueFromCursor(frame)
        local mx = GetCursorPosition()
        if not mx then return end
        local sScale = frame:GetEffectiveScale()
        local sLeft = frame:GetLeft() * sScale
        local sWidth = frame:GetWidth() * sScale

        local relX = (mx - sLeft) / sWidth
        currentVal = minVal + (relX * (maxVal - minVal))
        currentVal = math.max(minVal, math.min(maxVal, currentVal))

        UpdateThumb()
        RunCallback(false)
    end

    local function StopDragging(frame)
        frame.isDragging = false
        frame:SetScript("OnUpdate", nil)
    end

    s:EnableMouse(true)
    s:SetScript("OnMouseDown", function(self)
        self.isDragging = true
        UpdateValueFromCursor(self)
        self:SetScript("OnUpdate", UpdateValueFromCursor)
    end)
    
    s:SetScript("OnMouseUp", function(self)
        if self.isDragging then
            UpdateValueFromCursor(self)
            RunCallback(true)
        end
        StopDragging(self)
    end)
    s:SetScript("OnHide", function(self)
        if self.isDragging then
            RunCallback(true)
        end
        StopDragging(self)
    end)

    s.SetValue = function(self, val)
        currentVal = math.max(minVal, math.min(maxVal, val))
        lastCallbackValue = currentVal
        UpdateThumb()
    end

    return s
end

local function OpenPalettePicker(parent, mapID, callback, isSearchMode, ownerKey, anchor)
    local owner = ownerKey or anchor or parent
    local function PositionPalette(frame)
        frame:ClearAllPoints()
        if anchor then
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
        else
            frame:SetPoint("RIGHT", parent, "LEFT", -5, 0)
        end
    end

    if addon.PaletteFrame then 
        if addon.PaletteFrame:IsShown() and addon.PaletteFrame.owner == owner then
            addon.PaletteFrame:Hide() 
            return
        end
        addon.PaletteFrame:Show()
        addon.PaletteFrame:SetParent(parent) 
        PositionPalette(addon.PaletteFrame)
        addon.PaletteFrame:SetFrameStrata("TOOLTIP")
        addon.PaletteFrame:SetFrameLevel(1000)
        addon.PaletteFrame:EnableMouse(true)
        addon.PaletteFrame.callback = callback
        addon.PaletteFrame.mapID = mapID
        addon.PaletteFrame.isSearchMode = isSearchMode
        addon.PaletteFrame.owner = owner
        addon.PaletteFrame:Refresh()
        addon.MapFrame:ApplySettings() 
        addon.PaletteFrame:SetAlpha(1)
        addon.PaletteFrame:SetBackdropColor(0.025, 0.025, 0.025, 1)
        addon.PaletteFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        return 
    end

    local f = CreateFrame("Frame", "PathmakerPalette", parent, "BackdropTemplate")
    f:SetSize(125, 175) 
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(1000)
    PositionPalette(f)
    f:SetClampedToScreen(true) 
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() end)
    f:SetScript("OnMouseUp", function() end)
    
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0.025, 0.025, 0.025, 1)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    f.surface = f:CreateTexture(nil, "ARTWORK")
    f.surface:SetPoint("TOPLEFT", 1, -1)
    f.surface:SetPoint("BOTTOMRIGHT", -1, 1)
    f.surface:SetColorTexture(0.025, 0.025, 0.025, 1)
    
    local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    infoText:SetPoint("TOP", 0, -5)
    infoText:SetText("Route Color\nClick current to reset")
    infoText:SetJustifyH("CENTER")
    
    local closeBtn = StyleCloseButton(CreateMinimalButton(f, "X", 20, 20))
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f.buttons = {}
    local size = 20
    local gap = 4
    local palette = addon.Routes and addon.Routes.Palette or {}
    local startY = -28 
    
    for i, color in ipairs(palette) do
        if i > 24 then break end 
        local b = CreateFrame("Button", nil, f)
        b:SetSize(size, size)
        b.color = color
        local row = math.floor((i-1) / 4)
        local col = (i-1) % 4
        b:SetPoint("TOPLEFT", 15 + (col * (size+gap)), startY - (row * (size+gap))) 
        b.bg = b:CreateTexture(nil, "OVERLAY")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(unpack(color))
        b:SetScript("OnClick", function()
            if f.callback then f.callback(color) end
            f:Hide()
        end)
        f.buttons[i] = b
    end
    
    f.Refresh = function(self) end
    f.callback = callback
    f.mapID = mapID
    f.isSearchMode = isSearchMode
    f.owner = owner
    f.isSearchMode = isSearchMode
    f:Refresh()
    addon.PaletteFrame = f
    addon.MapFrame:ApplySettings()
    f:SetAlpha(1)
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
    slider:SetPoint("TOPLEFT", sf, "TOPRIGHT", 1, 0)
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

function addon.MapFrame:StopRouteCounters()
    local mapID = addon.selectedRouteMapID or C_Map.GetBestMapForUnit("player")
    if mapID and addon.selectedRouteGUID and PathmakerDB.routes[mapID] then
         local route = PathmakerDB.routes[mapID][addon.selectedRouteGUID]
         if route and route.points then
             for _, p in ipairs(route.points) do
                 p.countdownStart = nil
                 p.isStanding = false
             end
         end
         if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
    end
end

-- ============================================================================
-- MINIMAP BUTTON WRAPPER LOGIC ("PRO" SMOOTH MOVEMENT & TRUE FRONT RENDERING)
-- ============================================================================
function addon.MapFrame:LayoutMinimapButtons()
    if not self.ownsMinimap then return end
    if MBB_MinimapButtonFrame or MinimapButtonFrame or HidingBar or ElvUI or Tukui or SexyMap or ProjectAzilroka then
        return
    end

    local parentFrame = addon.isFarmMode and self.farmFrame or self.frame
    if not parentFrame or not parentFrame:IsShown() then return end

    ManageOverlays(true)

    local settings = EnsurePathmakerSettings()
    local minimapClickThrough = not addon.isFarmMode and (settings.alpha or 1) <= 0
    
    local children = {Minimap:GetChildren()}
    if MinimapCluster then
        for _, child in ipairs({MinimapCluster:GetChildren()}) do table.insert(children, child) end
    end
    local mapW, mapH = parentFrame:GetSize()
    
    local R = (mapW / 2) + 2 
    
    local mCX, mCY = Minimap:GetCenter()
    if not mCX or not mCY then return end
    
    for _, child in ipairs(children) do
        local name = child:GetName() or ""
        
        if child:IsShown() and not hiddenFrameStates[child] then
            if IsPathmakerManagedMinimapButton(child) then
                    if child:GetParent() ~= parentFrame then
                        child.pmOriginalParent = child.pmOriginalParent or child:GetParent()
                        child:SetParent(parentFrame)
                    end
                    child.pmManagedByPathmaker = true
                    
                    -- TRUE PRIORITY: Ensure icon sits gracefully with Pathmaker Menus (MEDIUM Level 20).
                    -- In Farm Mode, make them invisible and click-through.
                    if addon.isFarmMode or minimapClickThrough then
                        child:SetAlpha(0)
                        if child.EnableMouse then child:EnableMouse(false) end
                    else
                        child:SetAlpha(1)
                        if child.EnableMouse then child:EnableMouse(true) end
                        if child:GetFrameStrata() ~= "MEDIUM" then
                            child:SetFrameStrata("MEDIUM")
                        end
                        child:SetFrameLevel(20)
                    end
                    
                    -- SYNCHRONOUS DRAG HOOK: Instantly calculates while moving, 0 grid stutter
                    if not child.pmHooked then
                        child.pmHooked = true
                        hooksecurefunc(child, "SetPoint", function(self)
                            if self.pmIsUpdating or not addon.MapFrame.ownsMinimap then return end
                            
                            -- Lock priority aggressively even when dragged
                            local clickThrough = not addon.isFarmMode and PathmakerDB and PathmakerDB.settings and (PathmakerDB.settings.alpha or 1) <= 0
                            if addon.isFarmMode or clickThrough then
                                self:SetAlpha(0)
                                if self.EnableMouse then self:EnableMouse(false) end
                            else
                                self:SetAlpha(1)
                                if self.EnableMouse then self:EnableMouse(true) end
                                if self:GetFrameStrata() ~= "MEDIUM" then self:SetFrameStrata("MEDIUM") end
                                self:SetFrameLevel(20)
                            end
                            
                            local pFrame = addon.isFarmMode and addon.MapFrame.farmFrame or addon.MapFrame.frame
                            if not pFrame or not pFrame:IsShown() then return end
                            
                            local t_mCX, t_mCY = Minimap:GetCenter()
                            local bCX, bCY = self:GetCenter()
                            
                            if t_mCX and t_mCY and bCX and bCY then
                                local dx = bCX - t_mCX
                                local dy = bCY - t_mCY
                                
                                if math.abs(dx) > 1 or math.abs(dy) > 1 then
                                    local dragAngle = math.atan2(dy, dx)
                                    local btnName = self:GetName()
                                    if btnName then
                                        PathmakerDB.settings.buttonAngles[btnName] = dragAngle
                                    end
                                    self.pmNativeAngle = dragAngle
                                    
                                    local t_mapW = pFrame:GetSize()
                                    local t_R = (t_mapW / 2) + 2
                                    
                                    local targetX, targetY = GetMinimapButtonOffset(dragAngle, t_R, addon.useSquareMap)
                                    
                                    self.pmIsUpdating = true
                                    self:ClearAllPoints()
                                    self:SetPoint("CENTER", pFrame, "CENTER", targetX, targetY)
                                    self.pmLastX = targetX
                                    self.pmLastY = targetY
                                    self.pmIsUpdating = false
                                end
                            end
                        end)
                    end
                    
                    local storedAngle = settings.buttonAngles[name] or child.pmNativeAngle
                    local angle = storedAngle
                    
                    if not angle then
                        local bCX, bCY = child:GetCenter()
                        if bCX and bCY then
                            local dx = bCX - mCX
                            local dy = bCY - mCY
                            if math.abs(dx) > 1 or math.abs(dy) > 1 then
                                angle = math.atan2(dy, dx)
                                settings.buttonAngles[name] = angle
                                child.pmNativeAngle = angle
                            end
                        end
                    end
                    
                    if angle then
                        local targetX, targetY = GetMinimapButtonOffset(angle, R, addon.useSquareMap)
                        
                        -- Evaluates mathematically if it has visually diverged, no arbitrary grid blocks.
                        if not child.pmLastX or math.abs(child.pmLastX - targetX) > 0.01 or math.abs(child.pmLastY - targetY) > 0.01 then
                            child.pmIsUpdating = true
                            -- Ensure priority every layout check just in case native UI fights back
                            if addon.isFarmMode or minimapClickThrough then
                                child:SetAlpha(0)
                                if child.EnableMouse then child:EnableMouse(false) end
                            else
                                child:SetAlpha(1)
                                if child.EnableMouse then child:EnableMouse(true) end
                                if child:GetFrameStrata() ~= "MEDIUM" then child:SetFrameStrata("MEDIUM") end
                                child:SetFrameLevel(20)
                            end
                            
                            child:ClearAllPoints()
                            child:SetPoint("CENTER", parentFrame, "CENTER", targetX, targetY)
                            child.pmLastX = targetX
                            child.pmLastY = targetY
                            child.pmIsUpdating = false
                        end
                    end
                end
            end
        end

        if minimapClickThrough and self.frame then ApplyHiddenMinimapMouseMode(self.frame) end
    end

function addon.MapFrame:UpdateClampInsets(settings)
    if not self.frame then return end
    local s = settings or PathmakerDB.settings or {}
    
    -- Evaluate visibility of the top panels
    local topInset = 0
    if not s.hideZoneBar then topInset = topInset + 13 end
    if not s.hideHeaderBar then topInset = topInset + 15 end
    
    -- Evaluate visibility of the bottom panels
    local bottomInset = 0
    if not (s.hideRoutes and s.hideTacticalTools) then 
        bottomInset = bottomInset + 17 
    end
    if not s.hideQuickBar then 
        bottomInset = bottomInset + 18
    end
    
    -- 0 X values pull the map directly to the edge of the monitor securely
    self.frame:SetClampRectInsets(0, 0, topInset, -bottomInset)
end

function addon.MapFrame:UpdateClockPosition(settings)
    if not self.clockFrame or not self.frame then return end
    local s = settings or PathmakerDB.settings or {}
    local position = s.clockPosition or "DEFAULT"

    self.clockFrame:ClearAllPoints()

    local edgeOffset = s.minimapUseFullEdges and 0 or 4
    if position == "LEFT_BOTTOM" then
        self.clockFrame:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", edgeOffset, edgeOffset)
    elseif position == "BOTTOM" then
        self.clockFrame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, edgeOffset)
    elseif position == "RIGHT_BOTTOM" then
        self.clockFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -edgeOffset, edgeOffset)
    else
        -- Sit flush against the minimap with the two bottom buttons.
        self.clockFrame:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, -16)
    end
end

function addon.MapFrame:ApplySettings(settingsOverride)
    local s = settingsOverride or EnsurePathmakerSettings()
    if not s then return end
    if not self.ownsMinimap then
        if self.controlsFrame and PathmakerDB.isEnabled then self:RefreshStandaloneControls() end
        return
    end
    if not s.capturedButtons then s.capturedButtons = {} end
    if not s.clockPosition then s.clockPosition = "DEFAULT" end

    if addon.isFarmMode then
        -- Rotation and other Farm options must apply even when a city, cave, or
        -- transition map temporarily has no direct player coordinates.
        if self.farmFrame and self.UpdateFarmVisuals then
            self:UpdateFarmVisuals(s)
        end
        return
    end
    
    local alpha = s.alpha or 1.0
    local isHiddenMode = (alpha <= 0.0)

    -- The interface-opacity option controls PathMaker's chrome, not the map
    -- image. Retail reparents Minimap under this frame, so opt it out of the
    -- parent's alpha before applying the interface setting.
    if Minimap then
        if Minimap.SetIgnoreParentAlpha then Minimap:SetIgnoreParentAlpha(true) end
        Minimap:SetAlpha(1)
    end

    local scale = s.minimapScale or 1.0
    if self.frame then self.frame:SetScale(scale) end
    -- Farm Mode performs a complete refresh when it is entered. Rebuilding its
    -- hidden layout for every ordinary UI state change creates a CPU spike with
    -- no visible result.

    if isHiddenMode then
        if self.frame then self.frame:SetAlpha(0); self.frame:EnableMouse(false) end
        if self.headerBar then self.headerBar:EnableMouse(false) end
        if self.zoneBar then self.zoneBar:EnableMouse(false) end
        
        if self.quickBar then 
            self.quickBar:EnableMouse(false)
            for _, child in ipairs({self.quickBar:GetChildren()}) do
                if child.EnableMouse then child:EnableMouse(false) end
            end
        end
        if self.NorthTagFrame then self.NorthTagFrame:SetAlpha(0) end
        if self.btnRoutes then self.btnRoutes:SetAlpha(0); self.btnRoutes:EnableMouse(false) end
        if self.btnTools then self.btnTools:SetAlpha(0); self.btnTools:EnableMouse(false) end
        if self.clockFrame then self.clockFrame:SetAlpha(0) end

        if self.btnMarkedTimers then 
            self.btnMarkedTimers:Hide()
            self.btnMarkedTimers:EnableMouse(false)
        end

        if self.managerFrame then 
            self.managerFrame:Hide()
            self.managerFrame:EnableMouse(false) 
        end
        if self.tacticalFrame then 
            self.tacticalFrame:Hide()
            self.tacticalFrame:EnableMouse(false) 
        end
        if self.timersFrame then
            self.timersFrame:Hide()
            self.timersFrame:EnableMouse(false)
        end
        if self.nodeFilterFrame then
            self.nodeFilterFrame:Hide()
            self.nodeFilterFrame:EnableMouse(false)
        end
    else
        if self.frame then self.frame:SetAlpha(alpha); self.frame:EnableMouse(true) end
        if self.headerBar then self.headerBar:EnableMouse(true) end
        if self.zoneBar then self.zoneBar:EnableMouse(true) end
        
        if self.quickBar then 
            self.quickBar:EnableMouse(true) 
            for _, child in ipairs({self.quickBar:GetChildren()}) do
                if child.EnableMouse then child:EnableMouse(true) end
            end
        end
        if self.NorthTagFrame then self.NorthTagFrame:SetAlpha(1) end
        if self.btnRoutes then self.btnRoutes:SetAlpha(alpha); self.btnRoutes:EnableMouse(true) end
        if self.btnTools then self.btnTools:SetAlpha(alpha); self.btnTools:EnableMouse(true) end
        if self.clockFrame then self.clockFrame:SetAlpha(alpha) end
        
        if self.managerFrame then self.managerFrame:EnableMouse(true) end
        if self.tacticalFrame then self.tacticalFrame:EnableMouse(true) end
        if self.timersFrame then self.timersFrame:EnableMouse(true) end
        if self.nodeFilterFrame then
            self.nodeFilterFrame:EnableMouse(true)
            if s.nodeFilterOpen and not addon.isFarmMode then self.nodeFilterFrame:Show() end
        end
    end
    
    local lastAnchor = self.frame 
    local lastAnchorPoint = "TOP"
    local gap = 0

    if s.hideZoneBar then
        if self.zoneBar then self.zoneBar:Hide() end
        if self.ZoneText then self.ZoneText:Hide() end
    else
        if self.zoneBar then
            self.zoneBar:Show()
            if not isHiddenMode then self.zoneBar:SetAlpha(alpha) else self.zoneBar:SetAlpha(0) end
            self.zoneBar:ClearAllPoints()
            self.zoneBar:SetPoint("BOTTOM", lastAnchor, lastAnchorPoint, 0, gap)
            
            lastAnchor = self.zoneBar
            lastAnchorPoint = "TOP"
        end
        if self.ZoneText then
            self.ZoneText:Show()
            self.ZoneText:SetParent(self.zoneBar) 
            self.ZoneText:ClearAllPoints()
            self.ZoneText:SetPoint("CENTER", self.zoneBar, "CENTER", 0, 0)
        end
    end

    if s.hideHeaderBar then
        if self.headerBar then self.headerBar:Hide() end
    else
        if self.headerBar then
            self.headerBar:Show()
            if not isHiddenMode then self.headerBar:SetAlpha(alpha) else self.headerBar:SetAlpha(0) end
            self.headerBar:ClearAllPoints()
            self.headerBar:SetPoint("BOTTOM", lastAnchor, lastAnchorPoint, 0, gap)
        end
    end

    if self.managerFrame then self.managerFrame:SetAlpha(alpha) end
    if self.tacticalFrame then self.tacticalFrame:SetAlpha(alpha) end 
    if self.timersFrame then self.timersFrame:SetAlpha(alpha) end
    if self.nodeFilterFrame then self.nodeFilterFrame:SetAlpha(alpha) end
    -- Keep the modal color picker fully opaque so route labels beneath it do
    -- not show through and accidentally look like part of the picker.
    if addon.PaletteFrame then addon.PaletteFrame:SetAlpha(1) end
    
    if s.hideRoutes then 
        if self.btnRoutes then
            self.btnRoutes.ForceHighlight = false
            self.btnRoutes.PanelWasShown = false
            self.btnRoutes.SuppressHoverUntilLeave = nil
            self.btnRoutes:SetFrameLevel(10)
            self.btnRoutes:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            self.btnRoutes:SetBackdropBorderColor(0, 0, 0, 1)
            self.btnRoutes:Hide()
        end
        if self.managerFrame then self.managerFrame:Hide() end
    else
        if self.btnRoutes then
            if not self.managerFrame or not self.managerFrame:IsShown() then
                self.btnRoutes.ForceHighlight = false
                self.btnRoutes.PanelWasShown = false
                self.btnRoutes:SetBackdropBorderColor(0, 0, 0, 1)
            end
            self.btnRoutes:Show()
        end
    end
    
    if s.hideTacticalTools then
        if self.btnTools then
            self.btnTools.ForceHighlight = false
            self.btnTools.PanelWasShown = false
            self.btnTools.SuppressHoverUntilLeave = nil
            self.btnTools:SetFrameLevel(10)
            self.btnTools:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            self.btnTools:SetBackdropBorderColor(0, 0, 0, 1)
            self.btnTools:Hide()
        end
        if self.tacticalFrame then self.tacticalFrame:Hide() end
    else
        if self.btnTools then
            if not self.tacticalFrame or not self.tacticalFrame:IsShown() then
                self.btnTools.ForceHighlight = false
                self.btnTools.PanelWasShown = false
                self.btnTools:SetBackdropBorderColor(0, 0, 0, 1)
            end
            self.btnTools:Show()
        end
    end
    
    -- Dynamically push quickbar up depending on Bottom Button visibility
    if s.hideRoutes and s.hideTacticalTools then
        if self.quickBar then
            self.quickBar:ClearAllPoints()
            self.quickBar:SetPoint("TOP", self.frame, "BOTTOM", 0, 0)
        end
    else
        if self.quickBar then
            self.quickBar:ClearAllPoints()
            self.quickBar:SetPoint("TOPLEFT", self.btnRoutes, "BOTTOMLEFT", 0, 0)
        end
    end
    
    if s.hideClock then
        if self.clockFrame then self.clockFrame:Hide() end
    else
        if self.clockFrame then 
            self:UpdateClockPosition(s)
            self.clockFrame:Show()
            if isHiddenMode then self.clockFrame:SetAlpha(0) else self.clockFrame:SetAlpha(alpha) end
        end
    end
    
    if self.headerBar then
        if s.hideHeaderBar then self.headerBar:Hide() else 
            self.headerBar:Show() 
            if isHiddenMode then self.headerBar:SetAlpha(0) else self.headerBar:SetAlpha(alpha) end
        end
    end
    
    if self.quickBar then
        if s.hideQuickBar then 
            self.quickBar:Hide() 
            if self.btnMarkedTimers then self.btnMarkedTimers:Hide() end
        else 
            self.quickBar:Show() 
            if isHiddenMode then 
                self.quickBar:SetAlpha(0) 
                if self.btnMarkedTimers then self.btnMarkedTimers:SetAlpha(0) end
            else 
                self.quickBar:SetAlpha(alpha)
                if self.btnMarkedTimers then 
                    self.btnMarkedTimers:Show()
                    self.btnMarkedTimers:SetAlpha(alpha)
                end
            end
        end
    end

    if self.trackingButton and self.trackingButton.UpdateState then
        self.trackingButton:UpdateState()
    end

    if self.lfgButton and self.lfgButton.UpdateState then
        self.lfgButton:UpdateState()
    end

    if self.mailButton and self.mailButton.UpdateState then
        self.mailButton:UpdateState()
    end

    if self.pvpButton and self.pvpButton.UpdateState then
        self.pvpButton:UpdateState()
    end
    
    if addon.Heatmap and addon.Heatmap.RefreshWorldMap then
        addon.Heatmap:RefreshWorldMap()
    end

    self:SeedReleasedMinimapButtons()
    self:UpdateCapturedButtons(settingsOverride)
    self:UpdateClampInsets(s)
    
    if self.frame then
        for _, child in ipairs({self.frame:GetChildren()}) do
             local name = child:GetName()
             if name and s.capturedButtons[name] and child ~= Minimap then
                  if isHiddenMode then
                       child:EnableMouse(false)
                  else
                       child:EnableMouse(true)
                  end
             end
        end
    end

    -- Alpha zero is a true click-through mode. Run this last because captured
    -- minimap controls may have changed their mouse state while settings applied.
    if self.frame then
        if isHiddenMode then ApplyHiddenMinimapMouseMode(self.frame)
        else SetMouseTreeEnabled(self.frame, true) end
    end
    self:UpdateMinimapLockState(s)
end

function addon.MapFrame:UpdateMinimapLockState(settings)
    local s = settings or EnsurePathmakerSettings()
    local locked = s.minimapLocked == true
    local hidden = (s.alpha or 1) <= 0
    local canDrag = not locked and not hidden and not (addon.Routes and addon.Routes.isRecording)

    if self.frame then self.frame:SetMovable(not locked) end
    for _, border in ipairs(self.minimapDragBorders or {}) do
        border:EnableMouse(canDrag)
    end
end

function addon.MapFrame:UpdateCapturedButtons(settingsOverride)
    if not self.ownsMinimap then return end
    local s = settingsOverride or PathmakerDB.settings
    if not s then return end
    
    local allChildren = {}
    for _, child in ipairs({Minimap:GetChildren()}) do table.insert(allChildren, child) end
    if self.frame then
        for _, child in ipairs({self.frame:GetChildren()}) do table.insert(allChildren, child) end
    end

    local handled = {} 

    for _, child in ipairs(allChildren) do
        if child ~= Minimap then
            local name = child:GetName()
            if name and not handled[child] then
                handled[child] = true
                
                if name ~= "PathmakerTrackingButton" and 
                   name ~= "PathmakerNorthTagFrame" and 
                   name ~= "PathmakerCanvas" and 
                   name ~= "PathmakerMailButton" and
                   name ~= "PathmakerLFGButton" and
                   name ~= "PathmakerPVPButton" and
                   name ~= "PathmakerHeatmapMini" and
                   name ~= "MiniMapBattlefieldFrame" and 
                   name ~= "MinimapBattlefieldFrame" and 
                   name ~= "QueueStatusMinimapButton" and
                   not string.find(name, "Pathmaker") then
                   
                   if name == "GameTimeFrame" then
                   else
                        local shouldHide = false
                        if s.capturedButtons[name] then
                            shouldHide = true
                        end
                        
                        if shouldHide then
                            child:SetParent(Minimap)
                            child:Hide()
                            if child.EnableMouse then child:EnableMouse(false) end
                        end
                   end
                end
            end
        end
    end
end

-- ==========================================
-- SHARED: UPDATE UI STATE
-- ==========================================
function addon.MapFrame:FindSelectedRoute()
    if not addon.selectedRouteGUID or not PathmakerDB or not PathmakerDB.routes then return nil, nil end
    local mapID = addon.selectedRouteMapID
    if mapID and PathmakerDB.routes[mapID] and PathmakerDB.routes[mapID][addon.selectedRouteGUID] then
        return mapID, PathmakerDB.routes[mapID][addon.selectedRouteGUID]
    end
    for routeMapID, routes in pairs(PathmakerDB.routes) do
        if routes and routes[addon.selectedRouteGUID] then
            addon.selectedRouteMapID = routeMapID
            return routeMapID, routes[addon.selectedRouteGUID]
        end
    end
    return nil, nil
end

function addon.MapFrame:UpdateUIState(skipSettingsApply)
    local isRecording = addon.Routes and addon.Routes.isRecording
    local isEditing = addon.Routes and addon.Routes.isEditing
    local mapID = C_Map.GetBestMapForUnit("player")
    local selectedRoute = nil
    local selectedRouteMapID = nil
    
    local isPlannerOpen = addon.Planner and addon.Planner.frame and addon.Planner.frame:IsShown()
    
    if addon.selectedRouteGUID then
        selectedRouteMapID, selectedRoute = self:FindSelectedRoute()
    end
    if addon.selectedRouteGUID and not selectedRoute then
        addon.selectedRouteGUID = nil
        addon.selectedRouteMapID = nil
        self:ResetFarmVisuals()
    end
    
    if isRecording then
        self.frame:EnableMouse(false) 
        if self.headerBar then self.headerBar:EnableMouse(false) end
    else
        self.frame:EnableMouse(true)
        if self.headerBar then self.headerBar:EnableMouse(true) end
    end
    
    if self.quickBar then
        if isRecording and not isEditing then 
            self.btnQuickRec.text:SetTextColor(1, 0, 0) 
        elseif isRecording and isEditing then
            self.btnQuickRec:Disable()
            self.btnQuickRec.text:SetTextColor(0.3, 0.3, 0.3)
        elseif isPlannerOpen then
            self.btnQuickRec:Disable()
            self.btnQuickRec.text:SetTextColor(0.3, 0.3, 0.3)
        else 
            self.btnQuickRec:Enable()
            self.btnQuickRec.text:SetTextColor(1, 1, 1) 
        end
        
        if isRecording or isPlannerOpen then
             self.btnQuickFarm:Disable()
             self.btnQuickFarm.text:SetTextColor(0.3, 0.3, 0.3)
        else
             self.btnQuickFarm:Enable()
             if addon.isFarmMode then self.btnQuickFarm.text:SetTextColor(0, 1, 0) else self.btnQuickFarm.text:SetTextColor(1, 1, 1) end
        end
        
        if isEditing then
            self.btnQuickNav:Disable()
            self.btnQuickNav.text:SetTextColor(0.3, 0.3, 0.3)
        else
            self.btnQuickNav:Enable()
            if addon.drawConfig.navEnabled then self.btnQuickNav.text:SetTextColor(1, 0.82, 0) else self.btnQuickNav.text:SetTextColor(1, 1, 1) end
        end
        
        if addon.drawConfig.ghostView then self.btnQuickGhost.text:SetTextColor(0.5, 0.5, 1) else self.btnQuickGhost.text:SetTextColor(1, 1, 1) end

        if self.btnMarkedTimers then
            if self.timersFrame and self.timersFrame:IsShown() then
                self.btnMarkedTimers.text:SetTextColor(0, 1, 0) 
            else
                self.btnMarkedTimers.text:SetTextColor(1, 1, 1)
            end
        end
    end

    local function UpdatePanelToggleButton(button, panel)
        if not button then return end
        local isShown = panel and panel:IsShown() or false

        -- A click that closes a panel leaves the cursor over its toggle. Treat
        -- that moment as closed, not hovered, until the cursor actually leaves.
        if button.PanelWasShown and not isShown and button:IsMouseOver() then
            button.SuppressHoverUntilLeave = true
        end

        button.PanelWasShown = isShown
        button.ForceHighlight = isShown
        button:SetFrameLevel(isShown and 11 or 10)

        if isShown then
            button:SetBackdropBorderColor(1, 1, 1, 1)
        elseif button.SuppressHoverUntilLeave then
            button:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            button:SetBackdropBorderColor(0, 0, 0, 1)
        elseif button:IsMouseOver() then
            button:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
            button:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        else
            button:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            button:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    UpdatePanelToggleButton(self.btnRoutes, self.managerFrame)
    UpdatePanelToggleButton(self.btnTools, self.tacticalFrame)

    if self.tacticalFrame then
        if self.btnToggleShape then
             if addon.useSquareMap then
                 self.btnToggleShape.text:SetText("Square Map")
             else
                 self.btnToggleShape.text:SetText("Circle Map")
             end
        end

        if isPlannerOpen then
            self.btnTrack:Disable()
            self.btnTrack.text:SetTextColor(0.3, 0.3, 0.3)
        elseif isRecording and not isEditing then
             self.btnTrack.text:SetText("Stop New Route")
             self.btnTrack.text:SetTextColor(1, 0.2, 0.2) 
             self.btnTrack:Enable()
        elseif isRecording and isEditing then
             self.btnTrack:Disable()
             self.btnTrack.text:SetText("Start New Route")
             self.btnTrack.text:SetTextColor(0.3, 0.3, 0.3)
        else
             self.btnTrack:Enable()
             self.btnTrack.text:SetText("Start New Route")
             self.btnTrack.text:SetTextColor(0, 1, 0) 
        end
        
        if self.btnDraw then
            if isRecording then
                self.btnDraw:Disable()
                self.btnDraw.text:SetTextColor(0.3, 0.3, 0.3)
            else
                self.btnDraw:Enable()
                if isPlannerOpen then
                    self.btnDraw.text:SetTextColor(0, 1, 0)
                else
                    self.btnDraw.text:SetTextColor(1, 1, 1)
                end
            end
        end

        if isPlannerOpen then
            self.btnEditRoute:Disable()
            self.btnEditRoute.text:SetTextColor(0.3, 0.3, 0.3)
        elseif isRecording and isEditing then
             self.btnEditRoute.text:SetText("Stop Editing")
             self.btnEditRoute.text:SetTextColor(1, 0.2, 0.2) 
             self.btnEditRoute:Enable()
        elseif isRecording and not isEditing then
             self.btnEditRoute:Disable()
             self.btnEditRoute.text:SetText("Edit Current Route")
             self.btnEditRoute.text:SetTextColor(0.3, 0.3, 0.3)
        else
             if selectedRoute and selectedRouteMapID == mapID then
                 self.btnEditRoute.text:SetText("Edit Current Route")
                 self.btnEditRoute.text:SetTextColor(1, 1, 1)
                 self.btnEditRoute:Enable()
             else
                 self.btnEditRoute.text:SetText("Edit Current Route")
                 self.btnEditRoute.text:SetTextColor(0.5, 0.5, 0.5) 
                 self.btnEditRoute:Disable()
             end
        end

        if selectedRoute then
            self.activeRouteBtn.text:SetText(selectedRoute.name)
            local c = selectedRoute.color or {1,1,1,1}
            self.activeRouteBtn.text:SetTextColor(c[1], c[2], c[3], 1)
            
            if isRecording or isPlannerOpen or selectedRouteMapID ~= mapID then
                self.btnReverse:Disable()
                self.btnReverse.text:SetTextColor(0.5, 0.5, 0.5)
            else
                self.btnReverse:Enable()
                self.btnReverse.text:SetTextColor(1,1,1)
            end

            if selectedRoute.isReversed then
                self.btnReverse.ForceRedBorder = true
                self.btnReverse:SetBackdropBorderColor(1, 0, 0, 1)
            else
                self.btnReverse.ForceRedBorder = false
                self.btnReverse:SetBackdropBorderColor(0, 0, 0, 1)
            end
        else
            self.activeRouteBtn.text:SetText("None Selected")
            self.activeRouteBtn.text:SetTextColor(0.5, 0.5, 0.5)
            self.btnReverse:Disable()
            self.btnReverse.ForceRedBorder = false
            self.btnReverse:SetBackdropBorderColor(0, 0, 0, 1)
            self.btnReverse.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    
    if self.managerFrame then
        local disableImportExport = false
        if isRecording or isPlannerOpen then disableImportExport = true end
        if selectedRoute and selectedRoute.connectPaths then disableImportExport = true end
        
        if disableImportExport then
            self.btnImport:Disable()
            self.btnImport.text:SetTextColor(0.5, 0.5, 0.5)
        else
            self.btnImport:Enable()
            self.btnImport.text:SetTextColor(1, 1, 1)
        end

        if disableImportExport then
            self.btnExport:Disable()
            self.btnExport.text:SetTextColor(0.5, 0.5, 0.5)
        else
            if selectedRoute then
                self.btnExport:Enable()
                self.btnExport.text:SetTextColor(1,1,1)
            else
                self.btnExport:Disable()
                self.btnExport.text:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
    
    if self.timersFrame and self.timersFrame:IsShown() then
        self:UpdateTimerList()
    end

    if not skipSettingsApply then self:ApplySettings() end
end

local oldRefreshTactical = addon.MapFrame.RefreshTactical
function addon.MapFrame:RefreshTactical()
    self:UpdateUIState()
end

local function SuppressNativeMinimapZoomControls()
    if not addon.MapFrame.ownsMinimap then return end
    local controls = {}
    local function AddControl(control)
        if control then table.insert(controls, control) end
    end
    AddControl(MinimapZoomIn)
    AddControl(MinimapZoomOut)
    AddControl(Minimap and Minimap.ZoomIn)
    AddControl(Minimap and Minimap.ZoomOut)
    local seen = {}
    for _, control in ipairs(controls) do
        if control and not seen[control] then
            seen[control] = true
            if not control.pmPathmakerZoomSuppressed then
                control.pmPathmakerZoomSuppressed = true
                control:HookScript("OnShow", function(self)
                    local pathmakerFrame = addon.MapFrame and addon.MapFrame.frame
                    if addon.MapFrame.ownsMinimap and pathmakerFrame and pathmakerFrame:IsShown() then self:Hide() end
                end)
            end
            control:Hide()
        end
    end
end

function addon.MapFrame:CreateHeaderBar()
    self.headerBar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self.headerBar:SetSize(143, 15)
    self.headerBar:SetFrameLevel(10)
    self.headerBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", 
        edgeFile = "Interface\\Buttons\\WHITE8x8", 
        edgeSize = 1
    })
    self.headerBar:SetBackdropColor(0, 0, 0, 1)
    self.headerBar:SetBackdropBorderColor(0, 0, 0, 1)
    
    self.headerBar:EnableMouse(true)
    
    self.headerBar:SetScript("OnMouseDown", function(self, button) 
        local locked = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.minimapLocked
        if button == "LeftButton" and not locked and not (addon.Routes and addon.Routes.isRecording) then
            addon.MapFrame.frame:StartMoving() 
        end
    end)
    self.headerBar:SetScript("OnMouseUp", function(self) 
        addon.MapFrame.frame:StopMovingOrSizing() 
        local point, _, relativePoint, x, y = addon.MapFrame.frame:GetPoint()
        if not PathmakerDB.position then PathmakerDB.position = {} end
        PathmakerDB.position.point = point
        PathmakerDB.position.relativePoint = relativePoint
        PathmakerDB.position.x = x
        PathmakerDB.position.y = y
    end)
    
    self.frame:SetClampedToScreen(true)
    
    self.titleBadge = CreateFrame("Frame", nil, self.headerBar, "BackdropTemplate")
    self.titleBadge:SetSize(57, 14)
    self.titleBadge:SetPoint("LEFT", 20, 0)
    self.titleBadge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    self.titleBadge:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    self.titleBadge:SetBackdropBorderColor(0, 0, 0, 1)
    self.titleBadge:EnableMouse(false)

    self.dragText = self.titleBadge:CreateFontString(nil, "OVERLAY", "GameFontNormal") 
    self.dragText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE") 
    self.dragText:SetPoint("CENTER", 0, -1)
    self.dragText:SetText("PathMaker") 
    self.dragText:SetTextColor(1, 1, 0, 1)

    local controls = CreateFrame("Frame", nil, self.headerBar)
    controls:SetSize(62, 20) 
    controls:SetPoint("RIGHT", 0, 0)

    self.btnClose = StyleCloseButton(CreateMinimalButton(controls, "X", 14, 14))
    self.btnClose:SetPoint("RIGHT", 0, 0)
    self.btnClose:SetScript("OnClick", function() 
        addon.MapFrame:SetMinimapEnabled(false)
    end)

    self.btnZoomOut = StyleHeaderControlButton(CreateMinimalButton(controls, "-", 14, 14))
    self.btnZoomOut:SetPoint("RIGHT", self.btnClose, "LEFT", -3, 0) 
    self.btnZoomOut:SetScript("OnClick", function()
        if Minimap:GetZoom() > 0 then SetRememberedMinimapZoom(Minimap:GetZoom() - 1) end
    end)

    self.btnZoomIn = StyleHeaderControlButton(CreateMinimalButton(controls, "+", 14, 14))
    self.btnZoomIn:SetPoint("RIGHT", self.btnZoomOut, "LEFT", -3, 0) 
    self.btnZoomIn:SetScript("OnClick", function() SetRememberedMinimapZoom(Minimap:GetZoom() + 1) end)
    
    self.btnSettings = CreateFrame("Button", nil, self.headerBar, "BackdropTemplate")
    self.btnSettings:SetSize(14, 14)
    self.btnSettings:SetPoint("LEFT", 0, 0)
    self.btnSettings:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    self.btnSettings:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    self.btnSettings:SetBackdropBorderColor(0, 0, 0, 1)
    
    self.btnSettings.tex = self.btnSettings:CreateTexture(nil, "ARTWORK")
    self.btnSettings.tex:SetPoint("TOPLEFT", 2, -3)
    self.btnSettings.tex:SetPoint("BOTTOMRIGHT", -2, 1)
    self.btnSettings.tex:SetTexture("Interface\\Buttons\\UI-OptionsButton") 
    self.btnSettings.tex:SetVertexColor(0.82, 0.82, 0.82, 1)

    self.btnSettings:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintSettingsControl(self)
    end)
    self.btnSettings:SetScript("OnLeave", function(self)
        self.hovered = nil
        PaintSettingsControl(self)
    end)
    self.btnSettings:SetScript("OnHide", function(self)
        self.hovered = nil
        PaintSettingsControl(self)
    end)
    
    self.btnSettings:SetScript("OnClick", function() addon.MapFrame:ToggleSettings() end)

    SuppressNativeMinimapZoomControls()
end

-- ==========================================
-- MAIN CREATE FUNCTION
-- ==========================================
function addon.MapFrame:Create()
    self.frame = CreateFrame("Frame", "PathmakerMapFrame", UIParent, "BackdropTemplate")
    self.frame:SetSize(143, 143) 
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) 
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:SetFrameStrata("MEDIUM") 
    
    self.frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        if not PathmakerDB.position then PathmakerDB.position = {} end
        PathmakerDB.position.point = point
        PathmakerDB.position.relativePoint = relativePoint
        PathmakerDB.position.x = x
        PathmakerDB.position.y = y
    end)
    
    self.frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", tile = false, tileSize = 0, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
    self.frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9) 
    self.frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- The visible one-pixel black border has a slightly wider invisible hit
    -- area, so the minimap remains draggable even with both bars hidden.
    self.minimapDragBorders = {}
    local function SaveDraggedMinimapPosition()
        self.frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self.frame:GetPoint()
        PathmakerDB.position = PathmakerDB.position or {}
        PathmakerDB.position.point = point
        PathmakerDB.position.relativePoint = relativePoint
        PathmakerDB.position.x = x
        PathmakerDB.position.y = y
    end
    local borderLayouts = {
        function(border) border:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0); border:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0); border:SetHeight(5) end,
        function(border) border:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0); border:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0); border:SetHeight(5) end,
        function(border) border:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0); border:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0); border:SetWidth(5) end,
        function(border) border:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0); border:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0); border:SetWidth(5) end,
    }
    for _, layout in ipairs(borderLayouts) do
        local border = CreateFrame("Frame", nil, self.frame)
        layout(border)
        border:SetFrameLevel(self.frame:GetFrameLevel() + 25)
        border:EnableMouse(true)
        border:SetScript("OnMouseDown", function(_, button)
            local s = EnsurePathmakerSettings()
            if button == "LeftButton" and not s.minimapLocked and (s.alpha or 1) > 0 and not (addon.Routes and addon.Routes.isRecording) then
                addon.MapFrame.frame:StartMoving()
            end
        end)
        border:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then SaveDraggedMinimapPosition() end
        end)
        self.minimapDragBorders[#self.minimapDragBorders + 1] = border
    end

    -- Relaxed background failsafe timer
    self.frame:HookScript("OnUpdate", function(self, elapsed)
        addon.MapFrame.buttonLayoutTimer = (addon.MapFrame.buttonLayoutTimer or 0) + elapsed
        if addon.MapFrame.buttonLayoutTimer > 0.5 then
            addon.MapFrame.buttonLayoutTimer = 0
            addon.MapFrame:LayoutMinimapButtons()
        end
    end)

    self.inputBlocker = CreateFrame("Frame", nil, self.frame)
    self.inputBlocker:SetAllPoints()
    self.inputBlocker:EnableMouse(true) 
    self.inputBlocker:SetFrameLevel(self.frame:GetFrameLevel() + 10) 
    self.inputBlocker:Hide() 
    
    self.NorthTagFrame = CreateFrame("Frame", "PathmakerNorthTagFrame", self.frame)
    self.NorthTagFrame:SetSize(5, 5)
    self.NorthTagFrame:SetIgnoreParentAlpha(true) 
    
    self.NorthTagText = self.NorthTagFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.NorthTagText:SetPoint("CENTER")
    self.NorthTagText:SetText("N")
    self.NorthTagText:SetFontObject("GameFontNormal")
    self.NorthTagText:SetFont(self.NorthTagText:GetFont(), 10, "OUTLINE") 
    self.NorthTagText:SetTextColor(1, 0.82, 0, 1)
    
    self.NorthTagFrame:Hide()

    self.zoneBar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self.zoneBar:SetSize(143, 13)
    self.zoneBar:SetFrameLevel(10)
    self.zoneBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    self.zoneBar:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    self.zoneBar:SetBackdropBorderColor(0, 0, 0, 1)
    
    self.zoneBar:EnableMouse(true)
    self.zoneBar:SetScript("OnMouseDown", function(self, button) 
        local locked = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.minimapLocked
        if button == "LeftButton" and not locked and not (addon.Routes and addon.Routes.isRecording) then
            addon.MapFrame.frame:StartMoving() 
        end
    end)
    self.zoneBar:SetScript("OnMouseUp", function(self) 
        addon.MapFrame.frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = addon.MapFrame.frame:GetPoint()
        if not PathmakerDB.position then PathmakerDB.position = {} end
        PathmakerDB.position.point = point
        PathmakerDB.position.relativePoint = relativePoint
        PathmakerDB.position.x = x
        PathmakerDB.position.y = y
    end)
    
    self.ZoneText = self.zoneBar:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    self.ZoneText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    self.ZoneText:SetPoint("CENTER", self.zoneBar, "CENTER", 0, 0)
    self.ZoneText:SetWidth(135) 
    self.ZoneText:SetWordWrap(false)
    self.ZoneText:SetNonSpaceWrap(false)
    self.ZoneText:SetTextColor(1, 0.82, 0, 1) 
    self.ZoneText:SetText("")
    
    self:CreateHeaderBar() 
    self:CreateBottomButtons() 
    self:CreateQuickBar() 
    self:CreateTacticalMenu()
    self:CreateRouteManager() 
    self:CreateFarmFrame() 
    self:CreateTimersFrame() 
    
    self.frame:Hide() 
    
    self.frame:SetScript("OnEvent", function(self, event)
        if not addon.MapFrame then return end

        local zoneName = GetZoneText() or ""
        local subZoneName = GetSubZoneText() or ""
        if addon.MapFrame.ZoneText then
            addon.MapFrame.ZoneText:SetText(
                subZoneName ~= "" and subZoneName ~= zoneName and subZoneName or zoneName)
        end

        -- WoW emits several zone events for one transition. Collapse that
        -- burst into a single refresh so route lists, pins, and Farm Mode are
        -- not rebuilt three or four times in the same frame.
        if event == "PLAYER_ENTERING_WORLD" then addon.MapFrame.zoneRefreshSawEnteringWorld = true end
        addon.MapFrame.zoneRefreshGeneration = (addon.MapFrame.zoneRefreshGeneration or 0) + 1
        local generation = addon.MapFrame.zoneRefreshGeneration
        C_Timer.After(0.05, function()
            if not addon.MapFrame or addon.MapFrame.zoneRefreshGeneration ~= generation then return end

            local mapID = C_Map.GetBestMapForUnit("player")
            local mapChanged = addon.MapFrame.lastPlayerMapID ~= mapID
            local sawEnteringWorld = addon.MapFrame.zoneRefreshSawEnteringWorld == true
            addon.MapFrame.zoneRefreshSawEnteringWorld = nil
            addon.MapFrame.lastPlayerMapID = mapID

            if addon.Heatmap then
                addon.Heatmap:InvalidateVisibleNodeCache()
                if addon.Heatmap.OnPlayerMapChanged then addon.Heatmap:OnPlayerMapChanged() end
            end

            if addon.MapFrame.farmFrame then
                local farmFrame = addon.MapFrame.farmFrame
                farmFrame.pmFarmNodesDirty = true
                farmFrame.pmFarmOverlayDirty = true
                farmFrame.lastFarmNodeVisualUpdate = nil
                if mapChanged then
                    farmFrame.pmSmoothMapID = nil
                    farmFrame.pmSmoothPlayerX = nil
                    farmFrame.pmSmoothPlayerY = nil
                end
            end

            addon.MapFrame:UpdateRouteList()
            addon.MapFrame:UpdateUIState()
            if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end

            if addon.MapFrame.nodeFilterFrame and addon.MapFrame.nodeFilterFrame:IsShown() then
                addon.MapFrame:UpdateNodeFilterList()
            elseif sawEnteringWorld and EnsurePathmakerSettings().nodeFilterOpen
                and PathmakerDB.isEnabled and not addon.isFarmMode
            then
                if not addon.MapFrame.nodeFilterFrame then addon.MapFrame:CreateNodeFilterFrame() end
                addon.MapFrame.nodeFilterFrame:Show()
                addon.MapFrame:UpdateNodeFilterList()
            end
        end)
    end)
    
    self:CreateTrackingButton()
    self:CreateMailButton()
    self:CreateLFGButton() 
    self:CreatePVPButton()

    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function()
            if addon.MapFrame.settingsFrame and addon.MapFrame.settingsFrame:IsShown() then
                addon.MapFrame.settingsFrame:Hide()
                addon.MapFrame:ApplySettings(nil) 
                if addon.MapFrame.btnClose then 
                    addon.MapFrame.btnClose:Enable() 
                    addon.MapFrame.btnClose.text:SetTextColor(1,1,1) 
                end
            end
        end)
    end
end

-- ==========================================
-- TRACKING HELPER FUNCTIONS
-- ==========================================
local function GetNumTrackingTypes()
    return addon.Compat and addon.Compat:GetNumTrackingTypes() or 0
end

local function GetTrackingInfo(i)
    if addon.Compat then return addon.Compat:GetTrackingInfo(i) end
end

local function SetTracking(i, val)
    if addon.Compat then addon.Compat:SetTracking(i, val) end
end

function addon.MapFrame:ToggleTrackingMenu(anchor)
    if self.trackingMenu and self.trackingMenu:IsShown() then
        self.trackingMenu:Hide()
        return
    end
    if not self.trackingMenu then self:CreateTrackingMenu() end
    
    self.trackingMenu:ClearAllPoints()
    if anchor then
        self.trackingMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    else
        self.trackingMenu:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 5, 0)
    end
    self.trackingMenu:Show()
    self:UpdateTrackingList()
end

function addon.MapFrame:CreateTrackingMenu()
    local f = CreateFrame("Frame", "PathmakerTrackingMenu", UIParent, "BackdropTemplate")
    f:SetSize(135, 300)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH") 
    f:SetFrameLevel(50)
    f:SetToplevel(true)
    
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -8)
    header:SetText("Tracking")
    
    local btnClose = StyleCloseButton(CreateMinimalButton(f, "X", 16, 16))
    btnClose:SetPoint("TOPRIGHT", -2, -2)
    btnClose:SetScript("OnClick", function() f:Hide() end)
    
    local scrollFrame, scrollChild, slider = CreateDarkScrollArea(f, 115, 260)
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    
    f.scrollFrame = scrollFrame
    f.scrollChild = scrollChild
    f.slider = slider
    f.buttons = {}
    
    self.trackingMenu = f
end

function addon.MapFrame:UpdateTrackingList()
    local f = self.trackingMenu
    if not f then return end
    
    local child = f.scrollChild
    for _, btn in pairs(f.buttons) do btn:Hide() end
    
    local count = GetNumTrackingTypes()
    local height = 0
    local buttonHeight = 20
    
    for i = 1, count do
        local name, texture, active, category
        local raw1, raw2, raw3, raw4 = GetTrackingInfo(i)
        
        if type(raw1) == "table" then
            name = raw1.name
            texture = raw1.texture
            active = raw1.active
            category = raw1.subType
        else
            name, texture, active, category = raw1, raw2, raw3, raw4
        end

        if type(name) == "table" and name.name then
             texture = name.texture
             active = name.active
             category = name.subType
             name = name.name
        end
        
        if name and type(name) == "string" then 
            local btn = f.buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, child, "BackdropTemplate")
                btn:SetSize(170, buttonHeight)
                btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
                
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(14, 14)
                btn.icon:SetPoint("LEFT", 2, 0)
                
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
                btn.text:SetPoint("RIGHT", -5, 0)
                btn.text:SetJustifyH("LEFT")
                
                btn:SetScript("OnClick", function(self)
                    SetTracking(self.index, not self.active)
                    C_Timer.After(0.1, function() addon.MapFrame:UpdateTrackingList() end)
                end)
                
                btn:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
                end)
                btn:SetScript("OnLeave", function(self)
                    if self.active then
                        self:SetBackdropColor(0.2, 0.5, 0.2, 0.6)
                    else
                        self:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
                    end
                end)
                f.buttons[i] = btn
            end
            
            btn.index = i
            btn.active = active
            btn.text:SetText(name)
            btn.icon:SetTexture(texture)
            
            if active then
                btn:SetBackdropColor(0.2, 0.5, 0.2, 0.6)
                btn.text:SetTextColor(1, 1, 1)
            else
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
                btn.text:SetTextColor(0.5, 0.5, 0.5)
            end
            
            btn:SetPoint("TOPLEFT", 0, -height)
            btn:Show()
            height = height + buttonHeight + 1
        end
    end
    
    child:SetHeight(math.max(1, height))
    local maxScroll = math.max(0, height - 210)
    f.slider:SetMinMaxValues(0, maxScroll)
end

function addon.MapFrame:CreateTrackingButton()
    local size = 20
    local btn = CreateFrame("Button", "PathmakerTrackingButton", self.frame, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 5, -5)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(20)
    
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetSize(16, 16)
    btn.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    
    local function HasTrackingAPI()
        return addon.Compat and addon.Compat:HasMinimapTracking()
    end

    local function GetActiveTrackingTexture()
        return addon.Compat and addon.Compat:GetTrackingTexture()
    end

    local function UpdateTrackingIcon()
        if (PathmakerDB.settings and PathmakerDB.settings.hideTracking) or not HasTrackingAPI() then
            btn:Hide()
            if addon.MapFrame.mailButton then addon.MapFrame.mailButton:UpdateAnchor() end
            return
        end
        
        btn:Show()
        local icon = GetActiveTrackingTexture()
        if icon then
            btn.icon:SetTexture(icon)
        else
            btn.icon:SetTexture("Interface\\Icons\\inv_misc_spyglass_02") 
        end
        
        if addon.MapFrame.mailButton then addon.MapFrame.mailButton:UpdateAnchor() end
    end
    
    function btn:UpdateAnchor()
        btn:ClearAllPoints()
        local fullEdges = PathmakerDB.settings and PathmakerDB.settings.minimapUseFullEdges
        btn:SetPoint("TOPLEFT", addon.MapFrame.frame, "TOPLEFT", fullEdges and 0 or 5, fullEdges and 0 or -5)
    end

    function btn:UpdateState()
        self:UpdateAnchor()
        UpdateTrackingIcon()
    end
    
    function btn:EnableEvents()
        if not HasTrackingAPI() then
            self:UnregisterAllEvents()
            self:Hide()
            return
        end
        pcall(self.RegisterEvent, self, "MINIMAP_UPDATE_TRACKING")
        pcall(self.RegisterEvent, self, "PLAYER_LOGIN")
        pcall(self.RegisterEvent, self, "PLAYER_ENTERING_WORLD")
        pcall(self.RegisterEvent, self, "SPELLS_CHANGED")
        self:UpdateState()
    end

    function btn:DisableEvents()
        self:UnregisterAllEvents()
        self:Hide()
    end

    btn:SetScript("OnEvent", function() btn:UpdateState() end)
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function(self)
        PlaySound(856)
        addon.MapFrame:ToggleTrackingMenu(self)
    end)
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Tracking")
        GameTooltip:AddLine(GetActiveTrackingTexture() and "Click to change tracking" or "Click to select tracking", 1,1,1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        GameTooltip:Hide()
    end)
    btn:EnableMouse(true)
    self.trackingButton = btn
end

function addon.MapFrame:CreateMailButton()
    local size = 20
    local btn = CreateFrame("Button", "PathmakerMailButton", self.frame, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(20)
    
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    btn:SetBackdropBorderColor(0, 0, 0, 1)
    
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetSize(16, 16)
    btn.icon:SetTexture("Interface\\Icons\\INV_Letter_15") 
    btn.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    
    function btn:UpdateAnchor()
        btn:ClearAllPoints()
        local fullEdges = PathmakerDB.settings and PathmakerDB.settings.minimapUseFullEdges
        if fullEdges then
            if addon.MapFrame.trackingButton and addon.MapFrame.trackingButton:IsShown() then
                btn:SetPoint("TOP", addon.MapFrame.trackingButton, "BOTTOM", 0, 0)
            else
                btn:SetPoint("TOPLEFT", addon.MapFrame.frame, "TOPLEFT", 0, 0)
            end
        elseif addon.MapFrame.trackingButton and addon.MapFrame.trackingButton:IsShown() then
            btn:SetPoint("TOP", addon.MapFrame.trackingButton, "BOTTOM", 0, -0)
        else
            btn:SetPoint("TOPLEFT", addon.MapFrame.frame, "TOPLEFT", 5, -5)
        end
        if addon.MapFrame.lfgButton then addon.MapFrame.lfgButton:UpdateAnchor() end
    end
    
    local function UpdateMail()
        if MiniMapMailFrame then 
             MiniMapMailFrame:Hide() 
             MiniMapMailFrame:SetAlpha(0) 
        end

        if HasNewMail() then
            btn:Show()
            btn:UpdateAnchor()
        else
            btn:Hide()
            if addon.MapFrame.lfgButton then addon.MapFrame.lfgButton:UpdateAnchor() end
        end
    end

    function btn:UpdateState()
        UpdateMail()
    end
    
    function btn:EnableEvents()
        self:RegisterEvent("UPDATE_PENDING_MAIL")
        self:RegisterEvent("MAIL_INBOX_UPDATE")
        self:RegisterEvent("MAIL_CLOSED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        UpdateMail()
    end

    function btn:DisableEvents()
        self:UnregisterAllEvents()
        self:Hide()
    end

    btn:SetScript("OnEvent", UpdateMail)
    
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Unread Mail From:")
        
        -- Enhanced Mail Tooltip Logic to display who sent it
        local sender1, sender2, sender3 = GetLatestThreeSenders()
        if sender1 or sender2 or sender3 then
            if sender1 then GameTooltip:AddLine(sender1, 1, 1, 1) end
            if sender2 then GameTooltip:AddLine(sender2, 1, 1, 1) end
            if sender3 then GameTooltip:AddLine(sender3, 1, 1, 1) end
        end
        
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        GameTooltip:Hide()
    end)
    self.mailButton = btn
end

function addon.MapFrame:CreateLFGButton()
    local size = 20
    local btn = CreateFrame("Button", "PathmakerLFGButton", self.frame, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(20)

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    -- Reverted back to the original icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetSize(16, 16)
    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore") 
    btn.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    function btn:UpdateAnchor()
        btn:ClearAllPoints()
        local parent = addon.MapFrame.frame
        local settings = PathmakerDB.settings or {}
        if settings.minimapUseFullEdges then
             if addon.MapFrame.mailButton and addon.MapFrame.mailButton:IsShown() then
                 btn:SetPoint("TOP", addon.MapFrame.mailButton, "BOTTOM", 0, 0)
             elseif addon.MapFrame.trackingButton and addon.MapFrame.trackingButton:IsShown() then
                 btn:SetPoint("TOP", addon.MapFrame.trackingButton, "BOTTOM", 0, 0)
             else
                 btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
             end
        elseif addon.MapFrame.mailButton and addon.MapFrame.mailButton:IsShown() then
             btn:SetPoint("TOP", addon.MapFrame.mailButton, "BOTTOM", 0, -0)
        elseif addon.MapFrame.trackingButton and addon.MapFrame.trackingButton:IsShown() then
             btn:SetPoint("TOP", addon.MapFrame.trackingButton, "BOTTOM", 0, -0)
        else
             -- Give it a cleaner inset from the top left corner
             btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
        end
        if addon.MapFrame.pvpButton then addon.MapFrame.pvpButton:UpdateAnchor() end
    end

    function btn:UpdateState()
        if PathmakerDB.settings and PathmakerDB.settings.hideLFG then
            btn:Hide()
        else
            btn:Show()
        end
        btn:UpdateAnchor()
    end

    -- Variable to remember the last tab for the current session (resets on reload/relog)
    local lastLFGTab = nil

    btn:SetScript("OnClick", function(self)
        -- 1. Identify the LFG Parent Frame for Classic/TBC
        local pFrame = LFGParentFrame or GroupFinderFrame or PVEFrame
        
        -- 2. If it's already shown, just hide it and exit safely
        if pFrame and pFrame:IsShown() then
            HideUIPanel(pFrame)
            return
        end

        -- 3. Open the frame natively based on available APIs
        if ToggleLookingForGroupFrame then 
            ToggleLookingForGroupFrame() 
        elseif PVEFrame_ToggleFrame then 
            PVEFrame_ToggleFrame() 
        else
            if pFrame then
                ShowUIPanel(pFrame)
            elseif ToggleFriendsFrame then 
                ToggleFriendsFrame(4) 
            end
        end
        
        -- 4. Force switch to the remembered tab
        -- A tiny 0.05s delay ensures the UI has finished its internal OnShow frame building
        C_Timer.After(0.05, function()
            local frameToCheck = LFGParentFrame or GroupFinderFrame or PVEFrame
            if frameToCheck and frameToCheck:IsShown() then
                
                -- Hook OnHide to safely save the user's active tab when they close the window
                if not frameToCheck.pmHookedOnHide then
                    frameToCheck:HookScript("OnHide", function(f)
                        if PanelTemplates_GetSelectedTab then
                            lastLFGTab = PanelTemplates_GetSelectedTab(f)
                        end
                    end)
                    frameToCheck.pmHookedOnHide = true
                end

                -- In TBC/Classic Anniversary, Tab 1 is "Create Listing" and Tab 2 is "Group Browser"
                local targetTab = lastLFGTab or 1 
                local tabButton = _G[(frameToCheck:GetName() or "") .. "Tab" .. targetTab]
                
                if tabButton then
                    -- Visually and logically click the tab
                    tabButton:Click()
                    
                    -- Force the OnClick script just in case the standard Click() didn't fire UI updates
                    local onClick = tabButton:GetScript("OnClick")
                    if onClick then onClick(tabButton) end
                    
                    -- Classic UI sometimes needs an explicit call to update the PanelTemplates
                    if PanelTemplates_SetTab then
                        PanelTemplates_SetTab(frameToCheck, targetTab)
                    end
                    
                    -- Ensure the specific sub-frame is refreshed by trying common update functions
                    if LFGParentFrame_Update then LFGParentFrame_Update() end
                    if LFGFrame_Update then LFGFrame_Update() end
                end
            end
        end)
    end)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Looking For Group") 
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0, 0, 0, 1)
        GameTooltip:Hide()
    end)

    self.lfgButton = btn
end

function addon.MapFrame:CreatePVPButton()
    local size = 20
    local btn = CreateFrame("Button", "PathmakerPVPButton", self.frame, "BackdropTemplate")
    btn:SetSize(size, size)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(20)

    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    btn:SetBackdropBorderColor(0, 0, 0, 1)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetSize(16, 16)
    
    local factionGroup = UnitFactionGroup("player")
    if factionGroup == "Alliance" then
        btn.icon:SetTexture("Interface\\Icons\\INV_BannerPVP_02")
    else
        btn.icon:SetTexture("Interface\\Icons\\INV_BannerPVP_01")
    end
    btn.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    function btn:UpdateAnchor()
        btn:ClearAllPoints()
        local parent = addon.MapFrame.frame
        local settings = PathmakerDB.settings or {}
        if settings.minimapUseFullEdges then
             if addon.MapFrame.lfgButton and addon.MapFrame.lfgButton:IsShown() then
                 btn:SetPoint("TOP", addon.MapFrame.lfgButton, "BOTTOM", 0, 0)
             elseif addon.MapFrame.mailButton and addon.MapFrame.mailButton:IsShown() then
                 btn:SetPoint("TOP", addon.MapFrame.mailButton, "BOTTOM", 0, 0)
             elseif addon.MapFrame.trackingButton and addon.MapFrame.trackingButton:IsShown() then
                 btn:SetPoint("TOP", addon.MapFrame.trackingButton, "BOTTOM", 0, 0)
             else
                 btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
             end
        elseif addon.MapFrame.lfgButton and addon.MapFrame.lfgButton:IsShown() then
             btn:SetPoint("TOP", addon.MapFrame.lfgButton, "BOTTOM", 0, -0)
        elseif addon.MapFrame.mailButton and addon.MapFrame.mailButton:IsShown() then
             btn:SetPoint("TOP", addon.MapFrame.mailButton, "BOTTOM", 0, -0)
        elseif addon.MapFrame.trackingButton and addon.MapFrame.trackingButton:IsShown() then
             btn:SetPoint("TOP", addon.MapFrame.trackingButton, "BOTTOM", 0, -0)
        else
             btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
        end
    end

    local function UpdatePVPIcon()
        local inQueueOrMatch = false
        if GetMaxBattlefieldID then
            for i = 1, GetMaxBattlefieldID() do
                local status = GetBattlefieldStatus(i)
                if status == "queued" or status == "confirm" or status == "active" then
                    inQueueOrMatch = true
                    break
                end
            end
        end
        
        if QueueStatusMinimapButton and QueueStatusMinimapButton:IsShown() then
            inQueueOrMatch = true
        end
        
        if inQueueOrMatch then
            btn:Show()
        else
            btn:Hide()
        end
        btn:UpdateAnchor()
        
        -- FIX: Securely overlay the Blizzard PVP frame transparently.
        -- This forces right-clicks and tooltips to fire off the native UI component, 
        -- keeping addon compatibility clean while preserving the custom grey border visual.
        if addon.MapFrame.ownsMinimap then
            if MiniMapBattlefieldFrame then 
                MiniMapBattlefieldFrame:SetParent(btn)
                MiniMapBattlefieldFrame:ClearAllPoints()
                MiniMapBattlefieldFrame:SetAllPoints(btn)
                MiniMapBattlefieldFrame:SetFrameLevel(btn:GetFrameLevel() + 5)
                
                MiniMapBattlefieldFrame:SetAlpha(1)
                MiniMapBattlefieldFrame:EnableMouse(true)
                
                local regions = {MiniMapBattlefieldFrame:GetRegions()}
                for _, region in ipairs(regions) do
                    if region:IsObjectType("Texture") then region:SetAlpha(0) end
                end
                
                -- Catch internal icons like MiniMapBattlefieldIcon if they exist natively
                for _, child in ipairs({MiniMapBattlefieldFrame:GetChildren()}) do
                     if child:IsObjectType("Texture") then child:SetAlpha(0) end
                end
                if MiniMapBattlefieldIcon then MiniMapBattlefieldIcon:SetAlpha(0) end
                if MiniMapBattlefieldBorder then MiniMapBattlefieldBorder:SetAlpha(0) end
                
                if inQueueOrMatch then
                    MiniMapBattlefieldFrame:Show()
                end
            end
            
            if QueueStatusMinimapButton then
                QueueStatusMinimapButton:SetParent(btn)
                QueueStatusMinimapButton:ClearAllPoints()
                QueueStatusMinimapButton:SetAllPoints(btn)
                QueueStatusMinimapButton:SetFrameLevel(btn:GetFrameLevel() + 5)
                
                QueueStatusMinimapButton:SetAlpha(1)
                QueueStatusMinimapButton:EnableMouse(true)
                
                local regions = {QueueStatusMinimapButton:GetRegions()}
                for _, region in ipairs(regions) do
                    if region:IsObjectType("Texture") then region:SetAlpha(0) end
                end
                for _, child in ipairs({QueueStatusMinimapButton:GetChildren()}) do
                     if child:IsObjectType("Texture") then child:SetAlpha(0) end
                end
                if QueueStatusMinimapButtonIcon then QueueStatusMinimapButtonIcon:SetAlpha(0) end
                if QueueStatusMinimapButtonBorder then QueueStatusMinimapButtonBorder:SetAlpha(0) end
            end
        end
    end

    function btn:UpdateState()
        UpdatePVPIcon()
    end

    function btn:EnableEvents()
        self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("LFG_UPDATE")
        self:UpdateState()
    end

    function btn:DisableEvents()
        self:UnregisterAllEvents()
        self:Hide()
    end

    btn:SetScript("OnEvent", function() btn:UpdateState() end)

    if MiniMapBattlefieldFrame then
        -- Native Hover Highlights Translation
        MiniMapBattlefieldFrame:HookScript("OnEnter", function()
            btn:SetBackdropBorderColor(1, 1, 1, 1)
        end)
        MiniMapBattlefieldFrame:HookScript("OnLeave", function()
            btn:SetBackdropBorderColor(0, 0, 0, 1)
        end)
    end
    
    if QueueStatusMinimapButton then
        QueueStatusMinimapButton:HookScript("OnEnter", function()
            btn:SetBackdropBorderColor(1, 1, 1, 1)
        end)
        QueueStatusMinimapButton:HookScript("OnLeave", function()
            btn:SetBackdropBorderColor(0, 0, 0, 1)
        end)
    end
    
    -- Safety Fallback for unrecognized/heavily modded clients
    if not MiniMapBattlefieldFrame and not QueueStatusMinimapButton then
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Player vs Player")
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0, 0, 0, 1)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                if ToggleWorldStateScoreFrame then ToggleWorldStateScoreFrame()
                elseif ToggleBattlefieldMinimap then ToggleBattlefieldMinimap() 
                end
            end
        end)
    end
    
    self.pvpButton = btn
end

function addon.MapFrame:SetFarmMouseMode(settings)
    if not Minimap then return end
    local s = settings or EnsurePathmakerSettings()
    if addon.isFarmMode then RestoreNativeMinimapToFarmFrame(self.farmFrame, s) end
    SetNativeFarmPlayerArrowVisible(false, true)
    SetFarmMinimapZoomLocked(true)
    EnsureFarmMinimapTooltipFilter()

    Minimap:EnableMouse(false)
    if Minimap.SetMouseMotionEnabled then Minimap:SetMouseMotionEnabled(false) end
    if Minimap.SetMouseClickEnabled then Minimap:SetMouseClickEnabled(false) end
    Minimap.pmFarmGoldBlipMouseCapture = nil
    Minimap.pmFarmHoverEnabled = nil
    Minimap.pmFarmGoldBlipCheckedAt = nil
    Minimap.pmFarmGatheringRefreshAt = nil
    UpdateFarmGoldBlipMouseCapture(true)

    local explicitControls = {
        -- Keep Blizzard's opaque black minimap underlay hidden. Map-provider
        -- changes can Show() these objects again, so the farm-state helper also
        -- installs a guarded Show hook until Farm Mode exits.
        MinimapBackdrop,
        MinimapBorder,
        MinimapBorderTop,
        MinimapCluster and MinimapCluster.Backdrop,
        MinimapCluster and MinimapCluster.Border,
        MinimapCluster and MinimapCluster.BorderTop,
        MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.Backdrop,
        MinimapCluster and MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.Border,
        _G["MinimapCompassFrame"],
        _G["MinimapCompassTexture"],
        MinimapNorthTag,
        MinimapZoneTextButton,
        MinimapZoomIn,
        MinimapZoomOut,
        Minimap.ZoomIn,
        Minimap.ZoomOut,
        MinimapToggleButton,
        GameTimeFrame,
        TimeManagerClockButton,
        MiniMapTracking,
        MiniMapMailFrame,
        MiniMapInstanceDifficulty,
        GuildInstanceDifficulty,
        MiniMapChallengeMode,
        MiniMapWorldMapButton,
        MiniMapLFGFrame,
        LFGMinimapFrame,
        MiniMapVoiceChatFrame,
        MiniMapRecordingButton,
        GarrisonLandingPageMinimapButton,
        ExpansionLandingPageMinimapButton,
        MiniMapBattlefieldFrame,
        MinimapBattlefieldFrame,
        QueueStatusMinimapButton,
        _G["SuperTrackedFrame"],
        _G["SuperTrackedFrameContainer"],
        _G["NavigationFrame"],
        MinimapCluster and MinimapCluster.Tracking,
        MinimapCluster and MinimapCluster.IndicatorFrame,
    }

    for _, control in pairs(explicitControls) do
        StoreAndHideFarmMinimapObject(control)
    end

    for _, child in ipairs({Minimap:GetChildren()}) do
        local name = child:GetName() or ""
        local lowerName = string.lower(name)
        local isControl = string.find(lowerName, "mail") or
                          string.find(lowerName, "zoom") or
                          string.find(lowerName, "clock") or
                          string.find(lowerName, "north") or
                          string.find(lowerName, "worldmap") or
                          string.find(lowerName, "difficulty") or
                          string.find(lowerName, "instance") or
                          string.find(lowerName, "lfg") or
                          string.find(lowerName, "pvp") or
                          string.find(lowerName, "battlefield") or
                          string.find(lowerName, "queue") or
                          string.find(lowerName, "garrison") or
                          string.find(lowerName, "landing") or
                          string.find(lowerName, "voice") or
                          string.find(lowerName, "recording")

        if isControl and name ~= "PathmakerCanvas" and name ~= "PathmakerHeatmapMini" and not string.find(name, "Pathmaker") then
            StoreAndHideFarmMinimapObject(child)
            if child.GetRegions then
                for _, region in ipairs({child:GetRegions()}) do
                    StoreAndHideFarmMinimapObject(region)
                end
            end
        end
    end
    KeepNativeGatheringTrackingVisible()
end

function addon.MapFrame:ApplyFarmOverlayTransform(frame, settings)
    if not frame or not addon.isFarmMode or not self.farmFrame then return end
    local s = settings or EnsurePathmakerSettings()
    local rotation = GetFarmViewRotation()
    local farmCenterX, farmCenterY = self.farmFrame:GetCenter()
    if not farmCenterX or not farmCenterY then return end

    KeepFarmOverlayVisible(frame, 1)

    local maxRadius = ((s.farmCircleSize or 420) / 2) - 10
    local allowOutside = s.farmAllowRoutesBeyondCircle == true

    local function TransformRegion(region)
        if not region or region == self.farmFrame then return end
        if region.GetCenter and region.ClearAllPoints and region.SetPoint then
            if not region.pmFarmBaseX or not region.pmFarmBaseY or region.pmFarmResetBase then
                local cx, cy = region:GetCenter()
                if cx and cy then
                    region.pmFarmBaseX = cx - farmCenterX
                    region.pmFarmBaseY = cy - farmCenterY
                    region.pmFarmBaseRotation = region.GetRotation and region:GetRotation() or 0
                    region.pmFarmResetBase = nil
                end
            end

            if region.pmFarmBaseX and region.pmFarmBaseY then
                local baseX, baseY = region.pmFarmBaseX, region.pmFarmBaseY
                local outX = (baseX * math.cos(rotation)) - (baseY * math.sin(rotation))
                local outY = (baseX * math.sin(rotation)) + (baseY * math.cos(rotation))
                local isOutside = ((outX * outX) + (outY * outY)) > (maxRadius * maxRadius)

                if not allowOutside and isOutside then
                    if region.Hide then region:Hide() end
                else
                    if region.Show then region:Show() end
                    region:ClearAllPoints()
                    region:SetPoint("CENTER", self.farmFrame, "CENTER", outX, outY)
                    if region.SetRotation then
                        region:SetRotation((region.pmFarmBaseRotation or 0) + rotation)
                    end
                end
            end
        elseif region.SetRotation then
            region:SetRotation(rotation)
        end
    end

    for _, region in ipairs({frame:GetRegions()}) do
        TransformRegion(region)
    end

    for _, child in ipairs({frame:GetChildren()}) do
        TransformRegion(child)
        if child.GetRegions then
            for _, region in ipairs({child:GetRegions()}) do
                TransformRegion(region)
            end
        end
    end
end

function addon.MapFrame:RefreshFarmOverlays(settings, updateRoute, updateNodes)
    if not addon.isFarmMode then return end
    local s = settings or EnsurePathmakerSettings()
    if _G["PathmakerCanvas"] then _G["PathmakerCanvas"]:Hide() end
    if _G["PathmakerHeatmapMini"] then _G["PathmakerHeatmapMini"]:Hide() end
    if updateRoute ~= false and self.UpdateFarmRoute then self:UpdateFarmRoute(s) end
    if updateNodes ~= false and self.UpdateFarmNodes then self:UpdateFarmNodes(s) end
    if updateNodes == false and self.UpdateFarmNodePositions then self:UpdateFarmNodePositions(s) end
end

function addon.MapFrame:ResetFarmVisuals()
    local f = self.farmFrame
    if not f then return end

    -- Outside Farm Mode the entire frame is hidden. Mark its caches stale and
    -- let the next Farm Mode refresh recycle the visible subset; walking every
    -- pooled route line and node here made an ordinary route deselection hitch.
    if not addon.isFarmMode then
        f.pmFarmRouteGUID = nil
        f.pmFarmRouteDirty = true
        f.pmFarmNodesDirty = true
        return
    end

    for _, line in ipairs(f.routeLines or {}) do
        line:Hide()
        line:ClearAllPoints()
        line.pmFarmPoint1 = nil
        line.pmFarmPoint2 = nil
        if line.pmFarmNativeLine then
            line:SetStartPoint("CENTER", f, 0, 0)
            line:SetEndPoint("CENTER", f, 0, 0)
        else
            line:SetSize(1, 1)
            if line.SetRotation then line:SetRotation(0) end
        end
    end

    for _, btn in ipairs(f.nodeButtons or {}) do
        btn:Hide()
        btn:ClearAllPoints()
        btn.nodeData = nil
        btn.pmNodeMapID = nil
        btn.pmFarmDrawX = nil
        btn.pmFarmDrawY = nil
    end

    f.activeFarmRouteLineCount = 0
    f.activeFarmNodeCount = 0
    f.pmFarmRouteDirty = true
    f.pmFarmNodesDirty = true
end

function addon.MapFrame:ResetFarmOverlayTransform(frame)
    if not frame then return end
    local function ResetRegion(region)
        if not region then return end
        local baseRotation = region.pmFarmBaseRotation
        region.pmFarmBaseX = nil
        region.pmFarmBaseY = nil
        region.pmFarmBaseRotation = nil
        region.pmFarmResetBase = true
        if region.SetRotation then region:SetRotation(baseRotation or 0) end
    end

    for _, region in ipairs({frame:GetRegions()}) do
        ResetRegion(region)
    end
    for _, child in ipairs({frame:GetChildren()}) do
        ResetRegion(child)
        if child.GetRegions then
            for _, region in ipairs({child:GetRegions()}) do
                ResetRegion(region)
            end
        end
    end
    if frame.SetAlpha then frame:SetAlpha(1) end
end

function addon.MapFrame:UpdateFarmCompass(facing)
    local f = self.farmFrame
    if not f then return end
    local s = EnsurePathmakerSettings()
    local showCompass = s.farmShowCompass == true
    local radius = ((s.farmCircleSize or 420) / 2) + 18
    local rotation = GetFarmCompassRotation()

    for _, label in ipairs(f.compassLabels or {}) do
        if showCompass then
            local angle = label.baseAngle + rotation
            label:ClearAllPoints()
            label:SetPoint("CENTER", f, "CENTER", math.sin(angle) * radius, math.cos(angle) * radius)
            label:SetAlpha(1)
            label:Show()
        else
            label:Hide()
        end
    end
end

function addon.MapFrame:UpdateFarmCircleLayout(settings)
    local f = self.farmFrame
    if not f then return end
    local s = settings or EnsurePathmakerSettings()
    local size = math.max(160, math.min(900, s.farmCircleSize or 420))
    local alpha = s.farmCircleAlpha or 0.75
    -- This is the Farm Mode boundary, not a node heatmap circle.
    local showCircle = true
    local radius = (size / 2) - 10
    local lineCount = #(f.circleSegments or {})
    local segLen = math.max(8, (2 * math.pi * radius / math.max(lineCount, 1)) + 2)

    f:SetSize(size, size)

    for index, seg in ipairs(f.circleSegments or {}) do
        local angle = (index - 1) / lineCount * (2 * math.pi)
        seg:ClearAllPoints()
        if seg.SetDrawLayer then seg:SetDrawLayer("OVERLAY", 6) end
        if seg.SetRotation then
            seg:SetSize(segLen, 2)
        else
            seg:SetSize(4, 4)
        end
        seg:SetPoint("CENTER", f, "CENTER", math.sin(angle) * radius, math.cos(angle) * radius)
        seg:SetColorTexture(FARM_GREEN[1], FARM_GREEN[2], FARM_GREEN[3], alpha)
        SetTextureRotation(seg, -angle)
        if showCircle then seg:Show() else seg:Hide() end
    end

    for index, tick in ipairs(f.tickSegments or {}) do
        local angle = (index - 1) / 8 * (2 * math.pi)
        tick:ClearAllPoints()
        if tick.SetDrawLayer then tick:SetDrawLayer("OVERLAY", 7) end
        if tick.SetRotation then
            tick:SetSize(14, 3)
        else
            tick:SetSize(5, 5)
        end
        tick:SetPoint("CENTER", f, "CENTER", math.sin(angle) * radius, math.cos(angle) * radius)
        tick:SetColorTexture(FARM_GREEN[1], FARM_GREEN[2], FARM_GREEN[3], alpha)
        SetTextureRotation(tick, -angle + (math.pi / 2))
        if showCircle then tick:Show() else tick:Hide() end
    end

    self:UpdateFarmPlayerMarker((f and f.pmSmoothFacing) or GetPlayerFacing() or 0, s)

    if f.coordText then
        f.coordText:ClearAllPoints()
        f.coordText:SetPoint("TOP", f, "BOTTOM", 0, -4)
        f.coordText:SetAlpha(1)
    end

    if f.btnExit then
        f.btnExit:ClearAllPoints()
        f.btnExit:SetPoint("BOTTOM", f, "TOP", 0, 5)
    end
    self:UpdateFarmCompass((f and f.pmSmoothFacing) or GetPlayerFacing() or 0)
    if addon.isFarmMode then RestoreNativeMinimapToFarmFrame(f, s) end
end

function addon.MapFrame:ApplyFarmCircleAlpha(settings)
    local f = self.farmFrame
    if not f then return end

    local s = settings or EnsurePathmakerSettings()
    local alpha = math.max(0, math.min(1, tonumber(s.farmCircleAlpha) or 0.75))
    s.farmCircleAlpha = alpha
    addon.farmCircleAlpha = alpha

    for _, seg in ipairs(f.circleSegments or {}) do
        seg:SetColorTexture(FARM_GREEN[1], FARM_GREEN[2], FARM_GREEN[3], alpha)
        seg:Show()
    end

    for _, tick in ipairs(f.tickSegments or {}) do
        tick:SetColorTexture(FARM_GREEN[1], FARM_GREEN[2], FARM_GREEN[3], alpha)
        tick:Show()
    end
end

function addon.MapFrame:ApplyFarmMarkerSize(settings)
    local f = self.farmFrame
    if not f then return end

    local s = settings or EnsurePathmakerSettings()
    s.farmPlayerMarkerSize = GetFarmPlayerMarkerSize(s)
    self:UpdateFarmPlayerMarker((f and f.pmSmoothFacing) or GetPlayerFacing() or 0, s)
end

function addon.MapFrame:UpdateFarmDotMarker(settings)
    local f = self.farmFrame
    if not f then return end

    local s = settings or EnsurePathmakerSettings()
    local style = GetFarmPlayerMarkerStyle(s)
    local markerSize = GetFarmPlayerMarkerSize(s)
    local showDot = addon.isFarmMode and s.farmShowPlayerDot == true and style == "DOT"
    local radius = markerSize / 2
    local lineCount = #(f.playerDotSegments or {})
    local activeBars = math.max(6, math.min(lineCount, math.floor(markerSize + 0.5)))
    local barHeight = math.max(1, (markerSize / activeBars) + 0.5)

    for index, seg in ipairs(f.playerDotSegments or {}) do
        if showDot and index <= activeBars then
            local y = -radius + ((index - 0.5) * (markerSize / activeBars))
            local chord = 2 * math.sqrt(math.max(0, (radius * radius) - (y * y)))
            seg:ClearAllPoints()
            if seg.SetDrawLayer then seg:SetDrawLayer("OVERLAY", 7) end
            seg:SetSize(math.max(1, chord), barHeight)
            seg:SetPoint("CENTER", f, "CENTER", 0, y)
            seg:SetColorTexture(1, 1, 1, 1)
            if seg.SetRotation then seg:SetRotation(0) end
            seg:Show()
        else
            seg:Hide()
        end
    end
end

function addon.MapFrame:UpdateFarmPlayerMarker(facing, settings)
    local f = self.farmFrame
    if not f or not f.playerArrow then return end
    local s = settings or EnsurePathmakerSettings()
    local style = GetFarmPlayerMarkerStyle(s)
    local markerSize = GetFarmPlayerMarkerSize(s)
    local showMarker = addon.isFarmMode and s.farmShowPlayerDot == true
    local arrowTextures = { f.playerArrowShadow, f.playerArrowGlow, f.playerArrowTrim, f.playerArrow }

    local function HideArrowTextures()
        for _, tex in ipairs(arrowTextures) do
            if tex then tex:Hide() end
        end
    end

    local function LayoutArrowTexture(texture, width, height, offsetX, offsetY, rotation)
        if not texture then return end
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", f, "CENTER", offsetX or 0, offsetY or 0)
        texture:SetSize(width, height or width)
        SetTextureRotation(texture, rotation)
        texture:Show()
    end

    self:UpdateFarmDotMarker(s)

    if addon.isFarmMode then
        SetNativeFarmPlayerArrowVisible(false)
        if f.playerDotFill then f.playerDotFill:Hide() end
        HideArrowTextures()
        if not showMarker then return end

        if style == "DOT" then
            return
        end

        local markerRotation = (facing or 0) + GetFarmViewRotation()
        f.playerArrow:SetTexCoord(0, 1, 0, 1)
        if style == "NATIVE_ARROW" then
            f.playerArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
            f.playerArrow:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            f.playerArrow:SetVertexColor(1, 1, 1, 1)
            LayoutArrowTexture(f.playerArrow, markerSize, markerSize, 0, 0, markerRotation)
        else
            local routeColor = GetSelectedRouteColor()
            local arrowHeight = markerSize
            local arrowWidth = math.max(2, arrowHeight * (42 / 98))
            local shadowOffset = math.max(1, arrowHeight * 0.035)
            local highlightInset = math.max(1, arrowHeight * 0.04)

            if f.playerArrowShadow then
                f.playerArrowShadow:SetTexture(FARM_PLAYER_ARROW_TEXTURE)
                f.playerArrowShadow:SetTexCoord(0, 1, 0, 1)
                f.playerArrowShadow:SetVertexColor(0, 0, 0, 0.7)
                LayoutArrowTexture(f.playerArrowShadow, arrowWidth, arrowHeight, shadowOffset, -shadowOffset, markerRotation)
            end

            if f.playerArrowTrim then
                f.playerArrowTrim:SetTexture(FARM_PLAYER_ARROW_TEXTURE)
                f.playerArrowTrim:SetTexCoord(0, 1, 0, 1)
                f.playerArrowTrim:SetVertexColor(0.08, 0.08, 0.08, 0.95)
                LayoutArrowTexture(f.playerArrowTrim, arrowWidth, arrowHeight, 0, 0, markerRotation)
            end

            f.playerArrow:SetTexture(FARM_PLAYER_ARROW_TEXTURE)
            f.playerArrow:SetTexCoord(0, 1, 0, 1)
            f.playerArrow:SetVertexColor(routeColor[1] or FARM_GREEN[1], routeColor[2] or FARM_GREEN[2], routeColor[3] or FARM_GREEN[3], routeColor[4] or 1)
            LayoutArrowTexture(f.playerArrow, arrowWidth, arrowHeight, 0, 0, markerRotation)

            if f.playerArrowGlow then
                f.playerArrowGlow:SetTexture(FARM_PLAYER_ARROW_TEXTURE)
                f.playerArrowGlow:SetTexCoord(0, 1, 0, 1)
                f.playerArrowGlow:SetBlendMode("ADD")
                f.playerArrowGlow:SetVertexColor(1, 1, 1, 0.05)
                LayoutArrowTexture(f.playerArrowGlow, math.max(1, arrowWidth - highlightInset), math.max(1, arrowHeight - highlightInset), -highlightInset * 0.25, highlightInset * 0.25, markerRotation)
            end
        end
        return
    end

    if f.playerDotFill then f.playerDotFill:Hide() end
    HideArrowTextures()
end

function addon.MapFrame:UpdateFarmVisuals(settings)
    local f = self.farmFrame
    if not f then return end
    local s = settings or EnsurePathmakerSettings()
    ApplyFarmRotationSetting(s)

    self:UpdateFarmCircleLayout(s)

    if f.coordText then
        if s.farmShowCoords then f.coordText:Show() else f.coordText:Hide() end
    end

    if f.playerArrow then
        if f.playerArrow.EnableMouse then f.playerArrow:EnableMouse(false) end
        self:UpdateFarmPlayerMarker((f and f.pmSmoothFacing) or GetPlayerFacing() or 0, s)
    end

    if Minimap and addon.isFarmMode then
        RestoreNativeMinimapToFarmFrame(f, s)
        if Minimap.pmFarmSizeChanged then
            Minimap.pmFarmSizeChanged = nil
            RequestFarmMinimapTextureRefresh(f)
        end
        self:SetFarmMouseMode(s)
        local now = GetTime and GetTime() or 0
        local updateNodes = true
        if f.lastFarmNodeVisualUpdate and (now - f.lastFarmNodeVisualUpdate) < 0.18 then
            updateNodes = false
        else
            f.lastFarmNodeVisualUpdate = now
        end
        self:RefreshFarmOverlays(s, true, updateNodes)
    end
end

function addon.MapFrame:IsFarmRoutePointAllowed(point, mapID)
    local s = EnsurePathmakerSettings()
    if not addon.isFarmMode then return true end
    if not point then return false end

    local currentMapID = mapID or C_Map.GetBestMapForUnit("player")
    if not currentMapID then return true end
    local pos = C_Map.GetPlayerMapPosition(currentMapID, "player")
    if not pos then return true end

    local uiScaleX, uiScaleY = GetMapCoordinateScales(currentMapID)
    local dx = ((point.x or 0) - pos.x) * uiScaleX
    local dy = ((point.y or 0) - pos.y) * uiScaleY
    local visibleRadius = GetFarmVisibleRadiusYards() * (s.farmAllowRoutesBeyondCircle and 2.5 or 1)
    return ((dx * dx) + (dy * dy)) <= (visibleRadius * visibleRadius)
end

function addon.MapFrame:IsFarmScreenPointInsideCircle(screenX, screenY)
    local f = self.farmFrame
    if not addon.isFarmMode or not f then return true end
    local s = EnsurePathmakerSettings()
    if not screenX or not screenY then return true end

    local cx, cy = f:GetCenter()
    if not cx or not cy then return true end
    local scale = f:GetEffectiveScale() or 1
    local radius = GetFarmMaxDrawRadius(s) * scale
    local dx = screenX - cx
    local dy = screenY - cy
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function GetFarmRenderPlayerPosition(mapID, rawPos, advanceSample, frameElapsed)
    local f = addon.MapFrame and addon.MapFrame.farmFrame
    if not f or not mapID or not rawPos then return rawPos end

    -- Some caves keep the outdoor UiMapID while switching to a different
    -- coordinate context. Include that context in the smoothing identity so
    -- the overlay snaps cleanly at the boundary instead of sliding there.
    local indoors = IsIndoors and IsIndoors() or false
    local subZone = indoors and GetSubZoneText and GetSubZoneText() or ""
    local renderContext = indoors and ("indoor:" .. (subZone ~= "" and subZone or "indoor")) or "outdoor"

    -- Retail's native minimap uses the current position. Applying a second
    -- motion filter makes pins trail the terrain, then jump when a sample is
    -- unchanged. The shared stable sample already rejects stationary noise.
    if addon.Compat and addon.Compat.isRetail then
        if advanceSample or f.pmSmoothMapID ~= mapID
            or f.pmSmoothContext ~= renderContext or not f.pmSmoothPlayerPos
        then
            local facing = GetPlayerFacing and GetPlayerFacing() or 0
            local settings = EnsurePathmakerSettings()
            f.pmFarmRenderChanged = f.pmSmoothMapID ~= mapID
                or f.pmSmoothContext ~= renderContext
                or f.pmSmoothPlayerX ~= rawPos.x or f.pmSmoothPlayerY ~= rawPos.y
                or (settings.farmRotateMinimap == true and f.pmSmoothFacing ~= facing)
            f.pmSmoothMapID, f.pmSmoothContext = mapID, renderContext
            f.pmSmoothPlayerX, f.pmSmoothPlayerY = rawPos.x, rawPos.y
            f.pmSmoothFacing = facing
            f.pmSmoothPlayerPos = f.pmSmoothPlayerPos or {}
            f.pmSmoothPlayerPos.x, f.pmSmoothPlayerPos.y = rawPos.x, rawPos.y
        end
        return f.pmSmoothPlayerPos
    end

    local oldSmoothX, oldSmoothY = f.pmSmoothPlayerX, f.pmSmoothPlayerY
    local oldSmoothFacing = f.pmSmoothFacing
    local reset = f.pmSmoothMapID ~= mapID or f.pmSmoothContext ~= renderContext
        or not f.pmSmoothPlayerX or not f.pmSmoothPlayerY
    if reset then
        f.pmSmoothMapID = mapID
        f.pmSmoothContext = renderContext
        f.pmSmoothPlayerX = rawPos.x
        f.pmSmoothPlayerY = rawPos.y
        f.pmSmoothFacing = GetPlayerFacing and GetPlayerFacing() or 0
    elseif advanceSample then
        -- Classic's map position arrives in coarser steps than Retail's. Only
        -- advance this filter from the Farm frame's OnUpdate; route and node
        -- consumers in the same frame must all read the identical cached value.
        local elapsed = math.max(0, math.min(tonumber(frameElapsed) or 0, 0.05))
        local dx = rawPos.x - f.pmSmoothPlayerX
        local dy = rawPos.y - f.pmSmoothPlayerY
        local jump = ((dx * dx) + (dy * dy)) > 0.0004
        if jump then
            f.pmSmoothPlayerX = rawPos.x
            f.pmSmoothPlayerY = rawPos.y
        else
            local settings = EnsurePathmakerSettings()
            local size = math.max(160, math.min(900, settings.farmCircleSize or 420))
            local pixelsPerYard = ((size / 2) - 10) / GetFarmVisibleRadiusYards()
            local scaleX, scaleY = GetMapCoordinateScales(mapID)
            local screenDX = dx * scaleX * pixelsPerYard
            local screenDY = dy * scaleY * pixelsPerYard
            local screenDistance = math.sqrt((screenDX * screenDX) + (screenDY * screenDY))
            local unitSpeed = GetUnitSpeed and GetUnitSpeed("player")
            -- Forever can return a secret number: type() alone does not make
            -- it comparable. Unknown speed keeps coordinate-based smoothing.
            local moving = not addon.Compat:IsFiniteNumber(unitSpeed) or unitSpeed > 0.1
            local movementThreshold = moving and 0.01 or 0.35
            if screenDistance > movementThreshold then
                f.pmSmoothPlayerX = SmoothFarmValue(f.pmSmoothPlayerX, rawPos.x, elapsed, 24)
                f.pmSmoothPlayerY = SmoothFarmValue(f.pmSmoothPlayerY, rawPos.y, elapsed, 24)
            end
        end
    end

    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    if reset or advanceSample then
        local elapsed = reset and 0 or math.max(0, math.min(tonumber(frameElapsed) or 0, 0.05))
        local settings = EnsurePathmakerSettings()
        if settings.farmRotateMinimap == true then
            f.pmSmoothFacing = facing
        else
            f.pmSmoothFacing = SmoothFarmAngle(f.pmSmoothFacing, facing, elapsed, 28)
        end
    end
    if reset then
        f.pmFarmRenderChanged = true
    elseif advanceSample then
        local moved = math.abs((f.pmSmoothPlayerX or 0) - (oldSmoothX or 0)) > 0.0000001
            or math.abs((f.pmSmoothPlayerY or 0) - (oldSmoothY or 0)) > 0.0000001
        local settings = EnsurePathmakerSettings()
        local turned = settings.farmRotateMinimap == true and oldSmoothFacing ~= nil
            and math.abs(math.atan2(
                math.sin((f.pmSmoothFacing or 0) - oldSmoothFacing),
                math.cos((f.pmSmoothFacing or 0) - oldSmoothFacing))) > 0.0001
        f.pmFarmRenderChanged = moved or turned
    end
    f.pmSmoothPlayerPos = f.pmSmoothPlayerPos or {}
    f.pmSmoothPlayerPos.x = f.pmSmoothPlayerX
    f.pmSmoothPlayerPos.y = f.pmSmoothPlayerY
    return f.pmSmoothPlayerPos
end

local stableFarmPositionState = {}

-- Follow the current zone's node map, then use world-position movement to
-- reject stationary city/cave coordinate drift.
-- This path is shared by Retail, Classic Era, and TBC Anniversary.
local function GetFarmDisplayMapAndPosition(advanceSample, frameElapsed)
    local f = addon.MapFrame and addon.MapFrame.farmFrame
    local playerMapID = C_Map.GetBestMapForUnit("player")
    local routeMapID
    if addon.selectedRouteGUID and addon.Routes and addon.Routes.GetRouteMapID then
        routeMapID = addon.Routes:GetRouteMapID(addon.selectedRouteGUID, addon.selectedRouteMapID)
    end
    local nodeMapID
    if addon.Heatmap and addon.Heatmap.ResolveNodeDisplayMap then
        nodeMapID = addon.Heatmap:ResolveNodeDisplayMap(playerMapID)
    end
    -- A selected route must not pin the node overlay to a zone we have left.
    -- Only retain its coordinate space if it is the current map or an ancestor.
    local routeBelongsToArea = false
    local ancestor = playerMapID
    for _ = 1, 8 do
        if not ancestor or ancestor == 0 then break end
        if ancestor == routeMapID then routeBelongsToArea = true break end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(ancestor)
        ancestor = info and info.parentMapID
    end
    local mapID = nodeMapID or playerMapID
    local nodeSource = mapID and PathmakerDB and PathmakerDB.nodes and PathmakerDB.nodes[mapID]
    if routeBelongsToArea and (not nodeSource or #nodeSource == 0) then mapID = routeMapID end
    if not mapID then return nil, nil, false end

    local rawPos, moving
    if addon.Compat and addon.Compat.GetStableUnitMapPosition then
        rawPos, moving = addon.Compat:GetStableUnitMapPosition(mapID, "player", stableFarmPositionState)
    elseif addon.Compat and addon.Compat.GetUnitMapPosition then
        rawPos, moving = addon.Compat:GetUnitMapPosition(mapID, "player"), true
    else
        rawPos, moving = C_Map.GetPlayerMapPosition(mapID, "player"), true
    end

    if mapID == routeMapID and not rawPos then
        mapID = playerMapID
        if not mapID then return nil, nil, false end
        if addon.Compat and addon.Compat.GetStableUnitMapPosition then
            rawPos, moving = addon.Compat:GetStableUnitMapPosition(mapID, "player", stableFarmPositionState)
        else
            rawPos, moving = C_Map.GetPlayerMapPosition(mapID, "player"), true
        end
    end

    if f then
        f.pmFarmRenderMapID = mapID
        f.pmFarmViewRadiusOverride = nil
    end
    if not rawPos then return mapID, nil, false end

    -- Every consumer reads the same render sample. An unchanged world sample
    -- between movement updates must not reset an in-progress Classic filter.
    return mapID, GetFarmRenderPlayerPosition(mapID, rawPos, advanceSample, frameElapsed), moving

end

local function SnapFarmPixel(value, frame)
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

function addon.MapFrame:GetFarmPointOffset(point, playerPos, settings, snapToPixel, rotationOverride)
    local s = settings or EnsurePathmakerSettings()
    local size = math.max(160, math.min(900, s.farmCircleSize or 420))
    local radius = (size / 2) - 10
    local maxDrawRadius = GetFarmMaxDrawRadius(s)
    local renderMapID = addon.MapFrame and addon.MapFrame.farmFrame
        and addon.MapFrame.farmFrame.pmFarmRenderMapID
    local uiScaleX, uiScaleY = GetMapCoordinateScales(renderMapID)
    local pixelsPerYard = radius / GetFarmVisibleRadiusYards()
    local dx = ((point.x or 0) - playerPos.x) * uiScaleX * pixelsPerYard
    local dy = -((point.y or 0) - playerPos.y) * uiScaleY * pixelsPerYard
    local rotation = rotationOverride
    if rotation == nil then rotation = GetFarmViewRotation() end
    local outX = (dx * math.cos(rotation)) - (dy * math.sin(rotation))
    local outY = (dx * math.sin(rotation)) + (dy * math.cos(rotation))
    if snapToPixel == false then
        return outX, outY, radius, maxDrawRadius
    end
    local snapFrame = addon.MapFrame and addon.MapFrame.farmFrame
    return SnapFarmPixel(outX, snapFrame), SnapFarmPixel(outY, snapFrame), radius, maxDrawRadius
end

local function ClipLineToCircle(x1, y1, x2, y2, radius)
    local dx, dy = x2 - x1, y2 - y1
    local a = dx * dx + dy * dy
    local b = 2 * (x1 * dx + y1 * dy)
    local c = (x1 * x1 + y1 * y1) - (radius * radius)

    if a == 0 then
        return nil
    end

    local disc = (b * b) - (4 * a * c)
    local t1, t2 = 0, 1

    if c > 0 and (x2 * x2 + y2 * y2) > (radius * radius) and disc < 0 then
        return nil
    end

    if disc >= 0 then
        local root = math.sqrt(disc)
        local enter = (-b - root) / (2 * a)
        local exit = (-b + root) / (2 * a)
        if c > 0 then t1 = math.max(t1, enter) end
        if (x2 * x2 + y2 * y2) > (radius * radius) then t2 = math.min(t2, exit) end
        if c <= 0 then t2 = math.min(t2, exit) end
    end

    if t2 < t1 or t2 < 0 or t1 > 1 then return nil end
    t1 = math.max(0, math.min(1, t1))
    t2 = math.max(0, math.min(1, t2))
    return x1 + dx * t1, y1 + dy * t1, x1 + dx * t2, y1 + dy * t2
end

function addon.MapFrame:ClipNativeMinimapLine(x1, y1, x2, y2, radius)
    return ClipLineToCircle(x1, y1, x2, y2, radius)
end

function addon.MapFrame:AcquireFarmRouteLine(index)
    local f = self.farmFrame
    if not f then return nil end
    f.routeLines = f.routeLines or {}
    if not f.routeLines[index] then
        local line
        -- Native Line regions keep their endpoints stable while moving and do
        -- not resample a thin rectangular texture on every rotation. The old
        -- rotated-texture path could shimmer or briefly disappear at certain
        -- angles as Farm Mode updated it every frame.
        if f.CreateLine then
            line = f:CreateLine(nil, "OVERLAY", nil, 5)
            line.pmFarmNativeLine = true
        else
            line = f:CreateTexture(nil, "OVERLAY", nil, 5)
            line:SetTexture("Interface\\Buttons\\WHITE8x8")
        end
        -- Farm lines move by fractional screen pixels. Pixel-grid snapping
        -- makes Classic alternate their endpoints between adjacent pixels,
        -- which presents as a route segment jittering or flashing.
        if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
        if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
        f.routeLines[index] = line
    end
    return f.routeLines[index]
end

local function PositionFarmRouteLine(f, line, x1, y1, x2, y2, thickness)
    local dx, dy = x2 - x1, y2 - y1
    local length = math.sqrt((dx * dx) + (dy * dy))
    if length < 1 then
        line:Hide()
        return false
    end

    thickness = thickness or 3
    if line.pmFarmNativeLine then
        if line.pmFarmThickness ~= thickness then
            line:SetThickness(thickness)
            line.pmFarmThickness = thickness
        end
        line:SetStartPoint("CENTER", f, x1, y1)
        line:SetEndPoint("CENTER", f, x2, y2)
    else
        line:ClearAllPoints()
        line:SetSize(math.max(1, length), thickness)
        line:SetPoint("CENTER", f, "CENTER", (x1 + x2) / 2, (y1 + y2) / 2)
        SetTextureRotation(line, math.atan2(dy, dx))
    end
    line:Show()
    return true
end

function addon.MapFrame:UpdateFarmRoute(settings)
    local f = self.farmFrame
    if not f then return end
    local s = settings or EnsurePathmakerSettings()
    local mapID, pos = GetFarmDisplayMapAndPosition(false)
    local mapRoutes = mapID and PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[mapID]
    local route = mapRoutes and addon.selectedRouteGUID and mapRoutes[addon.selectedRouteGUID]
    local previousLineCount = f.activeFarmRouteLineCount or #(f.routeLines or {})

    f.pmFarmRouteMapID = mapID
    f.pmFarmRoutePlayerX = pos and pos.x or nil
    f.pmFarmRoutePlayerY = pos and pos.y or nil
    f.pmFarmRouteGUID = addon.selectedRouteGUID
    f.pmFarmRouteSource = mapRoutes
    f.pmFarmRouteGhostView = addon.drawConfig and addon.drawConfig.ghostView == true
    f.pmFarmRouteDirty = false

    if not pos then
        for i = 1, previousLineCount do
            local line = f.routeLines and f.routeLines[i]
            if line then line:Hide() end
        end
        f.activeFarmRouteLineCount = 0
        return
    end

    local color = (route and route.color) or {0.8, 1, 0.1, 1}
    local alpha = math.max(0, math.min(1, tonumber(s.activeRouteAlpha) or 1))
    local clipRadius = GetFarmMaxDrawRadius(s)
    local lineIndex = 0
    local renderRotation = GetFarmViewRotation()

    local function DrawSegment(p1, p2, segmentColor, segmentAlpha, segmentWidth)
        if not p1 or not p2 or p1.isGap then return end
        local x1, y1 = self:GetFarmPointOffset(p1, pos, s, false, renderRotation)
        local x2, y2 = self:GetFarmPointOffset(p2, pos, s, false, renderRotation)

        local cx1, cy1, cx2, cy2 = ClipLineToCircle(x1, y1, x2, y2, clipRadius)
        if not cx1 then return end
        x1, y1, x2, y2 = cx1, cy1, cx2, cy2

        local dx, dy = x2 - x1, y2 - y1
        local length = math.sqrt((dx * dx) + (dy * dy))
        if length < 1 then return end

        lineIndex = lineIndex + 1
        local line = self:AcquireFarmRouteLine(lineIndex)
        if not line then return end
        line.pmFarmPoint1 = p1
        line.pmFarmPoint2 = p2
        line.pmFarmSegmentWidth = segmentWidth or 3
        PositionFarmRouteLine(f, line, x1, y1, x2, y2, line.pmFarmSegmentWidth)

        local red = segmentColor[1] or 0.8
        local green = segmentColor[2] or 1
        local blue = segmentColor[3] or 0.1
        local drawAlpha = segmentAlpha or alpha
        if line.pmFarmRed ~= red or line.pmFarmGreen ~= green or line.pmFarmBlue ~= blue or line.pmFarmAlpha ~= drawAlpha then
            line:SetColorTexture(red, green, blue, drawAlpha)
            line.pmFarmRed, line.pmFarmGreen, line.pmFarmBlue, line.pmFarmAlpha = red, green, blue, drawAlpha
        end
        if not line:IsShown() then line:Show() end
    end

    local function DrawRoute(routeData, segmentColor, segmentAlpha, segmentWidth)
        if not routeData or not routeData.points or #routeData.points < 2 then return end
        for i = 1, #routeData.points - 1 do
            DrawSegment(routeData.points[i], routeData.points[i + 1], segmentColor, segmentAlpha, segmentWidth)
        end
        if routeData.connectPaths then
            DrawSegment(routeData.points[#routeData.points], routeData.points[1], segmentColor, segmentAlpha, segmentWidth)
        end
    end

    if addon.drawConfig and addon.drawConfig.ghostView and mapRoutes then
        for guid, routeData in pairs(mapRoutes) do
            if guid ~= addon.selectedRouteGUID then
                DrawRoute(routeData, routeData.color or {0.55, 0.75, 1, 1}, 0.35, 2)
            end
        end
    end

    if route then
        DrawRoute(route, color, alpha, 3)
    end

    for i = lineIndex + 1, previousLineCount do
        local line = f.routeLines and f.routeLines[i]
        if line then
            line.pmFarmPoint1 = nil
            line.pmFarmPoint2 = nil
            line:Hide()
        end
    end
    f.activeFarmRouteLineCount = lineIndex
end

function addon.MapFrame:UpdateFarmRoutePositions(settings)
    local f = self.farmFrame
    if not f then return end
    local s = settings or EnsurePathmakerSettings()
    local mapID, pos = GetFarmDisplayMapAndPosition(false)
    if not pos or f.pmFarmRouteMapID ~= mapID then return end

    local clipRadius = GetFarmMaxDrawRadius(s)
    local renderRotation = GetFarmViewRotation()
    for i = 1, (f.activeFarmRouteLineCount or 0) do
        local line = f.routeLines and f.routeLines[i]
        local p1, p2 = line and line.pmFarmPoint1, line and line.pmFarmPoint2
        if line and p1 and p2 and not p1.isGap then
            local x1, y1 = self:GetFarmPointOffset(p1, pos, s, false, renderRotation)
            local x2, y2 = self:GetFarmPointOffset(p2, pos, s, false, renderRotation)
            local cx1, cy1, cx2, cy2 = ClipLineToCircle(x1, y1, x2, y2, clipRadius)
            if cx1 then
                PositionFarmRouteLine(f, line, cx1, cy1, cx2, cy2, line.pmFarmSegmentWidth)
            else
                line:Hide()
            end
        elseif line then
            line:Hide()
        end
    end
end

function addon.MapFrame:AcquireFarmNodeButton(index)
    local f = self.farmFrame
    if not f then return nil end
    f.nodeButtons = f.nodeButtons or {}
    if not f.nodeButtons[index] then
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
        btn:SetFrameLevel(f:GetFrameLevel() + 8)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints()
        btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.ring = btn:CreateTexture(nil, "OVERLAY")
        btn.ring:SetPoint("CENTER")
        btn.ring:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
        btn.ring:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        btn.ring:SetBlendMode("ADD")
        for _, texture in ipairs({ btn.icon, btn.ring }) do
            if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
            if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
        end
        btn.ring:Hide()
        SetFarmNodeButtonMouseEnabled(btn)
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        f.nodeButtons[index] = btn
    end
    f.nodeButtons[index]:SetScript("OnEnter", nil)
    f.nodeButtons[index]:SetScript("OnLeave", nil)
    f.nodeButtons[index]:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
    f.nodeButtons[index]:SetFrameLevel(f:GetFrameLevel() + 8 + index)
    if f.nodeButtons[index].icon then
        f.nodeButtons[index].icon:ClearAllPoints()
        f.nodeButtons[index].icon:SetAllPoints()
        f.nodeButtons[index].icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if f.nodeButtons[index].ring then
        f.nodeButtons[index].ring:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
    end
    SetFarmNodeButtonMouseEnabled(f.nodeButtons[index])
    return f.nodeButtons[index]
end

local function IsFarmNodeInsideRingRange(frame, node, distYards)
    frame.pmFarmNodeCloseState = frame.pmFarmNodeCloseState or setmetatable({}, { __mode = "k" })
    local hysteresis = 3
    local threshold = FARM_NODE_RING_RANGE_YARDS
    local isClose = distYards < (threshold + (frame.pmFarmNodeCloseState[node] and hysteresis or 0))
    frame.pmFarmNodeCloseState[node] = isClose
    return isClose
end

local function IsFarmNodeInsideDrawRange(frame, node, x, y, maxDrawRadius)
    frame.pmFarmNodeRangeState = frame.pmFarmNodeRangeState or setmetatable({}, { __mode = "k" })
    local wasInside = frame.pmFarmNodeRangeState[node] == true
    local threshold = math.max(0, maxDrawRadius + (wasInside and 2 or -2))
    local inside = ((x * x) + (y * y)) <= (threshold * threshold)
    frame.pmFarmNodeRangeState[node] = inside
    return inside
end

local function PositionFarmNodeButton(button, frame, x, y)
    if not button or not frame then return end
    -- Preserve fractional motion so icons and rings move with the terrain;
    -- rounding each axis separately makes diagonal travel visibly stair-step.
    local drawX, drawY = x, y
    if button.pmFarmDrawX == drawX and button.pmFarmDrawY == drawY then return end
    button.pmFarmDrawX = drawX
    button.pmFarmDrawY = drawY
    button:ClearAllPoints()
    button:SetPoint("CENTER", frame, "CENTER", drawX, drawY)
end

function addon.MapFrame:UpdateFarmNodes(settings)
    local f = self.farmFrame
    if not f then return end
    local s = settings or EnsurePathmakerSettings()
    local mapID, pos = GetFarmDisplayMapAndPosition(false)
    local renderRotation = GetFarmViewRotation()
    local previousNodeCount = f.activeFarmNodeCount or #(f.nodeButtons or {})
    local source = mapID and PathmakerDB and PathmakerDB.nodes and PathmakerDB.nodes[mapID]

    f.pmFarmNodesMapID = mapID
    f.pmFarmNodesSource = source
    f.pmFarmNodesSourceCount = source and #source or 0
    f.pmFarmNodesGeneration = addon.Heatmap and addon.Heatmap.GetVisibleNodeCacheGeneration
        and addon.Heatmap:GetVisibleNodeCacheGeneration() or 0
    f.pmFarmNodesPlayerX = pos and pos.x or nil
    f.pmFarmNodesPlayerY = pos and pos.y or nil
    f.pmFarmNodesDirty = false

    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local instanceBlocked = addon.Heatmap and addon.Heatmap.IsNodeDisplayBlockedByInstance
        and addon.Heatmap:IsNodeDisplayBlockedByInstance(playerMapID)
    if instanceBlocked or not mapID or not pos or not PathmakerDB or not PathmakerDB.nodes or not PathmakerDB.nodes[mapID]
        or (addon.Compat and not addon.Compat:IsMapExpansionVisible(mapID))
    then
        for i = 1, previousNodeCount do
            local btn = f.nodeButtons and f.nodeButtons[i]
            if btn then btn:Hide() end
        end
        f.activeFarmNodeCount = 0
        return
    end

    local visibleNodes = addon.Heatmap and addon.Heatmap.GetVisibleNodesForMap
        and addon.Heatmap:GetVisibleNodesForMap(mapID) or PathmakerDB.nodes[mapID]
    local exactClusterLayout = addon.Heatmap and addon.Heatmap.BuildExactNodeClusterLayout
        and addon.Heatmap:BuildExactNodeClusterLayout(visibleNodes, mapID) or {}
    local index = 0
    for _, node in ipairs(visibleNodes) do
        if node.x and node.y then
            do
                local x, y, radius, maxDrawRadius = self:GetFarmPointOffset(node, pos, s, false, renderRotation)
                local insideDrawRange = IsFarmNodeInsideDrawRange(f, node, x, y, maxDrawRadius)
                if insideDrawRange then
                    index = index + 1
                    local btn = self:AcquireFarmNodeButton(index)
                    if btn then
                        btn.nodeData = node
                        btn.pmNodeMapID = mapID
                        btn.pmExactNodeCluster = exactClusterLayout[node]
                        local clusterOffsetX, clusterOffsetY = 0, 0
                        if addon.Heatmap and addon.Heatmap.GetExactNodeClusterOffset then
                            clusterOffsetX, clusterOffsetY = addon.Heatmap:GetExactNodeClusterOffset(
                                btn.pmExactNodeCluster, FARM_NODE_ICON_SIZE * 0.75)
                        end
                        btn.pmFarmClusterOffsetX = clusterOffsetX
                        btn.pmFarmClusterOffsetY = clusterOffsetY
                        local texture = addon.Heatmap and addon.Heatmap.ResolveNodeIcon and addon.Heatmap.ResolveNodeIcon(node)
                        if not texture then
                            texture = (node.type == "Mining" and "Interface\\Icons\\Trade_Mining")
                                or (node.type == "Treasure" and "Interface\\AddOns\\PathMaker_Nodes\\Artwork\\Treasure\\treasure.tga")
                                or "Interface\\Icons\\Trade_Herbalism"
                        end
                        btn.icon:SetTexture(texture)
                        local uiScaleX, uiScaleY = GetMapCoordinateScales(mapID)
                        local yardsX = (node.x - pos.x) * uiScaleX
                        local yardsY = (node.y - pos.y) * uiScaleY
                        local distYards = math.sqrt((yardsX * yardsX) + (yardsY * yardsY))
                        local isCloseNode = IsFarmNodeInsideRingRange(f, node, distYards)
                        btn.pmFarmWasCloseNode = isCloseNode
                        local hideCloseNode = isCloseNode and s.farmHideCircle == true

                        if hideCloseNode then
                            btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                            btn.icon:Hide()
                            if btn.ring then btn.ring:Hide() end
                        elseif isCloseNode then
                            btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                            btn.icon:Hide()
                            if btn.ring then
                                btn.ring:Show()
                                btn.ring:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                                if node.type == "Mining" then btn.ring:SetVertexColor(1, 0.5, 0, 1)
                                else btn.ring:SetVertexColor(0, 1, 0, 1) end
                            end
                        else
                            btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                            btn.icon:Show()
                            if btn.ring then btn.ring:Hide() end
                        end

                        PositionFarmNodeButton(btn, f,
                            x + clusterOffsetX, y + clusterOffsetY)
                        btn:SetAlpha(1)
                        SetFarmNodeButtonMouseEnabled(btn)
                        if hideCloseNode then btn:Hide() else btn:Show() end
                    end
                end
            end
        end
    end

    for i = index + 1, previousNodeCount do
        local btn = f.nodeButtons and f.nodeButtons[i]
        if btn then btn:Hide() end
    end
    f.activeFarmNodeCount = index
end

function addon.MapFrame:UpdateFarmNodePositions(settings)
    local f = self.farmFrame
    if not f then return end

    local s = settings or EnsurePathmakerSettings()
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if addon.Heatmap and addon.Heatmap.IsNodeDisplayBlockedByInstance
        and addon.Heatmap:IsNodeDisplayBlockedByInstance(playerMapID)
    then
        local nodeCount = f.activeFarmNodeCount or #(f.nodeButtons or {})
        for i = 1, nodeCount do
            local btn = f.nodeButtons and f.nodeButtons[i]
            if btn then btn:Hide() end
        end
        f.activeFarmNodeCount = 0
        return
    end
    local mapID, pos = GetFarmDisplayMapAndPosition(false)
    if not pos then return end
    -- Keep the last completed node frame during a map handoff. The rebuild pass
    -- replaces it atomically once the new coordinate space is ready.
    if f.pmFarmNodesMapID ~= mapID then return end
    local renderRotation = GetFarmViewRotation()

    local uiScaleX, uiScaleY = GetMapCoordinateScales(mapID)

    local nodeCount = f.activeFarmNodeCount or #(f.nodeButtons or {})
    for i = 1, nodeCount do
        local btn = f.nodeButtons and f.nodeButtons[i]
        local node = btn and btn.nodeData
        if btn and btn.pmNodeMapID == mapID and node and node.x and node.y then
            local x, y, radius, maxDrawRadius = self:GetFarmPointOffset(node, pos, s, false, renderRotation)
            local insideDrawRange = IsFarmNodeInsideDrawRange(f, node, x, y, maxDrawRadius)

            if insideDrawRange then
                local yardsX = (node.x - pos.x) * uiScaleX
                local yardsY = (node.y - pos.y) * uiScaleY
                local distYards = math.sqrt((yardsX * yardsX) + (yardsY * yardsY))
                local isCloseNode = IsFarmNodeInsideRingRange(f, node, distYards)
                btn.pmFarmWasCloseNode = isCloseNode
                local hideCloseNode = isCloseNode and s.farmHideCircle == true

                if hideCloseNode then
                    btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                    if btn.icon then btn.icon:Hide() end
                    if btn.ring then btn.ring:Hide() end
                elseif isCloseNode then
                    btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                    if btn.icon then btn.icon:Hide() end
                    if btn.ring then
                        btn.ring:Show()
                        btn.ring:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                        if node.type == "Mining" then btn.ring:SetVertexColor(1, 0.5, 0, 1)
                        else btn.ring:SetVertexColor(0, 1, 0, 1) end
                    end
                else
                    btn:SetSize(FARM_NODE_ICON_SIZE, FARM_NODE_ICON_SIZE)
                    if btn.icon then btn.icon:Show() end
                    if btn.ring then btn.ring:Hide() end
                end

                PositionFarmNodeButton(btn, f,
                    x + (btn.pmFarmClusterOffsetX or 0),
                    y + (btn.pmFarmClusterOffsetY or 0))
                SetFarmNodeButtonMouseEnabled(btn)
                if hideCloseNode then btn:Hide() else btn:Show() end
            else
                btn:Hide()
            end
        end
    end

end

function addon.MapFrame:CreateFarmFrame()
    local f = CreateFrame("Frame", "PathmakerFarmFrame", UIParent)
    f:SetSize(420, 420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("LOW") 
    f:EnableMouse(false)
    f:Hide()
    
    f:SetScale(1)

    -- Dedicated native-minimap anchor. Opacity is applied directly to Minimap;
    -- Farm artwork stays on f at full alpha.
    local alphaHost = CreateFrame("Frame", nil, f)
    alphaHost:SetAllPoints(f)
    alphaHost:SetFrameStrata("LOW")
    alphaHost:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
    alphaHost:EnableMouse(false)
    f.pmMinimapAlphaHost = alphaHost

    f.circleSegments = {}
    for i = 1, 96 do
        local seg = f:CreateTexture(nil, "OVERLAY")
        seg:SetTexture("Interface\\Buttons\\WHITE8x8")
        f.circleSegments[i] = seg
    end

    f.tickSegments = {}
    for i = 1, 8 do
        local tick = f:CreateTexture(nil, "OVERLAY")
        tick:SetTexture("Interface\\Buttons\\WHITE8x8")
        f.tickSegments[i] = tick
    end

    f.compassLabels = {}
    for i, item in ipairs(FARM_COMPASS_DIRECTIONS) do
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetText(item.text)
        label:SetTextColor(FARM_GREEN[1], FARM_GREEN[2], FARM_GREEN[3], 1)
        label:SetFont(label:GetFont(), 18, "OUTLINE")
        label.baseAngle = item.angle
        f.compassLabels[i] = label
    end

    f.playerArrow = f:CreateTexture(nil, "OVERLAY")
    f.playerArrow:SetTexture(FARM_PLAYER_ARROW_TEXTURE)
    f.playerArrow:SetTexCoord(0, 1, 0, 1)
    f.playerArrow:SetVertexColor(0.7, 0.95, 0.25, 1)
    SetTextureRotation(f.playerArrow, 0)
    f.playerArrow:Hide()

    f.playerArrowShadow = f:CreateTexture(nil, "ARTWORK")
    f.playerArrowShadow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.playerArrowShadow:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    f.playerArrowShadow:SetVertexColor(0, 0, 0, 0.75)
    f.playerArrowShadow:Hide()

    f.playerArrowGlow = f:CreateTexture(nil, "ARTWORK")
    f.playerArrowGlow:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.playerArrowGlow:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    f.playerArrowGlow:SetBlendMode("ADD")
    f.playerArrowGlow:SetVertexColor(0.2, 1, 0.2, 0.35)
    f.playerArrowGlow:Hide()

    f.playerArrowTrim = f:CreateTexture(nil, "ARTWORK")
    f.playerArrowTrim:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.playerArrowTrim:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    f.playerArrowTrim:SetVertexColor(1, 0.78, 0.28, 1)
    f.playerArrowTrim:Hide()

    f.playerDotFill = f:CreateTexture(nil, "OVERLAY")
    f.playerDotFill:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.playerDotFill:SetSize(14, 14)
    f.playerDotFill:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.playerDotFill:SetVertexColor(0.92, 0.92, 0.92, 1)
    if f.playerDotFill.SetMask then
        f.playerDotFill:SetMask("Interface\\Minimap\\UI-Minimap-Background")
    end
    f.playerDotFill:Hide()

    f.playerDotSegments = {}
    for i = 1, 48 do
        local seg = f:CreateTexture(nil, "OVERLAY")
        seg:SetTexture("Interface\\Buttons\\WHITE8x8")
        seg:Hide()
        f.playerDotSegments[i] = seg
    end
    
    f.coordText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.coordText:SetText("")
    f.coordText:SetTextColor(1, 1, 1, 1)
    
    addon.Compat:SetGuardedUpdate(f, "Farm Mode", function(self, elapsed)
        if not addon.isFarmMode then return end
        elapsed = elapsed or 0
        local settings = (PathmakerDB and PathmakerDB.settings) or EnsurePathmakerSettings()

        -- Area changes and other minimap code can rewrite rotateMinimap. Keep
        -- the actual CVar matched to the Farm Mode checkbox in both directions.
        ApplyFarmRotationSetting(settings)

        -- Blizzard can rewrite minimap alpha/parent-alpha flags while changing
        -- outdoor, city, cave, dungeon, or raid map providers. Reassert the
        -- selected visible percentage only when that state has drifted.
        if Minimap then
            local desiredAlpha = NormalizeFarmAlphaValue(settings.farmAlpha, addon.farmAlpha or 0.6)
            local alphaHost = self.pmMinimapAlphaHost or self
            local providerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local providerChanged = self.pmFarmOpacityMapID ~= nil and self.pmFarmOpacityMapID ~= providerMapID
            self.pmFarmOpacityMapID = providerMapID
            if providerChanged then ForceMinimapTextureRefresh() end

            local frameAlpha = self.GetAlpha and self:GetAlpha() or 1
            local hostAlpha = alphaHost.GetAlpha and alphaHost:GetAlpha() or 1
            local mapAlpha = Minimap.GetAlpha and Minimap:GetAlpha() or desiredAlpha
            local ignoresParent = Minimap.GetIgnoreParentAlpha and Minimap:GetIgnoreParentAlpha()
            if Minimap:GetParent() ~= alphaHost or Minimap.pmFarmAnchor ~= alphaHost then
                RestoreNativeMinimapToFarmFrame(self, settings)
            elseif not Minimap.pmFarmAlphaPriming and (
                math.abs(frameAlpha - 1) > 0.001
                or math.abs(hostAlpha - 1) > 0.001
                or math.abs(mapAlpha - desiredAlpha) > 0.001
                or ignoresParent == false)
            then
                ApplyFarmMinimapAlpha(self, desiredAlpha)
            end
        end

        local mapID, rawPos = GetFarmDisplayMapAndPosition(true, elapsed)
        if self.pmFarmRenderChanged then self.pmFarmOverlayDirty = true end

        local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local nodeInstanceBlocked = addon.Heatmap and addon.Heatmap.IsNodeDisplayBlockedByInstance
            and addon.Heatmap:IsNodeDisplayBlockedByInstance(playerMapID) or false
        if self.pmFarmNodesInstanceBlocked ~= nodeInstanceBlocked then
            self.pmFarmNodesInstanceBlocked = nodeInstanceBlocked
            self.pmFarmNodesDirty = true
            self.pmFarmOverlayDirty = true
        end
        if nodeInstanceBlocked then
            -- Unlike an ordinary map handoff, an instance transition must clear
            -- inherited outdoor pins even while no player position is available.
            addon.MapFrame:UpdateFarmNodePositions(settings)
        end

        -- A zoom change alters the yards-to-pixels ratio even when the player
        -- has not moved. Rebuild at every supported zoom level.
        local viewRadius = GetFarmVisibleRadiusYards()
        local zoomLevel = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
        if self.pmFarmLastZoomLevel ~= zoomLevel
            or not self.pmFarmLastViewRadius
            or math.abs(self.pmFarmLastViewRadius - viewRadius) > 0.01
        then
            self.pmFarmLastZoomLevel = zoomLevel
            self.pmFarmLastViewRadius = viewRadius
            self.pmFarmOverlayDirty = true
            self.pmFarmRouteDirty = true
            self.pmFarmNodesDirty = true
        end

        self.coordUpdateTimer = (self.coordUpdateTimer or 0) + elapsed
        if self.coordUpdateTimer >= FARM_COORD_UPDATE_INTERVAL then
            self.coordUpdateTimer = 0
            if settings.farmShowCoords and mapID then
                if rawPos then
                    self.coordText:SetText(string.format("%.1f, %.1f", rawPos.x * 100, rawPos.y * 100))
                else
                    self.coordText:SetText("")
                end
            else
                self.coordText:SetText("")
            end
        end

        self.markerUpdateTimer = (self.markerUpdateTimer or 0) + elapsed
        if self.markerUpdateTimer >= FARM_MARKER_UPDATE_INTERVAL then
            self.markerUpdateTimer = 0
            local facing = self.pmSmoothFacing or GetPlayerFacing() or 0
            addon.MapFrame:UpdateFarmCompass(facing)
            addon.MapFrame:UpdateFarmPlayerMarker(facing, settings)
        end

        UpdateFarmGoldBlipMouseCapture()

        -- Keep the completed overlay only while its coordinate space is still
        -- current. Clear old-zone pins/lines during a new provider's load.
        if not rawPos then
            if self.pmFarmNodesMapID ~= mapID then addon.MapFrame:UpdateFarmNodes(settings) end
            if self.pmFarmRouteMapID ~= mapID then
                for _, line in ipairs(self.routeLines or {}) do line:Hide() end
                self.pmFarmRouteDirty = true
            end
            return
        end

        -- Smooth path and heatmap motion only touches the already-visible
        -- objects. Full route/node discovery remains distance-throttled below.
        if self.pmFarmOverlayDirty then
            self.pmFarmOverlayDirty = false
            addon.MapFrame:UpdateFarmRoutePositions(settings)
            addon.MapFrame:UpdateFarmNodePositions(settings)
        end

        self.nodeOverlayTimer = (self.nodeOverlayTimer or 0) + elapsed
        local source = mapID and PathmakerDB and PathmakerDB.nodes and PathmakerDB.nodes[mapID]
        local routeSource = mapID and PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[mapID]
        local generation = addon.Heatmap and addon.Heatmap.GetVisibleNodeCacheGeneration
            and addon.Heatmap:GetVisibleNodeCacheGeneration() or 0
        local rebuildNodes = self.pmFarmNodesDirty == true
            or self.pmFarmNodesMapID ~= mapID
            or self.pmFarmNodesSource ~= source
            or self.pmFarmNodesSourceCount ~= (source and #source or 0)
            or self.pmFarmNodesGeneration ~= generation
            or (rawPos ~= nil and self.pmFarmNodesPlayerX == nil)

        if not rebuildNodes and rawPos and self.pmFarmNodesPlayerX and self.pmFarmNodesPlayerY then
            local scaleX, scaleY = GetMapCoordinateScales(mapID)
            local dx = (rawPos.x - self.pmFarmNodesPlayerX) * scaleX
            local dy = (rawPos.y - self.pmFarmNodesPlayerY) * scaleY
            rebuildNodes = ((dx * dx) + (dy * dy)) >=
                (FARM_NODE_REBUILD_DISTANCE_YARDS * FARM_NODE_REBUILD_DISTANCE_YARDS)
        end

        local rebuildRoute = self.pmFarmRouteDirty == true
            or self.pmFarmRouteMapID ~= mapID
            or self.pmFarmRouteSource ~= routeSource
            or self.pmFarmRouteGUID ~= addon.selectedRouteGUID
            or self.pmFarmRouteGhostView ~= (addon.drawConfig and addon.drawConfig.ghostView == true)
            or (rawPos ~= nil and self.pmFarmRoutePlayerX == nil)
        if not rebuildRoute and rawPos and self.pmFarmRoutePlayerX and self.pmFarmRoutePlayerY then
            local scaleX, scaleY = GetMapCoordinateScales(mapID)
            local dx = (rawPos.x - self.pmFarmRoutePlayerX) * scaleX
            local dy = (rawPos.y - self.pmFarmRoutePlayerY) * scaleY
            rebuildRoute = ((dx * dx) + (dy * dy)) >=
                (FARM_NODE_REBUILD_DISTANCE_YARDS * FARM_NODE_REBUILD_DISTANCE_YARDS)
        end

        if rebuildRoute then addon.MapFrame:UpdateFarmRoute(settings) end

        if rebuildNodes then
            self.nodeOverlayTimer = 0
            addon.MapFrame:RefreshFarmOverlays(settings, false, true)
        elseif self.nodeOverlayTimer >= FARM_NODE_REBUILD_INTERVAL then
            -- Keep the timer bounded without rescanning an unchanged map while
            -- the player is stationary.
            self.nodeOverlayTimer = 0
        end
    end)

    local btnExit = CreateFrame("Button", nil, f, "BackdropTemplate")
    btnExit:SetSize(40, 16) 
    btnExit:EnableMouse(true)
    btnExit:RegisterForClicks("LeftButtonUp")
    
    btnExit:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btnExit:SetBackdropColor(0.2, 0.2, 0.2, 1) 
    btnExit:SetBackdropBorderColor(0, 0, 0, 1) 
    
    local txt = btnExit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER")
    txt:SetText("Exit")
    txt:SetTextColor(1, 1, 1, 1) 
    btnExit.text = txt
    f.btnExit = btnExit
    
    btnExit:SetScript("OnClick", function()
        addon.MapFrame:ToggleFarmMode()
    end)

    -- Relaxed background failsafe timer
    f:HookScript("OnUpdate", function(self, elapsed)
        addon.MapFrame.buttonLayoutTimer = (addon.MapFrame.buttonLayoutTimer or 0) + elapsed
        if addon.MapFrame.buttonLayoutTimer > FARM_BUTTON_LAYOUT_INTERVAL then
            addon.MapFrame.buttonLayoutTimer = 0
            addon.MapFrame:LayoutMinimapButtons()
        end
    end)

    self.farmFrame = f
    self:UpdateFarmVisuals(EnsurePathmakerSettings())
end

function addon.MapFrame:ToggleFarmMode()
    if InCombatLockdown and InCombatLockdown() then
        addon:PrintMessage("disableMsgError", "|cffffff00PathMaker:|r Change minimap modes after combat.")
        return
    end
    if addon.Routes and addon.Routes.isRecording then
        addon:PrintMessage("disableMsgError", "|cffff0000Pathmaker:|r Cannot enter Farm Mode while recording/editing.")
        return
    end

    local settings = EnsurePathmakerSettings()
    if not addon.isFarmMode then
        -- Farm Mode always borrows the native minimap render surface. Remember
        -- whether it must return directly to Blizzard's UI instead of briefly
        -- passing through the disabled PathMaker minimap on the way out.
        self.farmReturnToNativeMinimap = settings.usePathmakerMinimap == false
        self.farmControlsWereShown = self.controlsFrame and self.controlsFrame:IsShown() or false
        if not self.ownsMinimap then self:Enable(true) end
    end
    if self.controlsFrame then self.controlsFrame:Hide() end
    addon.isFarmMode = not addon.isFarmMode
    
    if addon.isFarmMode then
        if self.inputBlocker then self.inputBlocker:Hide() end
        
        self.frame:Hide()
        if self.managerFrame then self.managerFrame:Hide() end
        if self.tacticalFrame then self.tacticalFrame:Hide() end
        if self.timersFrame then self.timersFrame:Hide() end
        if self.nodeFilterFrame then self.nodeFilterFrame:Hide() end
        if addon.PaletteFrame then addon.PaletteFrame:Hide() end
        
        if not self.farmFrame then self:CreateFarmFrame() end
        self.farmFrame:Show()
        self.farmFrame.nodeOverlayTimer = 0
        self.farmFrame.markerUpdateTimer = 0
        self.farmFrame.coordUpdateTimer = 0
        self.farmFrame.lastFarmNodeVisualUpdate = nil
        self.farmFrame.pmSmoothMapID = nil
        self.farmFrame.pmSmoothContext = nil
        self.farmFrame.pmSmoothPlayerX = nil
        self.farmFrame.pmSmoothPlayerY = nil
        self.farmFrame.pmSmoothFrameTime = nil
        self.farmFrame.pmSmoothFacing = nil
        self.farmFrame.pmFarmRenderChanged = nil
        self.farmFrame.pmFarmStableMapID = nil
        self.farmFrame.pmFarmStableX = nil
        self.farmFrame.pmFarmStableY = nil
        self.farmFrame.pmFarmStableFacing = nil
        self.farmFrame.pmFarmStableViewRadius = nil
        self.farmFrame.pmFarmViewRadiusOverride = nil
        self.farmFrame.pmFarmLastViewRadius = nil
        self.farmFrame.pmFarmLastZoomLevel = nil
        self.farmFrame.pmFarmRenderMapID = nil
        self.farmFrame.pmFarmAppliedRotate = nil
        self.farmFrame.pmFarmOverlayDirty = true
        self.farmFrame.pmFarmNodesDirty = true
        self:UpdateFarmVisuals(settings)

        if Minimap then
            RestoreNativeMinimapToFarmFrame(self.farmFrame, settings)
            self:SetFarmMouseMode(settings)
            ForceMinimapTextureRefresh()
        end
        if _G["PathmakerCanvas"] then _G["PathmakerCanvas"]:Hide() end
        if _G["PathmakerHeatmapMini"] then _G["PathmakerHeatmapMini"]:Hide() end

        if self.NorthTagFrame then
            self.NorthTagFrame:Hide()
        end
        
        if MinimapNorthTag then MinimapNorthTag:Hide() end
        ManageOverlays(true)
        self:LayoutMinimapButtons() 

        self.farmFrame:SetScale(1)
        self:UpdateFarmVisuals(settings)
        -- Refresh after the complete farm layout/alpha transition. Doing this
        -- only at 100% left lower saved opacity values with a stale minimap.
        RequestFarmMinimapTextureRefresh(self.farmFrame)
        
    else
        local returnedToNativeMinimap = self.farmReturnToNativeMinimap
            or settings.usePathmakerMinimap == false
        self:ResetFarmVisuals()
        SetFarmMinimapZoomLocked(false)
        RestoreFarmMinimapChildren()
        self:ResetFarmOverlayTransform(_G["PathmakerCanvas"])
        self:ResetFarmOverlayTransform(_G["PathmakerHeatmapMini"])
        self.farmFrame:Hide()

        if returnedToNativeMinimap then
            -- Restore the captured Blizzard minimap directly. Reparenting it to
            -- PathMaker first can leave Retail's MinimapCluster in a stale state.
            self:Disable(true)
            self:EnableNativeMinimapFeatures(settings, true)
        else
            RestorePathmakerMinimapToFrame(self.frame)
            ForceMinimapMouseRestore()
            self:Enable()
        end
        if self.farmControlsWereShown and not returnedToNativeMinimap then
            self:ShowStandaloneControls()
        end
        self.farmReturnToNativeMinimap = nil
        self.farmControlsWereShown = nil

        if addon.Heatmap then
            addon.Heatmap.minimapNodesDirty = true
            if addon.Heatmap.UpdateMinimap then addon.Heatmap:UpdateMinimap(0) end
        end
        if not returnedToNativeMinimap then ForceMinimapTextureRefresh() end
        
        C_Timer.After(0.1, function()
            if not addon.isFarmMode then
                if addon.MapFrame.ownsMinimap then
                    ForceMinimapMouseRestore()
                    ForceMinimapTextureRefresh()
                end
                if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
            end
        end)
    end
    self:UpdateUIState()
    if addon.Options and type(addon.Options.RefreshSettingsUI) == "function" then
        addon.Options:RefreshSettingsUI()
    end
end

function addon.MapFrame:CreateQuickBar()
    self.quickBar = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self.quickBar:SetSize(143, 17) 
    self.quickBar:SetFrameLevel(10)
    
    if self.btnRoutes then
         self.quickBar:SetPoint("TOPLEFT", self.btnRoutes, "BOTTOMLEFT", 0, 0)
    else
         self.quickBar:SetPoint("TOP", self.frame, "BOTTOM", 0, 0)
    end
    
    self.quickBar:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    self.quickBar:SetBackdropColor(0.05, 0.05, 0.05, 0.95)

    local line = self.quickBar:CreateTexture(nil, "OVERLAY")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", 0, 0)
    line:SetColorTexture(0.3, 0.3, 0.3, 0)
    
    local btnW = 35.75
    
    self.btnQuickRec = CreateMinimalButton(self.quickBar, "New", btnW, 17)
    self.btnQuickRec:SetPoint("LEFT", 0, 0)
    self.btnQuickRec:SetScript("OnClick", function()
        if addon.Routes then addon.Routes:ToggleRecording() end
        self:UpdateUIState()
    end)
    
    self.btnQuickNav = CreateMinimalButton(self.quickBar, "Arrow", btnW, 17)
    self.btnQuickNav:SetPoint("LEFT", self.btnQuickRec, "RIGHT", 0, 0)
    self.btnQuickNav:SetScript("OnClick", function()
        if addon.Navigation and addon.Navigation.Toggle then
    if addon.Navigation then

    if addon.selectedRoute then
        addon.activeRoute = addon.selectedRoute
    end

    if addon.Navigation.Toggle then
        addon.Navigation:Toggle()
    end
end
end
        addon.drawConfig.navEnabled = not addon.drawConfig.navEnabled
        self:UpdateUIState()
    end)

    self.btnQuickFarm = CreateMinimalButton(self.quickBar, "Farm", btnW, 17)
    self.btnQuickFarm:SetPoint("LEFT", self.btnQuickNav, "RIGHT", 0, 0)
    self.btnQuickFarm:SetScript("OnClick", function()
        if PathmakerDB.isEnabled then
            addon.MapFrame:ToggleFarmMode()
        else
            addon:PrintMessage("disableMsgError", "|cffff0000Pathmaker:|r Enable addon first (/pmon).")
        end
    end)

    self.btnQuickGhost = CreateMinimalButton(self.quickBar, "%", btnW, 17)
    self.btnQuickGhost:SetPoint("LEFT", self.btnQuickFarm, "RIGHT", 0, 0)
    self.btnQuickGhost:SetScript("OnClick", function()
        addon.drawConfig.ghostView = not addon.drawConfig.ghostView
        if addon.isFarmMode and addon.MapFrame.UpdateFarmVisuals then
            addon.MapFrame:UpdateFarmVisuals(PathmakerDB and PathmakerDB.settings)
        end
        if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
        self:UpdateUIState()
    end)
    
end

function addon.MapFrame:CreateClock()
    self.clockFrame = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self.clockFrame:SetSize(43, 16)
    self.clockFrame:SetFrameLevel(10)
    
    self.clockFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    self.clockFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    self.clockFrame:SetBackdropBorderColor(0, 0, 0, 1)

    self.clockText = self.clockFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.clockText:SetPoint("CENTER")
    self.clockText:SetTextColor(0.7, 0.7, 0.7) 

    self.clockFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timer = (self.timer or 0) + elapsed
        if self.timer > 1 then
            self.timer = 0
            if addon.MapFrame.clockText then
                addon.MapFrame.clockText:SetText(date("%H:%M"))
            end
        end
    end)
    
    self.clockText:SetText(date("%H:%M"))
    self:UpdateClockPosition(EnsurePathmakerSettings())
end

function addon.MapFrame:CreateBottomButtons()
    -- 50 + 43 + 50 exactly covers the 143px minimap width. Avoiding the old
    -- one-pixel overlap keeps the clock from painting over a button outline.
    local btnW = 50
    
    self.btnRoutes = CreateMinimalButton(self.frame, "Routes", btnW, 16)
    self.btnRoutes:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", 0, 0)
    self.btnRoutes:SetFrameLevel(10)
    self.btnRoutes:SetScript("OnClick", function()
        if self.managerFrame:IsShown() then 
            self.managerFrame:Hide() 
            if addon.PaletteFrame then addon.PaletteFrame:Hide() end
        else 
            self.managerFrame:Show()
            self:UpdateRouteList() 
        end
        self:UpdateUIState(true) 
    end)

    self.btnTools = CreateMinimalButton(self.frame, "Tools", btnW, 16)
    self.btnTools:SetPoint("TOPRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
    self.btnTools:SetFrameLevel(10)
    self.btnTools:SetScript("OnClick", function()
        if self.tacticalFrame:IsShown() then 
            self.tacticalFrame:Hide() 
        else 
            self.tacticalFrame:Show()
        end
        self:UpdateUIState(true) 
    end)
    
    self:CreateClock()
    
    if self.quickBar then
        self.quickBar:ClearAllPoints()
        self.quickBar:SetPoint("TOPLEFT", self.btnRoutes, "BOTTOMLEFT", 0, 0)
    end
end

function addon.MapFrame:CreateTimersFrame()
    local f = CreateFrame("Frame", "PathmakerTimersFrame", UIParent, "BackdropTemplate") 
    f:SetSize(143, 150) 
    f:SetPoint("TOP", self.frame, "BOTTOM", 0, -50) 
    f:Hide()
    f:SetFrameStrata("MEDIUM") 
    f:SetFrameLevel(20)
    f:SetClampedToScreen(true) 
    f:SetMovable(true) 
    f:EnableMouse(true)
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", tile = false, tileSize = 0, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    
    f:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then self:StartMoving() end end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnShow", function() addon.MapFrame:UpdateTimerList() end)
    
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -8); header:SetText("Route Markers")
    
    local btnClose = StyleCloseButton(CreateMinimalButton(f, "X", 16, 16))
    btnClose:SetPoint("TOPRIGHT", -2, -2)
    btnClose:SetScript("OnClick", function() 
        f:Hide()
        addon.MapFrame:StopRouteCounters()
        addon.MapFrame:UpdateUIState() 
    end)

    local btnStartAll = CreateMinimalButton(f, "Start All", 120, 20)
    btnStartAll:SetPoint("TOP", 0, -25)
    btnStartAll:SetScript("OnClick", function()
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and addon.selectedRouteGUID and PathmakerDB.routes[mapID] then
             local route = PathmakerDB.routes[mapID][addon.selectedRouteGUID]
             if route and route.points then
                 local now = GetTime()
                 for _, p in ipairs(route.points) do
                     if p.isMarker and p.duration then
                         p.countdownStart = now
                         p.isStanding = false 
                     end
                 end
                 if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
             end
        end
    end)
    
    local scrollFrame, scrollChild, slider = CreateDarkScrollArea(f, 118, 90) 
    scrollFrame:SetPoint("TOP", 0, -50)
    f.scrollFrame = scrollFrame; f.scrollChild = scrollChild; f.slider = slider; f.rows = {} 
    
    f:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        self.updateTimer = (self.updateTimer or 0) + elapsed
        if self.updateTimer < 0.1 then return end 
        self.updateTimer = 0
        
        local now = GetTime()
        for _, row in ipairs(self.rows) do
            if row:IsShown() and row.markerData then
                 local p = row.markerData
                 if p.countdownStart then
                      local diff = now - p.countdownStart
                      local remaining = p.duration - diff
                      
                      if remaining > 0 then
                          row.time:SetText(string.format("%.0fs", remaining))
                          local pct = remaining / p.duration
                          if pct > 0.5 then row.time:SetTextColor(1, 1, 1) 
                          elseif pct > 0.25 then row.time:SetTextColor(1, 1, 0) 
                          else row.time:SetTextColor(1, 0, 0) end 
                      else
                          local over = math.abs(remaining)
                          row.time:SetText(string.format("+%.0fs", over))
                          row.time:SetTextColor(0, 1, 0) 
                      end
                 else
                      row.time:SetText(string.format("%ds", p.duration))
                      row.time:SetTextColor(0.5, 0.5, 0.5) 
                 end
            end
        end
    end)

    self.timersFrame = f
end

function addon.MapFrame:UpdateTimerList()
    if not self.timersFrame then return end
    local f = self.timersFrame
    local child = f.scrollChild
    for _, r in pairs(f.rows) do r:Hide() end
    
    local mapID = C_Map.GetBestMapForUnit("player")
    local markers = {}
    local route = nil

    if mapID and addon.selectedRouteGUID and PathmakerDB.routes[mapID] then
         route = PathmakerDB.routes[mapID][addon.selectedRouteGUID]
         if route and route.points then
              local pts = route.points
              for i, p in ipairs(pts) do
                  if p.isMarker and p.duration then
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
         end
    end
    
    local idx = 0
    for i, item in ipairs(markers) do
         idx = idx + 1
         local row = f.rows[idx]
         if not row then
              row = CreateFrame("Button", nil, child, "BackdropTemplate")
              row:SetSize(110, 20) 
              row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
              row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
              
              row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
              row.name:SetPoint("LEFT", 5, 0)
              row.name:SetWidth(70)
              row.name:SetJustifyH("LEFT")
              
              row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
              row.time:SetPoint("RIGHT", -5, 0)
              row.time:SetJustifyH("RIGHT")
              
              row:SetScript("OnClick", function()
                   row:SetBackdropColor(1, 1, 1, 0.5)
                   C_Timer.After(0.1, function() row:SetBackdropColor(0.1, 0.1, 0.1, 0.5) end)

                   if row.markerData and row.markerIndex and row.routePoints then
                        local now = GetTime()
                        local pts = row.routePoints
                        for k = row.markerIndex, #pts do
                             local p = pts[k]
                             if k > row.markerIndex and (p.isGap or not p.isMarker or p.duration ~= row.markerData.duration) then
                                  break 
                             end
                             p.countdownStart = now
                             p.isStanding = false
                        end
                        if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
                   end
              end)
              f.rows[idx] = row
         end
         
         row.markerData = item.data
         row.markerIndex = item.index
         row.routePoints = route and route.points or nil
         
         row.name:SetText(item.data.name or ("Marker " .. idx))
         row:SetPoint("TOPLEFT", 5, -((idx-1) * 22))
         row:Show()
    end
    
    child:SetHeight(math.max(1, idx * 22))
    local maxScroll = math.max(0, (idx * 22) - 90) 
    f.slider:SetMinMaxValues(0, maxScroll)
end

function addon.MapFrame:GetDiscoveredNodes()
    local discovered = {}
    if PathmakerDB and PathmakerDB.nodes then
        for mapID, nodes in pairs(PathmakerDB.nodes) do
            if not addon.Compat or addon.Compat:IsMapExpansionVisible(mapID) then
                for _, node in ipairs(nodes) do
                    local normName = addon.Heatmap and addon.Heatmap:GetNormalizedName(node.specificName) or node.specificName
                    if normName and normName ~= "Unknown" then
                        local icon = addon.Heatmap and addon.Heatmap.ResolveNodeIcon
                            and addon.Heatmap.ResolveNodeIcon(node) or node.icon
                        discovered[normName] = { icon = icon, type = node.type }
                    end
                end
            end
        end
    end
    return discovered
end

function addon.MapFrame:ToggleNodeFilter()
    if not self.nodeFilterFrame then self:CreateNodeFilterFrame() end
    local settings = EnsurePathmakerSettings()
    if self.nodeFilterFrame:IsShown() then
        self.nodeFilterFrame:Hide()
        settings.nodeFilterOpen = false
    else
        settings.nodeFilterOpen = true
        self.nodeFilterFrame:Show()
        self:UpdateNodeFilterList()
        if self.nodeFilterFrame.searchBox then
            self.nodeFilterFrame.searchBox:ClearFocus()
        end
    end
end

function addon.MapFrame:CreateNodeFilterFrame()
    local f = CreateFrame("Frame", "PathmakerNodeFilterFrame", UIParent, "BackdropTemplate")
    f:SetSize(220, 400)
    local savedPosition = EnsurePathmakerSettings().nodeFilterPosition
    if savedPosition and savedPosition.point then
        f:SetPoint(savedPosition.point, UIParent, savedPosition.relativePoint or savedPosition.point, savedPosition.x or 0, savedPosition.y or 0)
    else
        f:SetPoint("TOPLEFT", self.tacticalFrame, "TOPRIGHT", 5, 0)
    end
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        EnsurePathmakerSettings().nodeFilterPosition = {point=point, relativePoint=relativePoint, x=x, y=y}
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Filter Nodes")
    f.title = title

    local btnClose = StyleCloseButton(CreateMinimalButton(f, "X", 20, 20))
    btnClose:SetPoint("TOPRIGHT", -5, -5)
    btnClose:SetScript("OnClick", function()
        f:Hide()
        EnsurePathmakerSettings().nodeFilterOpen = false
    end)

    f.searchBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    f.searchBox:SetSize(200, 20)
    f.searchBox:SetPoint("TOPLEFT", 10, -35)
    f.searchBox:SetAutoFocus(false)
    f.searchBox:SetFontObject("GameFontHighlightSmall")
    f.searchBox:SetTextInsets(4,4,0,0)
    f.searchBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    f.searchBox:SetBackdropColor(0.1, 0.1, 0.1, 1)
    f.searchBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    f.searchBox.placeholder = f.searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.searchBox.placeholder:SetPoint("LEFT", 4, 0)
    f.searchBox.placeholder:SetText("Search nodes...")
    
    f.searchBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then self.placeholder:Show() else self.placeholder:Hide() end
        EnsurePathmakerSettings().nodeFilterSearch = self:GetText()
        addon.MapFrame:UpdateNodeFilterList()
    end)
    f.searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    f.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local btnW = 95
    local btnAll = CreateMinimalButton(f, "Show All", btnW, 20)
    btnAll:SetPoint("TOPLEFT", 10, -60)
    btnAll:SetScript("OnClick", function()
        if not PathmakerDB.settings then PathmakerDB.settings = {} end
        PathmakerDB.settings.hiddenNodes = {}
        if addon.Heatmap and addon.Heatmap.InvalidateVisibleNodeCache then addon.Heatmap:InvalidateVisibleNodeCache() end
        addon.MapFrame:UpdateNodeFilterList()
        if addon.Heatmap then addon.Heatmap:RefreshWorldMap() end
    end)

    local btnNone = CreateMinimalButton(f, "Hide All", btnW, 20)
    btnNone:SetPoint("TOPRIGHT", -10, -60)
    btnNone:SetScript("OnClick", function()
        if not PathmakerDB.settings then PathmakerDB.settings = {} end
        if not PathmakerDB.settings.hiddenNodes then PathmakerDB.settings.hiddenNodes = {} end

        local discovered = addon.MapFrame:GetDiscoveredNodes()
        for name, _ in pairs(discovered) do PathmakerDB.settings.hiddenNodes[name] = true end
        if addon.Heatmap and addon.Heatmap.InvalidateVisibleNodeCache then addon.Heatmap:InvalidateVisibleNodeCache() end
        addon.MapFrame:UpdateNodeFilterList()
        if addon.Heatmap then addon.Heatmap:RefreshWorldMap() end
    end)

    local btnHerbs = CreateMinimalButton(f, "Herbalism Only", btnW, 20)
    btnHerbs:SetPoint("TOPLEFT", 10, -85)
    btnHerbs:SetScript("OnClick", function()
        if not PathmakerDB.settings then PathmakerDB.settings = {} end
        if not PathmakerDB.settings.hiddenNodes then PathmakerDB.settings.hiddenNodes = {} end
        local discovered = addon.MapFrame:GetDiscoveredNodes()
        for name, data in pairs(discovered) do
            PathmakerDB.settings.hiddenNodes[name] = (NormalizeGatheringNodeType(data.type) ~= "Herb")
        end
        if addon.Heatmap and addon.Heatmap.InvalidateVisibleNodeCache then addon.Heatmap:InvalidateVisibleNodeCache() end
        addon.MapFrame:UpdateNodeFilterList()
        if addon.Heatmap then addon.Heatmap:RefreshWorldMap() end
    end)

    local btnMining = CreateMinimalButton(f, "Mining Only", btnW, 20)
    btnMining:SetPoint("TOPRIGHT", -10, -85)
    btnMining:SetScript("OnClick", function()
        if not PathmakerDB.settings then PathmakerDB.settings = {} end
        if not PathmakerDB.settings.hiddenNodes then PathmakerDB.settings.hiddenNodes = {} end
        local discovered = addon.MapFrame:GetDiscoveredNodes()
        for name, data in pairs(discovered) do
            PathmakerDB.settings.hiddenNodes[name] = (NormalizeGatheringNodeType(data.type) ~= "Mining")
        end
        if addon.Heatmap and addon.Heatmap.InvalidateVisibleNodeCache then addon.Heatmap:InvalidateVisibleNodeCache() end
        addon.MapFrame:UpdateNodeFilterList()
        if addon.Heatmap then addon.Heatmap:RefreshWorldMap() end
    end)

    local sf, content, slider = CreateDarkScrollArea(f, 190, 275)
    sf:SetPoint("TOPLEFT", 10, -115)
    f.scrollFrame = sf
    f.scrollChild = content
    f.slider = slider
    f.rows = {}

    self.nodeFilterFrame = f
    f.searchBox:SetText(EnsurePathmakerSettings().nodeFilterSearch or "")
    f:Hide()
end

function addon.MapFrame:UpdateNodeFilterList()
    local f = self.nodeFilterFrame
    if not f then return end

    for _, row in pairs(f.rows) do row:Hide() end

    local discovered = self:GetDiscoveredNodes()
    local sorted = {}
    local searchTxt = (f.searchBox and f.searchBox:GetText() or ""):lower()

    for name, data in pairs(discovered) do
        if searchTxt == "" or string.find(name:lower(), searchTxt, 1, true) then
            table.insert(sorted, {name = name, icon = data.icon, type = data.type})
        end
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    if not PathmakerDB.settings then PathmakerDB.settings = {} end
    if not PathmakerDB.settings.hiddenNodes then PathmakerDB.settings.hiddenNodes = {} end

    local enabledCount, totalCount = 0, 0
    for name in pairs(discovered) do
        totalCount = totalCount + 1
        if not PathmakerDB.settings.hiddenNodes[name] then enabledCount = enabledCount + 1 end
    end
    if f.title then f.title:SetText(string.format("Filter Nodes (%d/%d)", enabledCount, totalCount)) end

    local height = 0
    local btnHeight = 24
    for i, item in ipairs(sorted) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Button", nil, f.scrollChild, "BackdropTemplate")
            row:SetSize(180, btnHeight)
            row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)

            row.chk = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.chk:SetSize(20, 20)
            row.chk:SetPoint("LEFT", 2, 0)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", row.chk, "RIGHT", 5, 0)

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
            row.text:SetPoint("RIGHT", -5, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(false)
            if row.text.SetMaxLines then row.text:SetMaxLines(1) end

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.nodeName or "")
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self)
                if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
            end)

            row.chk:SetScript("OnClick", function(self)
                local isChecked = self:GetChecked()
                PathmakerDB.settings.hiddenNodes[row.nodeName] = not isChecked
                if addon.Heatmap and addon.Heatmap.InvalidateVisibleNodeCache then addon.Heatmap:InvalidateVisibleNodeCache() end
                if addon.Heatmap then addon.Heatmap:RefreshWorldMap() end
                addon.MapFrame:UpdateNodeFilterList()
            end)
            row:SetScript("OnClick", function(self)
                self.chk:SetChecked(not self.chk:GetChecked())
                local onClick = self.chk:GetScript("OnClick")
                if onClick then onClick(self.chk) end
            end)
            f.rows[i] = row
        end

        row.nodeName = item.name
        row.icon:SetTexture(item.icon)
        row.text:SetText(item.name)

        local isHidden = PathmakerDB.settings.hiddenNodes[item.name]
        row.chk:SetChecked(not isHidden)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -height)
        row:Show()
        height = height + btnHeight + 1
    end

    f.scrollChild:SetHeight(math.max(1, height))
    local maxScroll = math.max(0, height - 275)
    f.slider:SetMinMaxValues(0, maxScroll)
end


function addon.MapFrame:CreateTacticalMenu()
    local f = CreateFrame("Frame", "PathmakerTacticalTools", UIParent, "BackdropTemplate")
    f:SetSize(140, 230) 
    f:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 5, 0)
    f:Hide()
    f:SetFrameStrata("MEDIUM") 
    f:SetFrameLevel(20)
    f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", tile = false, tileSize = 0, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -8); header:SetText("Tactical Tools")
    
    local yOffset = -30; local labelX = 10
    local lblMode = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblMode:SetPoint("TOPLEFT", labelX, yOffset); lblMode:SetText("Modes:")
    
    self.btnTrack = CreateMinimalButton(f, "Start New Route", 120, 20)
    self.btnTrack:SetPoint("TOP", 0, yOffset - 15)
    self.btnTrack.text:SetTextColor(0, 1, 0) 
    self.btnTrack:SetScript("OnClick", function() 
        if addon.Routes then 
            if addon.Routes.isRecording then 
                addon.Routes:StopRecording()
                addon.MapFrame.inputBlocker:Hide() 
            else 
                addon.Routes:StartRecording(nil) 
                addon.MapFrame.inputBlocker:Show() 
            end 
            self:UpdateUIState() 
        end 
    end)

    self.btnDraw = CreateMinimalButton(f, "Draw Mode", 120, 20)
    self.btnDraw:SetPoint("TOP", self.btnTrack, "BOTTOM", 0, -2)
    self.btnDraw:SetScript("OnClick", function()
        if addon.Planner and type(addon.Planner.Toggle) == "function" then
            addon.Planner:Toggle()
        else
            addon:PrintMessage("disableMsgError", "|cffff0000PathMaker:|r Draw Mode could not initialize. Reload the UI and check for an earlier Planner error.")
        end
    end)
    
    local line1 = f:CreateTexture(nil, "OVERLAY"); line1:SetHeight(2); line1:SetColorTexture(0.6, 0.6, 0.6, 0.0); line1:SetPoint("TOPLEFT", 8, yOffset - 40 - 25); line1:SetPoint("TOPRIGHT", -8, yOffset - 40 - 25)

    self.btnEditRoute = CreateMinimalButton(f, "Edit Current Route", 120, 20)
    self.btnEditRoute:SetPoint("TOP", self.btnDraw, "BOTTOM", 0, -5) 
    self.btnEditRoute:SetScript("OnClick", function() 
        if not addon.selectedRouteGUID then return end 
        if addon.Routes.isRecording then 
            addon.Routes:StopRecording() 
            addon.MapFrame.inputBlocker:Hide() 
        else 
            addon.Routes:StartRecording(addon.selectedRouteGUID)
            addon.MapFrame.inputBlocker:Show() 
        end 
        self:UpdateUIState() 
    end)
    
    yOffset = yOffset - 100 
    self.btnReverse = CreateMinimalButton(f, "Reverse Route", 120, 20)
    self.btnReverse:SetPoint("TOP", self.btnEditRoute, "BOTTOM", 0, -2)
    self.btnReverse:SetScript("OnClick", function() if addon.Routes then addon.Routes:ReverseCurrentRoute() end self:UpdateUIState() end)
    
    yOffset = yOffset - 13
    local lblVis = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblVis:SetPoint("TOPLEFT", labelX, yOffset); lblVis:SetText("Current Route:")
    
    self.activeRouteBtn = CreateFrame("Button", nil, f)
    self.activeRouteBtn:SetSize(120, 8)
    self.activeRouteBtn:SetPoint("TOPLEFT", labelX, yOffset - 18)
    self.activeRouteBtn.text = self.activeRouteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); self.activeRouteBtn.text:SetAllPoints(); self.activeRouteBtn.text:SetJustifyH("LEFT")
    self.activeRouteBtn.text:SetText("None Selected"); self.activeRouteBtn.text:SetTextColor(0.5, 0.5, 0.5)
    self.activeRouteBtn:SetScript("OnClick", function() 
        if addon.selectedRouteGUID then 
            addon.MapFrame:StopRouteCounters()
            addon.selectedRouteGUID = nil
            addon.selectedRouteMapID = nil
            addon.MapFrame:ResetFarmVisuals()
            addon.MapFrame:UpdateRouteList()
            if addon.UI then addon.UI:RefreshRendering() end
            self:UpdateUIState() 
        end 
    end)

    yOffset = yOffset - 35

    local sliderText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sliderText:SetPoint("TOP", 0, yOffset + 5)
    sliderText:SetText("Farm Mode Opacity")
    sliderText:SetTextColor(0.5, 0.5, 0.5) 

    -- Load saved alpha value if it exists
    local currentAlpha = NormalizeFarmAlphaValue((PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.farmAlpha) or addon.farmAlpha, 0.6)
    addon.farmAlpha = currentAlpha

    local customSlider
    customSlider = CreateCustomSlider(f, 120, 16, 0.0, 1.0, currentAlpha, function(val)
        val = NormalizeFarmAlphaValue(val, addon.farmAlpha or 0.6)
        addon.farmAlpha = val
        -- Save the changed alpha state
        if PathmakerDB and PathmakerDB.settings then
            PathmakerDB.settings.farmAlpha = val
        end
        if customSlider then customSlider:SetValue(val) end
        if addon.isFarmMode and addon.MapFrame.ApplyFarmAlpha and PathmakerDB and PathmakerDB.settings then
            val = addon.MapFrame:ApplyFarmAlpha(PathmakerDB.settings, true) or val
        elseif addon.isFarmMode then
            if Minimap then
                if Minimap.SetIgnoreParentAlpha then Minimap:SetIgnoreParentAlpha(true) end
                Minimap:SetAlpha(val)
            end
            if addon.MapFrame.farmFrame then
                addon.MapFrame.farmFrame:SetAlpha(1)
                local alphaHost = addon.MapFrame.farmFrame.pmMinimapAlphaHost
                if alphaHost then alphaHost:SetAlpha(1) end
            end
            addon.MapFrame:UpdateFarmVisuals(PathmakerDB.settings)
        end
        
        -- Sync Options UI
        if addon.Options and addon.Options.farmAlphaSlider then
            addon.Options.farmAlphaSlider:SetValue(val)
        end
        if addon.Options and addon.Options.farmAlphaLabelVal then
            addon.Options.farmAlphaLabelVal:SetText(string.format("%d%%", math.floor(val * 100 + 0.5)))
        end
    end)
    customSlider:SetPoint("TOP", sliderText, "BOTTOM", 0, -2)
    self.tacticalFarmAlphaSlider = customSlider

    self.btnToggleShape = CreateMinimalButton(f, "Circle Map", 120, 20)
    self.btnToggleShape:SetPoint("TOP", customSlider, "BOTTOM", 0, -5) 
    self.btnToggleShape:SetScript("OnClick", function()
        EnsurePathmakerSettings()
        addon.useSquareMap = not addon.useSquareMap
        -- Save the toggled map shape state
        PathmakerDB.settings.useSquareMap = addon.useSquareMap
        
        self:ApplyMinimapShape(addon.useSquareMap)
        self:LayoutMinimapButtons()
        self:UpdateUIState() 
        
        -- Keep Options panel in sync
        if addon.Options and type(addon.Options.RefreshSettingsUI) == "function" then
            addon.Options:RefreshSettingsUI()
        end
    end)

    self.tacticalFrame = f
end

function addon.MapFrame:CreateRouteManager()
    local f = CreateFrame("Frame", "PathmakerRouteManager", UIParent, "BackdropTemplate")
    f:SetSize(150, 220) 
    f:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", -5, 0) 
    f:Hide()
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(20)
    f:SetClampedToScreen(true) 
    f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", tile = false, tileSize = 0, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOP", 0, -8); header:SetText("Route Manager")
    
    self.btnImport = CreateMinimalButton(f, "Import Route String", 130, 18)
    self.btnImport:SetPoint("TOP", 0, -25)
    self.btnImport:SetScript("OnClick", function() if addon.ImportExport then addon.ImportExport:ShowImport() end end)
    
    self.btnExport = CreateMinimalButton(f, "Export Route", 130, 18)
    self.btnExport:SetPoint("TOP", self.btnImport, "BOTTOM", 0, -4)
    self.btnExport:SetScript("OnClick", function() if addon.ImportExport then addon.ImportExport:ShowExport(addon.selectedRouteGUID) end end)
    self.btnExport:Disable()

    local searchY = -70 
    self.searchEdit = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    self.searchEdit:SetSize(100, 18)
    self.searchEdit:SetPoint("TOPLEFT", 10, searchY)
    self.searchEdit:SetAutoFocus(false)
    self.searchEdit:SetFontObject("GameFontHighlightSmall")
    self.searchEdit.placeholder = self.searchEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.searchEdit.placeholder:SetPoint("LEFT", 4, 0); self.searchEdit.placeholder:SetText("Search...")
    self.searchEdit:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    self.searchEdit:SetBackdropColor(0.1, 0.1, 0.1, 1)
    self.searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.searchEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end) 
    self.searchEdit:SetScript("OnTextChanged", function(self) local txt = self:GetText(); if txt == "" then self.placeholder:Show() else self.placeholder:Hide() end; searchFilter = txt; addon.MapFrame:UpdateRouteList() end)
    
    self.searchColorBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    self.searchColorBtn:SetSize(18, 18)
    self.searchColorBtn:SetPoint("LEFT", self.searchEdit, "RIGHT", 4, 0)
    self.searchColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    self.searchColorBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    self.searchColorBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    self.searchColorBtn.tex = self.searchColorBtn:CreateTexture(nil, "OVERLAY")
    self.searchColorBtn.tex:SetAllPoints(); self.searchColorBtn.tex:SetColorTexture(0,0,0,0) 
    self.searchColorBtn:SetScript("OnClick", function() local mapID = C_Map.GetBestMapForUnit("player"); OpenPalettePicker(f, mapID, function(c) if colorFilter and addon.Routes and addon.Routes:ColorsMatch(colorFilter, c) then colorFilter = nil; self.searchColorBtn.tex:SetColorTexture(0,0,0,0) else colorFilter = c; self.searchColorBtn.tex:SetColorTexture(unpack(c)) end addon.MapFrame:UpdateRouteList() end, true, "SearchColor", self.searchColorBtn) end)
    
    self.nameEdit = CreateFrame("EditBox", nil, f, "BackdropTemplate")
    self.nameEdit:SetSize(120, 18) 
    self.nameEdit:SetPoint("TOPLEFT", 10, searchY - 25)
    self.nameEdit:SetAutoFocus(false)
    self.nameEdit:SetFontObject("GameFontHighlightSmall")
    self.nameEdit:SetMaxLetters(12) 
    self.nameEdit:SetTextInsets(4,4,0,0)
    self.nameEdit:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
    self.nameEdit:SetBackdropColor(0.1, 0.1, 0.1, 1)
    self.nameEdit.placeholder = self.nameEdit:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.nameEdit.placeholder:SetPoint("LEFT", 4, 0); self.nameEdit.placeholder:SetText("Rename...")
    self.nameEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    self.nameEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); local mapID, route = addon.MapFrame:FindSelectedRoute(); if mapID and route then local newName = self:GetText(); route.name = newName; addon.selectedRouteMapID = mapID; addon.MapFrame:UpdateRouteList(); addon.MapFrame:RefreshTactical() end end)
    self.nameEdit:SetScript("OnTextChanged", function(self) if self:GetText() == "" then self.placeholder:Show() else self.placeholder:Hide() end end)
    
    local scrollFrame, scrollChild, slider = CreateDarkScrollArea(f, 128, 90)
    scrollFrame:SetPoint("TOPLEFT", 5, searchY - 50)
    f.scrollFrame = scrollFrame; f.scrollChild = scrollChild; f.slider = slider; f.buttons = {} 
    self.managerFrame = f
end

function addon.MapFrame:RefreshRouteSelectionVisuals()
    local frame = self.managerFrame
    if not frame then return end

    local playerMapID = C_Map.GetBestMapForUnit("player")
    local selectedMapID, selectedRoute = self:FindSelectedRoute()
    local selectedRouteInZone = selectedMapID == playerMapID and selectedRoute or nil
    if self.nameEdit then
        if selectedRouteInZone then
            if not self.nameEdit:HasFocus() then self.nameEdit:SetText(selectedRouteInZone.name or "") end
            self.nameEdit:Enable()
        else
            self.nameEdit:SetText("")
            self.nameEdit:Disable()
        end
    end

    for _, button in pairs(frame.buttons or {}) do
        if button:IsShown() then
            if button.guid == addon.selectedRouteGUID then
                button:SetBackdropColor(0.2, 0.4, 0.8, 0.4)
            else
                button:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
            end
        end
    end
end

function addon.MapFrame:SyncRouteSelectionToOpenEditors()
    local options = addon.Options
    local optionsPanel = options and options.panel
    if optionsPanel and optionsPanel:IsShown() then
        if options.routeManagerPanel and options.routeManagerPanel:IsShown()
            and optionsPanel.RefreshRouteList
        then
            optionsPanel.RefreshRouteList()
        end
        if options.drawModePanel and options.drawModePanel:IsShown() then
            if addon.selectedRouteGUID and addon.selectedRouteMapID
                and optionsPanel.SelectRouteInOptionsDrawMode
            then
                optionsPanel.SelectRouteInOptionsDrawMode(
                    addon.selectedRouteGUID, addon.selectedRouteMapID)
            elseif optionsPanel.ClearRouteInOptionsDrawMode then
                optionsPanel.ClearRouteInOptionsDrawMode()
            end
        end
    end

    local planner = addon.Planner
    if planner and planner.panel and planner.panel:IsShown() then
        if addon.selectedRouteGUID and addon.selectedRouteMapID and planner.ShowGeneratedRoute then
            planner:ShowGeneratedRoute(addon.selectedRouteGUID, addon.selectedRouteMapID)
        elseif planner.ClearExternalRouteSelection then
            planner:ClearExternalRouteSelection()
        end
    end
end

function addon.MapFrame:UpdateRouteList()
    local f = self.managerFrame; local child = f.scrollChild; for _, btn in pairs(f.buttons) do btn:Hide() end
    
    local mapID = C_Map.GetBestMapForUnit("player")
    
    local selectedRouteMapID, selectedRoute = self:FindSelectedRoute()
    if addon.selectedRouteGUID and not selectedRoute then
        addon.selectedRouteGUID = nil
        addon.selectedRouteMapID = nil
        self:ResetFarmVisuals()
    end

    local selectedRouteInZone = selectedRouteMapID == mapID and selectedRoute or nil
    if selectedRouteInZone then local name = selectedRouteInZone.name; if not self.nameEdit:HasFocus() then self.nameEdit:SetText(name) end; self.nameEdit:Enable() else self.nameEdit:SetText(""); self.nameEdit:Disable() end
    
    local index = 0; local sortedRoutes = {}
    local routesInZone = mapID and PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[mapID] or {}
    for guid, data in pairs(routesInZone) do
        if not addon.Routes or not addon.Routes.IsRouteData or addon.Routes:IsRouteData(data) then
            table.insert(sortedRoutes, {guid=guid, data=data, mapID=mapID})
        end
    end
    table.sort(sortedRoutes, function(a, b)
        return (a.data.name or "") < (b.data.name or "")
    end)
    
    for i, item in ipairs(sortedRoutes) do
        local show = true
        if searchFilter and searchFilter ~= "" then if not string.find(string.lower(item.data.name or ""), string.lower(searchFilter)) then show = false end end
        if show and colorFilter then if not (addon.Routes and addon.Routes:ColorsMatch(item.data.color, colorFilter)) then show = false end end
        if show then
            index = index + 1; local btn = f.buttons[index]
            if not btn then
                btn = CreateFrame("Button", nil, child, "BackdropTemplate"); btn:SetSize(118, 20); btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
                btn.color = CreateFrame("Button", nil, btn, "BackdropTemplate"); btn.color:SetSize(12, 12); btn.color:SetPoint("LEFT", 4, 0); btn.color:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1}); btn.color:SetBackdropBorderColor(0,0,0,1)
                
                btn.color:SetScript("OnClick", function() 
                    local currentMapID = btn.mapID
                    
                    OpenPalettePicker(f, currentMapID, function(newColor) 
                        if btn.guid and PathmakerDB.routes[currentMapID] and PathmakerDB.routes[currentMapID][btn.guid] then 
                            PathmakerDB.routes[currentMapID][btn.guid].color = newColor; 
                            if addon.Routes and addon.Routes.NotifyRouteColorChanged then
                                addon.Routes:NotifyRouteColorChanged(btn.guid, currentMapID, newColor)
                            end
                            addon.MapFrame:UpdateRouteList(); 
                            addon.MapFrame:UpdateUIState(); 
                            if addon.UI then addon.UI:RefreshRendering() end 
                        end 
                    end, false, btn.guid, btn.color) 
                end)
                
                btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); btn.name:SetPoint("LEFT", 20, 0); btn.name:SetWidth(82); btn.name:SetJustifyH("LEFT")
                
                btn:SetScript("OnClick", function() 
                    if addon.selectedRouteGUID == btn.guid then 
                        addon.MapFrame:StopRouteCounters()
                        addon.selectedRouteGUID = nil 
                        addon.selectedRouteMapID = nil
                        addon.MapFrame:ResetFarmVisuals()
                    else 
                        addon.selectedRouteGUID = btn.guid 
                        addon.selectedRouteMapID = btn.mapID
                    end
                    addon.MapFrame:RefreshRouteSelectionVisuals()
                    addon.MapFrame:SyncRouteSelectionToOpenEditors()
                    addon.MapFrame:UpdateUIState(true)
                    if addon.UI then addon.UI:RefreshRendering() end 
                end)
                
                btn.del = CreateFrame("Button", nil, btn); btn.del:SetSize(16, 16); btn.del:SetPoint("RIGHT", -2, 0); btn.del.text = btn.del:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); btn.del.text:SetPoint("CENTER"); btn.del.text:SetText("X"); btn.del.text:SetTextColor(1, 1, 0) 
                
                btn.del:SetScript("OnClick", function() 
                    local currentMapID = btn.mapID

                    if btn.guid and PathmakerDB.routes[currentMapID] and PathmakerDB.routes[currentMapID][btn.guid] then 
                        local r = PathmakerDB.routes[currentMapID][btn.guid]; 
                        lastDeleted.mapID = currentMapID; 
                        lastDeleted.guid = btn.guid; 
                        lastDeleted.data = r; 
                        
                        if addon.selectedRouteGUID == btn.guid then 
                            addon.MapFrame:StopRouteCounters()
                            addon.selectedRouteGUID = nil 
                            addon.selectedRouteMapID = nil
                            addon.MapFrame:ResetFarmVisuals()
                        end
                        PathmakerDB.routes[currentMapID][btn.guid] = nil; 
                        addon.MapFrame:UpdateRouteList(); 
                        addon.MapFrame:UpdateUIState(); 
                        if addon.UI then addon.UI:RefreshRendering() end 
                    end 
                end)
                f.buttons[index] = btn
            end
            btn:SetPoint("TOPLEFT", 0, -((index-1) * 22)); btn.name:SetText(item.data.name or "Unnamed"); btn.guid = item.guid; btn.mapID = item.mapID; btn.routeName = item.data.name
            if item.data and item.data.color then btn.color:SetBackdropColor(unpack(item.data.color or {1,1,1,1})) else btn.color:SetBackdropColor(1,1,1,1) end
            if item.guid == addon.selectedRouteGUID then btn:SetBackdropColor(0.2, 0.4, 0.8, 0.4) else btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5) end; btn:Show()
        end
    end
    child:SetHeight(math.max(1, index * 22)); local maxScroll = math.max(0, (index * 22) - 90); f.slider:SetMinMaxValues(0, maxScroll); if f.slider:GetValue() > maxScroll then f.slider:SetValue(maxScroll) end

    -- Sync visually to the Options Panel Route Manager
    if addon.Options and type(addon.Options.RefreshRouteList) == "function" then
        addon.Options.RefreshRouteList()
    end
    if addon.Options and addon.Options.drawModePanel and addon.Options.drawModePanel:IsShown() and addon.Options.panel and addon.Options.panel.RefreshOptionsDrawMode then
        addon.Options.panel.RefreshOptionsDrawMode()
    end
    if addon.Planner and addon.Planner.panel and addon.Planner.panel.UpdateList then
        local plannerSearch = addon.Planner.panel.searchBox and addon.Planner.panel.searchBox:GetText() or ""
        addon.Planner.panel:UpdateList(plannerSearch)
    end
end

function addon.MapFrame:UpdateClampInsets(settings)
    if not self.frame then return end
    local s = settings or PathmakerDB.settings or {}
    
    -- Evaluate visibility of the top panels
    local topInset = 0
    if not s.hideZoneBar then topInset = topInset + 13 end
    if not s.hideHeaderBar then topInset = topInset + 15 end
    
    -- Evaluate visibility of the bottom panels
    local bottomInset = 0
    if not (s.hideRoutes and s.hideTacticalTools) then 
        bottomInset = bottomInset + 17 
    end
    if not s.hideQuickBar then 
        bottomInset = bottomInset + 18
    end
    
    -- 0 X values pull the map directly to the edge of the monitor securely
    self.frame:SetClampRectInsets(0, 0, topInset, -bottomInset)
end

-- Keep ownership of the native minimap separate from the route/navigation state.
-- Capture each takeover, so Edit Mode or another addon can move it between uses.
function addon.MapFrame:CaptureNativeMinimap()
    nativeMinimapState = { frames = {}, zoom = Minimap:GetZoom() }
    local function Capture(frame, depth)
        if not frame or not frame.GetFrameLevel or nativeMinimapState.frames[frame] then return end
        local name = string.lower(frame:GetName() or "")
        if string.find(name, "pathmaker", 1, true) then return end
        local state = {
            parent = frame:GetParent(), points = {}, width = frame:GetWidth(), height = frame:GetHeight(),
            scale = frame:GetScale(), alpha = frame:GetAlpha(), strata = frame:GetFrameStrata(),
            level = frame:GetFrameLevel(), mouse = frame:IsMouseEnabled(),
            shown = frame:IsShown(), movable = ReadOptionalObjectState(frame, "IsMovable"),
            mouseMotion = ReadOptionalObjectState(frame, "IsMouseMotionEnabled"),
            mouseClick = ReadOptionalObjectState(frame, "IsMouseClickEnabled"),
        }
        if frame.GetIgnoreParentAlpha then state.ignoreAlpha = frame:GetIgnoreParentAlpha()
        elseif frame.IsIgnoringParentAlpha then state.ignoreAlpha = frame:IsIgnoringParentAlpha() end
        if frame.GetMaskTexture then state.mask = frame:GetMaskTexture() end
        for i = 1, frame:GetNumPoints() do state.points[i] = { frame:GetPoint(i) } end
        nativeMinimapState.frames[frame] = state
        if depth > 0 then
            for _, child in ipairs({frame:GetChildren()}) do Capture(child, depth - 1) end
        end
    end
    Capture(MinimapCluster, 2)
    Capture(Minimap, 1)
    Capture(MinimapNorthTag, 0)
    Capture(MiniMapBattlefieldFrame, 0)
    Capture(QueueStatusMinimapButton, 0)
    nativeMinimapState.zoomControls = {}
    for _, control in pairs({MinimapZoomIn, MinimapZoomOut, Minimap.ZoomIn, Minimap.ZoomOut}) do
        nativeMinimapState.zoomControls[control] = control:IsShown()
    end
    originalParent = Minimap:GetParent()
    originalPoint = {Minimap:GetPoint()}
    if MinimapNorthTag then
        originalNorthTagParent = MinimapNorthTag:GetParent()
        originalNorthTagPoint = {MinimapNorthTag:GetPoint()}
    end
end

function addon.MapFrame:RestoreNativeMinimapState()
    if not nativeMinimapState then return end
    for frame, state in pairs(nativeMinimapState.frames) do
        frame:SetParent(state.parent)
        frame:ClearAllPoints()
        frame:SetSize(state.width, state.height)
        frame:SetScale(state.scale)
        for _, point in ipairs(state.points) do frame:SetPoint(unpack(point)) end
        frame:SetFrameStrata(state.strata)
        frame:SetAlpha(state.alpha)
        frame:EnableMouse(state.mouse)
        if state.movable ~= nil and frame.SetMovable then frame:SetMovable(state.movable) end
        if state.mouseMotion ~= nil and frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(state.mouseMotion) end
        if state.mouseClick ~= nil and frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(state.mouseClick) end
        if state.ignoreAlpha ~= nil then frame:SetIgnoreParentAlpha(state.ignoreAlpha) end
        if state.mask then frame:SetMaskTexture(state.mask) end
    end
    -- SetParent can adjust descendant levels: restore levels after all parents.
    for frame, state in pairs(nativeMinimapState.frames) do frame:SetFrameLevel(state.level) end
    for control, shown in pairs(nativeMinimapState.zoomControls) do
        if shown then control:Show() else control:Hide() end
    end
    suppressMinimapZoomSave = true
    Minimap:SetZoom(nativeMinimapState.zoom)
    suppressMinimapZoomSave = false
    for frame, state in pairs(nativeMinimapState.frames) do
        if state.shown then frame:Show() else frame:Hide() end
    end
    nativeMinimapState = nil
end

function addon.MapFrame:AnchorToolPanels(anchor)
    if self.managerFrame then
        self.managerFrame:ClearAllPoints()
        self.managerFrame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -5, 0)
    end
    if self.tacticalFrame then
        self.tacticalFrame:ClearAllPoints()
        self.tacticalFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 5, 0)
    end
end

local function PaintStandaloneControl(button)
    if button.isSettingsControl then PaintSettingsControl(button); return end
    local enabled = button:IsEnabled()
    if enabled and button.hovered then
        button:SetBackdropColor(0.3, 0.3, 0.3, 0.9)
    else
        button:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    end
    if enabled and button.ForceHighlight then
        button:SetBackdropBorderColor(1, 1, 1, 1)
    else
        button:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

local function StyleStandaloneControl(button)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintStandaloneControl(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = nil
        PaintStandaloneControl(self)
    end)
    button:SetScript("OnHide", function(self) self.hovered = nil end)
    return button
end

function addon.MapFrame:RefreshStandaloneControls()
    if self.controlsFrame then
        local alpha = EnsurePathmakerSettings().controlsAlpha
        self.controlsFrame:SetAlpha(alpha)
        if self.controlsOpacitySlider then self.controlsOpacitySlider:SetValue(alpha) end
        if self.controlsOpacityLabel then
            self.controlsOpacityLabel:SetText(string.format("Interface Opacity  %d%%", math.floor(alpha * 100 + 0.5)))
        end
    end
    local active = {
        btnRoutes = self.managerFrame and self.managerFrame:IsShown(),
        btnTools = self.tacticalFrame and self.tacticalFrame:IsShown(),
    }
    for _, entry in ipairs(self.standaloneButtons or {}) do
        local source = self[entry.source]
        if source then
            if source:IsEnabled() then entry.button:Enable() else entry.button:Disable() end
            if source.text then
                local r, g, b = source.text:GetTextColor()
                entry.button.text:SetTextColor(r, g, b)
            end
        end
        entry.button.ForceHighlight = active[entry.source] == true
        PaintStandaloneControl(entry.button)
    end
    if self.standaloneRecord then
        self.standaloneRecord.text:SetText(addon.Routes and addon.Routes.isRecording and "Stop" or "New")
    end
    for _, panel in pairs({self.managerFrame, self.tacticalFrame, self.timersFrame, self.nodeFilterFrame}) do
        panel:SetAlpha(1)
    end
end

function addon.MapFrame:ShowStandaloneControls()
    if not self.controlsFrame then
        local f = CreateFrame("Frame", "PathmakerControls", UIParent, "BackdropTemplate")
        self.controlsFrame = f
        f:SetSize(216, 164)
        f:SetFrameStrata("MEDIUM")
        f:SetClampedToScreen(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        local saved = EnsurePathmakerSettings().controlsPosition
        if saved and saved.point then
            f:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
        else
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        end
        f:SetScript("OnDragStart", function()
            if not IsShiftKeyDown() then return end
            f.isMoving = true
            f:StartMoving()
        end)
        local function StopMoving()
            if not f.isMoving then return end
            f.isMoving = nil
            f:StopMovingOrSizing()
            local point, _, relativePoint, x, y = f:GetPoint()
            EnsurePathmakerSettings().controlsPosition = {point=point, relativePoint=relativePoint, x=x, y=y}
        end
        f:SetScript("OnDragStop", StopMoving)
        f:SetScript("OnHide", StopMoving)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 7, -7)
        title:SetText("PathMaker Controls")
        title:SetFont(STANDARD_TEXT_FONT, 10)

        local close = StyleCloseButton(CreateMinimalButton(f, "X", 16, 16))
        close:SetPoint("TOPRIGHT", -5, -4)
        close:SetScript("OnClick", function() f:Hide() end)
        local dragHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dragHint:SetPoint("RIGHT", close, "LEFT", -4, 0)
        dragHint:SetFont(STANDARD_TEXT_FONT, 9)
        dragHint:SetText("Shift+Drag")
        dragHint:SetTextColor(0.5, 0.5, 0.5)

        local opacity = CreateCustomSlider(f, 202, 18, 0, 1, EnsurePathmakerSettings().controlsAlpha, function(value)
            EnsurePathmakerSettings().controlsAlpha = value
            f:SetAlpha(value)
            self.controlsOpacityLabel:SetText(string.format("Interface Opacity  %d%%", math.floor(value * 100 + 0.5)))
        end)
        self.controlsOpacitySlider = opacity
        opacity:SetPoint("TOPLEFT", 7, -40)
        self.controlsOpacityLabel = opacity:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        self.controlsOpacityLabel:SetPoint("CENTER")

        local actions = {
            {"Routes", "btnRoutes"}, {"Tools", "btnTools"}, {"Settings", "btnSettings"},
            {"New", "btnQuickRec"}, {"Arrow", "btnQuickNav"}, {"Farm", "btnQuickFarm"},
            {"%", "btnQuickGhost"},
        }
        self.standaloneButtons = {}
        for i, action in ipairs(actions) do
            local button = StyleStandaloneControl(CreateMinimalButton(f, action[1], 66, 20))
            button.isSettingsControl = action[2] == "btnSettings"
            -- Fade the window chrome, but keep actions readable at every opacity.
            button:SetIgnoreParentAlpha(true)
            button:SetPoint("TOPLEFT", 7 + ((i - 1) % 3) * 68, -66 - math.floor((i - 1) / 3) * 23)
            local source = action[2]
            if type(source) == "string" then
                table.insert(self.standaloneButtons, {button=button, source=source})
                button:SetScript("OnClick", function()
                    self:UpdateUIState()
                    local original = self[source]
                    if original and original:IsEnabled() then original:GetScript("OnClick")(original, "LeftButton") end
                    self:RefreshStandaloneControls()
                end)
                if source == "btnQuickRec" then self.standaloneRecord = button end
            else
                button:SetScript("OnClick", source)
            end
        end
        local restore = StyleStandaloneControl(CreateMinimalButton(f, "Use PathMaker Minimap", 202, 20))
        restore:SetIgnoreParentAlpha(true)
        restore:SetPoint("BOTTOM", 0, 6)
        restore:SetScript("OnClick", function() self:SetMinimapEnabled(true) end)
    end
    self:AnchorToolPanels(self.controlsFrame)
    self.controlsFrame:Show()
    self:RefreshStandaloneControls()
end

function addon.MapFrame:ResetStandaloneControls()
    local settings = EnsurePathmakerSettings()
    settings.controlsPosition = nil
    settings.controlsAlpha = 1
    if self.controlsFrame then
        local f = self.controlsFrame
        f.isMoving = nil
        f:StopMovingOrSizing()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
        self:RefreshStandaloneControls()
    end
    if PathmakerDB.isEnabled then self:ShowStandaloneControls() end
end

function addon.MapFrame:SetMinimapEnabled(enabled)
    if InCombatLockdown and InCombatLockdown() then
        addon:PrintMessage("disableMsgError", "|cffffff00PathMaker:|r Change minimap modes after combat.")
        return
    end
    local settings = EnsurePathmakerSettings()
    settings.usePathmakerMinimap = enabled == true
    self.tempSettings.usePathmakerMinimap = settings.usePathmakerMinimap
    if PathmakerDB.isEnabled then self:Enable() end
    if addon.Options and addon.Options.RefreshSettingsUI then addon.Options:RefreshSettingsUI() end
end

function addon.MapFrame:EnableNativeMinimapFeatures(settings, showControls)
    local s = settings or EnsurePathmakerSettings()
    if PathmakerDB then PathmakerDB.isEnabled = true end

    if showControls ~= false then self:ShowStandaloneControls() end
    for _, event in ipairs({"ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD"}) do
        self.frame:RegisterEvent(event)
    end

    if addon.UI and addon.UI.Initialize then addon.UI:Initialize() end
    local routeCanvas = _G["PathmakerCanvas"]
    if routeCanvas and Minimap then
        if routeCanvas:GetParent() ~= Minimap then routeCanvas:SetParent(Minimap) end
        routeCanvas:ClearAllPoints()
        routeCanvas:SetAllPoints(Minimap)
        routeCanvas:SetScale(1)
        routeCanvas:SetAlpha(1)
        routeCanvas:SetFrameStrata(Minimap:GetFrameStrata())
        routeCanvas:SetFrameLevel(Minimap:GetFrameLevel() + 1)
        routeCanvas:Show()
    end

    local nodeOverlay = _G["PathmakerHeatmapMini"]
    if nodeOverlay and Minimap then
        local overlayParent = routeCanvas or Minimap
        if nodeOverlay:GetParent() ~= overlayParent then nodeOverlay:SetParent(overlayParent) end
        nodeOverlay:ClearAllPoints()
        nodeOverlay:SetAllPoints(overlayParent)
        nodeOverlay:SetScale(1)
        nodeOverlay:SetAlpha(1)
        nodeOverlay:SetFrameStrata(Minimap:GetFrameStrata())
        nodeOverlay:SetFrameLevel(overlayParent:GetFrameLevel() + 50)
        nodeOverlay:Show()
    end

    if s.nodeFilterOpen then
        if not self.nodeFilterFrame then self:CreateNodeFilterFrame() end
        self.nodeFilterFrame:Show()
        self:UpdateNodeFilterList()
    end

    self:UpdateRouteList()
    self:UpdateUIState()
    if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
    if addon.Heatmap then
        addon.Heatmap.minimapNodesDirty = true
        if addon.Heatmap.ForceUpdate then addon.Heatmap:ForceUpdate()
        elseif addon.Heatmap.UpdateMinimap then addon.Heatmap:UpdateMinimap(0) end
    end
end

function addon.MapFrame:Toggle()
    -- 1. If the frame doesn't exist yet, try all standard ways to build it
    if not self.frame then
        if type(self.Initialize) == "function" then self:Initialize() end
        if type(self.Init) == "function" then self:Init() end
        if type(self.Create) == "function" then self:Create() end
        if type(self.Setup) == "function" then self:Setup() end
        
        -- Also check if the UI module is responsible for building it
        if not self.frame and addon.UI and type(addon.UI.Initialize) == "function" then
            addon.UI:Initialize()
        end
        if not self.frame and type(addon.Initialize) == "function" then
            addon:Initialize()
        end
    end
    
    -- 2. If it STILL doesn't exist, stop right here so we don't crash
    if not self.frame then
        addon:PrintMessage("disableMsgError", "|cFFFF0000PathMaker:|r MapFrame is still missing. An error likely occurred during login that stopped it from building.")
        addon:PrintMessage("disableMsgError", "|cFFFFFF00Tip:|r Type /console scriptErrors 1 and /reload to see if there are any other errors breaking the addon.")
        return
    end

    -- 3. Now we are 100% sure self.frame exists, so we can toggle it safely
    if PathmakerDB and PathmakerDB.isEnabled then
        self:Disable()
    else
        self:Enable()
    end
end

function addon.MapFrame:Enable(forFarm)
    if InCombatLockdown and InCombatLockdown() then
        addon:PrintMessage("disableMsgError", "|cffffff00PathMaker:|r Change minimap modes after combat.")
        return
    end
    if not self.frame then self:Create() end
    local settings = EnsurePathmakerSettings()
    if settings.usePathmakerMinimap == false and not forFarm then
        self:Disable(true)
        self:EnableNativeMinimapFeatures(settings, true)
        return
    end
    if not self.ownsMinimap then self:CaptureNativeMinimap() end
    self.ownsMinimap = true
    if self.controlsFrame then self.controlsFrame:Hide() end
    self:AnchorToolPanels(self.frame)
    SuppressNativeMinimapZoomControls()
    EnsureMinimapZoomHook()
    self:SeedReleasedMinimapButtons()
    
    if addon.isFarmMode then
        addon.isFarmMode = false
        SetFarmMinimapZoomLocked(false)
        self:ResetFarmVisuals()
        RestoreFarmMinimapChildren()
        self:ResetFarmOverlayTransform(_G["PathmakerCanvas"])
        self:ResetFarmOverlayTransform(_G["PathmakerHeatmapMini"])
        RestorePathmakerMinimapToFrame(self.frame)
        if self.farmFrame then self.farmFrame:Hide() end
    end

    if not originalParent then
        local curr = Minimap:GetParent()
        if curr ~= self.frame and curr ~= self.farmFrame then
            originalParent = curr
            local p, r, rp, x, y = Minimap:GetPoint()
            originalPoint = { p, r, rp, x, y }
            
            if MinimapNorthTag then
                 originalNorthTagParent = MinimapNorthTag:GetParent()
                 local np, nr, nrp, nx, ny = MinimapNorthTag:GetPoint()
                 originalNorthTagPoint = { np, nr, nrp, nx, ny }
            end
        end
    end
    
    local currentRot = GetCVar("rotateMinimap")
    if not PathmakerDB.originalRotate then
        PathmakerDB.originalRotate = currentRot
    end
    
    if currentRot == "1" then
        SetCVar("rotateMinimap", "0")
    end

    if PathmakerDB and PathmakerDB.position and PathmakerDB.position.point then
        self.frame:ClearAllPoints()
        self.frame:SetPoint(PathmakerDB.position.point, UIParent, PathmakerDB.position.relativePoint, PathmakerDB.position.x, PathmakerDB.position.y)
        hasInitializedPosition = true
    elseif not hasInitializedPosition then
        local mx = Minimap:GetLeft()
        local my = Minimap:GetTop()
        if mx and my then
            self.frame:ClearAllPoints()
            self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mx, my)
        end
        hasInitializedPosition = true
    end

    self.frame:RegisterEvent("ZONE_CHANGED")
    self.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.frame:RegisterEvent("ZONE_CHANGED_INDOORS")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    
    if self.trackingButton then self.trackingButton:EnableEvents() end
    if self.mailButton then self.mailButton:EnableEvents() end
    if self.pvpButton then self.pvpButton:EnableEvents() end
    addon:ToggleMailEvents(true) 

    self.frame:Show()
    if settings.nodeFilterOpen and not addon.isFarmMode then
        if not self.nodeFilterFrame then self:CreateNodeFilterFrame() end
        self.nodeFilterFrame:Show()
        self:UpdateNodeFilterList()
    end
    if addon.UI and addon.UI.Initialize then addon.UI:Initialize() end
    
    if _G["PathmakerCanvas"] then _G["PathmakerCanvas"]:Show() end
    if _G["PathmakerHeatmapMini"] then _G["PathmakerHeatmapMini"]:Show() end
    
    RestorePathmakerMinimapToFrame(self.frame)
    SetRememberedMinimapZoom(settings.minimapZoom)
    
    if _G["PathmakerCanvas"] then
        _G["PathmakerCanvas"]:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    end
    if _G["PathmakerHeatmapMini"] then
        _G["PathmakerHeatmapMini"]:SetFrameLevel(Minimap:GetFrameLevel() + 50)
    end
    
    -- Load saved settings for Shape and Alpha before applying mask
    if settings then
        addon.useSquareMap = settings.useSquareMap
        if settings.farmAlpha ~= nil then
            addon.farmAlpha = NormalizeFarmAlphaValue(settings.farmAlpha, 0.6)
            settings.farmAlpha = addon.farmAlpha
        end
    end
    
    self:ApplyMinimapShape(addon.useSquareMap)
    
    Minimap:Show()
    self.inputBlocker:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    
    if self.NorthTagFrame then
        self.NorthTagFrame:SetParent(self.frame) 
        self.NorthTagFrame:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        self.NorthTagFrame:ClearAllPoints()
        self.NorthTagFrame:SetPoint("TOP", self.frame, "TOP", 0, -5) 
        self.NorthTagFrame:Show()
    end
    
    if PathmakerDB then PathmakerDB.isEnabled = true end

    ManageOverlays(true)
    
    if self.trackingButton then
        self.trackingButton:SetParent(self.frame)
        self.trackingButton:ClearAllPoints()
        self.trackingButton:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 5, -5)
        self.trackingButton:SetFrameStrata("MEDIUM")
        self.trackingButton:SetFrameLevel(20)
        self.trackingButton:UpdateState()
    end

    if self.lfgButton then
        self.lfgButton:SetParent(self.frame)
        self.lfgButton:SetFrameStrata("MEDIUM")
        self.lfgButton:SetFrameLevel(20)
        self.lfgButton:UpdateState()
    end

    if self.pvpButton then
        self.pvpButton:SetParent(self.frame)
        self.pvpButton:SetFrameStrata("MEDIUM")
        self.pvpButton:SetFrameLevel(20)
        self.pvpButton:UpdateState()
    end

    if PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.minimapScale then
         self.frame:SetScale(PathmakerDB.settings.minimapScale)
    end

    self:LayoutMinimapButtons() 

    self:UpdateRouteList()
    self:UpdateUIState()
    self:UpdateClampInsets()
    
    if addon.UI and addon.UI.RefreshRendering then
        addon.UI:RefreshRendering()
    end
    
    if self.ZoneText then
        local zone = GetZoneText() or ""
        self.ZoneText:SetText(zone)
    end
    
    ForceMinimapMouseRestore()
    C_Timer.After(0.1, function()
        if addon.MapFrame.frame:IsShown() and not addon.isFarmMode then
            ForceMinimapMouseRestore()
        end
    end)
end

local function RestoreMinimapButtons()
    local children = {Minimap:GetChildren()}
    if addon.MapFrame and addon.MapFrame.frame then
        for _, child in ipairs({addon.MapFrame.frame:GetChildren()}) do table.insert(children, child) end
    end
    
    for _, child in ipairs(children) do
        local name = child:GetName()
        local angle = child.pmNativeAngle
        if not angle and name and PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.buttonAngles then
            angle = PathmakerDB.settings.buttonAngles[name]
        end
        
        local lowerName = string.lower(name or "")
        local isButton = string.find(lowerName, "libdbicon") or 
                         string.find(lowerName, "button") or 
                         string.find(lowerName, "eye") or 
                         string.find(lowerName, "event") or 
                         string.find(lowerName, "activity")
        
        if (isButton or child.pmManagedByPathmaker) and not string.find(lowerName, "pathmaker") and name ~= "GameTimeFrame" then
            if child.pmManagedByPathmaker then
                child:SetParent(child.pmOriginalParent or Minimap)
            end
            child:SetAlpha(1)
            if child.EnableMouse then child:EnableMouse(true) end
            child:SetFrameStrata("MEDIUM")
            child:SetFrameLevel(5)
        end

        if angle and child.pmHooked then
            local R = 80 -- Standard classic circular minimap radius
            
            child.pmIsUpdating = true
            child:ClearAllPoints()
            child:SetPoint("CENTER", Minimap, "CENTER", R * math.cos(angle), R * math.sin(angle))
            child.pmIsUpdating = false
            
            child.pmNativeAngle = nil
            child.pmLastX = nil
            child.pmLastY = nil
            child.pmManagedByPathmaker = nil
            child.pmOriginalParent = nil
        end
    end
end

function addon.MapFrame:Disable(keepFeatures)
    if InCombatLockdown and InCombatLockdown() then
        addon:PrintMessage("disableMsgError", "|cffffff00PathMaker:|r Change minimap modes after combat.")
        return
    end
    if not self.frame then return end
    
    if not keepFeatures and addon.Routes and addon.Routes.isRecording then
        addon.Routes:StopRecording()
    end
    if not keepFeatures then addon.selectedRouteGUID = nil end
    
    if not keepFeatures and addon.Navigation then
        addon.Navigation:HideArrow() 
        addon.drawConfig.navEnabled = false
    end
    if not keepFeatures then addon.drawConfig.ghostView = false end
    if addon.isFarmMode then
        self:ResetFarmVisuals()
        self:ResetFarmOverlayTransform(_G["PathmakerCanvas"])
        self:ResetFarmOverlayTransform(_G["PathmakerHeatmapMini"])
    end
    addon.isFarmMode = false
    if self.ownsMinimap then
        SetFarmMinimapZoomLocked(false)
        RestoreFarmMinimapChildren()
    end
    
    if not keepFeatures and self.settingsFrame then self.settingsFrame:Hide() end
    if self.controlsFrame then self.controlsFrame:Hide() end
    if self.inputBlocker then self.inputBlocker:Hide() end
    if self.farmFrame then self.farmFrame:Hide() end

    self.frame:UnregisterAllEvents()
    if self.trackingButton then self.trackingButton:DisableEvents() end
    if self.mailButton then self.mailButton:DisableEvents() end
    if self.pvpButton then self.pvpButton:DisableEvents() end
    addon:ToggleMailEvents(false) 

    self.frame:Hide()
    if self.managerFrame then self.managerFrame:Hide() end
    if self.tacticalFrame then self.tacticalFrame:Hide() end
    if self.timersFrame then self.timersFrame:Hide() end
    if self.nodeFilterFrame then self.nodeFilterFrame:Hide() end
    if addon.PaletteFrame then addon.PaletteFrame:Hide() end
    
    if self.ZoneText then self.ZoneText:Hide() end
    
    if _G["PathmakerCanvas"] then _G["PathmakerCanvas"]:Hide() end
    if _G["PathmakerHeatmapMini"] then _G["PathmakerHeatmapMini"]:Hide() end
    
    if self.ownsMinimap then
        self.ownsMinimap = false
        local restoreParent = originalParent or MinimapCluster
    
        Minimap:SetParent(restoreParent)
        Minimap:SetFrameStrata("LOW") 
        Minimap:SetFrameLevel(1)
    
        -- Cleanup and perfectly restore the native UI frames we commandeered 
        if MiniMapBattlefieldFrame then
            MiniMapBattlefieldFrame:SetParent(Minimap)
            MiniMapBattlefieldFrame:ClearAllPoints()
            local regions = {MiniMapBattlefieldFrame:GetRegions()}
            for _, region in ipairs(regions) do
                if region:IsObjectType("Texture") then region:SetAlpha(1) end
            end
            for _, child in ipairs({MiniMapBattlefieldFrame:GetChildren()}) do
                if child:IsObjectType("Texture") then child:SetAlpha(1) end
            end
            if MiniMapBattlefieldIcon then MiniMapBattlefieldIcon:SetAlpha(1) end
            if MiniMapBattlefieldBorder then MiniMapBattlefieldBorder:SetAlpha(1) end
        end
    
        if QueueStatusMinimapButton then
            QueueStatusMinimapButton:SetParent(Minimap)
            QueueStatusMinimapButton:ClearAllPoints()
            local regions = {QueueStatusMinimapButton:GetRegions()}
            for _, region in ipairs(regions) do
                if region:IsObjectType("Texture") then region:SetAlpha(1) end
            end
            for _, child in ipairs({QueueStatusMinimapButton:GetChildren()}) do
                if child:IsObjectType("Texture") then child:SetAlpha(1) end
            end
            if QueueStatusMinimapButtonIcon then QueueStatusMinimapButtonIcon:SetAlpha(1) end
            if QueueStatusMinimapButtonBorder then QueueStatusMinimapButtonBorder:SetAlpha(1) end
        end
    
        if _G["PathmakerHeatmapMini"] then
            _G["PathmakerHeatmapMini"]:SetFrameLevel(Minimap:GetFrameLevel() + 50)
        end
    
        ForceMinimapMouseRestore()
    
        Minimap:SetMovable(false) 
    
        Minimap:ClearAllPoints()
        if originalParent and originalPoint[1] then
            Minimap:SetPoint(originalPoint[1], originalPoint[2], originalPoint[3], originalPoint[4], originalPoint[5])
        else
            Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
        end
    
        if self.NorthTagFrame then
            self.NorthTagFrame:Hide()
        end
    
        RestoreMinimapButtons()
    
        ApplyMinimapShapeMask(false)
        Minimap:SetAlpha(1)
        SetRememberedMinimapZoom(EnsurePathmakerSettings().minimapZoom)
        Minimap:Show() 
    
        if PathmakerDB.originalRotate then
            SetCVar("rotateMinimap", PathmakerDB.originalRotate)
            PathmakerDB.originalRotate = nil
        end

        ManageOverlays(false)
    
        if MinimapNorthTag and originalNorthTagParent then
            MinimapNorthTag:SetParent(originalNorthTagParent)
            MinimapNorthTag:ClearAllPoints()
            if originalNorthTagPoint[1] then
                MinimapNorthTag:SetPoint(originalNorthTagPoint[1], originalNorthTagPoint[2], originalNorthTagPoint[3], originalNorthTagPoint[4], originalNorthTagPoint[5])
            end
            MinimapNorthTag:Show()
        end
        self:RestoreNativeMinimapState()
        -- Reparenting and restoring the mask/size can leave the native terrain
        -- provider stale. Refresh only after the captured state is restored.
        RefreshRestoredNativeMinimap()
    end
    if PathmakerDB then PathmakerDB.isEnabled = keepFeatures == true end
    
    self:UpdateUIState()
    
    -- Native input flags were restored from the ownership snapshot above. Do
    -- not force-enable them afterward: Retail's MinimapCluster controls these
    -- flags and changing them can break the standard minimap interaction layer.
end
-- ============================================================================
-- AUTO-RESTORE STATE ON LOGIN / RELOAD
-- Add this to the very bottom of MapFrame.lua
-- ============================================================================
local startupCheck = CreateFrame("Frame")
local hasStarted = false
startupCheck:RegisterEvent("PLAYER_ENTERING_WORLD")
startupCheck:SetScript("OnEvent", function()
    -- Only run this once per session/reload, not every time you zone
    if hasStarted then return end
    hasStarted = true
    
    -- Wait a little longer (0.5s) for UI and variables to completely settle
    C_Timer.After(0.5, function()
        if PathmakerDB and PathmakerDB.isEnabled then
            
            -- 1. Ensure the frame is built using all possible initializers
            if addon.MapFrame and not addon.MapFrame.frame then
                if type(addon.MapFrame.Initialize) == "function" then addon.MapFrame:Initialize() end
                if type(addon.MapFrame.Init) == "function" then addon.MapFrame:Init() end
                if type(addon.MapFrame.Create) == "function" then addon.MapFrame:Create() end
                if type(addon.MapFrame.Setup) == "function" then addon.MapFrame:Setup() end
                
                if not addon.MapFrame.frame and addon.UI and type(addon.UI.Initialize) == "function" then
                    addon.UI:Initialize()
                end
                if not addon.MapFrame.frame and type(addon.Initialize) == "function" then
                    addon:Initialize()
                end
            end
            
            -- 2. Force the map to enable and show itself
            if addon.MapFrame and addon.MapFrame.frame and type(addon.MapFrame.Enable) == "function" then
                addon.MapFrame:Enable()
            end
            
        end
    end)
end)
