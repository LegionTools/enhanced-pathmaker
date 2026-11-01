-- ============================================================================
-- PATHMAKER OPTIONS, UI & DATABASE MANAGEMENT
-- ============================================================================
local addonName, addon = ...
if type(addon) ~= "table" then addon = _G["PathMaker"] or _G["Pathmaker"] or {} end
_G["PathMaker"] = _G["PathMaker"] or addon
_G["Pathmaker"] = _G["Pathmaker"] or addon
addon.Options = addon.Options or {}

local function T(text)
    return addon.Translate and addon:Translate(text) or text
end

local CLOCK_POSITIONS = {
    { key = "DEFAULT", label = "Clock: Default" },
    { key = "LEFT_BOTTOM", label = "Clock: Left" },
    { key = "BOTTOM", label = "Clock: Middle" },
    { key = "RIGHT_BOTTOM", label = "Clock: Right" },
}

local FARM_PLAYER_MARKER_STYLES = {
    { key = "ARROW_HEAD", label = "Marker: Nav Arrow" },
    { key = "DOT", label = "Marker: Dot" },
    { key = "NATIVE_ARROW", label = "Marker: Native Arrow" },
}

local NAV_ARROW_STYLES = {
    { key = "2D", label = "Style: 2D" },
    { key = "3D", label = "Style: 3D" },
}

local NAV_ARROW_DESIGNS = {
    { key = "BLADE", label = "Design: Runeblade" },
    { key = "POINTER", label = "Design: Pointer" },
    { key = "FRAME", label = "Design: Framed" },
}

local MINIMAP_UI_OPTION_KEYS = {
    hideRoutes = true,
    hideHeaderBar = true,
    hideTracking = true,
    hideLFG = true,
    hideHeatmap = true,
    hideTacticalTools = true,
    hideQuickBar = true,
    hideZoneBar = true,
    hideClock = true,
    minimapLocked = true,
}

local function GetClockPositionLabel(position)
    for _, item in ipairs(CLOCK_POSITIONS) do
        if item.key == position then return item.label end
    end
    return CLOCK_POSITIONS[1].label
end

local function GetNextClockPosition(position)
    for i, item in ipairs(CLOCK_POSITIONS) do
        if item.key == position then
            return CLOCK_POSITIONS[(i % #CLOCK_POSITIONS) + 1].key
        end
    end
    return CLOCK_POSITIONS[2].key
end

local function GetFarmMarkerStyleLabel(style)
    for _, item in ipairs(FARM_PLAYER_MARKER_STYLES) do
        if item.key == style then return item.label end
    end
    return FARM_PLAYER_MARKER_STYLES[1].label
end

local function GetNextFarmMarkerStyle(style)
    for i, item in ipairs(FARM_PLAYER_MARKER_STYLES) do
        if item.key == style then
            return FARM_PLAYER_MARKER_STYLES[(i % #FARM_PLAYER_MARKER_STYLES) + 1].key
        end
    end
    return FARM_PLAYER_MARKER_STYLES[2].key
end

local function GetNavArrowStyleLabel(style)
    for _, item in ipairs(NAV_ARROW_STYLES) do
        if item.key == style then return item.label end
    end
    return NAV_ARROW_STYLES[1].label
end

local function GetNextNavArrowStyle(style)
    for i, item in ipairs(NAV_ARROW_STYLES) do
        if item.key == style then
            return NAV_ARROW_STYLES[(i % #NAV_ARROW_STYLES) + 1].key
        end
    end
    return NAV_ARROW_STYLES[1].key
end

local function GetNavArrowDesignLabel(design)
    for _, item in ipairs(NAV_ARROW_DESIGNS) do
        if item.key == design then return item.label end
    end
    return NAV_ARROW_DESIGNS[1].label
end

local function GetNextNavArrowDesign(design)
    for i, item in ipairs(NAV_ARROW_DESIGNS) do
        if item.key == design then
            return NAV_ARROW_DESIGNS[(i % #NAV_ARROW_DESIGNS) + 1].key
        end
    end
    return NAV_ARROW_DESIGNS[1].key
end

local function NormalizeFarmAlphaValue(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 0.6 end
    value = math.max(0, math.min(1, value))
    if value > 0.995 then return 1 end
    if value < 0.005 then return 0 end
    return value
end

local function SetOptionControlDisabled(control, disabled)
    if not control then return end
    if control.Disable and control.Enable then
        if disabled then control:Disable() else control:Enable() end
    elseif control.EnableMouse then
        control:EnableMouse(not disabled)
    end
    if control.SetAlpha then control:SetAlpha(disabled and 0.35 or 1) end
    if control.text and control.text.SetTextColor then
        if disabled then control.text:SetTextColor(0.45, 0.45, 0.45)
        else control.text:SetTextColor(1, 1, 1) end
    end
end

local function SetOptionTextDisabled(fontString, disabled, r, g, b)
    if not fontString or not fontString.SetTextColor then return end
    if disabled then
        fontString:SetTextColor(0.45, 0.45, 0.45)
    else
        fontString:SetTextColor(r or 1, g or 1, b or 1)
    end
end

local function EnsureOptionsSettings()
    PathmakerDB = PathmakerDB or {}
    PathmakerDB.settings = PathmakerDB.settings or {}
    local s = PathmakerDB.settings
    if s.usePathmakerMinimap == nil then s.usePathmakerMinimap = true end
    if not addon.Localization or not addon.Localization:IsSupported(s.language) then s.language = "enUS" end
    s.minimapScale = math.max(0.5, math.min(2.5, tonumber(s.minimapScale) or 1.0))
    s.worldMapNodeIconSize = math.max(6, math.min(40, tonumber(s.worldMapNodeIconSize) or 13))
    s.worldMapNodeIconOpacity = math.max(0, math.min(1, tonumber(s.worldMapNodeIconOpacity) or 1))
    if s.worldMapShowHerbalism == nil then s.worldMapShowHerbalism = true end
    if s.worldMapShowMining == nil then s.worldMapShowMining = true end
    if s.worldMapShowTreasure == nil then s.worldMapShowTreasure = true end
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
    if s.navArrowStyle ~= "2D" and s.navArrowStyle ~= "3D" then s.navArrowStyle = "3D" end
    if s.navArrowDesign ~= "BLADE" and s.navArrowDesign ~= "POINTER" and s.navArrowDesign ~= "FRAME" then s.navArrowDesign = "BLADE" end
    if s.navArrowColorless == nil then s.navArrowColorless = false end
    if s.navArrowLocked == nil then s.navArrowLocked = false end
    if s.navArrowClickThrough == nil then s.navArrowClickThrough = false end
    s.navArrowColorOuter = nil
    s.navArrowColorMiddle = nil
    s.navArrowColorGem = nil
    if s.useSquareMap == nil then s.useSquareMap = true end
    if s.minimapUseFullEdges == nil then s.minimapUseFullEdges = false end
    if not s.clockPosition then s.clockPosition = "DEFAULT" end
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
    return s
end

-- ============================================================================
-- TWO-WAY SYNCHRONIZATION RECEIVER
-- Allows MapFrame.lua to force the Blizzard Options panel to update visually
-- ============================================================================
addon.Options.checkboxes = addon.Options.checkboxes or {}

function addon.Options:RefreshSettingsUI()
    if self._refreshingSettingsUI then return end
    self._refreshingSettingsUI = true

    local s = EnsureOptionsSettings()
    addon.useSquareMap = s.useSquareMap

    if self.languageBtn and self.languageBtn.text and addon.Localization then
        self.languageBtn.text:SetText(T("Language") .. ": " .. addon.Localization:GetLanguageName(s.language))
    end
    
    -- Sync Sliders and their visual text labels
    if self.farmAlphaSlider then 
        local farmAlpha = NormalizeFarmAlphaValue(s.farmAlpha, 0.6)
        self.farmAlphaSlider:SetValue(farmAlpha)
        if self.farmAlphaLabelVal then
            self.farmAlphaLabelVal:SetText(string.format("%d%%", math.floor(farmAlpha * 100 + 0.5)))
        end
    end
    
    if self.alphaSlider then 
        local alpha = s.alpha or 1.0
        self.alphaSlider:SetValue(alpha) 
        if self.alphaLabelVal then
            if alpha <= 0.0 then
                self.alphaLabelVal:SetText("Hidden (0%)")
                self.alphaLabelVal:SetTextColor(1, 0, 0)
            else
                self.alphaLabelVal:SetText(string.format("%d%%", alpha * 100))
                self.alphaLabelVal:SetTextColor(1, 1, 1)
            end
        end
    end
    
    if self.scaleSlider then 
        local scale = s.minimapScale or 1.0
        self.scaleSlider:SetValue(scale) 
        if self.sizeLabelVal then
            self.sizeLabelVal:SetText(string.format("%d%%", math.floor(scale * 100 + 0.5)))
        end
    end

    if self.farmCircleAlphaSlider then
        local circleAlpha = s.farmCircleAlpha or 0.75
        self.farmCircleAlphaSlider:SetValue(circleAlpha)
        if self.farmCircleAlphaLabelVal then
            self.farmCircleAlphaLabelVal:SetText(string.format("%d%%", math.floor(circleAlpha * 100 + 0.5)))
        end
    end

    if self.farmCircleSizeSlider then
        local circleSize = s.farmCircleSize or 420
        self.farmCircleSizeSlider:SetValue(circleSize)
        if self.farmCircleSizeLabelVal then
            self.farmCircleSizeLabelVal:SetText(string.format("%d px", math.floor(circleSize + 0.5)))
        end
    end

    -- Sync Map Shape Toggle
    if self.mapShapeBtn and self.mapShapeBtn.text then
        if addon.useSquareMap then
            self.mapShapeBtn.text:SetText("Square Map")
        else
            self.mapShapeBtn.text:SetText("Circle Map")
        end
    end

    if self.clockPositionBtn and self.clockPositionBtn.text then
        self.clockPositionBtn.text:SetText(GetClockPositionLabel(s.clockPosition or "DEFAULT"))
    end

    if self.minimapEdgesBtn and self.minimapEdgesBtn.text then
        self.minimapEdgesBtn.text:SetText(s.minimapUseFullEdges and "Full Edges: On" or "Full Edges: Off")
    end

    if self.farmMarkerStyleBtn and self.farmMarkerStyleBtn.text then
        self.farmMarkerStyleBtn.text:SetText(GetFarmMarkerStyleLabel(s.farmPlayerMarkerStyle or "ARROW_HEAD"))
    end

    if self.farmMarkerSizeSlider then
        local markerSize = math.max(5, math.min(80, s.farmPlayerMarkerSize or 24))
        self.farmMarkerSizeSlider:SetValue(markerSize)
        if self.farmMarkerSizeLabelVal then
            self.farmMarkerSizeLabelVal:SetText(string.format("%d px", math.floor(markerSize + 0.5)))
        end
    end

    if self.activeRouteAlphaSlider then
        local routeAlpha = math.max(0, math.min(1, tonumber(s.activeRouteAlpha) or 1))
        self.activeRouteAlphaSlider:SetValue(routeAlpha)
        if self.activeRouteAlphaLabelVal then
            self.activeRouteAlphaLabelVal:SetText(string.format("%d%%", math.floor(routeAlpha * 100 + 0.5)))
        end
    end

    if self.navArrowWidthSlider then
        self.navArrowWidthSlider:SetValue(s.navArrowWidth)
        if self.navArrowWidthLabelVal then self.navArrowWidthLabelVal:SetText(string.format("%d px", math.floor(s.navArrowWidth + 0.5))) end
    end
    if self.navArrowLengthSlider then
        self.navArrowLengthSlider:SetValue(s.navArrowLength)
        if self.navArrowLengthLabelVal then self.navArrowLengthLabelVal:SetText(string.format("%d px", math.floor(s.navArrowLength + 0.5))) end
    end
    if self.navArrow3DTransformationSlider then
        self.navArrow3DTransformationSlider:SetValue(s.navArrow3DTransformation)
        if self.navArrow3DTransformationLabelVal then self.navArrow3DTransformationLabelVal:SetText(string.format("%d%%", math.floor((s.navArrow3DTransformation * 100) + 0.5))) end
    end
    if self.navArrow3DThicknessSlider then
        self.navArrow3DThicknessSlider:SetValue(s.navArrow3DThickness)
        if self.navArrow3DThicknessLabelVal then self.navArrow3DThicknessLabelVal:SetText(string.format("%d px", math.floor(s.navArrow3DThickness + 0.5))) end
    end
    if self.navArrowScaleSlider then
        self.navArrowScaleSlider:SetValue(s.navArrowScale)
        if self.navArrowScaleLabelVal then self.navArrowScaleLabelVal:SetText(string.format("%d%%", math.floor((s.navArrowScale * 100) + 0.5))) end
    end
    if self.navArrowStyleBtn and self.navArrowStyleBtn.text then
        self.navArrowStyleBtn.text:SetText(GetNavArrowStyleLabel(s.navArrowStyle))
    end
    if self.navArrowDesignBtn and self.navArrowDesignBtn.text then
        self.navArrowDesignBtn.text:SetText(GetNavArrowDesignLabel(s.navArrowDesign))
    end
    local thicknessDisabled = s.navArrowStyle ~= "3D"
    SetOptionControlDisabled(self.navArrow3DThicknessSlider, thicknessDisabled)
    SetOptionControlDisabled(self.navArrow3DThicknessLabelVal, thicknessDisabled)
    SetOptionTextDisabled(self.navArrow3DThicknessLabel, thicknessDisabled, 1, 0.82, 0)
    SetOptionTextDisabled(self.navArrow3DThicknessLabelVal, thicknessDisabled, 1, 1, 1)

    -- Sync Checkboxes strictly to their saved boolean states
    if self.checkboxes then
        for key, chk in pairs(self.checkboxes) do
            chk:SetChecked(s[key] == true)
        end
    end

    if self.worldMapNodeSizeSlider then
        self.worldMapNodeSizeSlider:SetValue(s.worldMapNodeIconSize)
        if self.worldMapNodeSizeLabelVal then
            self.worldMapNodeSizeLabelVal:SetText(string.format("%d px", math.floor(s.worldMapNodeIconSize + 0.5)))
        end
    end

    if self.worldMapNodeOpacitySlider then
        self.worldMapNodeOpacitySlider:SetValue(s.worldMapNodeIconOpacity)
        if self.worldMapNodeOpacityLabelVal then
            self.worldMapNodeOpacityLabelVal:SetText(string.format("%d%%", math.floor((s.worldMapNodeIconOpacity * 100) + 0.5)))
        end
    end

    if self.generalValueBoxes then
        for _, valueBox in ipairs(self.generalValueBoxes) do
            if valueBox.RefreshDisplay then valueBox:RefreshDisplay() end
        end
    end

    local minimapDisabled = addon.isFarmMode == true or s.usePathmakerMinimap == false
    SetOptionControlDisabled(self.alphaSlider, minimapDisabled)
    SetOptionControlDisabled(self.scaleSlider, minimapDisabled)
    SetOptionControlDisabled(self.alphaValueBox, minimapDisabled)
    SetOptionControlDisabled(self.sizeValueBox, minimapDisabled)
    SetOptionControlDisabled(self.mapShapeBtn, minimapDisabled)
    SetOptionControlDisabled(self.clockPositionBtn, minimapDisabled)
    SetOptionControlDisabled(self.minimapEdgesBtn, minimapDisabled)
    SetOptionTextDisabled(self.alphaLabel, minimapDisabled, 1, 0.82, 0)
    SetOptionTextDisabled(self.sizeLabel, minimapDisabled, 1, 0.82, 0)
    local alphaForColor = s.alpha or 1.0
    SetOptionTextDisabled(self.alphaLabelVal, minimapDisabled, 1, alphaForColor <= 0 and 0 or 1, alphaForColor <= 0 and 0 or 1)
    SetOptionTextDisabled(self.sizeLabelVal, minimapDisabled, 1, 1, 1)
    if self.checkboxes then
        for key in pairs(MINIMAP_UI_OPTION_KEYS) do
            SetOptionControlDisabled(self.checkboxes[key], minimapDisabled and (key ~= "hideHeatmap" or addon.isFarmMode == true))
        end
    end

    -- Refresh Route List if the tab is open
    if addon.Options.RefreshRouteList then
        addon.Options.RefreshRouteList()
    end

    self._refreshingSettingsUI = false
end

-- ----------------------------------------------------------------------------
-- UI HELPERS (Scroll Frame & Palette)
-- ----------------------------------------------------------------------------
local function CreateDarkScrollArea(parent, width, height, scrollStyle)
    local goldStyle = scrollStyle == true or scrollStyle == "gold"
    local minimalStyle = scrollStyle == "minimal"
    local pixelSnapped = goldStyle or minimalStyle
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:EnableMouse(true)
    sf:EnableMouseWheel(true)
    sf:SetSize(width, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width, height) 
    sf:SetScrollChild(content)
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("VERTICAL")
    slider:SetSize(goldStyle and 12 or 6, goldStyle and (height - 36) or height)
    slider:SetPoint("TOPLEFT", sf, "TOPRIGHT", goldStyle and 0 or 1, goldStyle and -18 or 0)
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = goldStyle and "Interface\\Buttons\\WHITE8x8" or nil,
        edgeSize = goldStyle and 1 or nil,
    })
    if minimalStyle then
        slider:SetBackdropColor(0.055, 0.055, 0.055, 1)
    else
        slider:SetBackdropColor(goldStyle and 0.035 or 0.1, goldStyle and 0.03 or 0.1, goldStyle and 0.02 or 0.1, 1)
    end
    if goldStyle then slider:SetBackdropBorderColor(0.55, 0.39, 0.06, 1) end
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    if thumb.SetSnapToPixelGrid then thumb:SetSnapToPixelGrid(true) end
    if thumb.SetTexelSnappingBias then thumb:SetTexelSnappingBias(0) end
    if minimalStyle then thumb:SetColorTexture(0.48, 0.48, 0.48, 1)
    else thumb:SetColorTexture(goldStyle and 0.68 or 0.4, goldStyle and 0.46 or 0.4, goldStyle and 0.04 or 0.4, 1) end
    thumb:SetSize(goldStyle and 10 or 6, goldStyle and 48 or 20)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    local function SnapToPhysicalPixel(value)
        if not pixelSnapped then return value end
        local scale = sf:GetEffectiveScale() or 1
        if scale <= 0 then scale = 1 end
        local minValue, maxValue = slider:GetMinMaxValues()
        local snapped = math.floor((value * scale) + 0.5) / scale
        if snapped < minValue then snapped = minValue end
        if snapped > maxValue then snapped = math.floor(maxValue * scale) / scale end
        return snapped
    end
    slider:SetScript("OnValueChanged", function(self, value)
        if pixelSnapped then value = SnapToPhysicalPixel(value) end
        sf:SetVerticalScroll(value)
    end)
    slider.ApplyScroll = function(self)
        local value = self:GetValue()
        if pixelSnapped then value = SnapToPhysicalPixel(value) end
        sf:SetVerticalScroll(value)
    end
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = slider:GetValue()
        local min, max = slider:GetMinMaxValues()
        local step = pixelSnapped and 32 or 30
        local new = cur - (delta * step)
        if new < min then new = min elseif new > max then new = max end
        slider:SetValue(new)
    end)

    if goldStyle then
        local function CreateScrollArrow(point, relativePoint, y, glyph)
            local button = CreateFrame("Button", nil, slider, "BackdropTemplate")
            button:SetSize(12, 14)
            button:SetPoint(point, slider, relativePoint, 0, y)
            button:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            button:SetBackdropColor(0.08, 0.06, 0.02, 1)
            button:SetBackdropBorderColor(0.55, 0.39, 0.06, 1)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("CENTER", 0, glyph == "UP" and -1 or 1)
            button.text:SetText(glyph == "UP" and "^" or "v")
            button.text:SetTextColor(1, 0.72, 0.08)
            button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.72, 0.08, 1) end)
            button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.55, 0.39, 0.06, 1) end)
            return button
        end

        local up = CreateScrollArrow("BOTTOM", "TOP", 4, "UP")
        local down = CreateScrollArrow("TOP", "BOTTOM", -4, "DOWN")
        up:SetScript("OnClick", function()
            local min = select(1, slider:GetMinMaxValues())
            slider:SetValue(math.max(min, slider:GetValue() - 32))
        end)
        down:SetScript("OnClick", function()
            local _, max = slider:GetMinMaxValues()
            slider:SetValue(math.min(max, slider:GetValue() + 32))
        end)
    end
    return sf, content, slider 
end

local function OpenPalettePicker(parent, mapID, callback, isSearchMode, anchor)
    local function PositionPalette(frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -5)
    end

    if addon.PaletteFrame then 
        if addon.PaletteFrame:IsShown() and addon.PaletteFrame.owner == anchor then
            addon.PaletteFrame:Hide() 
            return
        end
        addon.PaletteFrame:Show()
        addon.PaletteFrame:SetParent(parent) 
        PositionPalette(addon.PaletteFrame)
        addon.PaletteFrame:SetFrameStrata("TOOLTIP")
        addon.PaletteFrame:SetFrameLevel(1000)
        addon.PaletteFrame:EnableMouse(true)
        addon.PaletteFrame:SetAlpha(1)
        addon.PaletteFrame:SetBackdropColor(0.025, 0.025, 0.025, 1)
        addon.PaletteFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        addon.PaletteFrame.callback = callback
        addon.PaletteFrame.mapID = mapID
        addon.PaletteFrame.isSearchMode = isSearchMode
        addon.PaletteFrame.owner = anchor
        addon.PaletteFrame:Refresh()
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

    -- A foreground surface guarantees route-row text can never render through
    -- the picker, even if another panel uses unusually high frame levels.
    f.surface = f:CreateTexture(nil, "ARTWORK")
    f.surface:SetPoint("TOPLEFT", 1, -1)
    f.surface:SetPoint("BOTTOMRIGHT", -1, 1)
    f.surface:SetColorTexture(0.025, 0.025, 0.025, 1)
    
    local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    infoText:SetPoint("TOP", 0, -5)
    infoText:SetText("Route Color\nClick current to reset")
    infoText:SetJustifyH("CENTER")
    
    local closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", 0, 0)
    closeBtn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    closeBtn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    closeBtn:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
    closeBtn.text = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    closeBtn.text:SetPoint("CENTER")
    closeBtn.text:SetText("X")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.32, 0.05, 0.05, 1)
        self:SetBackdropBorderColor(1, 0.22, 0.22, 1)
        self.text:SetTextColor(1, 1, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        self:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
        self.text:SetTextColor(1, 1, 1)
    end)

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
    f.owner = anchor
    f.isSearchMode = isSearchMode
    f:Refresh()
    addon.PaletteFrame = f
end

-- ----------------------------------------------------------------------------
-- INTERNAL NODE REGISTRY
-- ----------------------------------------------------------------------------
addon.NodeRegistry = {
    Expansions = {
        ["Forever"]      = { id = "Forever", name = "WoW Forever Beta", addon = "PathMaker_Nodes" },
        ["Classic"]      = { id = "Classic", name = "Classic Era", addon = "PathMaker_Nodes" },
        ["TBC"]          = { id = "TBC", name = "The Burning Crusade", addon = "PathMaker_Nodes" },
        ["Wrath"]        = { id = "Wrath", name = "Wrath of the Lich King", addon = "PathMaker_Nodes" },
        ["Cataclysm"]    = { id = "Cataclysm", name = "Cataclysm", addon = "PathMaker_Nodes" },
        ["Mists"]        = { id = "Mists", name = "Mists of Pandaria", addon = "PathMaker_Nodes" },
        ["Draenor"]      = { id = "Draenor", name = "Warlords of Draenor", addon = "PathMaker_Nodes" },
        ["Legion"]       = { id = "Legion", name = "Legion", addon = "PathMaker_Nodes" },
        ["BFA"]          = { id = "BFA", name = "Battle for Azeroth", addon = "PathMaker_Nodes" },
        ["Shadowlands"]  = { id = "Shadowlands", name = "Shadowlands", addon = "PathMaker_Nodes" },
        ["Dragonflight"] = { id = "Dragonflight", name = "Dragonflight", addon = "PathMaker_Nodes" },
        ["TWW"]          = { id = "TWW", name = "The War Within", addon = "PathMaker_Nodes" },
        ["Midnight"]     = { id = "Midnight", name = "Midnight", addon = "PathMaker_Nodes" }
    }
}

-- ----------------------------------------------------------------------------
-- MASTER NODE LISTS (Restricted strictly to your custom list)
-- ----------------------------------------------------------------------------
local CLASSIC_HERBS = {
    "Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", 
    "Stranglekelp", "Bruiseweed", "Wild Steelbloom", "Kingsblood", 
    "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker", "Wintersbite", 
    "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", 
    "Ghost Mushroom", "Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", 
    "Plaguebloom", "Icecap", "Black Lotus"
}

local CLASSIC_MINING = {
    "Copper Vein", "Tin Vein", "Silver Vein", "Iron Deposit", 
    "Gold Vein", "Mithril Deposit", "Truesilver Deposit", 
    "Dark Iron Deposit", "Small Thorium Vein", "Rich Thorium Vein"
}

local TBC_HERBS = {
    "Felweed", "Dreaming Glory", "Ragveil", "Flame Cap", "Terocone", 
    "Netherbloom", "Nightmare Vine", "Mana Thistle"
}

local TBC_MINING = {
    "Fel Iron Deposit", "Adamantite Deposit", "Rich Adamantite Deposit", "Khorium Vein"
}

local SPECIFIC_NODES = {
    ["Classic"] = {
        ["Herb Gathering"] = CLASSIC_HERBS,
        ["Mining"] = CLASSIC_MINING
    },
    ["TBC"] = {
        ["Herb Gathering"] = TBC_HERBS,
        ["Mining"] = TBC_MINING
    }
}

-- ----------------------------------------------------------------------------
-- EXACT NAME TRANSLATOR (Guarantees string matching)
-- ----------------------------------------------------------------------------
addon.NODE_TRANSLATOR = addon.NODE_TRANSLATOR or {}
local function SeedTranslator(list)
    for _, name in ipairs(list) do
        addon.NODE_TRANSLATOR[name] = name
        addon.NODE_TRANSLATOR[string.lower(name)] = name
    end
end
SeedTranslator(CLASSIC_HERBS)
SeedTranslator(CLASSIC_MINING)
SeedTranslator(TBC_HERBS)
SeedTranslator(TBC_MINING)

-- EXACT CORRECTED ID MAPPING DECODED FROM USER TESTS
local NUMERICAL_IDS = {
    [401]="Silverleaf", [402]="Peacebloom", [403]="Earthroot", [404]="Mageroyal", [405]="Briarthorn", 
    [407]="Stranglekelp", [408]="Bruiseweed", [410]="Wild Steelbloom", [411]="Kingsblood", 
    [412]="Liferoot", [413]="Goldthorn", [414]="Fadeleaf", [415]="Khadgar's Whisker", [416]="Wintersbite", 
    [417]="Firebloom", [418]="Purple Lotus", [420]="Arthas' Tears", [421]="Sungrass", [422]="Blindweed", 
    [423]="Ghost Mushroom", [424]="Gromsblood", [425]="Golden Sansam", [426]="Dreamfoil", [427]="Mountain Silversage", 
    [428]="Plaguebloom", [429]="Icecap", [431]="Black Lotus",
    
    [432]="Felweed", [433]="Dreaming Glory", [434]="Terocone", [435]="Ragveil", 
    [437]="Mana Thistle", [438]="Netherbloom", [439]="Nightmare Vine", [440]="Flame Cap",
    
    [201]="Copper Vein", [202]="Tin Vein", [203]="Iron Deposit", [204]="Silver Vein", 
    [205]="Gold Vein", [206]="Mithril Deposit", [208]="Truesilver Deposit", 
    [214]="Small Thorium Vein", [215]="Rich Thorium Vein", [217]="Dark Iron Deposit",
    
    [221]="Fel Iron Deposit", [222]="Adamantite Deposit", [223]="Rich Adamantite Deposit", 
    [224]="Khorium Vein"
}

for id, name in pairs(NUMERICAL_IDS) do
    addon.NODE_TRANSLATOR[id] = name
    addon.NODE_TRANSLATOR[tostring(id)] = name
end

-- ----------------------------------------------------------------------------
-- ITEM ID MAPPING (Pulls native game icons dynamically)
-- ----------------------------------------------------------------------------
addon.NODE_ITEM_IDS = {
    ["Peacebloom"] = 2447, ["Silverleaf"] = 765, ["Earthroot"] = 2449, ["Mageroyal"] = 785, 
    ["Briarthorn"] = 2450, ["Stranglekelp"] = 3820, ["Bruiseweed"] = 2453, ["Wild Steelbloom"] = 3355, 
    ["Kingsblood"] = 3356, ["Liferoot"] = 3357, ["Fadeleaf"] = 3818, 
    ["Goldthorn"] = 3821, ["Khadgar's Whisker"] = 3358, ["Wintersbite"] = 3819, ["Firebloom"] = 4625, 
    ["Purple Lotus"] = 8831, ["Arthas' Tears"] = 8836, ["Sungrass"] = 8838, ["Blindweed"] = 8839, 
    ["Ghost Mushroom"] = 8845, ["Gromsblood"] = 8846, ["Golden Sansam"] = 13464, ["Dreamfoil"] = 13463, 
    ["Mountain Silversage"] = 13465, ["Plaguebloom"] = 13466, ["Icecap"] = 13467, ["Black Lotus"] = 13468,
    
    ["Felweed"] = 22785, ["Dreaming Glory"] = 22786, ["Ragveil"] = 22787, ["Flame Cap"] = 22788, 
    ["Terocone"] = 22789, ["Netherbloom"] = 22791, ["Nightmare Vine"] = 22792, ["Mana Thistle"] = 22793,
    
    ["Copper Vein"] = 2770, ["Tin Vein"] = 2771, ["Silver Vein"] = 2775, ["Iron Deposit"] = 2772, 
    ["Gold Vein"] = 2776, ["Mithril Deposit"] = 3858, ["Truesilver Deposit"] = 7911, 
    ["Dark Iron Deposit"] = 11370, ["Small Thorium Vein"] = 10620, ["Rich Thorium Vein"] = 10620, 
    
    ["Fel Iron Deposit"] = 23424, ["Adamantite Deposit"] = 23425, ["Rich Adamantite Deposit"] = 23425, 
    ["Khorium Vein"] = 23426
}

-- Some Classic items intentionally share artwork even though their gathering
-- nodes are visually distinct. Gold Ore (2776), for example, uses the Copper
-- Ore artwork, so resolving its item icon makes Gold Vein look like Copper Vein
-- in the settings list. Keep node-specific artwork for those exceptions.
local NODE_ICON_OVERRIDES = {
    ["Gold Vein"] = "Interface\\Icons\\inv_ore_gold_01",
}
local RICH_THORIUM_FALLBACK_ICON = "Interface\\Icons\\inv_ore_thorium_01"

addon.NODE_ICONS = addon.NODE_ICONS or {}
for name, _ in pairs(addon.NODE_ITEM_IDS) do
    if not addon.NODE_ICONS[name] then
        addon.NODE_ICONS[name] = "Interface\\Icons\\INV_Misc_QuestionMark" 
    end
end

local function FormatNodeName(name)
    return name:gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest:lower() end)
end

local function TruncateNodeDisplayName(name, maxCharacters)
    name = tostring(name or "")
    maxCharacters = math.max(4, tonumber(maxCharacters) or 20)
    if string.len(name) <= maxCharacters then return name, false end
    return string.sub(name, 1, maxCharacters - 3) .. "...", true
end


-- ----------------------------------------------------------------------------
-- STRICT TBC / CLASSIC ERA UIMAPIDS FOR ROUTE GENERATOR SCOPE
-- ----------------------------------------------------------------------------
local CONTINENT_AZEROTH = _G.CONTINENT_AZEROTH or 947
local CONTINENT_EK = addon.Compat and addon.Compat.isRetail and 13 or (_G.CONTINENT_EK or 1415)
local CONTINENT_KALIMDOR = addon.Compat and addon.Compat.isRetail and 12 or (_G.CONTINENT_KALIMDOR or 1414)
local CONTINENT_OUTLAND = addon.Compat and addon.Compat.isTBC and (_G.CONTINENT_OUTLAND or 1945) or nil

local ZONE_DATA = {
    [CONTINENT_AZEROTH] = {},
    [CONTINENT_EK] = {
        {name="Silvermoon City", id=1954}, {name="Eversong Woods", id=1941}, {name="Ghostlands", id=1942}, {name="Isle of Quel'Danas", id=1957},
        {name="Stormwind City", id=1453}, {name="Ironforge", id=1455}, {name="Undercity", id=1458},
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
        {name="The Exodar", id=1947}, {name="Azuremyst Isle", id=1943}, {name="Bloodmyst Isle", id=1950},
        {name="Orgrimmar", id=1454}, {name="Thunder Bluff", id=1456}, {name="Darnassus", id=1457},
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
        {name="Shattrath City", id=1955}, {name="Hellfire Peninsula", id=1944}, {name="Zangarmarsh", id=1946},
        {name="Terokkar Forest", id=1952}, {name="Nagrand", id=1951}, {name="Blade's Edge Mountains", id=1949},
        {name="Netherstorm", id=1953}, {name="Shadowmoon Valley", id=1948}
    }
end

local CONTINENT_LABELS = {
    [CONTINENT_AZEROTH] = "Azeroth",
    [CONTINENT_EK] = "Eastern Kingdoms",
    [CONTINENT_KALIMDOR] = "Kalimdor"
}
if CONTINENT_OUTLAND then CONTINENT_LABELS[CONTINENT_OUTLAND] = "Outland" end

local CONTINENT_ORDER = {CONTINENT_AZEROTH, CONTINENT_EK, CONTINENT_KALIMDOR}
if CONTINENT_OUTLAND then CONTINENT_ORDER[#CONTINENT_ORDER + 1] = CONTINENT_OUTLAND end

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

function addon.Options:RefreshMapCatalog()
    MergeMapCatalog()
end

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

local function FindDrawZoneForMap(mapID)
    if not mapID then return nil, nil end
    for continentID, zones in pairs(ZONE_DATA) do
        for _, zone in ipairs(zones) do
            if zone.id == mapID then return continentID, zone end
        end
    end
    return nil, nil
end

local function GetDrawZoneName(mapID)
    local _, zone = FindDrawZoneForMap(mapID)
    return zone and zone.name or "Unknown"
end

local function GetSortedDrawZones(continentID)
    local sorted = {}
    for _, zone in ipairs(ZONE_DATA[continentID] or {}) do
        if IsMapVisibleForExpansion(zone.id) then table.insert(sorted, zone) end
    end
    table.sort(sorted, function(a, b) return (a.name or "") < (b.name or "") end)
    return sorted
end
-- ----------------------------------------------------------------------------
-- AUTO ROUTE BUILDER FOR IMPORTED NODES
-- Builds fast clockwise routes from imported node data and marks nodes by profession.
-- ----------------------------------------------------------------------------
local function GetNodeProfession(nodeName)
    if not nodeName then return nil end
    local PMNodes = _G.PathMakerNodes or _G.PathMaker_Nodes
    if PMNodes and type(PMNodes.GetNodeType) == "function" then
        local externalType = PMNodes:GetNodeType(nodeName)
        if externalType then return externalType end
    end
    for _, expNodes in pairs(SPECIFIC_NODES) do
        for profession, nodeList in pairs(expNodes) do
            for _, listedName in ipairs(nodeList) do
                if listedName == nodeName then return profession end
            end
        end
    end
    return nil
end

local function GetNodeVisual(profession)
    if profession == "Mining" then
        return "Interface\\MINIMAP\\TRACKING\\Profession", {0.95, 0.65, 0.25, 1}, "Mining"
    elseif profession == "Herb Gathering" or profession == "Herbalism" then
        return "Interface\\MINIMAP\\TRACKING\\Profession", {0.25, 0.95, 0.35, 1}, "Herbalism"
    elseif profession == "Treasure" then
        return "Interface\\AddOns\\PathMaker_Nodes\\Artwork\\Treasure\\treasure.tga", {1, 0.82, 0.2, 1}, "Treasure"
    end
    return "Interface\\MINIMAP\\ObjectIcons", {0.9, 0.9, 0.9, 1}, "Node"
end

local function GetRouteMapScale(mapID)
    local scaleX, scaleY
    if addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
    end
    local calibration = PathmakerDB and PathmakerDB.calibration and PathmakerDB.calibration[mapID]
    if type(calibration) == "table" then
        scaleX, scaleY = scaleX or calibration.x, scaleY or calibration.y
    end
    return scaleX or 6000, scaleY or 6000
end

local function RouteDistance(a, b, scaleX, scaleY)
    local dx = ((a.x or 0) - (b.x or 0)) * (scaleX or 1)
    local dy = ((a.y or 0) - (b.y or 0)) * (scaleY or 1)
    return (dx * dx) + (dy * dy)
end

local ROUTE_DENSITY_YARDS = { DETAILED = 4, NORMAL = 8 }

local function CollapseNearbyRoutePoints(points, mapID, density)
    if #points < 2 then return points end

    local scaleX, scaleY
    if addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
    end
    scaleX, scaleY = scaleX or 6000, scaleY or 6000

    local cellSize = ROUTE_DENSITY_YARDS[density] or ROUTE_DENSITY_YARDS.NORMAL
    local radiusSquared = cellSize * cellSize
    local grid, result = {}, {}

    for _, point in ipairs(points) do
        local worldX, worldY = point.x * scaleX, point.y * scaleY
        local bucketX = math.floor(worldX / cellSize)
        local bucketY = math.floor(worldY / cellSize)
        local grouped = false

        for checkX = bucketX - 1, bucketX + 1 do
            if grouped then break end
            for checkY = bucketY - 1, bucketY + 1 do
                for _, existing in ipairs(grid[checkX .. ":" .. checkY] or {}) do
                    local dx, dy = worldX - existing.x, worldY - existing.y
                    if ((dx * dx) + (dy * dy)) <= radiusSquared then
                        grouped = true
                        break
                    end
                end
                if grouped then break end
            end
        end

        -- Index grouped samples too, matching the visual logical-node behavior.
        local ownKey = bucketX .. ":" .. bucketY
        grid[ownKey] = grid[ownKey] or {}
        grid[ownKey][#grid[ownKey] + 1] = { x = worldX, y = worldY }
        if not grouped then result[#result + 1] = point end
    end

    return result
end

local function PointInAvoidArea(point, area)
    local inside = false
    local j = #area
    for i = 1, #area do
        local a, b = area[i], area[j]
        if ((a.y > point.y) ~= (b.y > point.y))
            and point.x < (b.x - a.x) * (point.y - a.y) / ((b.y - a.y) ~= 0 and (b.y - a.y) or 0.000001) + a.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function SegmentsIntersect(a, b, c, d)
    local function orient(p, q, r)
        return ((q.x - p.x) * (r.y - p.y)) - ((q.y - p.y) * (r.x - p.x))
    end
    local o1, o2, o3, o4 = orient(a, b, c), orient(a, b, d), orient(c, d, a), orient(c, d, b)
    return ((o1 > 0 and o2 < 0) or (o1 < 0 and o2 > 0))
        and ((o3 > 0 and o4 < 0) or (o3 < 0 and o4 > 0))
end

local function SegmentHitsAvoidArea(a, b, area)
    if PointInAvoidArea(a, area) or PointInAvoidArea(b, area) then return true end
    for i = 1, #area do
        if SegmentsIntersect(a, b, area[i], area[(i % #area) + 1]) then return true end
    end
    return false
end

local function GetAvoidAreas(mapID)
    return PathmakerDB and PathmakerDB.avoidAreas and PathmakerDB.avoidAreas[mapID] or {}
end

local function RemovePointsInsideAvoidAreas(points, mapID)
    local areas = GetAvoidAreas(mapID)
    if #areas == 0 then return points end
    local result = {}
    for _, point in ipairs(points) do
        local blocked = false
        for _, area in ipairs(areas) do
            if #area >= 3 and PointInAvoidArea(point, area) then blocked = true; break end
        end
        if not blocked then result[#result + 1] = point end
    end
    return result
end

local function EdgeAvoidPenalty(a, b, avoidAreas, scaleX, scaleY)
    for _, area in ipairs(avoidAreas or {}) do
        if #area >= 3 and SegmentHitsAvoidArea(a, b, area) then
            return 1000000000 + RouteDistance(a, b, scaleX, scaleY)
        end
    end
    return 0
end

local function AddAvoidAreaDetours(points, mapID, scaleX, scaleY)
    local areas = GetAvoidAreas(mapID)
    if #areas == 0 or #points < 2 then return points end

    -- Build a small visibility graph around every polygon. The old detour
    -- chose one bounding-box corner, which could leave the following segment
    -- crossing the same area (or a second area). A shortest visible path can
    -- use as many corners as necessary and handles overlapping obstacles.
    local candidates = {}
    local function AddCandidate(x, y)
        x, y = math.max(0, math.min(1, x)), math.max(0, math.min(1, y))
        for _, existing in ipairs(candidates) do
            local dx, dy = (existing.x - x) * scaleX, (existing.y - y) * scaleY
            if dx * dx + dy * dy < 4 then return end
        end
        candidates[#candidates + 1] = {x=x, y=y, isDetour=true}
    end

    local clearance = 18
    for _, area in ipairs(areas) do
        if #area >= 3 then
            local centerX, centerY, minX, minY, maxX, maxY = 0, 0, 1, 1, 0, 0
            for _, p in ipairs(area) do
                centerX, centerY = centerX + p.x, centerY + p.y
                minX, minY = math.min(minX, p.x), math.min(minY, p.y)
                maxX, maxY = math.max(maxX, p.x), math.max(maxY, p.y)
            end
            centerX, centerY = centerX / #area, centerY / #area
            for _, p in ipairs(area) do
                local dx, dy = (p.x - centerX) * scaleX, (p.y - centerY) * scaleY
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0.001 then
                    AddCandidate(p.x + (dx / length) * clearance / scaleX, p.y + (dy / length) * clearance / scaleY)
                end
            end
            local mx, my = clearance / scaleX, clearance / scaleY
            AddCandidate(minX - mx, minY - my)
            AddCandidate(maxX + mx, minY - my)
            AddCandidate(maxX + mx, maxY + my)
            AddCandidate(minX - mx, maxY + my)
        end
    end

    local function IsVisible(a, b)
        for _, area in ipairs(areas) do
            if #area >= 3 and SegmentHitsAvoidArea(a, b, area) then return false end
        end
        return true
    end

    -- Candidate-to-candidate visibility is identical for every route edge,
    -- so calculate it once rather than repeating polygon tests for each node.
    local candidateVisibility = {}
    for first = 1, #candidates do
        candidateVisibility[first] = candidateVisibility[first] or {}
        for second = first + 1, #candidates do
            local visible = IsVisible(candidates[first], candidates[second])
            candidateVisibility[first][second] = visible
            candidateVisibility[second] = candidateVisibility[second] or {}
            candidateVisibility[second][first] = visible
        end
    end

    local function FindDetour(a, b)
        if IsVisible(a, b) then return {} end
        local nodes = {a, b}
        for _, candidate in ipairs(candidates) do nodes[#nodes + 1] = candidate end
        local distance, previous, visited = {[1] = 0}, {}, {}
        for _ = 1, #nodes do
            local current, best
            for index = 1, #nodes do
                if not visited[index] and distance[index] and (not best or distance[index] < best) then
                    current, best = index, distance[index]
                end
            end
            if not current then break end
            if current == 2 then break end
            visited[current] = true
            for nextIndex = 2, #nodes do
                local visible
                if current > 2 and nextIndex > 2 then
                    visible = candidateVisibility[current - 2] and candidateVisibility[current - 2][nextIndex - 2]
                else
                    visible = IsVisible(nodes[current], nodes[nextIndex])
                end
                if not visited[nextIndex] and nextIndex ~= current and visible then
                    local nextDistance = best + math.sqrt(RouteDistance(nodes[current], nodes[nextIndex], scaleX, scaleY))
                    if not distance[nextIndex] or nextDistance < distance[nextIndex] then
                        distance[nextIndex], previous[nextIndex] = nextDistance, current
                    end
                end
            end
        end
        if not distance[2] then return nil end
        local reversed, cursor = {}, 2
        while previous[cursor] and previous[cursor] ~= 1 do
            cursor = previous[cursor]
            reversed[#reversed + 1] = nodes[cursor]
        end
        local detour = {}
        for index = #reversed, 1, -1 do
            detour[#detour + 1] = {x=reversed[index].x, y=reversed[index].y, isDetour=true}
        end
        return detour
    end

    local result = {}
    for i = 1, #points do
        local a, b = points[i], points[(i % #points) + 1]
        result[#result + 1] = a
        local detour = FindDetour(a, b)
        if detour then
            for _, point in ipairs(detour) do result[#result + 1] = point end
        end
    end
    return result
end

local function ReverseRouteSlice(points, firstIndex, lastIndex)
    while firstIndex < lastIndex do
        points[firstIndex], points[lastIndex] = points[lastIndex], points[firstIndex]
        firstIndex = firstIndex + 1
        lastIndex = lastIndex - 1
    end
end

local function OptimizeClockwiseRoute(points, scaleX, scaleY, routeStyle, avoidAreas)
    if #points < 3 then return points end
    scaleX, scaleY = scaleX or 1, scaleY or 1
    routeStyle = routeStyle == "SHORTEST" and "SHORTEST" or "BALANCED"

    -- Route scoring revisits the same edges many times during nearest-neighbour
    -- seeding and 2-opt. Cache polygon intersection results for the duration of
    -- this route so avoid areas do not multiply the optimizer's running time.
    local avoidPenaltyCache = {}
    local function CachedEdgeAvoidPenalty(a, b)
        local fromA = avoidPenaltyCache[a]
        if fromA and fromA[b] ~= nil then return fromA[b] end
        local penalty = EdgeAvoidPenalty(a, b, avoidAreas, scaleX, scaleY)
        fromA = fromA or {}
        avoidPenaltyCache[a] = fromA
        fromA[b] = penalty
        local fromB = avoidPenaltyCache[b] or {}
        avoidPenaltyCache[b] = fromB
        fromB[a] = penalty
        return penalty
    end

    local atan2 = math.atan2 or function(y, x)
        if x > 0 then return math.atan(y / x) end
        if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
        if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
        if x == 0 and y > 0 then return math.pi / 2 end
        if x == 0 and y < 0 then return -math.pi / 2 end
        return 0
    end
    local centerX, centerY = 0, 0
    for _, point in ipairs(points) do
        centerX = centerX + (point.x or 0)
        centerY = centerY + (point.y or 0)
    end
    centerX = centerX / #points
    centerY = centerY / #points

    table.sort(points, function(a, b)
        local angleA = atan2(((a.y or 0) - centerY) * scaleY, ((a.x or 0) - centerX) * scaleX)
        local angleB = atan2(((b.y or 0) - centerY) * scaleY, ((b.x or 0) - centerX) * scaleX)
        if angleA == angleB then return RouteDistance(a, {x = centerX, y = centerY}, scaleX, scaleY) > RouteDistance(b, {x = centerX, y = centerY}, scaleX, scaleY) end
        return angleA < angleB
    end)

    local northIndex = 1
    for i = 2, #points do
        if (points[i].y or 1) < (points[northIndex].y or 1) then
            northIndex = i
        elseif (points[i].y or 1) == (points[northIndex].y or 1) and (points[i].x or 0) < (points[northIndex].x or 0) then
            northIndex = i
        end
    end

    local rotated = {}
    for offset = 0, #points - 1 do
        table.insert(rotated, points[((northIndex + offset - 1) % #points) + 1])
    end

    -- Also construct a nearest-neighbour seed. Choosing the better of the
    -- angular and proximity seeds before 2-opt avoids trapping generation in
    -- the same radial ordering on irregular node layouts.
    local nearestSeed, used = {rotated[1]}, {[rotated[1]] = true}
    while #nearestSeed < #rotated do
        local current, bestPoint, bestCost = nearestSeed[#nearestSeed], nil, nil
        for _, candidate in ipairs(rotated) do
            if not used[candidate] then
                local cost = math.sqrt(RouteDistance(current, candidate, scaleX, scaleY))
                    + CachedEdgeAvoidPenalty(current, candidate)
                if not bestCost or cost < bestCost then bestPoint, bestCost = candidate, cost end
            end
        end
        nearestSeed[#nearestSeed + 1] = bestPoint
        used[bestPoint] = true
    end

    local function CycleScore(route)
        local score, turnWeight = 0, routeStyle == "BALANCED" and 0.12 or 0
        local totalLength = 0
        for i = 1, #route do
            local a, b = route[i], route[(i % #route) + 1]
            local length = math.sqrt(RouteDistance(a, b, scaleX, scaleY))
            totalLength = totalLength + length
            score = score + length + CachedEdgeAvoidPenalty(a, b)
        end
        if turnWeight > 0 then
            local averageLength = totalLength / #route
            for i = 1, #route do
                local a, b, c = route[((i - 2) % #route) + 1], route[i], route[(i % #route) + 1]
                local abx, aby = (b.x-a.x)*scaleX, (b.y-a.y)*scaleY
                local bcx, bcy = (c.x-b.x)*scaleX, (c.y-b.y)*scaleY
                local abLen, bcLen = math.sqrt(abx*abx+aby*aby), math.sqrt(bcx*bcx+bcy*bcy)
                if abLen > 0 and bcLen > 0 then
                    local cosine = math.max(-1, math.min(1, (abx*bcx+aby*bcy)/(abLen*bcLen)))
                    score = score + (1 - cosine) * averageLength * turnWeight
                end
            end
        end
        return score
    end
    if CycleScore(nearestSeed) < CycleScore(rotated) then rotated = nearestSeed end

    -- Cyclic 2-opt includes the closing edge from the last point to the first.
    local improved, guard = true, 0
    while improved and guard < 32 do
        improved = false
        guard = guard + 1
        for i = 1, #rotated - 2 do
            for j = i + 2, #rotated do
                if not (i == 1 and j == #rotated) then
                    local a, b = rotated[i], rotated[i + 1]
                    local c, d = rotated[j], rotated[(j % #rotated) + 1]
                    local oldDist = math.sqrt(RouteDistance(a, b, scaleX, scaleY)) + math.sqrt(RouteDistance(c, d, scaleX, scaleY))
                        + CachedEdgeAvoidPenalty(a, b) + CachedEdgeAvoidPenalty(c, d)
                    local newDist = math.sqrt(RouteDistance(a, c, scaleX, scaleY)) + math.sqrt(RouteDistance(b, d, scaleX, scaleY))
                        + CachedEdgeAvoidPenalty(a, c) + CachedEdgeAvoidPenalty(b, d)
                    if routeStyle == "SHORTEST" then
                        newDist = newDist * 0.98
                    end
                    -- Crossing edges normally improve when uncrossed, but the
                    -- replacement must still win after obstacle penalties.
                    if newDist < oldDist then
                        ReverseRouteSlice(rotated, i + 1, j)
                        improved = true
                    end
                end
            end
        end
    end

    -- Keep generated routes clockwise on the map while retaining the
    -- northernmost start point selected above.
    local signedArea = 0
    for i = 1, #rotated do
        local a, b = rotated[i], rotated[(i % #rotated) + 1]
        signedArea = signedArea + (a.x * b.y) - (b.x * a.y)
    end
    if signedArea < 0 then ReverseRouteSlice(rotated, 2, #rotated) end
    return rotated
end


local function RemoveIsolatedRoutePoints(points, scaleX, scaleY)
    if #points < 4 then return points end
    local nearest = {}
    for i, point in ipairs(points) do
        local best = math.huge
        for j, other in ipairs(points) do
            if i ~= j then best = math.min(best, math.sqrt(RouteDistance(point, other, scaleX, scaleY))) end
        end
        nearest[#nearest + 1] = best
    end
    local sorted = {unpack(nearest)}
    table.sort(sorted)
    local median = sorted[math.ceil(#sorted / 2)] or 0
    local cutoff = math.max(140, median * 3.25)
    local result = {}
    for i, point in ipairs(points) do
        if nearest[i] <= cutoff then result[#result + 1] = point end
    end
    return #result >= 2 and result or points
end

local function SplitDistantRouteClusters(points, scaleX, scaleY)
    if #points <= 2 then return {points} end
    local nearestTotal = 0
    for i = 1, #points do
        local nearest = nil
        for j = 1, #points do
            if i ~= j then
                local dist = math.sqrt(RouteDistance(points[i], points[j], scaleX, scaleY))
                if not nearest or dist < nearest then nearest = dist end
            end
        end
        nearestTotal = nearestTotal + (nearest or 0)
    end
    local avgNearest = nearestTotal / #points
    -- Cluster in yards. Normalized thresholds split compact city/cave maps far
    -- more aggressively than outdoor zones and produce broken traces.
    local threshold = math.max(90, math.min(480, avgNearest * 3.0))
    local thresholdSq = threshold * threshold
    local visited = {}
    local clusters = {}
    for i = 1, #points do
        if not visited[i] then
            local cluster = {}
            local queue = {i}
            visited[i] = true
            while #queue > 0 do
                local current = table.remove(queue, 1)
                table.insert(cluster, points[current])
                for j = 1, #points do
                    if not visited[j] and RouteDistance(points[current], points[j], scaleX, scaleY) <= thresholdSq then
                        visited[j] = true
                        table.insert(queue, j)
                    end
                end
            end
            table.insert(clusters, cluster)
        end
    end
    return clusters
end
function addon.Options:BuildImportedNodeRoutes(nodeFilter, maxNodeTypes, targetMapID, routeMode, generationOptions)
    if not PathmakerDB or not PathmakerDB.nodes then return 0, 0 end
    PathmakerDB.routes = PathmakerDB.routes or {}
    generationOptions = generationOptions or {}
    local routeStyle = generationOptions.routeStyle == "SHORTEST" and "SHORTEST" or "BALANCED"
    local nodeDensity = generationOptions.nodeDensity == "DETAILED" and "DETAILED" or "NORMAL"
    local verifiedOnly = generationOptions.verifiedOnly == true
    local selectedNames = {}
    local selectedLookup = {}
    for nodeName, enabled in pairs(nodeFilter or {}) do
        if enabled then table.insert(selectedNames, nodeName) selectedLookup[nodeName] = true end
    end
    table.sort(selectedNames)
    maxNodeTypes = maxNodeTypes or 5
    if #selectedNames > maxNodeTypes then return 0, 0, "MAX_SELECTED" end
    local routesBuilt = 0
    local skippedTooFew = 0
    local targetLookup = type(targetMapID) == "table" and targetMapID or nil
    for mapID, nodes in pairs(PathmakerDB.nodes) do
        if not targetMapID or mapID == targetMapID or (targetLookup and targetLookup[mapID]) then
            local pointsByNode = {}
            local professionByNode = {}
            for _, node in ipairs(nodes) do
                local nodeName = node.specificName or node.name or node.type
                if selectedLookup[nodeName] and node.x and node.y and (not verifiedOnly or node.verified == true) then
                    local profession = GetNodeProfession(nodeName)
                    local icon, color, label = GetNodeVisual(profession)
                    node.profession = label
                    node.nodeProfession = label
                    node.drawModeIcon = icon
                    node.drawModeColor = color
                    professionByNode[nodeName] = label
                    pointsByNode[nodeName] = pointsByNode[nodeName] or {}
                    table.insert(pointsByNode[nodeName], {x=node.x, y=node.y, name=nodeName, type=node.type, specificName=node.specificName or nodeName, profession=label, icon=icon, color=color})
                end
            end
            for _, nodeName in ipairs(selectedNames) do
                local selectedPoints = pointsByNode[nodeName]
                if selectedPoints then
                    selectedPoints = CollapseNearbyRoutePoints(selectedPoints, mapID, nodeDensity)
                end
                if selectedPoints and #selectedPoints >= 2 then
                    local scaleX, scaleY = GetRouteMapScale(mapID)
                    local respectAvoidAreas = generationOptions.avoidAreaMode ~= "IGNORE"
                    local avoidAreas = respectAvoidAreas and GetAvoidAreas(mapID) or {}
                    if respectAvoidAreas then
                        selectedPoints = RemovePointsInsideAvoidAreas(selectedPoints, mapID)
                    end
                    if generationOptions.distantNodes ~= "INCLUDE" then
                        selectedPoints = RemoveIsolatedRoutePoints(selectedPoints, scaleX, scaleY)
                    end
                    local profession = professionByNode[nodeName]
                    local _, _, label = GetNodeVisual(profession)
                    local routeColor = {1, 1, 1, 1}
                    PathmakerDB.routes[mapID] = PathmakerDB.routes[mapID] or {}
                    routeMode = routeMode == "FULL" and "FULL" or "HALF"
                    local clusters = routeMode == "FULL" and {selectedPoints} or SplitDistantRouteClusters(selectedPoints, scaleX, scaleY)
                    local builtForNode = 0
                    for clusterIndex, clusterPoints in ipairs(clusters) do
                        if #clusterPoints >= 2 then
                            local orderedPoints = OptimizeClockwiseRoute(clusterPoints, scaleX, scaleY, routeStyle, avoidAreas)
                            if respectAvoidAreas then
                                orderedPoints = AddAvoidAreaDetours(orderedPoints, mapID, scaleX, scaleY)
                            end
                            builtForNode = builtForNode + 1
                            local safeNodeName = tostring(nodeName):gsub("%W", "_")
                            local guidBase = "AUTO_NODE_" .. tostring(mapID) .. "_" .. safeNodeName .. "_" .. routeMode .. "_" .. tostring(clusterIndex) .. "_" .. tostring(time())
                            local guid = guidBase
                            local guidSuffix = 1
                            while PathmakerDB.routes[mapID][guid] do
                                guidSuffix = guidSuffix + 1
                                guid = guidBase .. "_" .. tostring(guidSuffix)
                            end
                            local routeName = "Auto " .. FormatNodeName(nodeName)
                            if routeMode == "FULL" then routeName = routeName .. " Full" end
                            routeName = routeName .. " " .. tostring(clusterIndex)
                            PathmakerDB.routes[mapID][guid] = {name=routeName, color=routeColor, points=orderedPoints, route=orderedPoints, nodes=orderedPoints, connectPaths=true, autoGenerated=true, source="Imported Nodes", nodeName=nodeName, profession=label, startMode="Northernmost Clockwise", avoidCrossing=respectAvoidAreas, routeMode=routeMode, routeStyle=routeStyle, nodeDensity=nodeDensity, distantNodes=generationOptions.distantNodes or "IGNORE", avoidAreaMode=generationOptions.avoidAreaMode or "RESPECT", clusterIndex=clusterIndex, clusterCount=#clusters, mapScaleX=scaleX, mapScaleY=scaleY}
                            addon.selectedRouteGUID = guid
                            addon.selectedRouteMapID = mapID
                            routesBuilt = routesBuilt + 1
                        end
                    end
                    if builtForNode == 0 then skippedTooFew = skippedTooFew + 1 end
                elseif selectedLookup[nodeName] then skippedTooFew = skippedTooFew + 1 end
            end
        end
    end
    return routesBuilt, skippedTooFew
end

-- ----------------------------------------------------------------------------
-- POST-IMPORT DEDUPLICATION ENGINE
-- ----------------------------------------------------------------------------
local IMPORT_SAFETY_YARDS = 3
local IMPORT_FALLBACK_MAP_YARDS = 6000

local function GetImportMapScales(mapID)
    if addon.UI and addon.UI.GetMapWorldScale then
        local scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
        if scaleX and scaleY then return scaleX, scaleY end
    end
    return IMPORT_FALLBACK_MAP_YARDS, IMPORT_FALLBACK_MAP_YARDS
end

local function GetImportCoordBucket(mapID, x, y)
    local scaleX, scaleY = GetImportMapScales(mapID)
    return math.floor(((x or 0) * scaleX) / IMPORT_SAFETY_YARDS),
           math.floor(((y or 0) * scaleY) / IMPORT_SAFETY_YARDS)
end

local function GetImportBucketKey(bucketX, bucketY)
    return bucketX .. ":" .. bucketY
end

local function IndexImportNode(index, mapID, nodeName, node)
    if not nodeName or not node or not node.x or not node.y then return end
    index[nodeName] = index[nodeName] or {}
    local bucketX, bucketY = GetImportCoordBucket(mapID, node.x, node.y)
    local key = GetImportBucketKey(bucketX, bucketY)
    index[nodeName][key] = index[nodeName][key] or {}
    table.insert(index[nodeName][key], node)
end

local function ImportIndexContains(index, mapID, nodeName, x, y)
    local nameIndex = index[nodeName]
    if not nameIndex then return false end
    local scaleX, scaleY = GetImportMapScales(mapID)
    local bucketX, bucketY = GetImportCoordBucket(mapID, x, y)
    for checkX = bucketX - 1, bucketX + 1 do
        for checkY = bucketY - 1, bucketY + 1 do
            for _, existing in ipairs(nameIndex[GetImportBucketKey(checkX, checkY)] or {}) do
                local dx = (existing.x - x) * scaleX
                local dy = (existing.y - y) * scaleY
                if ((dx * dx) + (dy * dy)) <= (IMPORT_SAFETY_YARDS * IMPORT_SAFETY_YARDS) then
                    return true
                end
            end
        end
    end
    return false
end

function addon.Options:DeduplicateDatabase()
    if not PathmakerDB or not PathmakerDB.nodes then return end
    
    -- Keep at most one point for each resource/location. Learned points are
    -- considered first, so an imported copy never replaces a learned marker.
    local totalRemoved = 0

    for mapID, nodes in pairs(PathmakerDB.nodes) do
        local keptNodes = {}
        local index = {}
        for pass = 1, 2 do
            local importedPass = pass == 2
            for i = 1, #nodes do
                local nodeA = nodes[i]
                local isImported = nodeA.source == "PathMaker_Nodes"
                if isImported == importedPass then
                    local nameA = nodeA.specificName or nodeA.name or nodeA.type
                    local isDuplicate = nodeA.x and nodeA.y
                        and ImportIndexContains(index, mapID, nameA, nodeA.x, nodeA.y)

                    if not isDuplicate then
                        table.insert(keptNodes, nodeA)
                        IndexImportNode(index, mapID, nameA, nodeA)
                    else
                        totalRemoved = totalRemoved + 1
                    end
                end
            end
        end
        PathmakerDB.nodes[mapID] = keptNodes
    end

    if totalRemoved > 0 then
        local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgDedupe
        if not hideMsg then
            print(string.format("|cFF00FF00PathMaker:|r Cleaned up %d overlapping duplicate nodes during import.", totalRemoved))
        end
    end
end

local function DecodeExternalNodeCoord(coord)
    coord = tonumber(coord)
    if not coord then return nil, nil end
    local x = math.floor(coord / 1000000) / 10000
    local y = math.floor((coord % 1000000) / 100) / 10000
    x = math.floor(x * 10000 + 0.5) / 10000
    y = math.floor(y * 10000 + 0.5) / 10000
    return x, y
end

local function ImportExternalNodeTables(PMNodes, nodeFilter)
    if type(PMNodes) ~= "table" then return nil end
    PathmakerDB = PathmakerDB or {}
    PathmakerDB.nodes = PathmakerDB.nodes or {}

    local resolvedFilter = {}
    local hasFilter = false
    for filterID, isChecked in pairs(nodeFilter or {}) do
        if isChecked then
            local resolvedName = addon.NODE_TRANSLATOR[filterID] or addon.NODE_TRANSLATOR[tostring(filterID)] or filterID
            resolvedFilter[resolvedName] = true
            hasFilter = true
        end
    end

    local importedCount = 0
    local hasSourceTables = type(PMNodes.MasterMineDB) == "table"
        or type(PMNodes.MasterHerbDB) == "table"
        or type(PMNodes.MasterTreasureDB) == "table"
    if not hasSourceTables then return nil end

    local indexes = {}
    local function GetMapImportIndex(mapID)
        if indexes[mapID] then return indexes[mapID] end
        local index = {}
        indexes[mapID] = index
        for _, existing in ipairs(PathmakerDB.nodes[mapID] or {}) do
            local existingName = existing.specificName or existing.name or existing.id or existing.type
            IndexImportNode(index, mapID, existingName, existing)
        end
        return index
    end

    local function InjectNode(mapID, coord, nodeID, nodeType)
        if addon.Compat and addon.Compat.IsMapAvailable and not addon.Compat:IsMapAvailable(mapID) then return end
        local x, y = DecodeExternalNodeCoord(coord)
        if not x or not y then return end

        local nodeName = addon.NODE_TRANSLATOR[nodeID] or addon.NODE_TRANSLATOR[tostring(nodeID)] or tostring(nodeID)
        if hasFilter and not resolvedFilter[nodeName] then return end

        PathmakerDB.nodes[mapID] = PathmakerDB.nodes[mapID] or {}
        local index = GetMapImportIndex(mapID)
        if ImportIndexContains(index, mapID, nodeName, x, y) then return end

        local importedNode = {
            x = x,
            y = y,
            id = nodeName,
            type = nodeType,
            name = nodeName,
            specificName = nodeName,
            icon = addon.NODE_ICONS and addon.NODE_ICONS[nodeName],
            source = "PathMaker_Nodes",
            verified = false,
        }
        table.insert(PathmakerDB.nodes[mapID], importedNode)
        IndexImportNode(index, mapID, nodeName, importedNode)
        importedCount = importedCount + 1
    end

    if type(PMNodes.MasterMineDB) == "table" then
        for mapID, nodes in pairs(PMNodes.MasterMineDB) do
            for coord, nodeID in pairs(nodes) do
                InjectNode(mapID, coord, nodeID, "Mining")
            end
        end
    end

    if type(PMNodes.MasterHerbDB) == "table" then
        for mapID, nodes in pairs(PMNodes.MasterHerbDB) do
            for coord, nodeID in pairs(nodes) do
                InjectNode(mapID, coord, nodeID, "Herb Gathering")
            end
        end
    end

    if type(PMNodes.MasterTreasureDB) == "table" then
        for mapID, nodes in pairs(PMNodes.MasterTreasureDB) do
            for coord, nodeID in pairs(nodes) do
                InjectNode(mapID, coord, nodeID, "Treasure")
            end
        end
    end

    return importedCount
end

-- ----------------------------------------------------------------------------
-- IMPORT TRIGGER
-- ----------------------------------------------------------------------------
function addon.Options:ProcessDatasets(actionType, expansion, nodeFilter)
    if actionType == "WIPE" then
        if PathmakerDB then PathmakerDB.nodes = {} end
        
        local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgWipe
        if not hideMsg then
            print("|cFF00FF00PathMaker:|r Entire database wiped.")
        end
        
        if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
        return
    end

    if actionType == "WIPE_SELECTED" then
        local selectedLookup = {}
        local selectedCount = 0
        for nodeName, enabled in pairs(nodeFilter or {}) do
            if enabled then
                selectedLookup[nodeName] = true
                selectedCount = selectedCount + 1
            end
        end

        if selectedCount == 0 then
            local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
            if not hideErr then
                print("|cFFFF4444PathMaker:|r Please select at least one node in the list to wipe.")
            end
            return
        end

        local removedCount = 0
        if PathmakerDB and PathmakerDB.nodes then
            for mapID, nodes in pairs(PathmakerDB.nodes) do
                local keptNodes = {}
                for _, node in ipairs(nodes) do
                    local nodeName = node.specificName or node.name or node.type
                    if selectedLookup[nodeName] then
                        removedCount = removedCount + 1
                    else
                        table.insert(keptNodes, node)
                    end
                end
                PathmakerDB.nodes[mapID] = keptNodes
            end
        end

        if PathmakerDB and PathmakerDB.PMNodes_Filter then
            for nodeName in pairs(selectedLookup) do
                PathmakerDB.PMNodes_Filter[nodeName] = false
            end
        end

        local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgWipe
        if not hideMsg then
            print(string.format("|cFF00FF00PathMaker:|r Wiped %d imported point(s) from selected node data.", removedCount))
        end

        if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
        return
    end

    if actionType == "IMPORT" then
        local PMNodes = _G["PathMakerNodes"] or _G["PathMaker_Nodes"]
        if PMNodes and type(PMNodes.CaptureAll) == "function" then
            pcall(function() PMNodes:CaptureAll() end)
        end
        
        if PMNodes and type(PMNodes.ImportNodes) == "function" then
            local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgNodeImport
            local oldPrint = print
            if hideMsg then
                print = function(...)
                    local str = tostring(...)
                    if str:lower():find("imported") then return end
                    oldPrint(...)
                end
            end
            
            local importResult = nil
            local success, err = pcall(function()
                importResult = PMNodes:ImportNodes(expansion, nodeFilter)
            end)
            
            if hideMsg then print = oldPrint end
            
            if not success or importResult == false then
                local fallbackCount = ImportExternalNodeTables(PMNodes, nodeFilter)
                local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
                if fallbackCount and fallbackCount >= 0 then
                    addon.Options:DeduplicateDatabase()
                    if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
                    if not hideMsg then
                        print(string.format("|cFF00FF00PathMaker:|r Imported %d selected node point(s).", fallbackCount))
                    end
                elseif not hideErr then
                    print("|cFFFF0000PathMaker Import Error:|r " .. tostring(err))
                end
            else
                -- The primary importer maintains its own coordinate index and
                -- already prevents exact duplicates as points are inserted.
                if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
            end

            if PathmakerDB then PathmakerDB.lastImport = "All" end
        else
            local fallbackCount = ImportExternalNodeTables(PMNodes, nodeFilter)
            if fallbackCount and fallbackCount >= 0 then
                addon.Options:DeduplicateDatabase()
                if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
                local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgNodeImport
                if not hideMsg then
                    print(string.format("|cFF00FF00PathMaker:|r Imported %d selected node point(s).", fallbackCount))
                end
                if PathmakerDB then PathmakerDB.lastImport = "All" end
                return
            end
            local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
            if not hideErr then
                print("|cFFFF0000PathMaker:|r Node data not found! Make sure you have PathMaker_Nodes addon installed.")
            end
        end
    end
end

-- HELPER FOR SLIDERS
local function StabilizeScrollingTexture(texture)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(true) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

local function GetDefaultDrawMapID()
    local currentMapID = C_Map.GetBestMapForUnit("player")
    if currentMapID and IsMapVisibleForExpansion(currentMapID) then return currentMapID end
    for _, continentID in ipairs(GetVisibleContinentOrder()) do
        local zones = GetSortedDrawZones(continentID)
        if zones and zones[1] then return zones[1].id end
    end
    return 947
end

local function GetDefaultDrawContinentID()
    for _, continentID in ipairs(GetVisibleContinentOrder()) do
        local zones = GetSortedDrawZones(continentID)
        if zones and zones[1] then return continentID end
    end
    return CONTINENT_AZEROTH
end

local function CreateCustomSlider(parent, width, height, minVal, maxVal, currentVal, callback)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(width, height)

    local trackBorder = StabilizeScrollingTexture(s:CreateTexture(nil, "BACKGROUND"))
    trackBorder:SetColorTexture(0.52, 0.36, 0.04, 1)
    trackBorder:SetAllPoints()

    local trackInner = StabilizeScrollingTexture(s:CreateTexture(nil, "BACKGROUND", nil, 1))
    trackInner:SetColorTexture(0.025, 0.02, 0.01, 1)
    trackInner:SetPoint("TOPLEFT", 1, -1)
    trackInner:SetPoint("BOTTOMRIGHT", -1, 1)

    local fill = StabilizeScrollingTexture(s:CreateTexture(nil, "ARTWORK"))
    fill:SetColorTexture(0.95, 0.66, 0.02, 0.95)
    fill:SetPoint("LEFT", s, "LEFT", 2, 0)
    fill:SetHeight(math.max(3, height - 6))

    local shine = StabilizeScrollingTexture(s:CreateTexture(nil, "ARTWORK", nil, 1))
    shine:SetColorTexture(1, 0.88, 0.2, 0.65)
    shine:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    shine:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    shine:SetHeight(2)

    local thumb = CreateFrame("Frame", nil, s)
    thumb:SetSize(14, height + 10)
    thumb:SetFrameLevel(s:GetFrameLevel() + 2)

    local thumbBorder = StabilizeScrollingTexture(thumb:CreateTexture(nil, "ARTWORK"))
    thumbBorder:SetColorTexture(0.95, 0.68, 0.06, 1)
    thumbBorder:SetAllPoints()

    local thumbInner = StabilizeScrollingTexture(thumb:CreateTexture(nil, "ARTWORK", nil, 1))
    thumbInner:SetColorTexture(0.54, 0.35, 0.025, 1)
    thumbInner:SetPoint("TOPLEFT", 1, -1)
    thumbInner:SetPoint("BOTTOMRIGHT", -1, 1)

    local thumbShine = StabilizeScrollingTexture(thumb:CreateTexture(nil, "OVERLAY"))
    thumbShine:SetColorTexture(1, 0.79, 0.15, 0.45)
    thumbShine:SetPoint("TOPLEFT", 2, -2)
    thumbShine:SetPoint("TOPRIGHT", -2, -2)
    thumbShine:SetHeight(2)

    local function UpdateThumb()
        local pct = (currentVal - minVal) / (maxVal - minVal)
        pct = math.max(0, math.min(1, pct))
        local maxDist = width - thumb:GetWidth() - 2
        local scale = s:GetEffectiveScale() or 1
        if scale <= 0 then scale = 1 end
        local thumbX = 1 + (math.floor((maxDist * pct * scale) + 0.5) / scale)
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", s, "LEFT", thumbX, 0)
        local fillWidth = thumbX + (thumb:GetWidth() / 2) - 2
        fillWidth = math.floor((fillWidth * scale) + 0.5) / scale
        fill:SetWidth(math.max(1, fillWidth))
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

    local function UpdateValueFromCursor(frame, deferCallback)
        local mx = GetCursorPosition()
        if not mx then return end
        local sScale = frame:GetEffectiveScale() or 1
        if sScale <= 0 then sScale = 1 end

        -- Use the same bordered thumb-travel range as UpdateThumb. Mapping
        -- against the full frame width makes the thumb drift away from the
        -- cursor near either end and can oscillate when grabbed off-centre.
        local travelWidth = math.max(1, frame:GetWidth() - thumb:GetWidth() - 2)
        local travelLeft = frame:GetLeft() + 1 + (thumb:GetWidth() / 2)
        local cursorX = (mx / sScale) - (frame.dragCursorOffset or 0)
        local relX = (cursorX - travelLeft) / travelWidth
        currentVal = minVal + (relX * (maxVal - minVal))
        currentVal = math.max(minVal, math.min(maxVal, currentVal))

        UpdateThumb()
        if not deferCallback then
            RunCallback(false)
        end
    end

    local function StopDragging(frame)
        frame.isDragging = false
        frame.dragCursorOffset = nil
        frame:SetScript("OnUpdate", nil)
    end

    s:EnableMouse(true)
    s:SetScript("OnMouseDown", function(self)
        if self.disabled then return end
        self.isDragging = true
        local mx = GetCursorPosition()
        local scale = self:GetEffectiveScale() or 1
        local thumbLeft = thumb:GetLeft()
        if mx and thumbLeft and scale > 0 then
            local cursorX = mx / scale
            local thumbCenter = thumbLeft + (thumb:GetWidth() / 2)
            local offset = cursorX - thumbCenter
            -- Preserve where the thumb was grabbed so an off-centre click
            -- does not make it jump under the cursor on the first update.
            if math.abs(offset) <= (thumb:GetWidth() / 2) + 1 then
                self.dragCursorOffset = offset
            else
                self.dragCursorOffset = 0
            end
        else
            self.dragCursorOffset = 0
        end
        UpdateValueFromCursor(self)
        self:SetScript("OnUpdate", function(self)
            if self.disabled then
                StopDragging(self)
                return
            end
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                RunCallback(true)
                StopDragging(self)
                return
            end
            UpdateValueFromCursor(self)
        end)
    end)
    
    s:SetScript("OnMouseUp", function(self)
        if self.isDragging then
            -- Capture the final cursor position without firing a second live
            -- callback immediately before the committed/rounded callback.
            UpdateValueFromCursor(self, true)
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

    s.SetValue = function(self, val, forceWhileDragging)
        if self.isDragging and not forceWhileDragging then return end
        currentVal = math.max(minVal, math.min(maxVal, val))
        lastCallbackValue = currentVal
        UpdateThumb()
    end

    s.Disable = function(self)
        self.disabled = true
        StopDragging(self)
        self:EnableMouse(false)
    end

    s.Enable = function(self)
        self.disabled = false
        self:EnableMouse(true)
    end

    return s
end

local function CreateOptionsPanel()
    local currentTab = "General" 
    local nodeCheckboxStates = {}
    local activeCheckboxes = {}
    local currentNodesShown = {}

    local panel = CreateFrame("Frame", "PathMakerOptionsPanel")
    panel.name = "PathMaker"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("PathMaker")
    title:SetTextColor(1, 0.82, 0) -- Yellow text per design

    -- DOUBLE-LINE METALLIC BORDER CONTAINER
    local filterBox = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    filterBox:SetSize(640, 440)
    filterBox:SetPoint("TOPLEFT", 16, -70)
    filterBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1,
    })
    filterBox:SetBackdropColor(0.075, 0.075, 0.075, 0.94)
    filterBox:SetBackdropBorderColor(0.62, 0.43, 0.06, 1)

    local filterBoxInner = CreateFrame("Frame", nil, filterBox, "BackdropTemplate")
    filterBoxInner:SetPoint("TOPLEFT", 2, -2)
    filterBoxInner:SetPoint("BOTTOMRIGHT", -2, 2)
    filterBoxInner:SetBackdrop({
        bgFile = nil,
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1,
    })
    filterBoxInner:SetBackdropBorderColor(0.22, 0.16, 0.04, 0.9)

    -- INNER CONTAINERS FOR DIFFERENT TABS
    local NodePanel = CreateFrame("Frame", nil, filterBoxInner)
    NodePanel:SetAllPoints()

    -- Keep the clipping edges immediately inside the panel border.  An inset
    -- clip rect leaves partially clipped checkboxes/buttons visible in open
    -- space at the top and bottom while scrolling.
    local GeneralScrollFrame, GeneralPanel, GeneralScrollSlider = CreateDarkScrollArea(filterBoxInner, 608, 432)
    GeneralScrollFrame:SetPoint("TOPLEFT", 16, -2)
    GeneralPanel:SetSize(608, 432)
    GeneralScrollFrame:Hide()
    GeneralScrollSlider:Hide()
    
    local RoutePanel = CreateFrame("Frame", nil, filterBoxInner)
    RoutePanel:SetAllPoints()
    RoutePanel:Hide()
    addon.Options.routeManagerPanel = RoutePanel

    local DrawPanel = CreateFrame("Frame", nil, filterBoxInner)
    DrawPanel:SetAllPoints()
    DrawPanel:Hide()

    local DrawModePanel = CreateFrame("Frame", nil, filterBoxInner)
    DrawModePanel:SetAllPoints()
    DrawModePanel:Hide()
    addon.Options.drawModePanel = DrawModePanel

    -- TABS (Raised rectangular metallic boxes with hover states)
    local function CreateTabBtn(name, tabID, prevBtn, width)
        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn.tabID = tabID
        btn:SetSize(width, 32)
        if prevBtn then
            btn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
        else
            btn:SetPoint("BOTTOMLEFT", filterBox, "TOPLEFT", 10, 1)
        end
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, edgeSize = 1,
        })
        
        -- Bevel effect highlight (3D look)
        local topHighlight = btn:CreateTexture(nil, "OVERLAY")
        topHighlight:SetColorTexture(1, 1, 1, 0.05)
        topHighlight:SetHeight(2)
        topHighlight:SetPoint("TOPLEFT", 1, -1)
        topHighlight:SetPoint("TOPRIGHT", -1, -1)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(T(name))

        -- Hover Highlights
        btn:SetScript("OnEnter", function(self)
            if currentTab ~= self.tabID then
                self:SetBackdropColor(0.14, 0.14, 0.14, 1)
                self:SetBackdropBorderColor(0.75, 0.53, 0.08, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if currentTab ~= self.tabID then
                self:SetBackdropColor(0.075, 0.075, 0.075, 1)
                self:SetBackdropBorderColor(0.43, 0.31, 0.07, 1)
            end
        end)

        return btn
    end

    local tabGen = CreateTabBtn("General", "General", nil, 68)
    local tabHerb = CreateTabBtn("Herbalism", "Herb Gathering", tabGen, 78)
    local tabMine = CreateTabBtn("Mining", "Mining", tabHerb, 60)
    local tabTreasure = CreateTabBtn("Treasures", "Treasure", tabMine, 76)
    local tabDraw = CreateTabBtn("Route Generator", "Route Generator", tabTreasure, 116)
    local tabRoute = CreateTabBtn("Route Manager", "Route Manager", tabDraw, 108)
    local tabDrawMode = CreateTabBtn("Draw Mode", "Draw Mode", tabRoute, 80)

    local function UpdateTabVisuals()
        local tabs = {tabGen, tabHerb, tabMine, tabTreasure, tabDraw, tabRoute, tabDrawMode}
        for _, t in ipairs(tabs) do
            t:SetBackdropColor(0.075, 0.075, 0.075, 1)
            t:SetBackdropBorderColor(0.43, 0.31, 0.07, 1)
            if t.text then t.text:SetTextColor(0.62, 0.62, 0.62) end
            t:SetFrameLevel(filterBox:GetFrameLevel() - 1)
            if t.bottomCover then t.bottomCover:Hide() end
        end

        local activeTab
        for _, t in ipairs(tabs) do
            if t.tabID == currentTab then
                activeTab = t
                break
            end
        end

        if activeTab then
            activeTab:SetBackdropColor(0.13, 0.13, 0.13, 1)
            activeTab:SetBackdropBorderColor(1, 0.72, 0.08, 1)
            if activeTab.text then activeTab.text:SetTextColor(1, 0.82, 0) end
            activeTab:SetFrameLevel(filterBoxInner:GetFrameLevel() + 2)
            
            -- Seamless connection to inner frame (covers the main border)
            if not activeTab.bottomCover then
                activeTab.bottomCover = activeTab:CreateTexture(nil, "OVERLAY")
                activeTab.bottomCover:SetColorTexture(0.13, 0.13, 0.13, 1)
                activeTab.bottomCover:SetHeight(4) 
                activeTab.bottomCover:SetPoint("BOTTOMLEFT", 1, -2)
                activeTab.bottomCover:SetPoint("BOTTOMRIGHT", -1, -2)
            end
            activeTab.bottomCover:Show()
        end

        if panel.standaloneLayout then
            -- The standalone host owns both dimensions through anchors.
        elseif currentTab == "Draw Mode" then
            filterBox:SetSize(640, 521)
        else
            filterBox:SetSize(640, 440)
        end

        -- Panel Switching
        if currentTab == "General" then
            GeneralScrollFrame:Show()
            GeneralScrollSlider:Show()
            NodePanel:Hide()
            RoutePanel:Hide()
            DrawPanel:Hide()
            DrawModePanel:Hide()
        elseif currentTab == "Herb Gathering" or currentTab == "Mining" or currentTab == "Treasure" then
            GeneralScrollFrame:Hide()
            GeneralScrollSlider:Hide()
            NodePanel:Show()
            RoutePanel:Hide()
            DrawPanel:Hide()
            DrawModePanel:Hide()
            if panel.RefreshNodeList then panel.RefreshNodeList() end
        elseif currentTab == "Route Manager" then
            GeneralScrollFrame:Hide()
            GeneralScrollSlider:Hide()
            NodePanel:Hide()
            RoutePanel:Show()
            DrawPanel:Hide()
            DrawModePanel:Hide()
            if panel.RefreshRouteList then panel.RefreshRouteList() end
        elseif currentTab == "Route Generator" then
            GeneralScrollFrame:Hide()
            GeneralScrollSlider:Hide()
            NodePanel:Hide()
            RoutePanel:Hide()
            DrawPanel:Show()
            DrawModePanel:Hide()
            if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end
        elseif currentTab == "Draw Mode" then
            GeneralScrollFrame:Hide()
            GeneralScrollSlider:Hide()
            NodePanel:Hide()
            RoutePanel:Hide()
            DrawPanel:Hide()
            DrawModePanel:Show()
            if addon.selectedRouteGUID and addon.selectedRouteMapID
                and panel.SelectRouteInOptionsDrawMode
            then
                panel.SelectRouteInOptionsDrawMode(addon.selectedRouteGUID, addon.selectedRouteMapID)
            elseif panel.RefreshOptionsDrawMode then
                panel.RefreshOptionsDrawMode()
            end
        else
            GeneralScrollFrame:Hide()
            GeneralScrollSlider:Hide()
            NodePanel:Hide()
            RoutePanel:Hide()
            DrawPanel:Hide()
            DrawModePanel:Hide()
        end
    end

    tabGen:SetScript("OnClick", function()
        currentTab = "General"
        UpdateTabVisuals()
    end)

    tabHerb:SetScript("OnClick", function()
        currentTab = "Herb Gathering"
        UpdateTabVisuals()
    end)

    tabMine:SetScript("OnClick", function()
        currentTab = "Mining"
        UpdateTabVisuals()
    end)

    tabTreasure:SetScript("OnClick", function()
        currentTab = "Treasure"
        UpdateTabVisuals()
    end)

    tabRoute:SetScript("OnClick", function()
        currentTab = "Route Manager"
        UpdateTabVisuals()
    end)

    tabDraw:SetScript("OnClick", function()
        currentTab = "Route Generator"
        UpdateTabVisuals()
    end)

    tabDrawMode:SetScript("OnClick", function()
        currentTab = "Draw Mode"
        UpdateTabVisuals()
    end)

    UpdateTabVisuals()

    -- Helper Button Function across Option Panels
    local function CreateActionBtn(parent, text, width, height, colorTheme)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, height)
        btn:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false, edgeSize = 1,
        })
        
        if colorTheme == "red" then
            btn.leaveColor = {0.25, 0.05, 0.05, 0.9}
            btn.hoverColor = {0.35, 0.1, 0.1, 1}
            btn.borderColor = {0.6, 0.15, 0.15, 1}
            btn.textColor = {1, 0.4, 0.4}
        elseif colorTheme == "green" then
            btn.leaveColor = {0.05, 0.25, 0.05, 0.9}
            btn.hoverColor = {0.1, 0.35, 0.1, 1}
            btn.borderColor = {0.15, 0.6, 0.15, 1}
            btn.textColor = {0.4, 1, 0.4}
        else
            btn.leaveColor = {0.15, 0.15, 0.15, 0.9}
            btn.hoverColor = {0.25, 0.25, 0.25, 1}
            btn.borderColor = {0.4, 0.4, 0.4, 1}
            btn.textColor = {1, 0.82, 0}
        end
        
        btn:SetBackdropColor(unpack(btn.leaveColor))
        btn:SetBackdropBorderColor(unpack(btn.borderColor))
        
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(T(text))
        btn.text:SetTextColor(unpack(btn.textColor))
        
        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(self.hoverColor)) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(self.leaveColor)) end)
        
        return btn
    end


    -- ============================================================================
    -- ROUTE GENERATOR: AUTOMATIC ROUTES FROM ALREADY IMPORTED NODES
    -- ============================================================================
    local MAX_DRAW_ROUTE_NODE_TYPES = 5
    local drawNodeCheckboxStates = {}
    local drawNodeButtons = {}
    local currentDrawNodes = {}
    local drawScope = "ZONE"
    local drawRouteMode = (PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.drawRouteMode) == "FULL" and "FULL" or "HALF"
    local generatorSettings = EnsureOptionsSettings()
    local avoidAreaMode = generatorSettings.avoidAreaMode == "IGNORE" and "IGNORE" or "RESPECT"
    local verifiedOnlyFilter = generatorSettings.verifiedOnly == true
    local drawSelectedContinentID = nil
    local drawSelectedZoneID = nil
    local drawDropdowns = {}

    local function SetDrawDefaultScope()
        if drawSelectedZoneID and IsMapVisibleForExpansion(drawSelectedZoneID) then return end
        local currentMapID = C_Map.GetBestMapForUnit("player")
        local continentID, zone = FindDrawZoneForMap(currentMapID)
        if not currentMapID or not IsMapVisibleForExpansion(currentMapID) then continentID, zone = nil, nil end
        drawSelectedContinentID = continentID or GetDefaultDrawContinentID()
        local fallbackZones = GetSortedDrawZones(drawSelectedContinentID)
        drawSelectedZoneID = zone and zone.id or (fallbackZones[1] and fallbackZones[1].id) or GetDefaultDrawMapID()
    end

    local function GetDrawScopeMapTarget()
        SetDrawDefaultScope()
        if drawScope == "CONTINENT" then
            local lookup = {}
            for _, zone in ipairs(GetSortedDrawZones(drawSelectedContinentID)) do lookup[zone.id] = true end
            return lookup
        end
        return drawSelectedZoneID
    end

    local function GetDrawScopeMapIDs()
        local target = GetDrawScopeMapTarget()
        if type(target) == "table" then return target end
        return {[target] = true}
    end

    local function CountDrawScopeAvoidAreas()
        local count = 0
        for mapID in pairs(GetDrawScopeMapIDs()) do
            for _, area in ipairs(GetAvoidAreas(mapID)) do
                if type(area) == "table" and #area >= 3 then count = count + 1 end
            end
        end
        return count
    end

    local function CreateDrawDropdown(parent, width, height)
        local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b:SetSize(width, height)
        b:SetBackdrop({bgFile="Interface\\ChatFrame\\ChatFrameBackground", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
        b:SetBackdropColor(0, 0, 0, 1)
        b:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 6, 0)
        b.text:SetPoint("RIGHT", -24, 0)
        b.text:SetJustifyH("LEFT")
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        b.arrow:SetVertexColor(1, 0.82, 0)
        b.arrow:SetSize(16, 16)
        b.arrow:SetPoint("RIGHT", -4, 0)
        b.menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        b.menu:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -1)
        b.menu:SetSize(width, 160)
        b.menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
        b.menu:SetBackdropColor(0, 0, 0, 1)
        b.menu:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        b.menu:SetFrameStrata("FULLSCREEN_DIALOG")
        b.menu:SetFrameLevel(math.max((parent:GetFrameLevel() or 1) + 200, 9000))
        if b.menu.SetToplevel then b.menu:SetToplevel(true) end
        b.menu:SetClampedToScreen(true)
        b.menu:EnableMouse(true)
        b.menu:Hide()
        b.items = {}
        b:SetScript("OnClick", function(self)
            for _, dd in ipairs(drawDropdowns) do if dd ~= self then dd.menu:Hide() end end
            if self.menu:IsShown() then
                self.menu:Hide()
            else
                self.menu:Show()
                self.menu:Raise()
            end
        end)
        table.insert(drawDropdowns, b)
        return b
    end

    local function StyleLocationDropdown(dropdown)
        local gold = {0.78, 0.58, 0.14, 0.95}
        dropdown:SetBackdropBorderColor(unpack(gold))
        dropdown.menu:SetBackdropBorderColor(unpack(gold))
        dropdown:HookScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.78, 0.22, 1)
        end)
        dropdown:HookScript("OnLeave", function(self)
            self:SetBackdropBorderColor(unpack(gold))
        end)
        dropdown.menu:HookScript("OnShow", function(self)
            self:SetBackdropBorderColor(1, 0.72, 0.18, 1)
        end)
        dropdown.menu:HookScript("OnHide", function(self)
            self:SetBackdropBorderColor(unpack(gold))
        end)
    end

    local continentDrop = CreateDrawDropdown(DrawPanel, 250, 24)
    continentDrop:SetPoint("TOPLEFT", 16, -10)
    local zoneDrop = CreateDrawDropdown(DrawPanel, 320, 24)
    zoneDrop:SetPoint("LEFT", continentDrop, "RIGHT", 8, 0)
    StyleLocationDropdown(continentDrop)
    StyleLocationDropdown(zoneDrop)

    local drawSepLine = DrawPanel:CreateTexture(nil, "ARTWORK")
    drawSepLine:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    drawSepLine:SetHeight(1)
    drawSepLine:SetPoint("TOPLEFT", 10, -42)
    drawSepLine:SetPoint("TOPRIGHT", -10, -42)

    local function CreatePresetRow(label, values, selectedValue, y, onSelect)
        local title = DrawPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 16, y)
        title:SetWidth(95)
        title:SetJustifyH("LEFT")
        title:SetText(label)
        local buttons = {}
        local x = 112
        local function Refresh(value)
            selectedValue = value
            for _, button in ipairs(buttons) do
                button.text:SetText((button.value == selectedValue and "|cff44ff44[X]|r " or "[ ] ") .. button.label)
            end
        end
        for _, option in ipairs(values) do
            local button = CreateActionBtn(DrawPanel, option.label, option.width or 92, 20, "normal")
            button:SetPoint("TOPLEFT", x, y + 3)
            button.value, button.label = option.value, option.label
            button:SetScript("OnClick", function()
                Refresh(button.value)
                onSelect(button.value)
            end)
            buttons[#buttons + 1] = button
            x = x + (option.width or 92) + 4
        end
        Refresh(selectedValue)
        return Refresh, buttons
    end

    local refreshAvoidAreaRow, avoidAreaButtons = CreatePresetRow("Avoid Areas", {
        {label="Respect drawn (0)", value="RESPECT", width=132}, {label="Ignore", value="IGNORE", width=92},
    }, avoidAreaMode, -52, function(value)
        avoidAreaMode = value; PathmakerDB.settings.avoidAreaMode = value
    end)
    local function UpdateAvoidAreaRow()
        avoidAreaButtons[1].label = string.format("Respect drawn (%d)", CountDrawScopeAvoidAreas())
        refreshAvoidAreaRow(avoidAreaMode)
    end
    UpdateAvoidAreaRow()

    local verifiedOnlyCheck = CreateFrame("CheckButton", nil, DrawPanel, "UICheckButtonTemplate")
    verifiedOnlyCheck:SetSize(20, 20)
    verifiedOnlyCheck:SetPoint("TOPLEFT", 360, -49)
    verifiedOnlyCheck.text = verifiedOnlyCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verifiedOnlyCheck.text:SetPoint("LEFT", verifiedOnlyCheck, "RIGHT", 2, 0)
    verifiedOnlyCheck.text:SetText(T("Verified Nodes Only"))
    verifiedOnlyCheck:SetHitRectInsets(0, -140, 0, 0)
    verifiedOnlyCheck:SetChecked(verifiedOnlyFilter)
    verifiedOnlyCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("Verified Nodes Only"))
        GameTooltip:AddLine(T("Only use nodes you have actually gathered on this server. Bundled/imported nodes that have not been confirmed yet are left out of generated routes."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    verifiedOnlyCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    verifiedOnlyCheck:SetScript("OnClick", function(self)
        verifiedOnlyFilter = self:GetChecked() and true or false
        PathmakerDB.settings.verifiedOnly = verifiedOnlyFilter
    end)

    local drawMapText = DrawPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    drawMapText:SetPoint("TOPLEFT", 16, -78)
    drawMapText:SetText("Imported Nodes")
    drawMapText:SetTextColor(1, 0.82, 0)

    local drawScrollFrame, drawScrollChild, drawScrollSlider = CreateDarkScrollArea(DrawPanel, 608, 286)
    drawScrollFrame:SetPoint("TOPLEFT", 16, -103)

    local fullRouteModeBtn = CreateActionBtn(DrawPanel, "Full Route", 80, 24, "normal")
    fullRouteModeBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    local halfRouteModeBtn = CreateActionBtn(DrawPanel, "Half Routes", 90, 24, "normal")
    halfRouteModeBtn:SetPoint("RIGHT", fullRouteModeBtn, "LEFT", -5, 0)
    local generateDrawRouteBtn = CreateActionBtn(DrawPanel, "Generate Route", 125, 24, "green")
    generateDrawRouteBtn:SetPoint("RIGHT", halfRouteModeBtn, "LEFT", -10, 0)
    local drawSelectNoneBtn = CreateActionBtn(DrawPanel, "Select None", 85, 24, "red")
    drawSelectNoneBtn:SetPoint("RIGHT", generateDrawRouteBtn, "LEFT", -10, 0)
    local drawStatusText = DrawPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    drawStatusText:SetPoint("RIGHT", drawSelectNoneBtn, "LEFT", -10, 0)
    drawStatusText:SetText("0/" .. MAX_DRAW_ROUTE_NODE_TYPES .. " selected")

    local function UpdateDrawRouteModeButtons()
        local function PaintModeButton(btn, active)
            if active then
                btn.leaveColor = {0.05, 0.25, 0.05, 0.9}
                btn.hoverColor = {0.1, 0.35, 0.1, 1}
                btn.borderColor = {0.15, 0.6, 0.15, 1}
                btn.textColor = {0.4, 1, 0.4}
            else
                btn.leaveColor = {0.15, 0.15, 0.15, 0.9}
                btn.hoverColor = {0.25, 0.25, 0.25, 1}
                btn.borderColor = {0.4, 0.4, 0.4, 1}
                btn.textColor = {1, 0.82, 0}
            end
            btn:SetBackdropColor(unpack(btn.leaveColor))
            btn:SetBackdropBorderColor(unpack(btn.borderColor))
            btn.text:SetTextColor(unpack(btn.textColor))
        end
        PaintModeButton(halfRouteModeBtn, drawRouteMode == "HALF")
        PaintModeButton(fullRouteModeBtn, drawRouteMode == "FULL")
    end

    local function SetDrawRouteMode(mode)
        drawRouteMode = mode == "FULL" and "FULL" or "HALF"
        PathmakerDB = PathmakerDB or {}
        PathmakerDB.settings = PathmakerDB.settings or {}
        PathmakerDB.settings.drawRouteMode = drawRouteMode
        UpdateDrawRouteModeButtons()
    end

    halfRouteModeBtn:SetScript("OnClick", function() SetDrawRouteMode("HALF") end)
    fullRouteModeBtn:SetScript("OnClick", function() SetDrawRouteMode("FULL") end)
    UpdateDrawRouteModeButtons()

    local function RefreshDrawDropdowns()
        SetDrawDefaultScope()
        UpdateAvoidAreaRow()
        continentDrop.text:SetText("Continent: " .. (CONTINENT_LABELS[drawSelectedContinentID] or "Unknown"))
        if drawScope == "CONTINENT" then zoneDrop.text:SetText("Zone: All " .. (CONTINENT_LABELS[drawSelectedContinentID] or "Continent")) else zoneDrop.text:SetText("Zone: " .. GetDrawZoneName(drawSelectedZoneID)) end
        for _, child in ipairs(continentDrop.items) do child:Hide() end
        wipe(continentDrop.items)
        for i, continentID in ipairs(GetVisibleContinentOrder()) do
            local rowContinentID = continentID
            local row = CreateFrame("Button", nil, continentDrop.menu, "BackdropTemplate")
            row:SetSize(continentDrop:GetWidth() - 10, 15)
            row:SetPoint("TOPLEFT", 5, -5 - ((i - 1) * 20))
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"})
            row:SetBackdropColor(0, 0, 0, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetText(CONTINENT_LABELS[rowContinentID] or tostring(rowContinentID))
            row:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.18, 0.18, 1) end)
            row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
            row:SetScript("OnClick", function()
                drawSelectedContinentID = rowContinentID
                drawScope = "CONTINENT"
                continentDrop.menu:Hide()
                RefreshDrawDropdowns()
                if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end
            end)
            table.insert(continentDrop.items, row)
        end
        continentDrop.menu:SetHeight(math.max(24, (#continentDrop.items * 20) + 10))
        for _, child in ipairs(zoneDrop.items) do child:Hide() end
        wipe(zoneDrop.items)
        local zones = GetSortedDrawZones(drawSelectedContinentID)
        local zoneColWidth = 155
        local zoneRows = math.max(1, math.ceil(#zones / 2))
        zoneDrop.menu:SetWidth((2 * zoneColWidth) + 10)
        for i, zone in ipairs(zones) do
            local rowZone = zone
            local row = CreateFrame("Button", nil, zoneDrop.menu, "BackdropTemplate")
            row:SetSize(zoneColWidth, 15)
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"})
            row:SetBackdropColor(0, 0, 0, 0)
            local rowCol = math.floor((i - 1) / zoneRows)
            local rowIndex = (i - 1) % zoneRows
            row:SetPoint("TOPLEFT", 5 + (rowCol * zoneColWidth), -5 - (rowIndex * 20))
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetText(rowZone.name)
            row:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.18, 0.18, 1) end)
            row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
            row:SetScript("OnClick", function()
                drawSelectedZoneID = rowZone.id
                drawScope = "ZONE"
                zoneDrop.menu:Hide()
                RefreshDrawDropdowns()
                if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end
            end)
            table.insert(zoneDrop.items, row)
        end
        zoneDrop.menu:SetHeight(math.max(24, (zoneRows * 20) + 10))
    end

    drawSelectNoneBtn:SetScript("OnClick", function()
        for nodeName in pairs(drawNodeCheckboxStates) do drawNodeCheckboxStates[nodeName] = false end
        if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end
    end)

    generateDrawRouteBtn:SetScript("OnClick", function()
        local selected = {}
        local selectedCount = 0
        for nodeName, checked in pairs(drawNodeCheckboxStates) do if checked then selected[nodeName] = true selectedCount = selectedCount + 1 end end
        local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
        if selectedCount == 0 then if not hideErr then print("|cFFFF4444PathMaker:|r Select one imported node type in Route Generator first.") end return end
        if selectedCount > MAX_DRAW_ROUTE_NODE_TYPES then if not hideErr then print(string.format("|cFFFF4444PathMaker:|r Select %d or fewer node types at once.", MAX_DRAW_ROUTE_NODE_TYPES)) end return end
        local builtRoutes, skippedTooFew = addon.Options:BuildImportedNodeRoutes(selected, MAX_DRAW_ROUTE_NODE_TYPES, GetDrawScopeMapTarget(), drawRouteMode, {
            avoidAreaMode=avoidAreaMode,
            verifiedOnly=verifiedOnlyFilter,
        })
        local hideRouteMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgGeneratedRoutes
        if builtRoutes > 0 and not hideRouteMsg then print(string.format("|cFF00FF00PathMaker:|r Generated %d route(s) from selected imported nodes.", builtRoutes)) elseif builtRoutes == 0 and not hideErr then print("|cFFFF4444PathMaker:|r Not enough imported points for the selected node type(s).") end
        if skippedTooFew and skippedTooFew > 0 and not hideErr then print(string.format("|cFFFFCC00PathMaker:|r Skipped %d node type(s) with fewer than 2 points.", skippedTooFew)) end
        if panel.RefreshRouteList then panel.RefreshRouteList() end
        if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end
        if builtRoutes > 0 and panel.SelectRouteInOptionsDrawMode then
            panel.SelectRouteInOptionsDrawMode(addon.selectedRouteGUID, addon.selectedRouteMapID)
        elseif panel.RefreshOptionsDrawMode then
            panel.RefreshOptionsDrawMode()
        end
        if builtRoutes > 0 and addon.Planner and addon.Planner.ShowGeneratedRoute then
            addon.Planner:ShowGeneratedRoute(addon.selectedRouteGUID, addon.selectedRouteMapID)
        end
        if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
        if addon.MapFrame and addon.MapFrame.UpdateUIState then addon.MapFrame:UpdateUIState() end
        if addon.UI then addon.UI:RefreshRendering() end
    end)

    panel.RefreshDrawNodeList = function()
        RefreshDrawDropdowns()
        for _, cb in pairs(drawNodeButtons) do cb:Hide() end
        wipe(currentDrawNodes)
        local mapTargets = GetDrawScopeMapIDs()
        drawMapText:SetText(drawScope == "CONTINENT" and ("Imported Nodes: " .. (CONTINENT_LABELS[drawSelectedContinentID] or "Continent")) or ("Imported Nodes: " .. GetDrawZoneName(drawSelectedZoneID)))
        local searchText = ""
        local counts = {}
        if PathmakerDB and PathmakerDB.nodes then
            for mapID in pairs(mapTargets) do
                if PathmakerDB.nodes[mapID] then
                    for _, node in ipairs(PathmakerDB.nodes[mapID]) do
                        local nodeName = node.specificName or node.name or node.type
                        if nodeName and (searchText == "" or nodeName:lower():find(searchText, 1, true)) then counts[nodeName] = (counts[nodeName] or 0) + 1 end
                    end
                end
            end
        end
        for nodeName in pairs(counts) do table.insert(currentDrawNodes, nodeName) end
        table.sort(currentDrawNodes)
        local selectedCount = 0
        for _, checked in pairs(drawNodeCheckboxStates) do if checked then selectedCount = selectedCount + 1 end end
        drawStatusText:SetText(string.format("%d/%d selected", selectedCount, MAX_DRAW_ROUTE_NODE_TYPES))
        drawStatusText:SetTextColor(selectedCount > MAX_DRAW_ROUTE_NODE_TYPES and 1 or 0.6, selectedCount > MAX_DRAW_ROUTE_NODE_TYPES and 0.25 or 0.6, selectedCount > MAX_DRAW_ROUTE_NODE_TYPES and 0.25 or 0.6)
        for i, nodeName in ipairs(currentDrawNodes) do
            local cb = drawNodeButtons[i]
            if not cb then
                cb = CreateFrame("CheckButton", nil, drawScrollChild, "UICheckButtonTemplate")
                cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                cb.text:SetPoint("LEFT", cb, "RIGHT", 0, 0)
                cb.text:SetWidth(125)
                cb.text:SetJustifyH("LEFT")
                cb.text:SetWordWrap(false)
                cb.countText = cb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                cb.countText:SetPoint("LEFT", cb.text, "RIGHT", 4, 0)
                cb.countText:SetWidth(35)
                cb.countText:SetJustifyH("RIGHT")
                cb.countText:SetWordWrap(false)
                cb:SetHitRectInsets(0, -160, 0, 0)
                cb:SetScript("OnEnter", function(self)
                    if not self.pmNodeNameTruncated then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.pmFullNodeName or self.nodeName or "")
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function(self)
                    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
                end)
                drawNodeButtons[i] = cb
            end
            cb.nodeName = nodeName
            cb:SetScript("OnClick", function(self) drawNodeCheckboxStates[self.nodeName] = self:GetChecked() == true if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end end)
            cb:SetChecked(drawNodeCheckboxStates[nodeName] == true)
            local profession = GetNodeProfession(nodeName)
            local _, color, label = GetNodeVisual(profession)
            local fullNodeName = FormatNodeName(nodeName)
            local displayName, wasTruncated = TruncateNodeDisplayName(fullNodeName, 17)
            if addon.NODE_ICONS and addon.NODE_ICONS[nodeName] then displayName = string.format("|T%s:18:18:0:0|t %s", addon.NODE_ICONS[nodeName], displayName) end
            cb.text:SetText(displayName)
            cb.pmFullNodeName = fullNodeName
            cb.pmNodeNameTruncated = wasTruncated
            cb.text:SetTextColor(color[1], color[2], color[3], 1)
            cb.countText:SetText(tostring(counts[nodeName] or 0))
            local numRows = math.ceil(#currentDrawNodes / 3)
            local col = math.floor((i - 1) / numRows)
            local row = (i - 1) % numRows
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", 12 + (col * 196), -0 - (row * 28))
            cb:Show()
        end
        drawScrollChild:SetHeight(math.max(1, math.ceil(#currentDrawNodes / 3) * 28))
        drawScrollSlider:SetMinMaxValues(0, math.max(0, drawScrollChild:GetHeight() - drawScrollFrame:GetHeight()))
    end
    -- ============================================================================
    -- ROUTE MANAGER PANEL (VISUALLY MATCHING SCREENSHOT)
    -- ============================================================================
    addon.Options.routeSearchFilter = ""
    addon.Options.routeColorFilter = nil
    addon.Options.showAllZones = true
    local routeButtons = {}
    local routeGroupHeaders = {}

    local function CopyRoutePoint(point)
        local copy = {}
        for key, value in pairs(point or {}) do
            copy[key] = value
        end
        return copy
    end

    local function CopyRouteData(routeData)
        if type(routeData) ~= "table" then return nil end
        local copy = {}
        for key, value in pairs(routeData) do
            if type(value) == "table" then
                local valueCopy = {}
                for childKey, childValue in pairs(value) do
                    if type(childValue) == "table" then
                        valueCopy[childKey] = CopyRoutePoint(childValue)
                    else
                        valueCopy[childKey] = childValue
                    end
                end
                copy[key] = valueCopy
            else
                copy[key] = value
            end
        end
        return copy
    end

    local function PushLimitedHistory(historyKey, entry)
        addon.Options[historyKey] = addon.Options[historyKey] or {}
        table.insert(addon.Options[historyKey], entry)
        while #addon.Options[historyKey] > 40 do
            table.remove(addon.Options[historyKey], 1)
        end
    end

    local function GetRoutePointList(routeData)
        if type(routeData) ~= "table" then return nil end
        if type(routeData.points) == "table" then return routeData.points end
        if type(routeData.route) == "table" then return routeData.route end
        if type(routeData.nodes) == "table" then return routeData.nodes end
        return nil
    end

    local function IsRouteData(routeData)
        if addon.Routes and addon.Routes.IsRouteData then return addon.Routes:IsRouteData(routeData) end
        return GetRoutePointList(routeData) ~= nil
    end

    local function RefreshRoutesAfterEdit()
        if panel.RefreshRouteList then panel.RefreshRouteList() end
        if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
        if addon.MapFrame and addon.MapFrame.UpdateUIState then addon.MapFrame:UpdateUIState() end
        if addon.UI then addon.UI:RefreshRendering() end
    end

    local function RouteExists(mapID, guid)
        local route = PathmakerDB and PathmakerDB.routes and PathmakerDB.routes[mapID] and PathmakerDB.routes[mapID][guid]
        return IsRouteData(route)
    end

    local function CombineRoutesInSameZone(sourceMapID, sourceGUID, targetMapID, targetGUID, skipHistory)
        local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
        if not sourceMapID or not sourceGUID or not targetMapID or not targetGUID then return false end
        if sourceGUID == targetGUID then return false end
        if sourceMapID ~= targetMapID then
            if not hideErr then
                print("|cFFFF4444PathMaker:|r Routes can only be combined when they are in the same zone.")
            end
            return false
        end
        if not PathmakerDB or not PathmakerDB.routes or not PathmakerDB.routes[targetMapID] then return false end

        local sourceRoute = PathmakerDB.routes[sourceMapID] and PathmakerDB.routes[sourceMapID][sourceGUID]
        local targetRoute = PathmakerDB.routes[targetMapID][targetGUID]
        local sourcePoints = GetRoutePointList(sourceRoute)
        local targetPoints = GetRoutePointList(targetRoute)
        if not sourceRoute or not targetRoute or not sourcePoints or not targetPoints then return false end

        if not skipHistory then
            PushLimitedHistory("combineUndoHistory", {
                targetMapID = targetMapID,
                targetGUID = targetGUID,
                targetRoute = CopyRouteData(targetRoute),
                sources = {
                    {mapID = sourceMapID, guid = sourceGUID, route = CopyRouteData(sourceRoute)}
                }
            })
        end

        local combinedPoints = {}
        for _, point in ipairs(targetPoints) do table.insert(combinedPoints, CopyRoutePoint(point)) end
        for _, point in ipairs(sourcePoints) do table.insert(combinedPoints, CopyRoutePoint(point)) end
        local combinedScaleX, combinedScaleY = GetRouteMapScale(targetMapID)
        if #combinedPoints >= 3 then
            combinedPoints = OptimizeClockwiseRoute(combinedPoints, combinedScaleX, combinedScaleY)
        end

        targetRoute.points = combinedPoints
        targetRoute.route = combinedPoints
        targetRoute.nodes = combinedPoints
        targetRoute.combinedRoute = true
        targetRoute.avoidCrossing = true
        targetRoute.mapScaleX = combinedScaleX
        targetRoute.mapScaleY = combinedScaleY
        targetRoute.combinedFrom = targetRoute.combinedFrom or {}
        table.insert(targetRoute.combinedFrom, sourceRoute.name or sourceGUID)

        PathmakerDB.routes[sourceMapID][sourceGUID] = nil
        addon.selectedRouteGUID = targetGUID
        addon.selectedRouteMapID = targetMapID

        local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgGeneratedRoutes
        if not hideMsg then
            print("|cFF00FF00PathMaker:|r Combined routes in the same zone.")
        end
        RefreshRoutesAfterEdit()
        return true
    end

    local function ConfirmPendingRouteCombines()
        local target = addon.Options.combineTargetRoute
        local pending = addon.Options.combinePendingRoutes
        local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
        if not target or not RouteExists(target.mapID, target.guid) or not pending or not next(pending) then
            if not hideErr then
                print("|cFFFFCC00PathMaker:|r Pick a Combined target and at least one same-zone route first.")
            end
            return
        end

        local targetRoute = PathmakerDB.routes[target.mapID][target.guid]
        local transaction = {
            targetMapID = target.mapID,
            targetGUID = target.guid,
            targetRoute = CopyRouteData(targetRoute),
            sources = {}
        }

        local ordered = {}
        for guid, routeInfo in pairs(pending) do
            table.insert(ordered, {guid = guid, mapID = routeInfo.mapID})
        end
        table.sort(ordered, function(a, b) return tostring(a.guid) < tostring(b.guid) end)

        local combinedCount = 0
        for _, routeInfo in ipairs(ordered) do
            if routeInfo.mapID == target.mapID and routeInfo.guid ~= target.guid and RouteExists(routeInfo.mapID, routeInfo.guid) then
                table.insert(transaction.sources, {
                    mapID = routeInfo.mapID,
                    guid = routeInfo.guid,
                    route = CopyRouteData(PathmakerDB.routes[routeInfo.mapID][routeInfo.guid])
                })
                if CombineRoutesInSameZone(routeInfo.mapID, routeInfo.guid, target.mapID, target.guid, true) then
                    combinedCount = combinedCount + 1
                end
            end
        end

        addon.Options.combineTargetRoute = nil
        addon.Options.combinePendingRoutes = nil
        if combinedCount > 0 then
            PushLimitedHistory("combineUndoHistory", transaction)
        end
        RefreshRoutesAfterEdit()
    end

    local function UndoLastRouteCombine()
        local history = addon.Options.combineUndoHistory
        local entry = history and table.remove(history)
        if not entry then return end
        PathmakerDB.routes = PathmakerDB.routes or {}
        PathmakerDB.routes[entry.targetMapID] = PathmakerDB.routes[entry.targetMapID] or {}
        PathmakerDB.routes[entry.targetMapID][entry.targetGUID] = CopyRouteData(entry.targetRoute)
        for _, source in ipairs(entry.sources or {}) do
            PathmakerDB.routes[source.mapID] = PathmakerDB.routes[source.mapID] or {}
            PathmakerDB.routes[source.mapID][source.guid] = CopyRouteData(source.route)
        end
        addon.Options.combineTargetRoute = nil
        addon.Options.combinePendingRoutes = nil
        addon.selectedRouteGUID = entry.targetGUID
        addon.selectedRouteMapID = entry.targetMapID
        RefreshRoutesAfterEdit()
    end

    local function RestoreLastDeletedRoute()
        local history = addon.Options.deletedRouteHistory
        local entry = history and table.remove(history)
        if not entry then return end
        PathmakerDB.routes = PathmakerDB.routes or {}
        PathmakerDB.routes[entry.mapID] = PathmakerDB.routes[entry.mapID] or {}
        local guid = entry.guid
        if PathmakerDB.routes[entry.mapID][guid] then
            local baseGUID = guid .. "_RESTORED_" .. tostring(time())
            guid = baseGUID
            local suffix = 1
            while PathmakerDB.routes[entry.mapID][guid] do
                suffix = suffix + 1
                guid = baseGUID .. "_" .. tostring(suffix)
            end
        end
        PathmakerDB.routes[entry.mapID][guid] = CopyRouteData(entry.route)
        addon.selectedRouteGUID = guid
        addon.selectedRouteMapID = entry.mapID
        RefreshRoutesAfterEdit()
    end

    -- ============================================================================
    -- OPTIONS DRAW MODE
    -- ============================================================================
    local function BuildOptionsDrawMode()
    local optDrawMapID = GetDefaultDrawMapID()
    local optDrawContinentID = nil
    local optDrawSelectedGUID = nil
    local optDrawSelectedMapID = nil
    local optDrawDraft = { points = {}, color = (addon.Routes and addon.Routes.Palette and addon.Routes.Palette[1]) or {1, 1, 1, 1}, thickness = 2 }
    local optDrawAvoidDraft = {}
    local optDrawTool = "PENCIL"
    local optDrawTimer = 1
    local optDrawZoom = 1
    local optDrawPanX = 0
    local optDrawPanY = 0
    local optDrawCoordinateBounds = {0, 0, 1, 1}
    local optDrawIsDrawing = false
    local optDrawIsPanning = false
    local optDrawHoverElapsed = 0
    local optDrawPanStart = {x = 0, y = 0, panX = 0, panY = 0}
    local optDrawGhostOn = false
    local optDrawUndoStack = {}
    local optDrawRedoStack = {}
    local optDrawRouteButtons = {}
    local optDrawLines = {}
    local optDrawDots = {}
    local optDrawLinePool = {}
    local optDrawDotPool = {}
    local optDrawMapTextures = {}
    local optDrawMapArtMapID = nil
    local optDrawPaletteButtons = {}
    local OptDrawRefreshCanvas

    local function OptDrawMapToCanvasXY(x, y)
        local bounds = optDrawCoordinateBounds
        local width = math.max(0.000001, bounds[3] - bounds[1])
        local height = math.max(0.000001, bounds[4] - bounds[2])
        return ((x or 0) - bounds[1]) / width, ((y or 0) - bounds[2]) / height
    end

    local function OptDrawCanvasToMapXY(x, y)
        local bounds = optDrawCoordinateBounds
        return bounds[1] + ((x or 0) * (bounds[3] - bounds[1])),
            bounds[2] + ((y or 0) * (bounds[4] - bounds[2]))
    end

    -- Classic map canvases can expose explored/partial art rather than a
    -- stable full-zone background. Use the complete references bundled for
    -- the image importer in Settings Draw Mode on Era and TBC clients.
    local optDrawClassicReferenceMaps = {
        [1411]={720,452}, [1412]={1002,668}, [1413]={1002,668}, [1416]={720,452},
        [1417]={720,452}, [1418]={720,452}, [1419]={720,452}, [1420]={720,452},
        [1421]={1002,668}, [1422]={1002,668}, [1423]={720,452}, [1424]={1002,668},
        [1425]={720,452}, [1426]={1002,668}, [1427]={1002,668}, [1428]={720,452},
        [1429]={1002,668}, [1430]={1002,668}, [1431]={720,452}, [1432]={720,452},
        [1433]={845,530}, [1434]={720,452}, [1435]={720,452}, [1436]={1002,668},
        [1437]={720,452}, [1438]={720,452}, [1439]={720,452}, [1440]={720,452},
        [1441]={720,452}, [1442]={720,452}, [1443]={1002,668}, [1444]={720,452},
        [1445]={720,452}, [1446]={720,452}, [1447]={720,452}, [1448]={720,452},
        [1449]={720,452}, [1450]={720,452}, [1451]={1002,668}, [1452]={1002,668},
    }
    local optDrawTBCReferenceMaps = {
        [1941]={720,452}, [1942]={720,452}, [1943]={720,452}, [1944]={720,452},
        [1946]={720,452}, [1948]={720,452}, [1949]={720,452}, [1950]={720,452},
        [1951]={720,452}, [1952]={720,452}, [1953]={720,452}, [1957]={720,452},
    }

    local function OptDrawCopyPoints(points)
        local copy = {}
        for _, p in ipairs(points or {}) do
            table.insert(copy, CopyRoutePoint(p))
        end
        return copy
    end

    local function OptDrawPushUndo()
        if #optDrawUndoStack > 50 then table.remove(optDrawUndoStack, 1) end
        table.insert(optDrawUndoStack, OptDrawCopyPoints(optDrawDraft.points))
        wipe(optDrawRedoStack)
    end

    local function OptDrawReverseDraft()
        local pts = optDrawDraft.points
        local n = #pts
        if n < 2 then return end
        local oldMeta = {}
        for i = 1, n do
            oldMeta[i] = {
                isGap = pts[i].isGap,
                isMarker = pts[i].isMarker,
                duration = pts[i].duration,
                name = pts[i].name,
            }
        end
        for i = 1, math.floor(n / 2) do
            pts[i], pts[n - i + 1] = pts[n - i + 1], pts[i]
        end
        for i = 1, n - 1 do
            pts[i].isGap = oldMeta[n - i].isGap
            pts[i].isMarker = oldMeta[n - i].isMarker
            pts[i].duration = oldMeta[n - i].duration
            pts[i].name = oldMeta[n - i].name
        end
        pts[n].isGap = true
    end

    local function OptDrawPrepareStroke(nx, ny)
        local pts = optDrawDraft.points
        if #pts == 0 or not nx or not ny then return end
        local first, last = pts[1], pts[#pts]
        if optDrawTool == "MARKER" then
            if last and (not last.isMarker or last.duration ~= optDrawTimer) then
                last.isGap = true
            end
            return
        end
        if optDrawTool == "PENCIL" then
            local dFirst = math.sqrt((first.x - nx) ^ 2 + (first.y - ny) ^ 2)
            local dLast = math.sqrt((last.x - nx) ^ 2 + (last.y - ny) ^ 2)
            local threshold = 0.03
            if dFirst < threshold and dFirst < dLast then
                OptDrawReverseDraft()
                optDrawDraft.points[#optDrawDraft.points].isGap = false
            elseif dLast < threshold then
                optDrawDraft.points[#optDrawDraft.points].isGap = false
            else
                optDrawDraft.points[#optDrawDraft.points].isGap = true
            end
        elseif optDrawTool == "ERASER" then
            local dFirst = math.sqrt((first.x - nx) ^ 2 + (first.y - ny) ^ 2)
            local dLast = math.sqrt((last.x - nx) ^ 2 + (last.y - ny) ^ 2)
            if dFirst < dLast then OptDrawReverseDraft() end
        end
    end

    local function OptDrawRefreshExternal()
        if panel.RefreshRouteList then panel.RefreshRouteList() end
        if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
        if addon.MapFrame and addon.MapFrame.UpdateUIState then addon.MapFrame:UpdateUIState() end
        if addon.UI then addon.UI:RefreshRendering() end
    end

    local function OptDrawSameColor(a, b)
        if not a or not b then return false end
        return math.abs((a[1] or 0) - (b[1] or 0)) < 0.001
            and math.abs((a[2] or 0) - (b[2] or 0)) < 0.001
            and math.abs((a[3] or 0) - (b[3] or 0)) < 0.001
    end

    local function OptDrawFindRouteByGUID(guid)
        if not guid or not PathmakerDB or not PathmakerDB.routes then return nil, nil end
        if optDrawSelectedMapID and PathmakerDB.routes[optDrawSelectedMapID] and PathmakerDB.routes[optDrawSelectedMapID][guid] then
            return optDrawSelectedMapID, PathmakerDB.routes[optDrawSelectedMapID][guid]
        end
        for mapID, routes in pairs(PathmakerDB.routes) do
            if routes and routes[guid] then
                return mapID, routes[guid]
            end
        end
        return nil, nil
    end

    local function OptDrawClearSelectedRoute()
        if addon.selectedRouteGUID == optDrawSelectedGUID then
            addon.selectedRouteGUID = nil
            addon.selectedRouteMapID = nil
        end
        optDrawSelectedGUID = nil
        optDrawSelectedMapID = nil
        wipe(optDrawDraft.points)
        if DrawModePanel.renameBox then DrawModePanel.renameBox:SetText("") end
    end

    local optDrawContinentDrop = CreateDrawDropdown(DrawModePanel, 250, 24)
    optDrawContinentDrop:SetPoint("TOPLEFT", 16, -10)
    local optDrawZoneDrop = CreateDrawDropdown(DrawModePanel, 320, 24)
    optDrawZoneDrop:SetPoint("LEFT", optDrawContinentDrop, "RIGHT", 8, 0)

    StyleLocationDropdown(optDrawContinentDrop)
    StyleLocationDropdown(optDrawZoneDrop)
    local optDrawDropdownContinentID = nil

    local optDrawMapFrame = CreateFrame("Frame", nil, DrawModePanel, "BackdropTemplate")
    optDrawMapFrame:SetPoint("TOP", DrawModePanel, "TOP", 0, -42)
    optDrawMapFrame:SetSize(616, 325)
    optDrawMapFrame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    optDrawMapFrame:SetBackdropColor(0.03, 0.03, 0.03, 1)
    optDrawMapFrame:SetBackdropBorderColor(0.78, 0.58, 0.14, 0.95)
    optDrawMapFrame:EnableMouse(true)
    optDrawMapFrame:EnableMouseWheel(true)
    if optDrawMapFrame.SetClipsChildren then optDrawMapFrame:SetClipsChildren(true) end

    local function OptDrawTooltip(frame, title, body)
        frame:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetFrameStrata("TOOLTIP")
            GameTooltip:SetFrameLevel(10000)
            GameTooltip:SetText(title, 1, 0.82, 0)
            if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        frame:HookScript("OnLeave", function(self)
            if GameTooltip and (not GameTooltip.GetOwner or GameTooltip:GetOwner() == self) then GameTooltip:Hide() end
        end)
    end

    local optDrawMapContent = CreateFrame("Frame", nil, optDrawMapFrame)
    optDrawMapContent:SetPoint("TOPLEFT", optDrawMapFrame, "TOPLEFT", 0, 0)
    optDrawMapContent:SetSize(616, 325)
    optDrawMapContent:SetFrameLevel(optDrawMapFrame:GetFrameLevel() + 1)

    local optDrawCanvas = CreateFrame("Frame", nil, optDrawMapContent)
    optDrawCanvas:SetAllPoints()
    optDrawCanvas:SetFrameLevel(optDrawMapContent:GetFrameLevel() + 5)

    local optDrawCoordLabel = DrawModePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optDrawCoordLabel:SetPoint("TOPLEFT", 236, -368)
    optDrawCoordLabel:SetText("Coordinates")
    optDrawCoordLabel:SetTextColor(0.72, 0.72, 0.72)

    local optDrawCoordText = DrawModePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optDrawCoordText:SetPoint("LEFT", optDrawCoordLabel, "RIGHT", 8, 0)
    optDrawCoordText:SetWidth(90)
    optDrawCoordText:SetJustifyH("RIGHT")
    optDrawCoordText:SetText("--, --")

    local optDrawToolsTitle = DrawModePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optDrawToolsTitle:SetPoint("TOPLEFT", 16, -364)
    optDrawToolsTitle:SetText("Tools")
    optDrawToolsTitle:SetTextColor(1, 0.82, 0)

    local function OptDrawButton(parent, text, width, height)
        local btn = CreateActionBtn(parent, text, width, height, "normal")
        btn.text:SetTextColor(1, 1, 1)
        return btn
    end

    local optBtnW = 66
    local optBtnH = 22
    local optBtnDraw = OptDrawButton(DrawModePanel, "Draw", optBtnW, optBtnH)
    optBtnDraw:SetPoint("TOPLEFT", 16, -384)
    local optBtnErase = OptDrawButton(DrawModePanel, "Erase", optBtnW, optBtnH)
    optBtnErase:SetPoint("LEFT", optBtnDraw, "RIGHT", 4, 0)
    local optBtnMove = OptDrawButton(DrawModePanel, "Move", optBtnW, optBtnH)
    optBtnMove:SetPoint("LEFT", optBtnErase, "RIGHT", 4, 0)
    -- Keep the single avoid-area action on its own row, clear of the route
    -- action buttons and search field.
    local optBtnAvoid = OptDrawButton(DrawModePanel, "Draw Avoid Area", 184, optBtnH)
    optBtnAvoid:SetPoint("TOPLEFT", 236, -438)
    optBtnAvoid:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local optBtnStitch = OptDrawButton(DrawModePanel, "Stitch", optBtnW, optBtnH)
    optBtnStitch:SetPoint("TOP", optBtnDraw, "BOTTOM", 0, -4)
    local optBtnClose = OptDrawButton(DrawModePanel, "Close", optBtnW, optBtnH)
    optBtnClose:SetPoint("TOP", optBtnErase, "BOTTOM", 0, -4)
    local function OptDrawZoomButton(text)
        local btn = OptDrawButton(DrawModePanel, text, 31, optBtnH)
        btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        btn:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
        btn.text:SetScale(1.2)
        btn:HookScript("OnEnter", function(self)
            self:SetBackdropColor(0.12, 0.18, 0.24, 1)
            self:SetBackdropBorderColor(0.35, 0.72, 1, 1)
            self.text:SetTextColor(1, 1, 1)
        end)
        btn:HookScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
            self:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
            self.text:SetTextColor(1, 1, 1)
        end)
        return btn
    end
    local optBtnZoomIn = OptDrawZoomButton("+")
    optBtnZoomIn:SetPoint("LEFT", optBtnClose, "RIGHT", 4, 0)
    local optBtnZoomOut = OptDrawZoomButton("-")
    optBtnZoomOut:SetPoint("LEFT", optBtnZoomIn, "RIGHT", 4, 0)
    local optBtnGhost = OptDrawButton(DrawModePanel, "%", 22, 22)
    local optBtnMark = OptDrawButton(DrawModePanel, "Mark", optBtnW, optBtnH)
    optBtnMark:SetPoint("TOP", optBtnStitch, "BOTTOM", 0, -4)
    local optBtnTimer = OptDrawButton(DrawModePanel, "Timer", optBtnW, optBtnH)
    optBtnTimer:SetPoint("TOP", optBtnClose, "BOTTOM", 0, -4)

    local optDrawTimerBox = CreateFrame("EditBox", nil, DrawModePanel, "BackdropTemplate")
    optDrawTimerBox:SetSize(40, 22)
    optDrawTimerBox:SetPoint("LEFT", optBtnTimer, "RIGHT", 4, 0)
    optBtnGhost:SetPoint("LEFT", optDrawTimerBox, "RIGHT", 4, 0)
    optDrawTimerBox:SetAutoFocus(false)
    optDrawTimerBox:SetFontObject("GameFontHighlightSmall")
    optDrawTimerBox:SetJustifyH("CENTER")
    optDrawTimerBox:SetTextInsets(4, 4, 0, 0)
    optDrawTimerBox:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    optDrawTimerBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
    optDrawTimerBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    optDrawTimerBox:SetText("1s")

    local function OptDrawPaintTool(activeBtn)
        local buttons = {optBtnDraw, optBtnErase, optBtnMove, optBtnMark, optBtnAvoid}
        for _, btn in ipairs(buttons) do
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            btn.text:SetTextColor(1, 1, 1)
        end
        activeBtn:SetBackdropBorderColor(0, 1, 0, 1)
        activeBtn.text:SetTextColor(0, 1, 0)
    end

    local function OptDrawSetTool(tool, btn)
        optDrawTool = tool
        OptDrawPaintTool(btn)
        if optDrawTool == "MARKER" or optDrawTool == "AVOID" then
            optBtnStitch:Disable()
            optBtnClose:Disable()
            optBtnStitch.text:SetTextColor(0.45, 0.45, 0.45)
            optBtnClose.text:SetTextColor(0.45, 0.45, 0.45)
        else
            optBtnStitch:Enable()
            optBtnClose:Enable()
            optBtnStitch.text:SetTextColor(1, 1, 1)
            optBtnClose.text:SetTextColor(1, 1, 1)
        end
        if OptDrawRefreshCanvas then OptDrawRefreshCanvas() end
    end

    local function OptDrawPaintGhost(isHover)
        if optDrawGhostOn then
            optBtnGhost:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            optBtnGhost:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            optBtnGhost.text:SetTextColor(0.55, 0.5, 1)
        else
            optBtnGhost:SetBackdropColor(isHover and 0.25 or 0.15, isHover and 0.25 or 0.15, isHover and 0.25 or 0.15, isHover and 1 or 0.9)
            optBtnGhost:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            optBtnGhost.text:SetTextColor(0.75, 0.75, 0.75)
        end
    end

    optBtnGhost:SetScript("OnEnter", function() OptDrawPaintGhost(true) end)
    optBtnGhost:SetScript("OnLeave", function() OptDrawPaintGhost(false) end)
    OptDrawPaintGhost(false)

    optBtnDraw:SetScript("OnClick", function() OptDrawSetTool("PENCIL", optBtnDraw) end)
    optBtnErase:SetScript("OnClick", function() OptDrawSetTool("ERASER", optBtnErase) end)
    optBtnMove:SetScript("OnClick", function() OptDrawSetTool("MOVE", optBtnMove) end)
    optBtnAvoid:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local areas = PathmakerDB and PathmakerDB.avoidAreas and optDrawMapID and PathmakerDB.avoidAreas[optDrawMapID]
            if areas and #areas > 0 then
                table.remove(areas)
                local remaining = #areas
                if remaining == 0 then PathmakerDB.avoidAreas[optDrawMapID] = nil end
                addon:PrintMessage("disableMsgRouteEditing", string.format("PathMaker: Removed the latest avoid area. %d remaining.", remaining))
            else
                addon:PrintMessage("disableMsgRouteEditing", "PathMaker: There are no avoid areas to remove on this map.")
            end
            wipe(optDrawAvoidDraft)
            if OptDrawRefreshCanvas then OptDrawRefreshCanvas() end
        else
            wipe(optDrawAvoidDraft)
            OptDrawSetTool("AVOID", optBtnAvoid)
        end
    end)
    optBtnMark:SetScript("OnClick", function() OptDrawSetTool("MARKER", optBtnMark) end)
    optBtnTimer:SetScript("OnClick", function() optDrawTimerBox:SetFocus() end)
    OptDrawTooltip(optBtnDraw, "Draw", "Click and drag on the map to draw a route.")
    OptDrawTooltip(optBtnErase, "Erase", "Drag over route points to remove them.")
    OptDrawTooltip(optBtnMove, "Move", "Hold left click on the map to pan around while zoomed in.")
    OptDrawTooltip(optBtnAvoid, "Draw Avoid Area", "Left-click to draw and show avoid areas. Right-click removes only the most recently drawn area; repeat to remove more.")
    OptDrawTooltip(optBtnStitch, "Stitch", "Join separated route segments into one route.")
    OptDrawTooltip(optBtnClose, "Close", "Connect the route end back to the start.")
    OptDrawTooltip(optBtnZoomOut, "Zoom Out", "Zoom out from the center of the map.")
    OptDrawTooltip(optBtnZoomIn, "Zoom In", "Zoom in toward the center of the map.")
    OptDrawTooltip(optBtnGhost, "Ghost Preview", "Toggle faint previews of saved routes for the selected zone.")
    OptDrawTooltip(optBtnMark, "Mark", "Draw timed marker segments.")
    OptDrawTooltip(optBtnTimer, "Timer", "Set the timer used by new marker segments.")
    OptDrawSetTool("PENCIL", optBtnDraw)
    optDrawToolsTitle:ClearAllPoints()
    optDrawToolsTitle:SetPoint("BOTTOM", optBtnDraw, "TOP", optBtnW + 4, 4)

    optDrawTimerBox:SetScript("OnEnterPressed", function(self)
        local text = (self:GetText() or ""):gsub("s", "")
        local val = tonumber(text)
        if val and val > 0 then optDrawTimer = val end
        self:SetText(tostring(optDrawTimer) .. "s")
        self:ClearFocus()
    end)
    optDrawTimerBox:SetScript("OnEscapePressed", function(self) self:SetText(tostring(optDrawTimer) .. "s"); self:ClearFocus() end)
    optDrawTimerBox:SetScript("OnEditFocusGained", function(self) self:SetText(tostring(optDrawTimer)); self:HighlightText() end)
    optDrawTimerBox:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(optDrawTimer) .. "s"); self:HighlightText(0, 0) end)

    local function OptDrawClampPan()
        local w, h = optDrawMapFrame:GetSize()
        w, h = tonumber(w) or 0, tonumber(h) or 0
        local zoom = optDrawZoom or 1
        if zoom <= 1.001 then
            optDrawPanX, optDrawPanY = 0, 0
            return
        end
        optDrawPanX = math.min(0, math.max(w - (w * zoom), optDrawPanX or 0))
        optDrawPanY = math.min(0, math.max(h - (h * zoom), optDrawPanY or 0))
    end

    local function OptDrawApplyZoom()
        OptDrawClampPan()
        if optDrawMapContent and optDrawMapContent.ClearAllPoints then
            local w, h = optDrawMapFrame:GetSize()
            local zoom = math.max(1, optDrawZoom or 1)
            optDrawMapContent:ClearAllPoints()
            -- SetScale also scales this frame's anchor offsets. Pan is stored
            -- in visible canvas pixels, so divide the anchor offset by zoom;
            -- otherwise maximum zoom can overshoot an edge and reveal void.
            optDrawMapContent:SetPoint("TOPLEFT", optDrawMapFrame, "TOPLEFT", (optDrawPanX or 0) / zoom, -((optDrawPanY or 0) / zoom))
            optDrawMapContent:SetSize(w or 616, h or 325)
        end
        if optDrawMapContent and optDrawMapContent.SetScale then
            optDrawMapContent:SetScale(optDrawZoom)
        end
    end

    local function OptDrawGetFrameCursorXY()
        local mx, my = GetCursorPosition()
        local s = optDrawMapFrame:GetEffectiveScale()
        local left, top = optDrawMapFrame:GetLeft(), optDrawMapFrame:GetTop()
        local w, h = optDrawMapFrame:GetSize()
        if not mx or not my or not left or not top or not w or not h or not s then return nil end
        local rx = (mx / s) - left
        local ry = top - (my / s)
        if rx < 0 or rx > w or ry < 0 or ry > h then return nil end
        return rx, ry, w, h
    end

    local function OptDrawZoomAt(rx, ry, zoomIn)
        local oldZoom = optDrawZoom or 1
        local focusX = (rx - (optDrawPanX or 0)) / oldZoom
        local focusY = (ry - (optDrawPanY or 0)) / oldZoom
        if zoomIn then
            optDrawZoom = math.min(3, oldZoom * 1.12)
        else
            optDrawZoom = math.max(1, oldZoom / 1.12)
        end
        if math.abs(optDrawZoom - oldZoom) < 0.001 then return end
        optDrawPanX = rx - (focusX * optDrawZoom)
        optDrawPanY = ry - (focusY * optDrawZoom)
        OptDrawApplyZoom()
    end

    optBtnZoomOut:SetScript("OnClick", function()
        local w, h = optDrawMapFrame:GetSize()
        OptDrawZoomAt((w or 616) / 2, (h or 325) / 2, false)
    end)
    optBtnZoomIn:SetScript("OnClick", function()
        local w, h = optDrawMapFrame:GetSize()
        OptDrawZoomAt((w or 616) / 2, (h or 325) / 2, true)
    end)

    optDrawMapFrame:SetScript("OnMouseWheel", function(_, delta)
        local rx, ry = OptDrawGetFrameCursorXY()
        if not rx or not ry then return end
        OptDrawZoomAt(rx, ry, delta and delta > 0)
    end)

    local function OptDrawGetMapXY()
        local rx, ry = OptDrawGetFrameCursorXY()
        if not rx or not ry then return nil end
        local mx, my = GetCursorPosition()
        local s = optDrawMapContent:GetEffectiveScale()
        local left, top = optDrawMapContent:GetLeft(), optDrawMapContent:GetTop()
        local w, h = optDrawMapContent:GetSize()
        if not mx or not my or not s or not left or not top or not w or not h then return nil end
        local localX = (mx / s) - left
        local localY = top - (my / s)
        local mapX, mapY = OptDrawCanvasToMapXY(localX / w, localY / h)
        return mapX, mapY, localX, localY, w, h
    end

    local function OptDrawClearCanvas()
        for _, tex in ipairs(optDrawLines) do
            tex:Hide()
            optDrawLinePool[#optDrawLinePool + 1] = tex
        end
        for _, tex in ipairs(optDrawDots) do
            tex:Hide()
            optDrawDotPool[#optDrawDotPool + 1] = tex
        end
        wipe(optDrawLines)
        wipe(optDrawDots)
    end

    local function OptDrawLine(p1, p2, width, color)
        local w, h = optDrawCanvas:GetSize()
        local x1, y1 = OptDrawMapToCanvasXY(p1.x, p1.y)
        local x2, y2 = OptDrawMapToCanvasXY(p2.x, p2.y)

        -- References with a cropped vertical margin can place valid route
        -- endpoints just outside the visible picture. Clip every segment to
        -- the canvas so clients without SetClipsChildren cannot leak lines
        -- into the controls beside the map.
        local dx, dy = x2 - x1, y2 - y1
        local enter, leave = 0, 1
        local function ClipBoundary(p, q)
            if math.abs(p) < 0.000001 then return q >= 0 end
            local ratio = q / p
            if p < 0 then
                if ratio > leave then return false end
                if ratio > enter then enter = ratio end
            else
                if ratio < enter then return false end
                if ratio < leave then leave = ratio end
            end
            return true
        end
        if not ClipBoundary(-dx, x1) or not ClipBoundary(dx, 1 - x1)
            or not ClipBoundary(-dy, y1) or not ClipBoundary(dy, 1 - y1)
        then
            return
        end
        x2, y2 = x1 + (leave * dx), y1 + (leave * dy)
        x1, y1 = x1 + (enter * dx), y1 + (enter * dy)

        local sx1, sy1 = x1 * w, -y1 * h
        local sx2, sy2 = x2 * w, -y2 * h
        local line = table.remove(optDrawLinePool) or optDrawCanvas:CreateTexture(nil, "OVERLAY")
        line:ClearAllPoints()
        line:SetColorTexture(unpack(color))
        local screenDX, screenDY = sx2 - sx1, sy2 - sy1
        local len = math.sqrt(screenDX * screenDX + screenDY * screenDY)
        line:SetSize(math.max(1, len), width)
        line:SetPoint("CENTER", optDrawCanvas, "TOPLEFT", (sx1 + sx2) / 2, (sy1 + sy2) / 2)
        line:SetRotation(math.atan2(screenDY, screenDX))
        line:Show()
        table.insert(optDrawLines, line)
        local dot = table.remove(optDrawDotPool) or optDrawCanvas:CreateTexture(nil, "OVERLAY")
        dot:ClearAllPoints()
        dot:SetColorTexture(unpack(color))
        dot:SetSize(width, width)
        dot:SetPoint("CENTER", optDrawCanvas, "TOPLEFT", sx2, sy2)
        dot:Show()
        table.insert(optDrawDots, dot)
    end

    OptDrawRefreshCanvas = function()
        OptDrawClearCanvas()
        local labels = {PENCIL="Drawing", ERASER="Erasing", MOVE="Moving", ZOOM="Zooming", MARKER="Marking", AVOID="Drawing Avoid Area"}
        local pointCount = optDrawTool == "AVOID" and #optDrawAvoidDraft or #optDrawDraft.points
        optDrawToolsTitle:SetText(string.format("%s - %d points", labels[optDrawTool] or "Draw Mode", pointCount))
        if optDrawTool == "AVOID" then
            local avoidAreas = PathmakerDB and PathmakerDB.avoidAreas and optDrawMapID and PathmakerDB.avoidAreas[optDrawMapID] or {}
            for _, area in ipairs(avoidAreas) do
                for i = 1, #area do
                    OptDrawLine(area[i], area[(i % #area) + 1], 3, {1, 0.18, 0.12, 0.9})
                end
            end
            for i = 1, #optDrawAvoidDraft - 1 do
                OptDrawLine(optDrawAvoidDraft[i], optDrawAvoidDraft[i + 1], 3, {1, 0.18, 0.12, 0.9})
            end
        end
        if optDrawGhostOn and PathmakerDB and PathmakerDB.routes and optDrawMapID and PathmakerDB.routes[optDrawMapID] then
            for guid, route in pairs(PathmakerDB.routes[optDrawMapID]) do
                if guid ~= optDrawSelectedGUID and type(route) == "table" and type(route.points) == "table" then
                    local ghostColor = route.color or {0.55, 0.75, 1, 1}
                    ghostColor = {ghostColor[1] or 0.55, ghostColor[2] or 0.75, ghostColor[3] or 1, 0.28}
                    for i = 1, #route.points - 1 do
                        local p1, p2 = route.points[i], route.points[i + 1]
                        if p1 and p2 and not p1.isGap then
                            OptDrawLine(p1, p2, 1, ghostColor)
                        end
                    end
                end
            end
        end
        for i = 1, #optDrawDraft.points - 1 do
            local p1, p2 = optDrawDraft.points[i], optDrawDraft.points[i + 1]
            if p1 and p2 and not p1.isGap then
                local col = p1.isMarker and {1, 0.82, 0, 1} or (optDrawDraft.color or {1, 1, 1, 1})
                if p1.isMarker and p2.isMarker and (((p1.x - p2.x) ^ 2 + (p1.y - p2.y) ^ 2) < 0.0002) then
                    col = {0, 0, 0, 1}
                end
                OptDrawLine(p1, p2, 2, col)
            end
        end
    end

    local function OptDrawUpdateMapArt()
        -- Map art is stable for a selected map. Retain its textures across
        -- tab switches and ordinary list refreshes instead of rebuilding all
        -- tiles every time Draw Mode opens.
        if optDrawMapArtMapID == optDrawMapID then return end
        for _, tex in ipairs(optDrawMapTextures) do tex:Hide() end
        optDrawMapArtMapID = nil
        optDrawCoordinateBounds = {0, 0, 1, 1}
        optDrawMapFrame:SetBackdropBorderColor(0.78, 0.58, 0.14, 0.95)

        local function SetMapAspect(width, height)
            width, height = tonumber(width), tonumber(height)
            if not width or not height or width <= 0 or height <= 0 then return end
            local maxWidth, maxHeight = 616, 325
            if panel.standaloneLayout then
                maxWidth = math.max(616, DrawModePanel:GetWidth() - 20)
                maxHeight = math.max(1, DrawModePanel:GetHeight() - 192)
            end
            local displayWidth = math.min(maxWidth, maxHeight * (width / height))
            local displayHeight = displayWidth * (height / width)
            local oldWidth, oldHeight = optDrawMapFrame:GetSize()
            if math.abs((oldWidth or 0) - displayWidth) > 0.1 or math.abs((oldHeight or 0) - displayHeight) > 0.1 then
                optDrawMapFrame:SetSize(displayWidth, displayHeight)
                OptDrawApplyZoom()
            end
        end

        local compat = addon.Compat
        if compat and (compat.isClassicEra or compat.isTBC or compat.isForever) and optDrawMapID then
            local folder, reference
            if compat.isTBC and optDrawTBCReferenceMaps[optDrawMapID] then
                folder, reference = "TBC", optDrawTBCReferenceMaps[optDrawMapID]
            elseif optDrawClassicReferenceMaps[optDrawMapID] then
                folder, reference = "ClassicEra", optDrawClassicReferenceMaps[optDrawMapID]
            end
            if folder and reference then
                if folder == "TBC" then
                    optDrawMapFrame:SetBackdropBorderColor(0.95, 0.55, 0.10, 0.98)
                else
                    optDrawMapFrame:SetBackdropBorderColor(0.78, 0.58, 0.14, 0.95)
                end
                local fullHeight = reference[1] * 2 / 3
                if reference[2] < fullHeight and (fullHeight / reference[2]) < 1.1 then
                    local margin = ((fullHeight - reference[2]) / 2) / fullHeight
                    optDrawCoordinateBounds = {0, margin, 1, 1 - margin}
                end
                SetMapAspect(reference[1], reference[2])
                local tex = optDrawMapTextures[1] or optDrawMapContent:CreateTexture(nil, "ARTWORK")
                tex:ClearAllPoints()
                tex:SetAllPoints(optDrawMapContent)
                tex:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Tools\\MapReferences\\DrawMode\\" .. folder .. "\\" .. optDrawMapID)
                tex:SetTexCoord(0, reference[1] / 1024, 0, reference[2] / 1024)
                tex:Show()
                optDrawMapTextures[1] = tex
                optDrawMapArtMapID = optDrawMapID
                return
            end
        end

        if not C_Map or not C_Map.GetMapArtLayers or not C_Map.GetMapArtLayerTextures or not optDrawMapID then return end
        local okLayers, layers = pcall(C_Map.GetMapArtLayers, optDrawMapID)
        if not okLayers or type(layers) ~= "table" or not layers[1] then return end
        local layer = layers[1]
        local okTextures, textures = pcall(C_Map.GetMapArtLayerTextures, optDrawMapID, layer.layerIndex or 1)
        if not okTextures or type(textures) ~= "table" or #textures == 0 then return end
        local layerWidth = layer.layerWidth or layer.width or 1002
        local layerHeight = layer.layerHeight or layer.height or 668
        SetMapAspect(layerWidth, layerHeight)
        local tileWidth = layer.tileWidth or 256
        local tileHeight = layer.tileHeight or 256
        local cols = math.max(1, math.ceil(layerWidth / tileWidth))
        local scaleX = optDrawMapFrame:GetWidth() / layerWidth
        local scaleY = optDrawMapFrame:GetHeight() / layerHeight
        for i, fileDataID in ipairs(textures) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            local tex = optDrawMapTextures[i] or optDrawMapContent:CreateTexture(nil, "ARTWORK")
            tex:ClearAllPoints()
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetTexture(fileDataID)
            tex:SetSize(tileWidth * scaleX, tileHeight * scaleY)
            tex:SetPoint("TOPLEFT", optDrawMapContent, "TOPLEFT", col * tileWidth * scaleX, -row * tileHeight * scaleY)
            tex:Show()
            optDrawMapTextures[i] = tex
        end
        if #optDrawMapTextures > 0 then optDrawMapArtMapID = optDrawMapID end
    end

    local function OptDrawSave(silent)
        if not optDrawMapID then return end
        PathmakerDB = PathmakerDB or {}
        PathmakerDB.routes = PathmakerDB.routes or {}
        PathmakerDB.routes[optDrawMapID] = PathmakerDB.routes[optDrawMapID] or {}
        local guid = optDrawSelectedGUID
        local existingMapID = optDrawSelectedMapID
        if not guid or not existingMapID or not PathmakerDB.routes[existingMapID] or not PathmakerDB.routes[existingMapID][guid] then
            guid = "Route_" .. date("%Y%m%d%H%M%S")
            existingMapID = optDrawMapID
        end
        PathmakerDB.routes[existingMapID] = PathmakerDB.routes[existingMapID] or {}
        local name = "Drawn Route"
        if DrawModePanel.renameBox and DrawModePanel.renameBox:GetText() ~= "" then name = DrawModePanel.renameBox:GetText() end
        PathmakerDB.routes[existingMapID][guid] = {
            name = name,
            color = optDrawDraft.color,
            thickness = 2,
            visible = true,
            connectPaths = false,
            points = OptDrawCopyPoints(optDrawDraft.points),
        }
        optDrawSelectedGUID = guid
        optDrawSelectedMapID = existingMapID
        addon.selectedRouteGUID = guid
        addon.selectedRouteMapID = existingMapID
        if not silent then addon:PrintMessage("disableMsgRouteEditing", "PathMaker: Saved.") end
        OptDrawRefreshExternal()
        if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
    end

    local function OptDrawAddPoint(nx, ny)
        if not nx or nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
        local p = {x = nx, y = ny, isGap = false}
        if optDrawTool == "MARKER" then
            p.isMarker = true
            p.duration = optDrawTimer
            p.name = "Marker"
        end
        table.insert(optDrawDraft.points, p)
        OptDrawRefreshCanvas()
    end

    local function OptDrawErase(rx, ry, w, h)
        local toRemove = {}
        for i, p in ipairs(optDrawDraft.points) do
            local canvasX, canvasY = OptDrawMapToCanvasXY(p.x, p.y)
            local dx, dy = (canvasX * w) - rx, (canvasY * h) - ry
            if math.sqrt(dx * dx + dy * dy) <= 14 then
                table.insert(toRemove, i)
            end
        end
        if #toRemove == 0 then return end
        local removeSet = {}
        for _, idx in ipairs(toRemove) do removeSet[idx] = true end
        for _, idx in ipairs(toRemove) do
            local prev = idx - 1
            if prev > 0 and not removeSet[prev] and optDrawDraft.points[prev] then
                optDrawDraft.points[prev].isGap = true
            end
        end
        table.sort(toRemove, function(a, b) return a > b end)
        for _, i in ipairs(toRemove) do
            local p = optDrawDraft.points[i]
            if p then
                table.remove(optDrawDraft.points, i)
            end
        end
        OptDrawRefreshCanvas()
    end

    local function OptDrawLoadSelectedRoute()
        local routeMapID, route = OptDrawFindRouteByGUID(optDrawSelectedGUID)
        if route then
            optDrawSelectedMapID = routeMapID
            addon.selectedRouteGUID = optDrawSelectedGUID
            addon.selectedRouteMapID = routeMapID
            optDrawMapID = routeMapID
            optDrawDraft.points = OptDrawCopyPoints(route.points)
            optDrawDraft.color = route.color or optDrawDraft.color
            if DrawModePanel.renameBox then DrawModePanel.renameBox:SetText(route.name or "") end
        end
    end

    optDrawMapFrame:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        if optDrawTool == "MOVE" then
            local rx, ry = OptDrawGetFrameCursorXY()
            if not rx or not ry then return end
            optDrawIsPanning = true
            optDrawPanStart.x, optDrawPanStart.y = rx, ry
            optDrawPanStart.panX, optDrawPanStart.panY = optDrawPanX or 0, optDrawPanY or 0
            return
        end
        local nx, ny, rx, ry, w, h = OptDrawGetMapXY()
        if not nx then return end
        if optDrawTool ~= "AVOID" then
            OptDrawPushUndo()
            OptDrawPrepareStroke(nx, ny)
        else
            wipe(optDrawAvoidDraft)
        end
        optDrawIsDrawing = true
        if optDrawTool == "ERASER" then
            OptDrawErase(rx, ry, w, h)
        elseif optDrawTool == "AVOID" then
            optDrawAvoidDraft[#optDrawAvoidDraft + 1] = {x=nx, y=ny}
            OptDrawRefreshCanvas()
        else
            OptDrawAddPoint(nx, ny)
        end
    end)
    optDrawMapFrame:SetScript("OnMouseUp", function()
        if optDrawIsPanning then
            optDrawIsPanning = false
            return
        end
        if not optDrawIsDrawing then return end
        optDrawIsDrawing = false
        if optDrawTool == "AVOID" then
            if #optDrawAvoidDraft >= 3 and optDrawMapID then
                PathmakerDB = PathmakerDB or {}
                PathmakerDB.avoidAreas = PathmakerDB.avoidAreas or {}
                PathmakerDB.avoidAreas[optDrawMapID] = PathmakerDB.avoidAreas[optDrawMapID] or {}
                table.insert(PathmakerDB.avoidAreas[optDrawMapID], OptDrawCopyPoints(optDrawAvoidDraft))
            end
            wipe(optDrawAvoidDraft)
            OptDrawRefreshCanvas()
            return
        end
        local last = optDrawDraft.points[#optDrawDraft.points]
        if last then last.isGap = true end
        OptDrawSave(true)
    end)
    optDrawMapFrame:SetScript("OnUpdate", function(_, elapsed)
        -- Drawing and panning stay frame-perfect. Idle coordinate/marker
        -- hover checks do not need to run at the full render frame rate.
        if not optDrawIsDrawing and not optDrawIsPanning then
            optDrawHoverElapsed = optDrawHoverElapsed + (elapsed or 0)
            if optDrawHoverElapsed < 0.05 then return end
        end
        optDrawHoverElapsed = 0
        local nx, ny, rx, ry, w, h = OptDrawGetMapXY()
        if nx and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
            optDrawCoordText:SetText(string.format("%.1f, %.1f", nx * 100, ny * 100))
        else
            optDrawCoordText:SetText("--, --")
        end
        if nx and GameTooltip then
            local hoveredMarker
            for _, p in ipairs(optDrawDraft.points) do
                if p.isMarker then
                    local canvasX, canvasY = OptDrawMapToCanvasXY(p.x, p.y)
                    local px, py = canvasX * w, canvasY * h
                    if math.sqrt(((px - rx) ^ 2) + ((py - ry) ^ 2)) < 10 then
                        hoveredMarker = p
                        break
                    end
                end
            end
            if hoveredMarker then
                GameTooltip:SetOwner(optDrawMapFrame, "ANCHOR_CURSOR")
                GameTooltip:SetText(hoveredMarker.name or "Marker")
                GameTooltip:AddLine("Time: " .. (hoveredMarker.duration or "?") .. "s", 1, 1, 1)
                GameTooltip:Show()
            elseif GameTooltip.GetOwner and GameTooltip:GetOwner() == optDrawMapFrame then
                GameTooltip:Hide()
            end
        elseif GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == optDrawMapFrame then
            GameTooltip:Hide()
        end
        if optDrawIsPanning then
            local rx, ry = OptDrawGetFrameCursorXY()
            if rx and ry then
                optDrawPanX = optDrawPanStart.panX + (rx - optDrawPanStart.x)
                optDrawPanY = optDrawPanStart.panY + (ry - optDrawPanStart.y)
                OptDrawApplyZoom()
            end
            return
        end
        if not optDrawIsDrawing then return end
        if not nx then return end
        if optDrawTool == "ERASER" then
            OptDrawErase(rx, ry, w, h)
        elseif optDrawTool == "PENCIL" or optDrawTool == "MARKER" or optDrawTool == "AVOID" then
            local points = optDrawTool == "AVOID" and optDrawAvoidDraft or optDrawDraft.points
            local last = points[#points]
            if not last then
                if optDrawTool == "AVOID" then
                    points[#points + 1] = {x=nx, y=ny}; OptDrawRefreshCanvas()
                else
                    OptDrawAddPoint(nx, ny)
                end
            else
                local dx, dy = (last.x - nx) * w, (last.y - ny) * h
                if math.sqrt(dx * dx + dy * dy) > 5 then
                    if optDrawTool == "AVOID" then points[#points + 1] = {x=nx, y=ny}; OptDrawRefreshCanvas() else OptDrawAddPoint(nx, ny) end
                end
            end
        end
    end)

    optBtnClose:SetScript("OnClick", function()
        if optDrawTool == "MARKER" then return end
        local pts = optDrawDraft.points
        if #pts < 2 then return end
        local first, last = pts[1], pts[#pts]
        local d = (first.x - last.x) ^ 2 + (first.y - last.y) ^ 2
        if d < 0.00000001 then
            if not last.isGap then
                last.isGap = true
                OptDrawRefreshCanvas()
                OptDrawSave(true)
            end
            return
        end
        OptDrawPushUndo()
        if last.isGap then last.isGap = false end
        if last.isMarker and first.isMarker then
            table.insert(pts, {x = last.x, y = last.y, isGap = false})
        end
        table.insert(pts, {x = first.x, y = first.y, isGap = true})
        OptDrawRefreshCanvas()
        OptDrawSave(true)
    end)

    optBtnStitch:SetScript("OnClick", function()
        if optDrawTool == "MARKER" then return end
        local pts = optDrawDraft.points
        if #pts < 2 then return end
        OptDrawPushUndo()
        local segments, currentSeg = {}, {}
        for i, p in ipairs(pts) do
            table.insert(currentSeg, p)
            if p.isGap or i == #pts then
                table.insert(segments, currentSeg)
                currentSeg = {}
            end
        end
        local stitched = segments[1]
        table.remove(segments, 1)
        while stitched and #segments > 0 do
            local tip = stitched[#stitched]
            local bestIdx, bestDist, shouldReverse = -1, math.huge, false
            for i, seg in ipairs(segments) do
                local startP, endP = seg[1], seg[#seg]
                local dStart = (tip.x - startP.x) ^ 2 + (tip.y - startP.y) ^ 2
                if dStart < bestDist then bestDist, bestIdx, shouldReverse = dStart, i, false end
                local dEnd = (tip.x - endP.x) ^ 2 + (tip.y - endP.y) ^ 2
                if dEnd < bestDist then bestDist, bestIdx, shouldReverse = dEnd, i, true end
            end
            if bestIdx == -1 then break end
            local bestSeg = table.remove(segments, bestIdx)
            local connectingTo = shouldReverse and bestSeg[#bestSeg] or bestSeg[1]
            if stitched[#stitched].isMarker and connectingTo.isMarker then
                table.insert(stitched, {x = stitched[#stitched].x, y = stitched[#stitched].y, isGap = false})
            end
            stitched[#stitched].isGap = false
            if shouldReverse then
                for i = 1, math.floor(#bestSeg / 2) do
                    bestSeg[i], bestSeg[#bestSeg - i + 1] = bestSeg[#bestSeg - i + 1], bestSeg[i]
                end
            end
            for _, p in ipairs(bestSeg) do table.insert(stitched, p) end
        end
        local finalPts = stitched or pts
        local maxDistSq, splitIndex = -1, -1
        for i = 1, #finalPts do
            local p1, p2 = finalPts[i], finalPts[(i % #finalPts) + 1]
            local d = (p1.x - p2.x) ^ 2 + (p1.y - p2.y) ^ 2
            if d > maxDistSq then maxDistSq, splitIndex = d, i end
        end
        if splitIndex ~= -1 then
            local rotated = {}
            for i = splitIndex + 1, #finalPts do table.insert(rotated, finalPts[i]) end
            for i = 1, splitIndex do table.insert(rotated, finalPts[i]) end
            finalPts = rotated
        end
        for i = 1, #finalPts - 1 do finalPts[i].isGap = false end
        finalPts[#finalPts].isGap = true
        optDrawDraft.points = finalPts
        OptDrawRefreshCanvas()
        OptDrawSave(true)
    end)

    optBtnGhost:SetScript("OnClick", function()
        optDrawGhostOn = not optDrawGhostOn
        OptDrawPaintGhost(false)
        OptDrawRefreshCanvas()
    end)

    local palFrame = CreateFrame("Frame", nil, DrawModePanel)
    palFrame:SetSize(248, 41)
    palFrame:SetPoint("TOPLEFT", 16, -470)
    local optPal = addon.Routes and addon.Routes.Palette or {}
    local function OptDrawPaintPalette()
        for _, b in ipairs(optDrawPaletteButtons) do
            if OptDrawSameColor(b.color, optDrawDraft.color) then b:SetBackdropBorderColor(0, 1, 0, 1) else b:SetBackdropBorderColor(0.08, 0.08, 0.08, 1) end
        end
    end
    panel.SyncOptionsDrawModeRouteColor = function(guid, mapID, color)
        if not guid or type(color) ~= "table" then return end
        local isSelectedRoute = guid == optDrawSelectedGUID and
            (not mapID or not optDrawSelectedMapID or mapID == optDrawSelectedMapID)
        if isSelectedRoute then
            optDrawDraft.color = color
            OptDrawPaintPalette()
        end
        -- Non-selected routes are visible as ghost lines, so repaint for every
        -- route color change, not only changes to the active draft.
        OptDrawRefreshCanvas()
    end
    for i, color in ipairs(optPal) do
        if i > 22 then break end
        local b = CreateFrame("Button", nil, palFrame, "BackdropTemplate")
        b:SetSize(18, 18)
        b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1, insets={left=1,right=1,top=1,bottom=1}})
        b:SetBackdropColor(0.03, 0.03, 0.03, 1)
        b:SetBackdropBorderColor(0.08, 0.08, 0.08, 1)
        b.color = color
        local row = math.floor((i - 1) / 11)
        local col = (i - 1) % 11
        b:SetPoint("TOPLEFT", col * 23, -row * 23)
        b.tex = b:CreateTexture(nil, "OVERLAY")
        b.tex:SetPoint("TOPLEFT", 1, -1)
        b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
        b.tex:SetColorTexture(unpack(color))
        b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0, 1, 0, 1) end)
        b:SetScript("OnLeave", function() OptDrawPaintPalette() end)
        OptDrawTooltip(b, "Route Color", "Set the active route color.")
        b:SetScript("OnClick", function()
            optDrawDraft.color = color
            OptDrawPaintPalette()
            OptDrawRefreshCanvas()
            OptDrawSave(true)
            if addon.Routes and addon.Routes.NotifyRouteColorChanged then
                addon.Routes:NotifyRouteColorChanged(optDrawSelectedGUID, optDrawSelectedMapID, color)
            end
        end)
        table.insert(optDrawPaletteButtons, b)
    end

    local optBtnUndo = OptDrawButton(DrawModePanel, "Undo", 46, 24)
    optBtnUndo:SetPoint("TOPLEFT", 236, -384)
    local optBtnRedo = OptDrawButton(DrawModePanel, "Redo", 46, 24)
    optBtnRedo:SetPoint("LEFT", optBtnUndo, "RIGHT", 4, 0)
    local optBtnClear = OptDrawButton(DrawModePanel, "Clear", 46, 24)
    optBtnClear:SetPoint("LEFT", optBtnRedo, "RIGHT", 4, 0)
    local optBtnSave = OptDrawButton(DrawModePanel, "Save", 46, 24)
    optBtnSave:SetPoint("LEFT", optBtnClear, "RIGHT", 4, 0)
    optBtnSave.text:SetTextColor(0, 1, 0)

    optBtnUndo:SetScript("OnClick", function()
        if #optDrawUndoStack == 0 then return end
        table.insert(optDrawRedoStack, OptDrawCopyPoints(optDrawDraft.points))
        optDrawDraft.points = table.remove(optDrawUndoStack)
        OptDrawRefreshCanvas()
        OptDrawSave(true)
    end)
    optBtnRedo:SetScript("OnClick", function()
        if #optDrawRedoStack == 0 then return end
        table.insert(optDrawUndoStack, OptDrawCopyPoints(optDrawDraft.points))
        optDrawDraft.points = table.remove(optDrawRedoStack)
        OptDrawRefreshCanvas()
        OptDrawSave(true)
    end)
    optBtnClear:SetScript("OnClick", function()
        OptDrawPushUndo()
        wipe(optDrawDraft.points)
        OptDrawRefreshCanvas()
        OptDrawSave(true)
    end)
    optBtnSave:SetScript("OnClick", function() OptDrawSave(false) end)
    OptDrawTooltip(optBtnUndo, "Undo", "Revert the last draw edit.")
    OptDrawTooltip(optBtnRedo, "Redo", "Restore the last undone edit.")
    OptDrawTooltip(optBtnClear, "Clear", "Remove all points from the current draft.")
    OptDrawTooltip(optBtnSave, "Save", "Save the current route.")

    local optRouteTitle = DrawModePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optRouteTitle:SetPoint("BOTTOM", optBtnUndo, "TOP", 267, 4)
    optRouteTitle:SetText("Route Manager")
    optRouteTitle:SetTextColor(1, 0.82, 0)

    local optImport = OptDrawButton(DrawModePanel, "Import", 58, 22)
    optImport:SetPoint("TOPLEFT", 236, -411)
    local optExport = OptDrawButton(DrawModePanel, "Export", 58, 22)
    optExport:SetPoint("LEFT", optImport, "RIGHT", 5, 0)
    local optRestore = OptDrawButton(DrawModePanel, "Restore", 58, 22)
    optRestore:SetPoint("LEFT", optExport, "RIGHT", 5, 0)
    optImport:SetScript("OnClick", function() if addon.ImportExport then addon.ImportExport:ShowImport() end end)
    optExport:SetScript("OnClick", function() if optDrawSelectedGUID and addon.ImportExport then addon.ImportExport:ShowExport(optDrawSelectedGUID, optDrawSelectedMapID) end end)
    optRestore:SetScript("OnClick", RestoreLastDeletedRoute)
    OptDrawTooltip(optImport, "Import", "Open the import window.")
    OptDrawTooltip(optExport, "Export", "Export the selected route.")
    OptDrawTooltip(optRestore, "Restore", "Restore the most recently deleted route.")

    local function OptDrawCreateEditBox(width, placeholder)
        local eb = CreateFrame("EditBox", nil, DrawModePanel, "BackdropTemplate")
        eb:SetSize(width, 22)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlightSmall")
        eb:SetTextInsets(5, 5, 0, 0)
        eb:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
        eb:SetBackdropColor(0.08, 0.08, 0.08, 1)
        eb:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        eb.placeholder = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        eb.placeholder:SetPoint("LEFT", 5, 0)
        eb.placeholder:SetText(placeholder)
        eb:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then self.placeholder:Show() else self.placeholder:Hide() end
            if self == DrawModePanel.searchBox and panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        return eb
    end

    DrawModePanel.searchBox = OptDrawCreateEditBox(184, "Search...")
    DrawModePanel.searchBox:SetPoint("TOPLEFT", 438, -384)
    DrawModePanel.renameBox = OptDrawCreateEditBox(184, "Rename...")
    DrawModePanel.renameBox:SetPoint("TOPLEFT", DrawModePanel.searchBox, "BOTTOMLEFT", 0, -6)
    DrawModePanel.renameBox:SetMaxLetters(12)
    DrawModePanel.renameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if optDrawSelectedGUID and optDrawSelectedMapID and PathmakerDB.routes and PathmakerDB.routes[optDrawSelectedMapID] and PathmakerDB.routes[optDrawSelectedMapID][optDrawSelectedGUID] then
            PathmakerDB.routes[optDrawSelectedMapID][optDrawSelectedGUID].name = self:GetText()
            OptDrawRefreshExternal()
            if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
        end
    end)

    local optRouteScroll, optRouteChild, optRouteSlider = CreateDarkScrollArea(DrawModePanel, 184, 76)
    optRouteScroll:SetPoint("TOPLEFT", 438, -440)

    local function OptDrawUpdateDropdowns()
        local continentID, zone = FindDrawZoneForMap(optDrawMapID)
        optDrawContinentID = continentID or optDrawContinentID or GetDefaultDrawContinentID()
        optDrawContinentDrop.text:SetText("Continent: " .. (CONTINENT_LABELS[optDrawContinentID] or "Continent"))
        optDrawZoneDrop.text:SetText("Zone: " .. (zone and zone.name or (C_Map.GetMapInfo(optDrawMapID) and C_Map.GetMapInfo(optDrawMapID).name) or "Zone"))

        -- Reopening the tab does not change the available locations. Reuse
        -- the existing dropdown rows unless the continent actually changed.
        if optDrawDropdownContinentID == optDrawContinentID
            and #optDrawContinentDrop.items > 0 and #optDrawZoneDrop.items > 0
        then
            return
        end

        for _, child in ipairs(optDrawContinentDrop.items) do child:Hide() end
        wipe(optDrawContinentDrop.items)
        for i, continent in ipairs(GetVisibleContinentOrder()) do
            local row = CreateFrame("Button", nil, optDrawContinentDrop.menu, "BackdropTemplate")
            row:SetSize(optDrawContinentDrop:GetWidth() - 10, 15)
            row:SetPoint("TOPLEFT", 5, -5 - ((i - 1) * 20))
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"})
            row:SetBackdropColor(0, 0, 0, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetText(CONTINENT_LABELS[continent] or tostring(continent))
            row:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.18, 0.18, 1) end)
            row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
            row:SetScript("OnClick", function()
                optDrawContinentID = continent
                local zones = GetSortedDrawZones(continent)
                if zones[1] then optDrawMapID = zones[1].id end
                optDrawContinentDrop.menu:Hide()
                OptDrawClearSelectedRoute()
                if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
            end)
            table.insert(optDrawContinentDrop.items, row)
        end
        optDrawContinentDrop.menu:SetHeight(math.max(24, (#optDrawContinentDrop.items * 20) + 10))

        for _, child in ipairs(optDrawZoneDrop.items) do child:Hide() end
        wipe(optDrawZoneDrop.items)
        local zones = GetSortedDrawZones(optDrawContinentID)
        local zoneColWidth = 155
        local zoneRows = math.max(1, math.ceil(#zones / 2))
        optDrawZoneDrop.menu:SetWidth((2 * zoneColWidth) + 10)
        for i, zoneInfo in ipairs(zones) do
            local row = CreateFrame("Button", nil, optDrawZoneDrop.menu, "BackdropTemplate")
            row:SetSize(zoneColWidth, 15)
            local rowCol = math.floor((i - 1) / zoneRows)
            local rowIndex = (i - 1) % zoneRows
            row:SetPoint("TOPLEFT", 5 + (rowCol * zoneColWidth), -5 - (rowIndex * 20))
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"})
            row:SetBackdropColor(0, 0, 0, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT")
            row.text:SetText(zoneInfo.name)
            row:SetScript("OnEnter", function(self) self:SetBackdropColor(0.18, 0.18, 0.18, 1) end)
            row:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
            row:SetScript("OnClick", function()
                optDrawMapID = zoneInfo.id
                optDrawZoneDrop.menu:Hide()
                OptDrawClearSelectedRoute()
                if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
            end)
            table.insert(optDrawZoneDrop.items, row)
        end
        optDrawZoneDrop.menu:SetHeight(math.max(24, (zoneRows * 20) + 10))
        optDrawDropdownContinentID = optDrawContinentID
    end

    panel.RefreshOptionsDrawMode = function()
        -- Route colors can also be changed from the minimap route list or the
        -- regular Route Manager. Keep the active Draw Mode draft synchronized
        -- before repainting its canvas and palette.
        local _, selectedRoute = OptDrawFindRouteByGUID(optDrawSelectedGUID)
        if selectedRoute and selectedRoute.color and not OptDrawSameColor(optDrawDraft.color, selectedRoute.color) then
            optDrawDraft.color = selectedRoute.color
        end
        OptDrawUpdateDropdowns()
        OptDrawUpdateMapArt()
        OptDrawPaintPalette()
        for _, btn in pairs(optDrawRouteButtons) do btn:Hide() end

        local items = {}
        local filter = DrawModePanel.searchBox and DrawModePanel.searchBox:GetText():lower() or ""
        if filter == "search..." then filter = "" end
        if PathmakerDB and PathmakerDB.routes and optDrawMapID and PathmakerDB.routes[optDrawMapID] then
            for guid, data in pairs(PathmakerDB.routes[optDrawMapID]) do
                if IsRouteData(data) then
                    local name = data.name or "Unnamed"
                    if filter == "" or name:lower():find(filter, 1, true) then
                        table.insert(items, {guid = guid, data = data, mapID = optDrawMapID})
                    end
                end
            end
        end
        local selectedAlreadyListed = false
        if optDrawSelectedGUID then
            for _, item in ipairs(items) do
                if item.guid == optDrawSelectedGUID then
                    selectedAlreadyListed = true
                    break
                end
            end
        end
        local selectedMapID, selectedRoute = OptDrawFindRouteByGUID(optDrawSelectedGUID)
        if selectedRoute and not selectedAlreadyListed then
            optDrawSelectedMapID = selectedMapID
            table.insert(items, {
                guid = optDrawSelectedGUID,
                data = selectedRoute,
                mapID = selectedMapID,
            })
        end
        table.sort(items, function(a, b) return (a.data.name or "") < (b.data.name or "") end)
        for i, item in ipairs(items) do
            local btn = optDrawRouteButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, optRouteChild, "BackdropTemplate")
                btn:SetSize(179, 22)
                btn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8"})
                btn.color = btn:CreateTexture(nil, "OVERLAY")
                btn.color:SetSize(12, 12)
                btn.color:SetPoint("LEFT", 6, 0)
                btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.name:SetPoint("LEFT", 24, 0)
                btn.name:SetWidth(108)
                btn.name:SetJustifyH("LEFT")
                btn.del = CreateFrame("Button", nil, btn)
                btn.del:SetSize(18, 18)
                btn.del:SetPoint("RIGHT", -4, 0)
                btn.del.text = btn.del:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.del.text:SetPoint("CENTER")
                btn.del.text:SetText("X")
                btn.del.text:SetTextColor(1, 1, 0)
                btn:SetScript("OnClick", function(self)
                    if optDrawSelectedGUID == self.guid then
                        OptDrawClearSelectedRoute()
                    else
                        optDrawSelectedGUID = self.guid
                        optDrawSelectedMapID = self.mapID
                        OptDrawLoadSelectedRoute()
                    end
                    if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
                    OptDrawRefreshExternal()
                end)
                btn.del:SetScript("OnClick", function()
                    if btn.guid and PathmakerDB.routes[btn.mapID] and PathmakerDB.routes[btn.mapID][btn.guid] then
                        PushLimitedHistory("deletedRouteHistory", {mapID = btn.mapID, guid = btn.guid, route = CopyRouteData(PathmakerDB.routes[btn.mapID][btn.guid])})
                        PathmakerDB.routes[btn.mapID][btn.guid] = nil
                        if optDrawSelectedGUID == btn.guid then OptDrawClearSelectedRoute() end
                        if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
                        OptDrawRefreshExternal()
                    end
                end)
                OptDrawTooltip(btn.del, "Delete Route", "Delete this route. Restore can bring back the latest deleted route.")
                optDrawRouteButtons[i] = btn
            end
            btn.guid = item.guid
            btn.mapID = item.mapID
            btn.routeName = item.data.name
            btn:SetPoint("TOPLEFT", 0, -((i - 1) * 24))
            btn:SetWidth(panel.standaloneLayout and optRouteChild:GetWidth() - 5 or 179)
            btn.name:SetWidth(panel.standaloneLayout and optRouteChild:GetWidth() - 76 or 108)
            btn.name:SetText(item.data.name or "Unnamed")
            btn.color:SetColorTexture(unpack(item.data.color or {1, 1, 1, 1}))
            btn:SetBackdropColor(item.guid == optDrawSelectedGUID and 0.2 or 0.1, item.guid == optDrawSelectedGUID and 0.4 or 0.1, item.guid == optDrawSelectedGUID and 0.8 or 0.1, item.guid == optDrawSelectedGUID and 0.4 or 0.5)
            btn:Show()
        end
        optRouteChild:SetHeight(math.max(1, #items * 24))
        optRouteSlider:SetMinMaxValues(0, math.max(0, optRouteChild:GetHeight() - optRouteScroll:GetHeight()))
        if optDrawSelectedGUID and optDrawSelectedMapID and PathmakerDB.routes and PathmakerDB.routes[optDrawSelectedMapID] and PathmakerDB.routes[optDrawSelectedMapID][optDrawSelectedGUID] then
            local r = PathmakerDB.routes[optDrawSelectedMapID][optDrawSelectedGUID]
            if DrawModePanel.renameBox and not DrawModePanel.renameBox:HasFocus() then DrawModePanel.renameBox:SetText(r.name or "") end
            optExport:Enable()
            optExport.text:SetTextColor(1, 1, 1)
        else
            optExport:Disable()
            optExport.text:SetTextColor(0.5, 0.5, 0.5)
        end
        -- One canvas rebuild per refresh, after map sizing/art is settled.
        OptDrawRefreshCanvas()
    end
    panel.SelectRouteInOptionsDrawMode = function(guid, mapID)
        if not guid or not mapID then return end
        optDrawSelectedGUID = guid
        optDrawSelectedMapID = mapID
        OptDrawLoadSelectedRoute()
        panel.RefreshOptionsDrawMode()
    end
    panel.ClearRouteInOptionsDrawMode = function()
        OptDrawClearSelectedRoute()
        panel.RefreshOptionsDrawMode()
    end
    -- Draw Mode owns these locals. Expose layout operations through a closure
    -- rather than letting the outer options layout resolve them as globals.
    function panel.LayoutStandaloneDrawMode(action, Remember, ScrollLayout, width, height)
        if action == "capture" then
            Remember(optDrawMapFrame)
            return
        elseif action == "reset" then
            optDrawMapArtMapID = nil
            return
        end
        Remember(optDrawZoneDrop)
        optDrawZoneDrop:SetWidth(width - 290)
        -- The map absorbs height changes in either direction. Keep the tools
        -- at their original distance from the bottom without scaling them.
        local extraHeight = height - 517
        for _, widget in ipairs({optDrawCoordLabel, optDrawToolsTitle, optBtnDraw,
            optBtnAvoid, palFrame, optBtnUndo, optImport, DrawModePanel.searchBox, optRouteScroll}) do
            local state = Remember(widget)
            widget:ClearAllPoints()
            for _, point in ipairs(state.points) do
                local offset = point[3] == "TOPLEFT" and extraHeight or 0
                widget:SetPoint(point[1], point[2], point[3], point[4], point[5] - offset)
            end
        end
        Remember(DrawModePanel.searchBox); Remember(DrawModePanel.renameBox)
        DrawModePanel.searchBox:SetWidth(width - 454)
        DrawModePanel.renameBox:SetWidth(width - 454)
        ScrollLayout(optRouteScroll, optRouteChild, optRouteSlider, width - 454, 76)
        for _, button in pairs(optDrawRouteButtons) do
            Remember(button); Remember(button.name)
            button:SetWidth(width - 459)
            button.name:SetWidth(width - 530)
        end
        optDrawMapArtMapID = nil
        OptDrawUpdateMapArt()
        OptDrawApplyZoom()
        OptDrawRefreshCanvas()
    end
    end
    BuildOptionsDrawMode()

    -- Import / Export Action Buttons (Bottom Right)
    local importBtn = CreateActionBtn(RoutePanel, "Import Route", 120, 24, "green")
    importBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    importBtn:SetScript("OnClick", function() if addon.ImportExport then addon.ImportExport:ShowImport() end end)

    local exportBtn = CreateActionBtn(RoutePanel, "Export Selected", 120, 24, "normal")
    exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -10, 0)
    exportBtn:SetScript("OnClick", function()
        if addon.selectedRouteGUID and addon.ImportExport then
            addon.ImportExport:ShowExport(addon.selectedRouteGUID, addon.selectedRouteMapID)
        end
    end)

    local confirmCombineBtn = CreateActionBtn(RoutePanel, "Confirm", 70, 24, "green")
    confirmCombineBtn:SetPoint("RIGHT", exportBtn, "LEFT", -10, 0)
    confirmCombineBtn:SetScript("OnClick", ConfirmPendingRouteCombines)

    local restoreRouteBtn = CreateActionBtn(RoutePanel, "Restore", 70, 24, "normal")
    restoreRouteBtn:SetPoint("RIGHT", confirmCombineBtn, "LEFT", -10, 0)
    restoreRouteBtn:SetScript("OnClick", RestoreLastDeletedRoute)

    local undoCombineBtn = CreateActionBtn(RoutePanel, "Undo", 60, 24, "normal")
    undoCombineBtn:SetPoint("RIGHT", restoreRouteBtn, "LEFT", -10, 0)
    undoCombineBtn:SetScript("OnClick", UndoLastRouteCombine)

    -- Custom Dark EditBox Helper (For Renaming Box)
    local function CreateDarkEditBox(parent, width, height, placeholderText, hasSearchIcon)
        local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
        eb:SetSize(width, height)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlight")
        eb:SetTextInsets(hasSearchIcon and 20 or 6, 6, 0, 0)
        eb:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        eb:SetBackdropColor(0.08, 0.08, 0.08, 1)
        eb:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

        eb.placeholder = eb:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        eb.placeholder:SetPoint("LEFT", hasSearchIcon and 20 or 6, 0)
        eb.placeholder:SetText(placeholderText)

        if hasSearchIcon then
            eb.icon = eb:CreateTexture(nil, "OVERLAY")
            eb.icon:SetSize(12, 12)
            eb.icon:SetPoint("LEFT", 4, -1)
            eb.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
            eb.icon:SetVertexColor(0.6, 0.6, 0.6)
        end

        eb:SetScript("OnTextChanged", function(self)
            if self:GetText() == "" then self.placeholder:Show() else self.placeholder:Hide() end
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

        return eb
    end

    -- Top Controls: Search / Color Picker / Rename (Matched with NodePanel styling)
    local routeSearchBox = CreateFrame("EditBox", "PathMakerRouteSearchBox", RoutePanel, "SearchBoxTemplate")
    routeSearchBox:SetSize(140, 20)
    routeSearchBox:SetPoint("TOPLEFT", 44, -12)
    routeSearchBox:SetAutoFocus(false)
    routeSearchBox:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        addon.Options.routeSearchFilter = self:GetText()
        if panel.RefreshRouteList then panel.RefreshRouteList() end
    end)

    local searchColorBtn = CreateFrame("Button", nil, RoutePanel, "BackdropTemplate")
    searchColorBtn:SetSize(20, 20)
    searchColorBtn:SetPoint("TOPLEFT", 16, -12)
    searchColorBtn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    searchColorBtn:SetBackdropColor(0.2, 0.2, 0.2, 1)
    searchColorBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    searchColorBtn.tex = searchColorBtn:CreateTexture(nil, "OVERLAY")
    searchColorBtn.tex:SetAllPoints()
    searchColorBtn.tex:SetColorTexture(0,0,0,0)

    searchColorBtn:SetScript("OnClick", function()
        local cMapID = C_Map.GetBestMapForUnit("player")
        if addon.Planner and addon.Planner.panel and addon.Planner.panel:IsShown() and addon.Planner.currentMapID then
            cMapID = addon.Planner.currentMapID
        end

        OpenPalettePicker(RoutePanel, cMapID, function(c)
            if addon.Options.routeColorFilter and addon.Routes and addon.Routes:ColorsMatch(addon.Options.routeColorFilter, c) then
                addon.Options.routeColorFilter = nil
                searchColorBtn.tex:SetColorTexture(0,0,0,0)
            else
                addon.Options.routeColorFilter = c
                searchColorBtn.tex:SetColorTexture(unpack(c))
            end
            if panel.RefreshRouteList then panel.RefreshRouteList() end
        end, true, searchColorBtn)
    end)

    local renameBox = CreateDarkEditBox(RoutePanel, 200, 20, "Rename Selected Route...", false)
    renameBox:SetPoint("LEFT", routeSearchBox, "RIGHT", 8, 0)
    renameBox:SetMaxLetters(12)
    renameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if addon.selectedRouteGUID and PathmakerDB.routes then
             -- Apply rename globally depending on which map it belongs to
             for mID, routes in pairs(PathmakerDB.routes) do
                 if routes[addon.selectedRouteGUID] then
                     routes[addon.selectedRouteGUID].name = self:GetText()
                     break
                 end
             end
             panel.RefreshRouteList()
             if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
             if addon.MapFrame and addon.MapFrame.RefreshTactical then addon.MapFrame:RefreshTactical() end
        end
    end)
    -- Hook text change properly so placeholder behaves correctly
    renameBox:HookScript("OnTextChanged", function(self)
        if self:GetText() == "" then self.placeholder:Show() else self.placeholder:Hide() end
    end)

    -- Toggle Buttons (All Zones / Zone Only) - Right Side
    local btnZoneOnly = CreateActionBtn(RoutePanel, "Zone Only", 80, 24, "red")
    btnZoneOnly:SetPoint("TOPRIGHT", -16, -10) -- Matched vertical center with searchBox

    local btnAllZones = CreateActionBtn(RoutePanel, "All Zones", 80, 24, "green")
    btnAllZones:SetPoint("RIGHT", btnZoneOnly, "LEFT", -5, 0)

    local function UpdateZoneToggles()
        if addon.Options.showAllZones then
            -- Active: All Zones
            btnAllZones.leaveColor = {0.05, 0.25, 0.05, 0.9}
            btnAllZones.hoverColor = {0.1, 0.35, 0.1, 1}
            btnAllZones.borderColor = {0.15, 0.6, 0.15, 1}
            btnAllZones.textColor = {0.4, 1, 0.4}
            
            -- Inactive: Zone Only (Generic Gray Hover)
            btnZoneOnly.leaveColor = {0.15, 0.15, 0.15, 0.9}
            btnZoneOnly.hoverColor = {0.25, 0.25, 0.25, 1}
            btnZoneOnly.borderColor = {0.3, 0.3, 0.3, 1}
            btnZoneOnly.textColor = {0.5, 0.5, 0.5}
        else
            -- Inactive: All Zones (Generic Gray Hover)
            btnAllZones.leaveColor = {0.15, 0.15, 0.15, 0.9}
            btnAllZones.hoverColor = {0.25, 0.25, 0.25, 1}
            btnAllZones.borderColor = {0.3, 0.3, 0.3, 1}
            btnAllZones.textColor = {0.5, 0.5, 0.5}

            -- Active: Zone Only
            btnZoneOnly.leaveColor = {0.25, 0.05, 0.05, 0.9}
            btnZoneOnly.hoverColor = {0.35, 0.1, 0.1, 1}
            btnZoneOnly.borderColor = {0.6, 0.15, 0.15, 1}
            btnZoneOnly.textColor = {1, 0.4, 0.4}
        end
        
        -- Apply visual baseline directly using dynamic properties so hover states adapt smoothly
        btnAllZones:SetBackdropColor(unpack(btnAllZones.leaveColor))
        btnAllZones:SetBackdropBorderColor(unpack(btnAllZones.borderColor))
        btnAllZones.text:SetTextColor(unpack(btnAllZones.textColor))

        btnZoneOnly:SetBackdropColor(unpack(btnZoneOnly.leaveColor))
        btnZoneOnly:SetBackdropBorderColor(unpack(btnZoneOnly.borderColor))
        btnZoneOnly.text:SetTextColor(unpack(btnZoneOnly.textColor))

        if panel.RefreshRouteList then panel.RefreshRouteList() end
    end

    btnAllZones:SetScript("OnClick", function()
        addon.Options.showAllZones = true
        UpdateZoneToggles()
    end)
    btnZoneOnly:SetScript("OnClick", function()
        addon.Options.showAllZones = false
        UpdateZoneToggles()
    end)
    UpdateZoneToggles() -- Init state

    -- Visual Break Line (Matched completely with Herbalism / Mining)
    local topSepLine = RoutePanel:CreateTexture(nil, "ARTWORK")
    topSepLine:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    topSepLine:SetHeight(1)
    topSepLine:SetPoint("TOPLEFT", 10, -42)
    topSepLine:SetPoint("TOPRIGHT", -10, -42)

    -- Zone Name Header
    local mapNameText = RoutePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mapNameText:SetPoint("TOPLEFT", 16, -52)
    mapNameText:SetText("Zone: Unknown")
    mapNameText:SetTextColor(1, 0.82, 0)

    -- Route Scroll Frame Container 
    local routeScrollFrame, routeScrollChild, routeScrollSlider = CreateDarkScrollArea(RoutePanel, 608, 312)
    routeScrollFrame:SetPoint("TOPLEFT", 16, -77)
    RoutePanel.routeScrollFrame = routeScrollFrame
    
    panel.RefreshRouteList = function()
        for _, btn in pairs(routeButtons) do btn:Hide() end
        for _, header in pairs(routeGroupHeaders) do header:Hide() end

        local mapID = C_Map.GetBestMapForUnit("player")
        if addon.Planner and addon.Planner.panel and addon.Planner.panel:IsShown() and addon.Planner.currentMapID then
             mapID = addon.Planner.currentMapID
        end

        if addon.Options.showAllZones then
            mapNameText:SetText("Zone: All Zones")
        else
            local mapInfo = mapID and C_Map.GetMapInfo(mapID)
            if mapInfo then
                mapNameText:SetText("Zone: " .. mapInfo.name)
            else
                mapNameText:SetText("Zone: Unknown Area")
            end
        end

        -- Sync Rename and Export states
        if addon.selectedRouteGUID and PathmakerDB.routes then
            local currentRouteName = ""
            local foundRoute = false
            for mID, routes in pairs(PathmakerDB.routes) do
                if routes[addon.selectedRouteGUID] then
                    currentRouteName = routes[addon.selectedRouteGUID].name or ""
                    addon.selectedRouteMapID = mID
                    foundRoute = true
                    break
                end
            end
            
            if foundRoute then
                exportBtn:Enable()
                exportBtn.text:SetTextColor(1, 0.82, 0)
                if not renameBox:HasFocus() then
                    renameBox:SetText(currentRouteName)
                end
            else
                exportBtn:Disable()
                exportBtn.text:SetTextColor(0.5, 0.5, 0.5)
                renameBox:SetText("")
                addon.selectedRouteMapID = nil
            end
        else
            exportBtn:Disable()
            exportBtn.text:SetTextColor(0.5, 0.5, 0.5)
            renameBox:SetText("")
            addon.selectedRouteMapID = nil
        end

        PathmakerDB = PathmakerDB or {}
        PathmakerDB.routes = PathmakerDB.routes or {}
        if addon.Options.combineTargetRoute and not RouteExists(addon.Options.combineTargetRoute.mapID, addon.Options.combineTargetRoute.guid) then
            addon.Options.combineTargetRoute = nil
            addon.Options.combinePendingRoutes = nil
        end
        if addon.Options.combinePendingRoutes then
            for pendingGUID, pendingRoute in pairs(addon.Options.combinePendingRoutes) do
                if not RouteExists(pendingRoute.mapID, pendingGUID) then
                    addon.Options.combinePendingRoutes[pendingGUID] = nil
                end
            end
        end
        local hasPendingCombine = addon.Options.combineTargetRoute and addon.Options.combinePendingRoutes and next(addon.Options.combinePendingRoutes) ~= nil
        if hasPendingCombine then
            confirmCombineBtn:Enable()
            confirmCombineBtn.text:SetTextColor(0.4, 1, 0.4)
        else
            confirmCombineBtn:Disable()
            confirmCombineBtn.text:SetTextColor(0.5, 0.5, 0.5)
        end
        if addon.Options.deletedRouteHistory and #addon.Options.deletedRouteHistory > 0 then
            restoreRouteBtn:Enable()
            restoreRouteBtn.text:SetTextColor(1, 0.82, 0)
        else
            restoreRouteBtn:Disable()
            restoreRouteBtn.text:SetTextColor(0.5, 0.5, 0.5)
        end
        if addon.Options.combineUndoHistory and #addon.Options.combineUndoHistory > 0 then
            undoCombineBtn:Enable()
            undoCombineBtn.text:SetTextColor(1, 0.82, 0)
        else
            undoCombineBtn:Disable()
            undoCombineBtn.text:SetTextColor(0.5, 0.5, 0.5)
        end

        local sortedRoutes = {}
        if addon.Options.showAllZones then
            for mID, routes in pairs(PathmakerDB.routes) do
                if type(routes) == "table" then
                    for guid, data in pairs(routes) do
                        if IsRouteData(data) then
                            table.insert(sortedRoutes, {guid=guid, data=data, mapID=tonumber(mID) or mID})
                        end
                    end
                end
            end
        else
            if mapID and PathmakerDB.routes[mapID] then
                for guid, data in pairs(PathmakerDB.routes[mapID]) do
                    if IsRouteData(data) then
                        table.insert(sortedRoutes, {guid=guid, data=data, mapID=mapID})
                    end
                end
            end
        end
        
        local function GetRouteGroup(item)
            local mapInfo = item.mapID and C_Map.GetMapInfo(item.mapID)
            local zoneName = mapInfo and mapInfo.name or "Unknown Zone"
            local parentInfo = mapInfo and mapInfo.parentMapID and C_Map.GetMapInfo(mapInfo.parentMapID)
            local continentName = parentInfo and parentInfo.name or "World"
            return continentName, zoneName
        end
        table.sort(sortedRoutes, function(a, b)
            local ac, az = GetRouteGroup(a)
            local bc, bz = GetRouteGroup(b)
            if ac ~= bc then return ac < bc end
            if az ~= bz then return az < bz end
            return (a.data.name or "") < (b.data.name or "")
        end)

        local index = 0
        local headerIndex = 0
        local contentY = 0
        local lastContinent, lastZone
        local function AddGroupHeader(text, indent, color)
            headerIndex = headerIndex + 1
            local header = routeGroupHeaders[headerIndex]
            if not header then
                header = routeScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                header:SetJustifyH("LEFT")
                routeGroupHeaders[headerIndex] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 8 + indent, -contentY)
            header:SetText(text)
            header:SetTextColor(unpack(color))
            header:Show()
            contentY = contentY + 19
        end
        local filterText = addon.Options.routeSearchFilter:lower()
        if filterText == "search" then filterText = "" end -- Handle new default template placeholder text clearing

        for _, item in ipairs(sortedRoutes) do
            local show = true
            local routeZoneName = ""
            local routeMapInfo = item.mapID and C_Map.GetMapInfo(item.mapID)
            if routeMapInfo and routeMapInfo.name then routeZoneName = routeMapInfo.name end
            if filterText ~= "" and not (item.data.name or ""):lower():find(filterText, 1, true) and not routeZoneName:lower():find(filterText, 1, true) then show = false end
            if show and addon.Options.routeColorFilter then
                if not (addon.Routes and addon.Routes:ColorsMatch(item.data.color, addon.Options.routeColorFilter)) then show = false end
            end

            if show then
                local continentName, zoneName = GetRouteGroup(item)
                if continentName ~= lastContinent then
                    AddGroupHeader(continentName, 0, {1, 0.82, 0})
                    lastContinent, lastZone = continentName, nil
                end
                if zoneName ~= lastZone then
                    AddGroupHeader("Zone: " .. zoneName, 12, {0.75, 0.85, 1})
                    lastZone = zoneName
                end
                index = index + 1
                local btn = routeButtons[index]
                if not btn then
                    btn = CreateFrame("Button", nil, routeScrollChild, "BackdropTemplate")
                    btn:SetSize(595, 30)
                    btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})

                    btn.colorBtn = CreateFrame("Button", nil, btn, "BackdropTemplate")
                    btn.colorBtn:SetSize(18, 18)
                    btn.colorBtn:SetPoint("LEFT", 10, 0)
                    btn.colorBtn:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
                    btn.colorBtn:SetBackdropBorderColor(0,0,0,1)

                    btn.colorBtn:SetScript("OnClick", function()
                        local cMapID = btn.mapID
                        OpenPalettePicker(RoutePanel, cMapID, function(newColor)
                            if btn.guid and PathmakerDB.routes[cMapID] and PathmakerDB.routes[cMapID][btn.guid] then
                                PathmakerDB.routes[cMapID][btn.guid].color = newColor
                                if addon.Routes and addon.Routes.NotifyRouteColorChanged then
                                    addon.Routes:NotifyRouteColorChanged(btn.guid, cMapID, newColor)
                                end
                                panel.RefreshRouteList()
                                if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
                                if addon.UI then addon.UI:RefreshRendering() end
                            end
                        end, false, btn.colorBtn)
                    end)

                    btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    btn.nameText:SetPoint("LEFT", 34, 0)
                    btn.nameText:SetWidth(390)
                    btn.nameText:SetJustifyH("LEFT")

                    btn:SetScript("OnClick", function()
                        if addon.selectedRouteGUID == btn.guid then
                            if addon.MapFrame and addon.MapFrame.StopRouteCounters then addon.MapFrame:StopRouteCounters() end
                            addon.selectedRouteGUID = nil
                            addon.selectedRouteMapID = nil
                            if addon.MapFrame and addon.MapFrame.ResetFarmVisuals then addon.MapFrame:ResetFarmVisuals() end
                        else
                            addon.selectedRouteGUID = btn.guid
                            addon.selectedRouteMapID = btn.mapID
                        end
                        panel.RefreshRouteList()
                        if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
                        if addon.MapFrame and addon.MapFrame.UpdateUIState then addon.MapFrame:UpdateUIState() end
                        if addon.UI then addon.UI:RefreshRendering() end
                    end)

                    btn.delBtn = CreateActionBtn(btn, "Delete", 60, 20, "red")
                    btn.delBtn:SetPoint("RIGHT", -10, 0)
                    btn.delBtn:SetScript("OnClick", function()
                        local cMapID = btn.mapID
                        if btn.guid and PathmakerDB.routes[cMapID] and PathmakerDB.routes[cMapID][btn.guid] then
                            if addon.selectedRouteGUID == btn.guid then
                                if addon.MapFrame and addon.MapFrame.StopRouteCounters then addon.MapFrame:StopRouteCounters() end
                                addon.selectedRouteGUID = nil
                                addon.selectedRouteMapID = nil
                                if addon.MapFrame and addon.MapFrame.ResetFarmVisuals then addon.MapFrame:ResetFarmVisuals() end
                            end
                            if addon.Options.combineTargetRoute and addon.Options.combineTargetRoute.guid == btn.guid then
                                addon.Options.combineTargetRoute = nil
                                addon.Options.combinePendingRoutes = nil
                            end
                            PushLimitedHistory("deletedRouteHistory", {
                                mapID = cMapID,
                                guid = btn.guid,
                                route = CopyRouteData(PathmakerDB.routes[cMapID][btn.guid])
                            })
                            PathmakerDB.routes[cMapID][btn.guid] = nil
                            panel.RefreshRouteList()
                            if addon.MapFrame and addon.MapFrame.UpdateRouteList then addon.MapFrame:UpdateRouteList() end
                            if addon.MapFrame and addon.MapFrame.UpdateUIState then addon.MapFrame:UpdateUIState() end
                            if addon.UI then addon.UI:RefreshRendering() end
                        end
                    end)

                    btn.combineBtn = CreateActionBtn(btn, "Combine", 70, 20, "normal")
                    btn.combineBtn:SetPoint("RIGHT", btn.delBtn, "LEFT", -5, 0)
                    btn.combineBtn:SetScript("OnClick", function()
                        local target = addon.Options.combineTargetRoute
                        if target and target.guid == btn.guid then
                            addon.Options.combineTargetRoute = nil
                            addon.Options.combinePendingRoutes = nil
                            panel.RefreshRouteList()
                            return
                        end

                        if not target or not RouteExists(target.mapID, target.guid) then
                            addon.Options.combineTargetRoute = {guid = btn.guid, mapID = btn.mapID}
                            addon.Options.combinePendingRoutes = {}
                            panel.RefreshRouteList()
                            return
                        end

                        if target.mapID ~= btn.mapID then
                            local hideErr = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
                            if not hideErr then
                                print("|cFFFF4444PathMaker:|r Only routes from the same zone can be combined.")
                            end
                            return
                        end

                        addon.Options.combinePendingRoutes = addon.Options.combinePendingRoutes or {}
                        if addon.Options.combinePendingRoutes[btn.guid] then
                            addon.Options.combinePendingRoutes[btn.guid] = nil
                        else
                            addon.Options.combinePendingRoutes[btn.guid] = {guid = btn.guid, mapID = btn.mapID}
                        end
                        panel.RefreshRouteList()
                    end)

                    routeButtons[index] = btn
                end

                btn.mapID = item.mapID
                btn.guid = item.guid
                
                local displayName = item.data.name or "Unnamed Route"
                btn.nameText:SetText(displayName)
                local routeProfession = item.data.profession or (item.data.nodeName and select(3, GetNodeVisual(GetNodeProfession(item.data.nodeName))))
                local _, routeNameColor = GetNodeVisual(routeProfession)
                if routeProfession == "Mining" or routeProfession == "Herbalism" or routeProfession == "Treasure" then
                    btn.nameText:SetTextColor(routeNameColor[1], routeNameColor[2], routeNameColor[3], 1)
                else
                    btn.nameText:SetTextColor(1, 1, 1, 1)
                end
                
                btn.colorBtn:SetBackdropColor(unpack(item.data.color or {1,1,1,1}))

                local combineTarget = addon.Options.combineTargetRoute
                local isCombineTarget = combineTarget and combineTarget.guid == item.guid
                local isPendingCombine = addon.Options.combinePendingRoutes and addon.Options.combinePendingRoutes[item.guid] ~= nil
                local canCombineWithTarget = (not combineTarget) or isCombineTarget or combineTarget.mapID == item.mapID
                if btn.combineBtn then
                    if canCombineWithTarget then
                        btn.combineBtn:Show()
                        btn.combineBtn:Enable()
                        btn.combineBtn.text:SetText((isCombineTarget or isPendingCombine) and "Combined" or "Combine")
                        if isCombineTarget or isPendingCombine then
                            btn.combineBtn.leaveColor = {0.18, 0.45, 0.18, 0.95}
                            btn.combineBtn.hoverColor = {0.24, 0.55, 0.24, 1}
                            btn.combineBtn.borderColor = {0.35, 0.75, 0.35, 1}
                            btn.combineBtn.textColor = {0.65, 1, 0.65}
                        else
                            btn.combineBtn.leaveColor = {0.46, 0.34, 0.12, 0.95}
                            btn.combineBtn.hoverColor = {0.58, 0.44, 0.18, 1}
                            btn.combineBtn.borderColor = {0.78, 0.61, 0.28, 1}
                            btn.combineBtn.textColor = {1, 0.86, 0.45}
                        end
                        btn.combineBtn:SetBackdropColor(unpack(btn.combineBtn.leaveColor))
                        btn.combineBtn:SetBackdropBorderColor(unpack(btn.combineBtn.borderColor))
                        btn.combineBtn.text:SetTextColor(unpack(btn.combineBtn.textColor))
                    else
                        btn.combineBtn:Hide()
                    end
                end

                if item.guid == addon.selectedRouteGUID then
                    btn:SetBackdropColor(0.2, 0.4, 0.8, 0.4)
                else
                    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
                end

                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", 0, -contentY)
                btn:SetWidth(panel.standaloneLayout and routeScrollChild:GetWidth() - 13 or 595)
                btn.nameText:SetWidth(panel.standaloneLayout and routeScrollChild:GetWidth() - 218 or 390)
                btn:Show()
                contentY = contentY + 32
            end
        end

        routeScrollChild:SetHeight(math.max(1, contentY))
        local maxScroll = math.max(0, contentY - routeScrollFrame:GetHeight())
        routeScrollSlider:SetMinMaxValues(0, maxScroll)
    end
    
    -- Bridge so external systems can force update
    addon.Options.RefreshRouteList = panel.RefreshRouteList

    -- ============================================================================
    -- GENERAL PANEL 
    -- ============================================================================
    
    do
        local CONTENT_LEFT_PADDING = 20
        local CONTENT_RIGHT_PADDING = 24
        local CONTENT_TOP_PADDING = 18
        local CONTENT_BOTTOM_PADDING = 20
        local SCROLLBAR_RESERVED_WIDTH = 12
        local SECTION_GAP = 24
        local ROW_HEIGHT = 32
        local ROW_GAP = 8
        local LABEL_WIDTH = 150
        local SLIDER_WIDTH = 230
        local VALUE_BOX_WIDTH = 68
        local VALUE_BOX_HEIGHT = 24
        local CHECKBOX_COLUMN_GAP = 24
        local CHECKBOX_SIZE = 24
        local CHECKBOX_ROW_HEIGHT = 24
        local STACKED_SLIDER_ROW_STEP = 58
        local CONTENT_WIDTH = 608
        local CONTENT_RIGHT = CONTENT_WIDTH - CONTENT_RIGHT_PADDING - SCROLLBAR_RESERVED_WIDTH
        local SLIDER_X = CONTENT_LEFT_PADDING + LABEL_WIDTH + 12
        local VALUE_BOX_X = SLIDER_X + SLIDER_WIDTH + 12
        addon.Options.generalValueBoxes = {}

        local function CreateSectionHeader(parent, titleText, yOffset)
            local header = CreateFrame("Frame", nil, parent)
            header:SetSize(CONTENT_RIGHT - CONTENT_LEFT_PADDING, 22)
            header:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_LEFT_PADDING, -math.floor(yOffset + 0.5))

            local separatorText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            separatorText:SetPoint("CENTER", header, "CENTER", 0, 0)
            separatorText:SetText(string.format(
                "|cff707070%s|r  |cffffd100%s|r  |cff707070%s|r",
                string.rep("-", 40), T(titleText), string.rep("-", 40)
            ))
        end

        local function CreateGeneralCheck(label, key, xPos, yPos, columnWidth)
            local cb = CreateFrame("CheckButton", nil, GeneralPanel, "UICheckButtonTemplate")
            cb:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
            cb:SetPoint("TOPLEFT", xPos, -yPos)

            cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            cb.text:SetJustifyH("LEFT")
            cb.text:SetText(T(label))
            cb:SetHitRectInsets(0, -(columnWidth - CHECKBOX_SIZE), 0, 0)

            addon.Options.checkboxes = addon.Options.checkboxes or {}
            addon.Options.checkboxes[key] = cb

            cb:SetScript("OnShow", function(self)
                self:SetChecked(PathmakerDB and PathmakerDB.settings and PathmakerDB.settings[key] == true)
            end)

            cb:SetScript("OnClick", function(self)
                if key == "usePathmakerMinimap" and addon.MapFrame then
                    addon.MapFrame:SetMinimapEnabled(self:GetChecked())
                    addon.Options:RefreshSettingsUI()
                    return
                end
                if addon.isFarmMode and MINIMAP_UI_OPTION_KEYS[key] then
                    self:SetChecked(PathmakerDB and PathmakerDB.settings and PathmakerDB.settings[key] == true)
                    return
                end
                local val = self:GetChecked()
                PathmakerDB = PathmakerDB or {}
                PathmakerDB.settings = PathmakerDB.settings or {}
                PathmakerDB.settings[key] = val

                if addon.MapFrame then
                    addon.MapFrame.tempSettings = addon.MapFrame.tempSettings or {}
                    addon.MapFrame.tempSettings[key] = val
                    if type(addon.MapFrame.ApplySettings) == "function" then
                        addon.MapFrame:ApplySettings(PathmakerDB.settings)
                    end
                    if type(addon.MapFrame.RefreshSettingsUI) == "function" then
                        addon.MapFrame:RefreshSettingsUI()
                    end
                end
                if string.find(key, "navArrow", 1, true) == 1 and addon.Navigation and addon.Navigation.ApplySettings then
                    addon.Navigation:ApplySettings()
                end
                if addon.UI and type(addon.UI.RefreshRendering) == "function" then
                    addon.UI:RefreshRendering()
                end
                if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then
                    addon.Heatmap:ForceUpdate()
                end
            end)
            return cb
        end

        local function CreateCheckboxGrid(items, columns, yOffset, leftOffset, totalWidth, columnGap)
            local gridLeft = leftOffset or CONTENT_LEFT_PADDING
            local usableWidth = totalWidth or (CONTENT_RIGHT - CONTENT_LEFT_PADDING)
            local gap = columnGap or CHECKBOX_COLUMN_GAP
            local columnWidth = (usableWidth - ((columns - 1) * gap)) / columns
            for index, item in ipairs(items) do
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                local x = gridLeft + column * (columnWidth + gap)
                CreateGeneralCheck(item[1], item[2], x, yOffset + row * CHECKBOX_ROW_HEIGHT, columnWidth)
            end
        end

        local function FormatSliderValue(value, displayScale, unit, hiddenAtZero)
            local displayValue = value * (displayScale or 1)
            local rounded = math.floor(displayValue + 0.5)
            if hiddenAtZero and rounded <= 0 then return "Hidden (0%)" end
            if unit == "%" then return string.format("%d%%", rounded) end
            if unit == "px" then return string.format("%d px", rounded) end
            return tostring(rounded)
        end

        local function CreateNumericValueBox(parent, width)
            local box = CreateFrame("Frame", nil, parent)
            box:SetSize(width or VALUE_BOX_WIDTH, VALUE_BOX_HEIGHT)

            box.display = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            box.display:SetAllPoints()
            box.display:SetJustifyH("RIGHT")
            box.display:SetTextColor(0.92, 0.92, 0.92)

            box.editor = CreateFrame("EditBox", nil, box)
            box.editor:SetAllPoints()
            box.editor:SetAutoFocus(false)
            box.editor:SetMaxLetters(14)
            box.editor:SetFontObject(GameFontHighlightSmall)
            box.editor:SetJustifyH("RIGHT")
            box.editor:SetTextInsets(0, 0, 0, 0)
            box.editor:SetTextColor(0.92, 0.92, 0.92)
            box.editor:Hide()

            box.SetText = function(self, text)
                self.currentText = text or ""
                self.display:SetText(self.currentText)
                if not self.editor:IsShown() then self.editor:SetText(self.currentText) end
            end
            box.GetText = function(self)
                if self.editor:IsShown() then return self.editor:GetText() end
                return self.currentText or ""
            end
            box.SetTextColor = function(self, r, g, b, a)
                self.display:SetTextColor(r, g, b, a or 1)
                self.editor:SetTextColor(r, g, b, a or 1)
            end
            box.BeginEditing = function(self)
                if self.disabled then return end
                self.editor:SetText(self.currentText or "")
                self.display:Hide()
                self.editor:Show()
                self.editor:SetFocus()
                self.editor:HighlightText()
            end
            box.EndEditing = function(self)
                self.editor:ClearFocus()
                self.editor:Hide()
                self.display:Show()
            end
            box.ClearFocus = function(self) self:EndEditing() end
            box.Disable = function(self)
                self.disabled = true
                self:EndEditing()
                self:EnableMouse(false)
            end
            box.Enable = function(self)
                self.disabled = false
                self:EnableMouse(true)
            end

            box:EnableMouse(true)
            box:SetScript("OnMouseDown", function(self) self:BeginEditing() end)
            return box
        end

        local function CreateSliderSettingRow(parent, config)
            local rowX = config.x or CONTENT_LEFT_PADDING
            local sliderWidth = config.sliderWidth or SLIDER_WIDTH
            local boxWidth = config.valueBoxWidth or VALUE_BOX_WIDTH
            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", parent, "TOPLEFT", rowX, -config.y)
            label:SetSize(config.stacked and (sliderWidth - boxWidth - 8) or LABEL_WIDTH, VALUE_BOX_HEIGHT)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            label:SetText(T(config.label))
            label:SetTextColor(1, 0.82, 0)

            local valueBox = CreateNumericValueBox(parent, boxWidth)
            valueBox:SetPoint("TOPLEFT", parent, "TOPLEFT", config.stacked and (rowX + sliderWidth - boxWidth) or VALUE_BOX_X, -config.y)

            local slider
            local function UpdateValueText(value)
                valueBox:SetText(FormatSliderValue(value, config.displayScale, config.unit, config.hiddenAtZero))
                if config.hiddenAtZero then
                    if value <= 0 then valueBox:SetTextColor(1, 0.15, 0.1)
                    else valueBox:SetTextColor(0.92, 0.92, 0.92) end
                else
                    valueBox:SetTextColor(0.92, 0.92, 0.92)
                end
            end

            local function ApplyValue(value, force)
                value = math.max(config.min, math.min(config.max, tonumber(value) or config.current))
                if config.roundStored then value = math.floor(value + 0.5) end
                if slider and config.roundStored and force then slider:SetValue(value, true) end
                UpdateValueText(value)
                config.callback(value, force)
            end

            slider = CreateCustomSlider(parent, sliderWidth, config.stacked and 10 or 16, config.min, config.max, config.current, ApplyValue)
            slider:SetPoint("TOPLEFT", parent, "TOPLEFT", config.stacked and rowX or SLIDER_X, -config.y - (config.stacked and 30 or 4))

            local committing = false
            local canceling = false
            local function RestoreValue()
                local current = config.getValue and config.getValue() or config.current
                slider:SetValue(current)
                UpdateValueText(current)
            end
            local function CommitValue()
                if committing then return end
                committing = true
                local displayValue = tonumber(string.match(valueBox:GetText() or "", "[-+]?%d*%.?%d+"))
                if displayValue then
                    local value = displayValue / (config.displayScale or 1)
                    value = math.max(config.min, math.min(config.max, value))
                    if config.roundStored then value = math.floor(value + 0.5) end
                    slider:SetValue(value)
                    ApplyValue(value, true)
                else
                    RestoreValue()
                end
                valueBox:ClearFocus()
                committing = false
            end
            valueBox.editor:SetScript("OnEnterPressed", CommitValue)
            valueBox.editor:SetScript("OnEditFocusLost", function()
                if canceling then return end
                CommitValue()
            end)
            valueBox.editor:SetScript("OnEscapePressed", function()
                canceling = true
                RestoreValue()
                valueBox:EndEditing()
                canceling = false
            end)
            valueBox.RefreshDisplay = function(self)
                local current = config.getValue and config.getValue() or config.current
                current = math.max(config.min, math.min(config.max, tonumber(current) or config.current))
                if config.roundStored then current = math.floor(current + 0.5) end
                slider:SetValue(current)
                UpdateValueText(current)
            end
            valueBox:SetScript("OnShow", function(self) self:RefreshDisplay() end)
            table.insert(addon.Options.generalValueBoxes, valueBox)
            valueBox:RefreshDisplay()
            return label, slider, valueBox
        end

        local function CreateCompactOptionButton(parent, text, width, x, y)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(width, 28)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)

            btn.border = StabilizeScrollingTexture(btn:CreateTexture(nil, "BACKGROUND"))
            btn.border:SetColorTexture(0.48, 0.34, 0.06, 1)
            btn.border:SetAllPoints()

            btn.background = StabilizeScrollingTexture(btn:CreateTexture(nil, "BACKGROUND", nil, 1))
            btn.background:SetColorTexture(0.055, 0.05, 0.035, 0.95)
            btn.background:SetPoint("TOPLEFT", 1, -1)
            btn.background:SetPoint("BOTTOMRIGHT", -1, 1)

            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text:SetPoint("CENTER")
            btn.text:SetText(T(text))
            btn.text:SetTextColor(0.88, 0.88, 0.88)
            btn:SetScript("OnEnter", function(self)
                if not self.IsEnabled or self:IsEnabled() then
                    self.background:SetColorTexture(0.12, 0.10, 0.05, 1)
                    self.border:SetColorTexture(1, 0.72, 0.08, 1)
                    self.text:SetTextColor(1, 0.82, 0)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                self.background:SetColorTexture(0.055, 0.05, 0.035, 0.95)
                self.border:SetColorTexture(0.48, 0.34, 0.06, 1)
                self.text:SetTextColor(0.88, 0.88, 0.88)
            end)
            return btn
        end

        local function RefreshExpansionViews()
            drawSelectedZoneID = nil
            drawSelectedContinentID = nil
            optDrawMapID = GetDefaultDrawMapID()
            optDrawContinentID = nil
            if addon.Planner and addon.Planner.RefreshMapCatalog then addon.Planner:RefreshMapCatalog() end
            RefreshDrawDropdowns()
            if panel.RefreshDrawNodeList then panel.RefreshDrawNodeList() end
            if panel.RefreshOptionsDrawMode then panel.RefreshOptionsDrawMode() end
            if panel.RefreshNodeList then panel.RefreshNodeList() end
            if addon.MapFrame and addon.MapFrame.UpdateNodeFilterList then addon.MapFrame:UpdateNodeFilterList() end
            if addon.RefreshAllVisuals then addon:RefreshAllVisuals() end
        end

        local function SetExpansionVisible(expansionKey, visible, deferRefresh)
            PathmakerDB = PathmakerDB or {}
            PathmakerDB.settings = PathmakerDB.settings or {}
            PathmakerDB.settings.expansionVisibility = PathmakerDB.settings.expansionVisibility or {}
            PathmakerDB.settings.expansionVisibility[expansionKey] = visible and true or false
            local checkbox = addon.Options.expansionCheckboxes and addon.Options.expansionCheckboxes[expansionKey]
            if checkbox then checkbox:SetChecked(visible) end
            if not deferRefresh then RefreshExpansionViews() end
        end

        local function CreateExpansionCheck(expansion, xPos, yPos, columnWidth)
            local cb = CreateFrame("CheckButton", nil, GeneralPanel, "UICheckButtonTemplate")
            cb:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
            cb:SetPoint("TOPLEFT", xPos, -yPos)
            cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            cb.text:SetJustifyH("LEFT")
            cb.text:SetText(expansion.label)
            cb:SetHitRectInsets(0, -(columnWidth - CHECKBOX_SIZE), 0, 0)
            addon.Options.expansionCheckboxes = addon.Options.expansionCheckboxes or {}
            addon.Options.expansionCheckboxes[expansion.key] = cb
            cb:SetScript("OnShow", function(self)
                self:SetChecked(not addon.Compat or addon.Compat:IsExpansionVisible(expansion.key))
            end)
            cb:SetScript("OnClick", function(self) SetExpansionVisible(expansion.key, self:GetChecked()) end)
            return cb
        end

        local settings = EnsureOptionsSettings()
        local cursor = CONTENT_TOP_PADDING
        CreateSectionHeader(GeneralPanel, "General options", cursor)
        cursor = cursor + SECTION_GAP

        local languageLabel = GeneralPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        languageLabel:SetPoint("TOPLEFT", GeneralPanel, "TOPLEFT", CONTENT_LEFT_PADDING, -cursor)
        languageLabel:SetSize(145, 28)
        languageLabel:SetJustifyH("LEFT")
        languageLabel:SetJustifyV("MIDDLE")
        languageLabel:SetText(T("Language"))
        languageLabel:SetTextColor(1, 0.82, 0)

        local languageButton = CreateCompactOptionButton(
            GeneralPanel,
            T("Language") .. ": " .. addon.Localization:GetLanguageName(settings.language),
            235,
            CONTENT_LEFT_PADDING + 150,
            cursor
        )
        addon.Options.languageBtn = languageButton

        local languageMenu = CreateFrame("Frame", nil, GeneralPanel, "BackdropTemplate")
        languageMenu:SetSize(370, 166)
        languageMenu:SetPoint("TOPLEFT", languageButton, "BOTTOMLEFT", 0, -2)
        languageMenu:SetFrameLevel(languageButton:GetFrameLevel() + 30)
        languageMenu:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        languageMenu:SetBackdropColor(0.025, 0.025, 0.025, 0.98)
        languageMenu:SetBackdropBorderColor(0.75, 0.53, 0.08, 1)
        languageMenu:Hide()
        addon.Options.languageMenu = languageMenu

        for index, language in ipairs(addon.Localization.languages) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local choice = CreateFrame("Button", nil, languageMenu, "BackdropTemplate")
            choice:SetSize(176, 20)
            choice:SetPoint("TOPLEFT", 6 + column * 182, -6 - row * 22)
            choice:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
            choice:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
            choice.text = choice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            choice.text:SetPoint("LEFT", 6, 0)
            choice.text:SetText(language.name)
            choice:SetScript("OnEnter", function(self) self:SetBackdropColor(0.22, 0.16, 0.04, 1) end)
            choice:SetScript("OnLeave", function(self) self:SetBackdropColor(0.08, 0.08, 0.08, 0.95) end)
            choice:SetScript("OnClick", function()
                PathmakerDB.settings.language = language.code
                languageMenu:Hide()
                ReloadUI()
            end)
        end
        languageButton:SetScript("OnClick", function()
            if languageMenu:IsShown() then languageMenu:Hide() else languageMenu:Show() end
        end)
        cursor = cursor + 38

        local versionsLabel = GeneralPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        versionsLabel:SetPoint("TOPLEFT", GeneralPanel, "TOPLEFT", CONTENT_LEFT_PADDING, -cursor)
        versionsLabel:SetText(T("Shown WoW Versions (Maps, Herbs & Mining)"))
        versionsLabel:SetTextColor(1, 0.82, 0)
        cursor = cursor + 22

        local expansionColumns = 3
        local expansionGap = CHECKBOX_COLUMN_GAP
        local expansionWidth = (CONTENT_RIGHT - CONTENT_LEFT_PADDING - ((expansionColumns - 1) * expansionGap)) / expansionColumns
        for index, expansion in ipairs(addon.Compat and addon.Compat.expansions or {}) do
            local column = (index - 1) % expansionColumns
            local row = math.floor((index - 1) / expansionColumns)
            CreateExpansionCheck(
                expansion,
                CONTENT_LEFT_PADDING + column * (expansionWidth + expansionGap),
                cursor + row * CHECKBOX_ROW_HEIGHT,
                expansionWidth
            )
        end
        cursor = cursor + (math.ceil(#(addon.Compat and addon.Compat.expansions or {}) / expansionColumns) * CHECKBOX_ROW_HEIGHT) + 4

        local showAllVersions = CreateCompactOptionButton(GeneralPanel, "Show All Versions", 130, CONTENT_LEFT_PADDING, cursor)
        local hideAllVersions = CreateCompactOptionButton(GeneralPanel, "Hide All Versions", 130, CONTENT_LEFT_PADDING + 142, cursor)
        showAllVersions:SetScript("OnClick", function()
            for _, expansion in ipairs(addon.Compat and addon.Compat.expansions or {}) do
                SetExpansionVisible(expansion.key, true, true)
            end
            RefreshExpansionViews()
        end)
        hideAllVersions:SetScript("OnClick", function()
            for _, expansion in ipairs(addon.Compat and addon.Compat.expansions or {}) do
                SetExpansionVisible(expansion.key, false, true)
            end
            RefreshExpansionViews()
        end)
        cursor = cursor + 36 + SECTION_GAP

        local disableMessagesLabel = GeneralPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        disableMessagesLabel:SetPoint("TOPLEFT", GeneralPanel, "TOPLEFT", CONTENT_LEFT_PADDING, -cursor)
        disableMessagesLabel:SetText(T("Disable Messages"))
        disableMessagesLabel:SetTextColor(1, 0.82, 0)
        cursor = cursor + 22

        CreateCheckboxGrid({
            { "Addon Enable / Disable", "disableMsgToggle" },
            { "Route Import / Export", "disableMsgRouteIO" },
            { "Nodes Imported", "disableMsgNodeImport" },
            { "Errors & Warnings", "disableMsgError" },
            { "Database Wipes", "disableMsgWipe" },
            { "Duplicates Cleaned", "disableMsgDedupe" },
            { "Deleted Nodes", "disableMsgNodeDelete" },
            { "Route Recording", "disableMsgRecording" },
            { "Generated Routes", "disableMsgGeneratedRoutes" },
            { "Route Editing", "disableMsgRouteEditing" },
            { "Controls Reset", "disableMsgControls" },
        }, 3, cursor)
        cursor = cursor + (4 * CHECKBOX_ROW_HEIGHT) + SECTION_GAP

        CreateSectionHeader(GeneralPanel, "Minimap UI", cursor)
        cursor = cursor + SECTION_GAP
        CreateGeneralCheck("Use PathMaker Minimap", "usePathmakerMinimap", CONTENT_LEFT_PADDING, cursor, 250)
        cursor = cursor + CHECKBOX_ROW_HEIGHT
        local minimapHint = GeneralPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        minimapHint:SetPoint("TOPLEFT", GeneralPanel, "TOPLEFT", CONTENT_LEFT_PADDING, -cursor)
        minimapHint:SetText("Off: use WoW's minimap and separate controls. Routes, nodes and navigation stay available.")
        minimapHint:SetTextColor(0.7, 0.7, 0.7)
        cursor = cursor + 24
        local minimapTop = cursor
        addon.Options.alphaLabel, addon.Options.alphaSlider, addon.Options.alphaLabelVal = CreateSliderSettingRow(GeneralPanel, {
            y = minimapTop, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Interface Opacity", min = 0, max = 1,
            current = settings.alpha or 1, displayScale = 100, unit = "%", hiddenAtZero = true,
            valueBoxWidth = 76, getValue = function() return EnsureOptionsSettings().alpha or 1 end,
            callback = function(val, force)
                if addon.isFarmMode then
                    if force then addon.Options:RefreshSettingsUI() end
                    return
                end
                if addon.MapFrame then
                    addon.MapFrame.tempSettings = addon.MapFrame.tempSettings or {}
                    addon.MapFrame.tempSettings.alpha = val
                end
                PathmakerDB.settings.alpha = val
                if addon.MapFrame then
                    if type(addon.MapFrame.ApplySettings) == "function" then addon.MapFrame:ApplySettings(PathmakerDB.settings) end
                    if force and type(addon.MapFrame.RefreshSettingsUI) == "function" then addon.MapFrame:RefreshSettingsUI() end
                end
            end,
        })
        addon.Options.alphaValueBox = addon.Options.alphaLabelVal
        addon.Options.sizeLabel, addon.Options.scaleSlider, addon.Options.sizeLabelVal = CreateSliderSettingRow(GeneralPanel, {
            y = minimapTop + 66, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Minimap Size", min = 0.5, max = 2.5,
            current = settings.minimapScale, displayScale = 100, unit = "%",
            getValue = function() return EnsureOptionsSettings().minimapScale end,
            callback = function(val, force)
                if addon.isFarmMode then
                    if force then addon.Options:RefreshSettingsUI() end
                    return
                end
                if addon.MapFrame then
                    addon.MapFrame.tempSettings = addon.MapFrame.tempSettings or {}
                    addon.MapFrame.tempSettings.minimapScale = val
                end
                PathmakerDB.settings.minimapScale = val
                if addon.MapFrame then
                    if type(addon.MapFrame.ApplySettings) == "function" then addon.MapFrame:ApplySettings(PathmakerDB.settings) end
                    if force and type(addon.MapFrame.RefreshSettingsUI) == "function" then addon.MapFrame:RefreshSettingsUI() end
                end
            end,
        })
        addon.Options.sizeValueBox = addon.Options.sizeLabelVal
        local btnToggleShape = CreateCompactOptionButton(GeneralPanel, "Circle Map", 112, CONTENT_LEFT_PADDING, minimapTop + 132)
        btnToggleShape:SetScript("OnClick", function()
            if addon.isFarmMode then addon.Options:RefreshSettingsUI() return end
            PathmakerDB = PathmakerDB or {}
            PathmakerDB.settings = PathmakerDB.settings or {}
            addon.useSquareMap = not addon.useSquareMap
            PathmakerDB.settings.useSquareMap = addon.useSquareMap
            if addon.MapFrame and addon.MapFrame.ApplyMinimapShape then
                addon.MapFrame:ApplyMinimapShape(addon.useSquareMap)
            elseif Minimap then
                Minimap:SetMaskTexture(addon.useSquareMap and "Interface\\Buttons\\WHITE8x8" or "Textures\\MinimapMask")
            end
            addon.Options:RefreshSettingsUI()
            if addon.MapFrame then
                if type(addon.MapFrame.UpdateUIState) == "function" then addon.MapFrame:UpdateUIState() end
                if type(addon.MapFrame.RefreshSettingsUI) == "function" then addon.MapFrame:RefreshSettingsUI() end
                if type(addon.MapFrame.LayoutMinimapButtons) == "function" then addon.MapFrame:LayoutMinimapButtons() end
            end
        end)
        addon.Options.mapShapeBtn = btnToggleShape

        local btnClockPosition = CreateCompactOptionButton(GeneralPanel, "Clock: Default", 130, CONTENT_LEFT_PADDING + 120, minimapTop + 132)
        btnClockPosition:SetScript("OnClick", function()
            if addon.isFarmMode then addon.Options:RefreshSettingsUI() return end
            PathmakerDB = PathmakerDB or {}
            PathmakerDB.settings = PathmakerDB.settings or {}
            PathmakerDB.settings.clockPosition = GetNextClockPosition(PathmakerDB.settings.clockPosition or "DEFAULT")
            addon.Options:RefreshSettingsUI()
            if addon.MapFrame then
                if type(addon.MapFrame.ApplySettings) == "function" then addon.MapFrame:ApplySettings(PathmakerDB.settings) end
                if type(addon.MapFrame.RefreshSettingsUI) == "function" then addon.MapFrame:RefreshSettingsUI() end
            end
        end)
        addon.Options.clockPositionBtn = btnClockPosition
        local btnMinimapEdges = CreateCompactOptionButton(GeneralPanel, "Full Edges: Off", 130, CONTENT_LEFT_PADDING, minimapTop + 168)
        btnMinimapEdges:SetScript("OnClick", function()
            if addon.isFarmMode then addon.Options:RefreshSettingsUI() return end
            local s = EnsureOptionsSettings()
            s.minimapUseFullEdges = not s.minimapUseFullEdges
            if addon.MapFrame and type(addon.MapFrame.ApplySettings) == "function" then
                addon.MapFrame:ApplySettings(s)
            end
            addon.Options:RefreshSettingsUI()
        end)
        addon.Options.minimapEdgesBtn = btnMinimapEdges
        CreateCheckboxGrid({
            { "Hide Header", "hideHeaderBar" }, { "Hide Clock", "hideClock" },
            { "Hide Zone Bar", "hideZoneBar" }, { "Hide Tracking", "hideTracking" },
            { "Hide Routes", "hideRoutes" }, { "Hide LFG", "hideLFG" },
            { "Hide Tools", "hideTacticalTools" }, { "Hide Nodes", "hideHeatmap" },
            { "Hide Quickbar", "hideQuickBar" }, { "No Node Circle", "farmHideCircle" },
        }, 2, minimapTop, CONTENT_LEFT_PADDING + 274, 278, 12)
        CreateGeneralCheck("Lock Minimap", "minimapLocked", CONTENT_LEFT_PADDING + 419,
            minimapTop + 5 * CHECKBOX_ROW_HEIGHT, 133)
        cursor = minimapTop + 196 + SECTION_GAP

        CreateSectionHeader(GeneralPanel, "World Map", cursor)
        cursor = cursor + SECTION_GAP
        local worldMapTop = cursor
        local worldMapNodeSizeLabel, worldMapNodeSizeSlider, worldMapNodeSizeVal = CreateSliderSettingRow(GeneralPanel, {
            y = worldMapTop, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Node Icon Size", min = 6, max = 40,
            current = settings.worldMapNodeIconSize, unit = "px", roundStored = true,
            getValue = function() return EnsureOptionsSettings().worldMapNodeIconSize end,
            callback = function(val)
                PathmakerDB.settings.worldMapNodeIconSize = val
                if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then addon.Heatmap:ForceUpdate() end
            end,
        })
        addon.Options.worldMapNodeSizeSlider = worldMapNodeSizeSlider
        addon.Options.worldMapNodeSizeLabelVal = worldMapNodeSizeVal

        local worldMapNodeOpacityLabel, worldMapNodeOpacitySlider, worldMapNodeOpacityVal = CreateSliderSettingRow(GeneralPanel, {
            y = worldMapTop + 66, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Node Icon Opacity", min = 0, max = 1,
            current = settings.worldMapNodeIconOpacity, displayScale = 100, unit = "%", hiddenAtZero = true,
            getValue = function() return EnsureOptionsSettings().worldMapNodeIconOpacity end,
            callback = function(val)
                PathmakerDB.settings.worldMapNodeIconOpacity = val
                if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then addon.Heatmap:ForceUpdate() end
            end,
        })
        addon.Options.worldMapNodeOpacitySlider = worldMapNodeOpacitySlider
        addon.Options.worldMapNodeOpacityLabelVal = worldMapNodeOpacityVal

        CreateCheckboxGrid({
            { "Herbalism", "worldMapShowHerbalism" },
            { "Mining", "worldMapShowMining" },
            { "Treasures", "worldMapShowTreasure" },
        }, 1, worldMapTop, CONTENT_LEFT_PADDING + 310, 220, 12)
        cursor = worldMapTop + 132 + SECTION_GAP

        CreateSectionHeader(GeneralPanel, "Farm Mode", cursor)
        cursor = cursor + SECTION_GAP
        local farmTop = cursor
        local farmAlphaLabel, farmAlphaSlider, farmAlphaVal = CreateSliderSettingRow(GeneralPanel, {
            y = farmTop + 132, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Farm Mode Opacity", min = 0, max = 1,
            current = settings.farmAlpha, displayScale = 100, unit = "%",
            getValue = function() return EnsureOptionsSettings().farmAlpha end,
            callback = function(val)
                val = NormalizeFarmAlphaValue(val, addon.farmAlpha or 0.6)
                addon.farmAlpha = val
                PathmakerDB.settings.farmAlpha = val
                if addon.isFarmMode and addon.MapFrame and addon.MapFrame.ApplyFarmAlpha then
                    val = addon.MapFrame:ApplyFarmAlpha(PathmakerDB.settings, true) or val
                elseif addon.isFarmMode and Minimap then
                    if Minimap.SetIgnoreParentAlpha then Minimap:SetIgnoreParentAlpha(true) end
                    Minimap:SetAlpha(val)
                    if addon.MapFrame and addon.MapFrame.farmFrame then
                        addon.MapFrame.farmFrame:SetAlpha(1)
                        local alphaHost = addon.MapFrame.farmFrame.pmMinimapAlphaHost
                        if alphaHost then alphaHost:SetAlpha(1) end
                    end
                elseif addon.MapFrame and addon.MapFrame.UpdateFarmVisuals then
                    addon.MapFrame:UpdateFarmVisuals(PathmakerDB.settings)
                end
                if addon.MapFrame and addon.MapFrame.tacticalFarmAlphaSlider then
                    addon.MapFrame.tacticalFarmAlphaSlider:SetValue(val)
                end
            end,
        })
        addon.Options.farmAlphaSlider = farmAlphaSlider
        addon.Options.farmAlphaLabelVal = farmAlphaVal
        local activeRouteAlphaLabel, activeRouteAlphaSlider, activeRouteAlphaVal = CreateSliderSettingRow(GeneralPanel, {
            y = farmTop + 190, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Active Route Opacity", min = 0, max = 1,
            current = settings.activeRouteAlpha, displayScale = 100, unit = "%",
            getValue = function() return EnsureOptionsSettings().activeRouteAlpha end,
            callback = function(val)
                PathmakerDB.settings.activeRouteAlpha = val
                if addon.MapFrame and addon.MapFrame.UpdateFarmRoute then addon.MapFrame:UpdateFarmRoute(PathmakerDB.settings) end
                if addon.UI and addon.UI.RefreshRendering then addon.UI:RefreshRendering() end
            end,
        })
        addon.Options.activeRouteAlphaSlider = activeRouteAlphaSlider
        addon.Options.activeRouteAlphaLabelVal = activeRouteAlphaVal
        local circleSizeLabel, circleSizeSlider, circleSizeVal = CreateSliderSettingRow(GeneralPanel, {
            y = farmTop, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Circle Max Range", min = 160, max = 800,
            current = settings.farmCircleSize, unit = "px", roundStored = true,
            getValue = function() return EnsureOptionsSettings().farmCircleSize end,
            callback = function(val)
                PathmakerDB.settings.farmCircleSize = val
                if addon.MapFrame and addon.MapFrame.UpdateFarmVisuals then addon.MapFrame:UpdateFarmVisuals(PathmakerDB.settings) end
            end,
        })
        addon.Options.farmCircleSizeSlider = circleSizeSlider
        addon.Options.farmCircleSizeLabelVal = circleSizeVal
        local circleAlphaLabel, circleAlphaSlider, circleAlphaVal = CreateSliderSettingRow(GeneralPanel, {
            y = farmTop + 66, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Circle Opacity", min = 0, max = 1,
            current = settings.farmCircleAlpha, displayScale = 100, unit = "%",
            getValue = function() return EnsureOptionsSettings().farmCircleAlpha end,
            callback = function(val)
                PathmakerDB.settings.farmCircleAlpha = val
                if addon.MapFrame then
                    if addon.isFarmMode and addon.MapFrame.ApplyFarmCircleAlpha then
                        addon.MapFrame:ApplyFarmCircleAlpha(PathmakerDB.settings)
                    elseif addon.MapFrame.UpdateFarmVisuals then
                        addon.MapFrame:UpdateFarmVisuals(PathmakerDB.settings)
                    end
                end
            end,
        })
        addon.Options.farmCircleAlphaSlider = circleAlphaSlider
        addon.Options.farmCircleAlphaLabelVal = circleAlphaVal
        local markerSizeLabel, markerSizeSlider, markerSizeVal = CreateSliderSettingRow(GeneralPanel, {
            y = farmTop + 248, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Player Marker Size", min = 5, max = 80,
            current = settings.farmPlayerMarkerSize, unit = "px", roundStored = true,
            getValue = function() return EnsureOptionsSettings().farmPlayerMarkerSize end,
            callback = function(val)
                PathmakerDB.settings.farmPlayerMarkerSize = val
                if addon.MapFrame then
                    if addon.isFarmMode and addon.MapFrame.ApplyFarmMarkerSize then
                        addon.MapFrame:ApplyFarmMarkerSize(PathmakerDB.settings)
                    elseif addon.MapFrame.UpdateFarmVisuals then
                        addon.MapFrame:UpdateFarmVisuals(PathmakerDB.settings)
                    end
                end
            end,
        })
        addon.Options.farmMarkerSizeSlider = markerSizeSlider
        addon.Options.farmMarkerSizeLabelVal = markerSizeVal
        local btnFarmMarkerStyle = CreateCompactOptionButton(GeneralPanel, "Marker: Nav Arrow", 160, CONTENT_LEFT_PADDING, farmTop + 306)
        btnFarmMarkerStyle:SetScript("OnClick", function()
            PathmakerDB.settings.farmPlayerMarkerStyle = GetNextFarmMarkerStyle(PathmakerDB.settings.farmPlayerMarkerStyle or "ARROW_HEAD")
            addon.Options:RefreshSettingsUI()
            if addon.MapFrame and addon.MapFrame.UpdateFarmVisuals then addon.MapFrame:UpdateFarmVisuals(PathmakerDB.settings) end
        end)
        addon.Options.farmMarkerStyleBtn = btnFarmMarkerStyle
        CreateCheckboxGrid({
            { "Player Marker", "farmShowPlayerDot" }, { "Compass", "farmShowCompass" },
            { "Mouse Tooltip", "farmShowTooltipHover" }, { "Coordinates", "farmShowCoords" },
            { "Outside Circle", "farmAllowRoutesBeyondCircle" }, { "Rotate Farm Mode", "farmRotateMinimap" },
        }, 2, farmTop, CONTENT_LEFT_PADDING + 274, 278, 12)
        cursor = farmTop + 346 + SECTION_GAP

        CreateSectionHeader(GeneralPanel, "Navigation Arrow", cursor)
        cursor = cursor + SECTION_GAP
        local navigationTop = cursor
        local function ApplyNavigationArrowSetting(key, value)
            PathmakerDB.settings[key] = value
            if addon.Navigation and addon.Navigation.ApplySettings then addon.Navigation:ApplySettings() end
        end

        -- Match Farm Mode: controls on the left, related toggles in a clean
        -- right-side column instead of placing the toggles below the section.
        CreateCheckboxGrid({
            { "Colorless on active route", "navArrowColorless" },
            { "Arrow Locked", "navArrowLocked" },
            { "Arrow Click Through", "navArrowClickThrough" },
        }, 1, navigationTop, CONTENT_LEFT_PADDING + 274, 278, 12)

        local arrowWidthLabel, arrowWidthSlider, arrowWidthVal = CreateSliderSettingRow(GeneralPanel, {
            y = cursor, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Arrow Width", min = 20, max = 120,
            current = settings.navArrowWidth, unit = "px", roundStored = true,
            getValue = function() return EnsureOptionsSettings().navArrowWidth end,
            callback = function(val) ApplyNavigationArrowSetting("navArrowWidth", val) end,
        })
        addon.Options.navArrowWidthSlider = arrowWidthSlider
        addon.Options.navArrowWidthLabelVal = arrowWidthVal
        cursor = cursor + STACKED_SLIDER_ROW_STEP

        local arrowLengthLabel, arrowLengthSlider, arrowLengthVal = CreateSliderSettingRow(GeneralPanel, {
            y = cursor, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Arrow Length", min = 40, max = 220,
            current = settings.navArrowLength, unit = "px", roundStored = true,
            getValue = function() return EnsureOptionsSettings().navArrowLength end,
            callback = function(val) ApplyNavigationArrowSetting("navArrowLength", val) end,
        })
        addon.Options.navArrowLengthSlider = arrowLengthSlider
        addon.Options.navArrowLengthLabelVal = arrowLengthVal
        cursor = cursor + STACKED_SLIDER_ROW_STEP

        local arrowTransformLabel, arrowTransformSlider, arrowTransformVal = CreateSliderSettingRow(GeneralPanel, {
            y = cursor, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "3D Transformation", min = 0, max = 1,
            current = settings.navArrow3DTransformation, displayScale = 100, unit = "%",
            getValue = function() return EnsureOptionsSettings().navArrow3DTransformation end,
            callback = function(val) ApplyNavigationArrowSetting("navArrow3DTransformation", val) end,
        })
        addon.Options.navArrow3DTransformationSlider = arrowTransformSlider
        addon.Options.navArrow3DTransformationLabelVal = arrowTransformVal
        cursor = cursor + STACKED_SLIDER_ROW_STEP

        local arrowThicknessLabel, arrowThicknessSlider, arrowThicknessVal = CreateSliderSettingRow(GeneralPanel, {
            y = cursor, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "3D Thickness", min = 0, max = 20,
            current = settings.navArrow3DThickness, unit = "px", roundStored = true,
            getValue = function() return EnsureOptionsSettings().navArrow3DThickness end,
            callback = function(val) ApplyNavigationArrowSetting("navArrow3DThickness", val) end,
        })
        addon.Options.navArrow3DThicknessSlider = arrowThicknessSlider
        addon.Options.navArrow3DThicknessLabel = arrowThicknessLabel
        addon.Options.navArrow3DThicknessLabelVal = arrowThicknessVal
        cursor = cursor + STACKED_SLIDER_ROW_STEP

        local arrowScaleLabel, arrowScaleSlider, arrowScaleVal = CreateSliderSettingRow(GeneralPanel, {
            y = cursor, x = CONTENT_LEFT_PADDING, sliderWidth = 250, stacked = true,
            label = "Overall Size", min = 0.5, max = 2,
            current = settings.navArrowScale, displayScale = 100, unit = "%",
            getValue = function() return EnsureOptionsSettings().navArrowScale end,
            callback = function(val) ApplyNavigationArrowSetting("navArrowScale", val) end,
        })
        addon.Options.navArrowScaleSlider = arrowScaleSlider
        addon.Options.navArrowScaleLabelVal = arrowScaleVal
        cursor = cursor + STACKED_SLIDER_ROW_STEP

        local btnArrowStyle = CreateCompactOptionButton(GeneralPanel, "Style: 3D", 125, CONTENT_LEFT_PADDING, cursor)
        btnArrowStyle:SetScript("OnClick", function()
            local s = EnsureOptionsSettings()
            s.navArrowStyle = GetNextNavArrowStyle(s.navArrowStyle)
            btnArrowStyle.text:SetText(GetNavArrowStyleLabel(s.navArrowStyle))
            if addon.Navigation and addon.Navigation.ApplySettings then addon.Navigation:ApplySettings() end
            addon.Options:RefreshSettingsUI()
        end)
        addon.Options.navArrowStyleBtn = btnArrowStyle

        local btnArrowDesign = CreateCompactOptionButton(GeneralPanel, "Design: Runeblade", 160, CONTENT_LEFT_PADDING + 137, cursor)
        btnArrowDesign:SetScript("OnClick", function()
            local s = EnsureOptionsSettings()
            s.navArrowDesign = GetNextNavArrowDesign(s.navArrowDesign)
            btnArrowDesign.text:SetText(GetNavArrowDesignLabel(s.navArrowDesign))
            if addon.Navigation and addon.Navigation.ApplySettings then addon.Navigation:ApplySettings() end
        end)
        addon.Options.navArrowDesignBtn = btnArrowDesign
        cursor = cursor + ROW_HEIGHT + ROW_GAP + CONTENT_BOTTOM_PADDING

        GeneralPanel:SetHeight(math.max(GeneralScrollFrame:GetHeight(), cursor))
        local maxScroll = math.max(0, GeneralPanel:GetHeight() - GeneralScrollFrame:GetHeight())
        GeneralScrollSlider:SetMinMaxValues(0, maxScroll)
        GeneralScrollSlider:SetValue(math.max(0, math.min(maxScroll, GeneralScrollSlider:GetValue() or 0)))
        if GeneralScrollSlider.ApplyScroll then GeneralScrollSlider:ApplyScroll() end
        GeneralScrollFrame:SetScript("OnShow", function()
            addon.Options:RefreshSettingsUI()
            local maximum = math.max(0, GeneralPanel:GetHeight() - GeneralScrollFrame:GetHeight())
            GeneralScrollSlider:SetMinMaxValues(0, maximum)
            GeneralScrollSlider:SetValue(math.max(0, math.min(maximum, GeneralScrollSlider:GetValue() or 0)))
            if GeneralScrollSlider.ApplyScroll then GeneralScrollSlider:ApplyScroll() end
        end)
    end

    -- ============================================================================
    -- NODE PANEL (ACTION BAR & LIST)
    -- ============================================================================
    local searchBox = CreateFrame("EditBox", "PathMakerNodeSearchBox", NodePanel, "SearchBoxTemplate")
    searchBox:SetSize(140, 20)
    searchBox:SetPoint("TOPLEFT", 16, -12)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        if panel.RefreshNodeList then panel.RefreshNodeList() end
    end)

    local selectAllBtn = CreateActionBtn(NodePanel, "Select All", 80, 24, "green")
    selectAllBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    
    local selectNoneBtn = CreateActionBtn(NodePanel, "Select None", 80, 24, "red")
    selectNoneBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 5, 0)

    -- SEPARATOR LINE
    local sepLine = NodePanel:CreateTexture(nil, "ARTWORK")
    sepLine:SetColorTexture(0.3, 0.3, 0.3, 0.5)
    sepLine:SetHeight(1)
    sepLine:SetPoint("TOPLEFT", 10, -42)
    sepLine:SetPoint("TOPRIGHT", -10, -42)

    -- CHECKBOX ACTIONS (Updated to force live heatmap updates)
    selectNoneBtn:SetScript("OnClick", function()
        for _, n in ipairs(currentNodesShown) do 
            nodeCheckboxStates[n] = false 
            if PathmakerDB then
                PathmakerDB.PMNodes_Filter = PathmakerDB.PMNodes_Filter or {}
                PathmakerDB.PMNodes_Filter[n] = false
            end
        end
        panel.RefreshNodeList()
        if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then
            addon.Heatmap:ForceUpdate()
        end
    end)

    selectAllBtn:SetScript("OnClick", function()
        for _, n in ipairs(currentNodesShown) do 
            nodeCheckboxStates[n] = true 
            if PathmakerDB then
                PathmakerDB.PMNodes_Filter = PathmakerDB.PMNodes_Filter or {}
                PathmakerDB.PMNodes_Filter[n] = true
            end
        end
        panel.RefreshNodeList()
        if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then
            addon.Heatmap:ForceUpdate()
        end
    end)

    -- SCROLLING NODE BOX: keep long Retail resource lists clipped above the
    -- import/wipe action row instead of letting checkboxes escape the panel.
    local nodeListBox = CreateFrame("Frame", nil, NodePanel, "BackdropTemplate")
    nodeListBox:SetPoint("TOPLEFT", 10, -50)
    nodeListBox:SetPoint("BOTTOMRIGHT", -10, 46)
    nodeListBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    nodeListBox:SetBackdropColor(0.025, 0.025, 0.025, 0.92)
    nodeListBox:SetBackdropBorderColor(0.28, 0.21, 0.07, 1)

    local nodeScrollFrame, listContainer, nodeScrollSlider = CreateDarkScrollArea(nodeListBox, 594, 326, "minimal")
    nodeScrollFrame:SetPoint("TOPLEFT", 6, -6)
    listContainer:SetSize(594, 326)

    panel.RefreshNodeList = function()
        for _, cb in pairs(activeCheckboxes) do cb:Hide() end
        wipe(currentNodesShown)
        
        local searchText = (PathMakerNodeSearchBox:GetText() or ""):lower()
        if searchText == "search" then searchText = "" end 
        local PMNodes = _G.PathMakerNodes or _G.PathMaker_Nodes
        local function IsNodeNameVisible(nodeName)
            return not PMNodes or type(PMNodes.IsNodeVisible) ~= "function" or PMNodes:IsNodeVisible(nodeName)
        end

        for expName, expNodes in pairs(SPECIFIC_NODES) do
            local expansionAvailable = not addon.Compat
                or not addon.Compat.IsExpansionAvailable
                or addon.Compat:IsExpansionAvailable(expName)
            if expansionAvailable and expNodes[currentTab] then
                for _, n in ipairs(expNodes[currentTab]) do
                    if IsNodeNameVisible(n) and (searchText == "" or n:lower():find(searchText, 1, true)) then
                        local alreadyAdded = false
                        for _, v in ipairs(currentNodesShown) do 
                            if v == n then alreadyAdded = true break end 
                        end
                        if not alreadyAdded then table.insert(currentNodesShown, n) end
                    end
                end
            end
        end

        -- PathMaker_Nodes exposes its complete standalone registry before any
        -- points are imported, so Retail resources can be selected immediately.
        if PMNodes and type(PMNodes.GetNodeNames) == "function" then
            for _, nodeName in ipairs(PMNodes:GetNodeNames(currentTab)) do
                if IsNodeNameVisible(nodeName) and (searchText == "" or nodeName:lower():find(searchText, 1, true)) then
                    local alreadyAdded = false
                    for _, shownName in ipairs(currentNodesShown) do
                        if shownName == nodeName then alreadyAdded = true break end
                    end
                    if not alreadyAdded then table.insert(currentNodesShown, nodeName) end
                end
            end
        end

        -- Include expansion nodes learned by the Retail recorder, even when
        -- their names did not exist when this addon version was packaged.
        if PathmakerDB and PathmakerDB.nodes then
            for mapID, mapNodes in pairs(PathmakerDB.nodes) do
                if IsMapVisibleForExpansion(mapID) then
                    for _, node in ipairs(mapNodes) do
                        local nodeType = (node.type == "Herbalism" or node.type == "Herb") and "Herb Gathering" or node.type
                        local nodeName = node.specificName or node.name
                        if nodeType == currentTab and nodeName and IsNodeNameVisible(nodeName) and (searchText == "" or nodeName:lower():find(searchText, 1, true)) then
                            local alreadyAdded = false
                            for _, shownName in ipairs(currentNodesShown) do
                                if shownName == nodeName then alreadyAdded = true break end
                            end
                            if not alreadyAdded then table.insert(currentNodesShown, nodeName) end
                        end
                    end
                end
            end
        end

        table.sort(currentNodesShown)

        local columnWidth = 195
        local rowHeight = 28
        local numItems = #currentNodesShown
        local numRows = math.max(1, math.ceil(numItems / 3))
        local contentHeight = math.max(nodeScrollFrame:GetHeight(), (numRows * rowHeight) + 20)
        listContainer:SetHeight(contentHeight)
        local maxScroll = math.max(0, contentHeight - nodeScrollFrame:GetHeight())
        nodeScrollSlider:SetMinMaxValues(0, maxScroll)
        if nodeScrollSlider:GetValue() > maxScroll then nodeScrollSlider:SetValue(maxScroll) end
        if nodeScrollSlider.ApplyScroll then nodeScrollSlider:ApplyScroll() end

        for i, nodeName in ipairs(currentNodesShown) do
            local cb = activeCheckboxes[nodeName]
            if not cb then
                cb = CreateFrame("CheckButton", nil, listContainer, "UICheckButtonTemplate")
                cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                cb.text:SetPoint("LEFT", cb, "RIGHT", 0, 0) 
                cb.text:SetWidth(columnWidth - 38)
                cb.text:SetJustifyH("LEFT")
                cb.text:SetWordWrap(false)
                if cb.text.SetMaxLines then cb.text:SetMaxLines(1) end

                cb:SetHitRectInsets(0, -(columnWidth - 38), 0, 0)
                cb:SetScript("OnEnter", function(self)
                    if not self.pmNodeNameTruncated then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.pmFullNodeName or self.nodeName or "")
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function(self)
                    if GameTooltip and (not GameTooltip.IsOwned or GameTooltip:IsOwned(self)) then GameTooltip:Hide() end
                end)
                
                -- FIXED: Node interactions now force real-time updates directly to the map
                cb:SetScript("OnClick", function(self) 
                    local isChecked = self:GetChecked()
                    local clickedNodeName = self.nodeName
                    nodeCheckboxStates[clickedNodeName] = isChecked
                    if PathmakerDB then
                        PathmakerDB.PMNodes_Filter = PathmakerDB.PMNodes_Filter or {}
                        PathmakerDB.PMNodes_Filter[clickedNodeName] = isChecked
                    end
                    if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then
                        addon.Heatmap:ForceUpdate()
                    end
                end)
                activeCheckboxes[nodeName] = cb
            end
            
            if PathmakerDB and PathmakerDB.PMNodes_Filter then
                if PathmakerDB.PMNodes_Filter[nodeName] == nil then
                    PathmakerDB.PMNodes_Filter[nodeName] = addon.Compat and addon.Compat.isRetail or false
                end
                nodeCheckboxStates[nodeName] = PathmakerDB.PMNodes_Filter[nodeName]
            elseif nodeCheckboxStates[nodeName] == nil then
                nodeCheckboxStates[nodeName] = false 
            end

            cb:SetChecked(nodeCheckboxStates[nodeName])

            cb.nodeName = nodeName
            local fullNodeName = FormatNodeName(nodeName)
            local displayName, wasTruncated = TruncateNodeDisplayName(fullNodeName, 20)
            if addon.NODE_ICONS and addon.NODE_ICONS[nodeName] then
                displayName = string.format("|T%s:18:18:0:0|t %s", addon.NODE_ICONS[nodeName], displayName)
            end
            cb.text:SetText(displayName)
            cb.pmFullNodeName = fullNodeName
            cb.pmNodeNameTruncated = wasTruncated
            
            -- Calculate Vertical Column Position
            local col = math.floor((i - 1) / numRows)
            local row = (i - 1) % numRows
            
            local calcX = 10 + (col * columnWidth)
            local calcY = -10 - (row * rowHeight)
            
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", calcX, calcY)
            cb:Show()
        end
    end

    local wipeBtn = CreateActionBtn(NodePanel, "Wipe Nodes Data", 140, 24, "red")
    wipeBtn:SetPoint("BOTTOMRIGHT", -10, 10)

    local wipeSelectedBtn = CreateActionBtn(NodePanel, "Wipe Selected Node Data", 160, 24, "red")
    wipeSelectedBtn:SetPoint("RIGHT", wipeBtn, "LEFT", -10, 0)

    local importBtnNode = CreateActionBtn(NodePanel, "Import Selected Nodes", 160, 24, "green")
    importBtnNode:SetPoint("RIGHT", wipeSelectedBtn, "LEFT", -10, 0)

    importBtnNode:SetScript("OnClick", function()
        local hasSelectedNodes = false
        for nodeName, isChecked in pairs(nodeCheckboxStates) do
            if isChecked then
                hasSelectedNodes = true
                break
            end
        end

        if not hasSelectedNodes then
            local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
            if not hideMsg then
                print("|cFFFF4444PathMaker:|r Please select at least one node in the list to import.")
            end
            return
        end

        addon.Options:ProcessDatasets("IMPORT", "All", nodeCheckboxStates)
    end)

    wipeSelectedBtn:SetScript("OnClick", function()
        local hasSelectedNodes = false
        for nodeName, isChecked in pairs(nodeCheckboxStates) do
            if isChecked then
                hasSelectedNodes = true
                break
            end
        end

        if not hasSelectedNodes then
            local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgError
            if not hideMsg then
                print("|cFFFF4444PathMaker:|r Please select at least one node in the list to wipe.")
            end
            return
        end

        addon.Options:ProcessDatasets("WIPE_SELECTED", "All", nodeCheckboxStates)
        for nodeName in pairs(nodeCheckboxStates) do
            nodeCheckboxStates[nodeName] = false
        end
        if panel.RefreshNodeList then panel.RefreshNodeList() end
        if addon.Heatmap and type(addon.Heatmap.ForceUpdate) == "function" then
            addon.Heatmap:ForceUpdate()
        end
    end)

    wipeBtn:SetScript("OnClick", function()
        addon.Options:ProcessDatasets("WIPE")
    end)

    -- Keep the shared Blizzard layout intact: capture and restore only the
    -- geometry that the standalone host changes. Fonts and buttons stay fixed.
    do
        local originals = {}
        local function Remember(widget)
            if originals[widget] then return originals[widget] end
            local state = {width = widget:GetWidth(), height = widget:GetHeight(), points = {}}
            for i = 1, widget:GetNumPoints() do state.points[i] = {widget:GetPoint(i)} end
            originals[widget] = state
            return state
        end
        local function ScrollLayout(scroll, child, slider, width, height)
            Remember(scroll); Remember(child); Remember(slider)
            scroll:SetSize(width, height)
            child:SetWidth(width)
            slider:SetHeight(height)
            slider:SetMinMaxValues(0, math.max(0, child:GetHeight() - height))
            slider:SetValue(math.min(slider:GetValue(), math.max(0, child:GetHeight() - height)))
        end
        local function RefreshLayout()
            if not panel.standaloneLayout then return end
            local width, height = filterBoxInner:GetSize()
            ScrollLayout(GeneralScrollFrame, GeneralPanel, GeneralScrollSlider, width - 32, height - 4)
            ScrollLayout(routeScrollFrame, routeScrollChild, routeScrollSlider, width - 32, height - 128)
            ScrollLayout(drawScrollFrame, drawScrollChild, drawScrollSlider, width - 32, height - 154)
            ScrollLayout(nodeScrollFrame, listContainer, nodeScrollSlider, width - 42, height - 108)
            Remember(zoneDrop)
            zoneDrop:SetWidth(width - 290)
            panel.LayoutStandaloneDrawMode("resize", Remember, ScrollLayout, width, height)
            for _, button in pairs(routeButtons) do
                Remember(button); Remember(button.nameText)
                button:SetWidth(width - 45)
                button.nameText:SetWidth(width - 250)
            end

        end
        function panel:SetStandaloneLayout(enabled)
            if self.standaloneLayout == enabled then return end
            if enabled then
                Remember(filterBox)
                panel.LayoutStandaloneDrawMode("capture", Remember)
                title:Hide()
                filterBox:ClearAllPoints()
                filterBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -33)
                filterBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
                self.standaloneLayout = true
                RefreshLayout()
            else
                self.standaloneLayout = false
                title:Show()
                for widget, state in pairs(originals) do
                    widget:ClearAllPoints()
                    widget:SetSize(state.width, state.height)
                    for _, point in ipairs(state.points) do widget:SetPoint(unpack(point)) end
                end
                wipe(originals)
                panel.LayoutStandaloneDrawMode("reset")
                UpdateTabVisuals()
            end
        end
        filterBoxInner:HookScript("OnSizeChanged", RefreshLayout)
    end

    if addon.Compat then addon.Compat:RegisterOptionsPanel(panel) end

    addon.Options.panel = panel
    addon.Options.UpdateTabVisuals = UpdateTabVisuals
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    for nodeName, itemID in pairs(addon.NODE_ITEM_IDS) do
        local icon = NODE_ICON_OVERRIDES[nodeName]
            or (addon.Compat and addon.Compat:GetItemIcon(itemID))
        if icon then
            addon.NODE_ICONS[nodeName] = icon
        end
    end
    -- Item 10620 is shared with Small Thorium and its item artwork used to
    -- overwrite the node artwork at PLAYER_LOGIN. Re-apply the ooze-covered
    -- Rich Thorium registration after all item icons have been resolved so the
    -- settings/import list cannot switch it back to the old icon.
    addon.NODE_ICONS["Rich Thorium Vein"] = addon.NODE_ICONS["Ooze Covered Rich Thorium Vein"]
        or RICH_THORIUM_FALLBACK_ICON
    CreateOptionsPanel()
    
    -- Ensure the panel matches saved variables at login
    addon.Options:RefreshSettingsUI()
end)
