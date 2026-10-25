-- ============================================================================
-- PATHMAKER STANDALONE SETTINGS WINDOW
-- Hosts the same live panel used by Blizzard's AddOn Options category.
-- ============================================================================
local addonName, addon = ...
if type(addon) ~= "table" then addon = _G["PathMaker"] or _G["Pathmaker"] or {} end

addon.Settings = addon.Settings or {}

local function T(text)
    return addon.Translate and addon:Translate(text) or text
end

local SETTINGS_WIDTH = 688
local SETTINGS_HEIGHT = 625
local SETTINGS_MIN_HEIGHT = 480

local function ApplyResizeBounds(frame)
    local scale = frame:GetEffectiveScale() or 1
    local parentScale = UIParent:GetEffectiveScale() or 1
    local maxWidth = math.max(1, UIParent:GetWidth() * parentScale / scale)
    local maxHeight = math.max(1, UIParent:GetHeight() * parentScale / scale)
    local minWidth, minHeight = math.min(660, maxWidth), math.min(SETTINGS_MIN_HEIGHT, maxHeight)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else
        frame:SetMinResize(minWidth, minHeight)
        frame:SetMaxResize(maxWidth, maxHeight)
    end
    frame:SetSize(math.max(minWidth, math.min(maxWidth, frame:GetWidth())),
        math.max(minHeight, math.min(maxHeight, frame:GetHeight())))
end

local function SaveWindowSize(frame)
    if not PathmakerDB then return end
    PathmakerDB.settings = PathmakerDB.settings or {}
    PathmakerDB.settings.settingsWindowWidth = frame:GetWidth()
    PathmakerDB.settings.settingsWindowHeight = frame:GetHeight()
end

local function RoundToPhysicalPixel(value, scale)
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 1 end
    return math.floor((value * scale) + 0.5) / scale
end

local function StabilizeSettingsTexture(texture)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(true) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

local function SnapStandaloneSettingsToPixels(frame)
    if not frame or not frame.pathmakerStablePixels or frame._pathmakerPixelSnapping then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end

    frame._pathmakerPixelSnapping = true
    local scale = frame:GetEffectiveScale() or 1
    if scale <= 0 then scale = 1 end
    frame:SetSize(RoundToPhysicalPixel(frame:GetWidth(), scale), RoundToPhysicalPixel(frame:GetHeight(), scale))
    frame:ClearAllPoints()
    frame:SetPoint(
        "TOPLEFT",
        UIParent,
        "BOTTOMLEFT",
        RoundToPhysicalPixel(left, scale),
        RoundToPhysicalPixel(top, scale)
    )

    local pixel = 1 / scale
    for _, edgeInfo in pairs(frame.pathmakerPixelEdges or {}) do
        if edgeInfo.orientation == "vertical" then
            edgeInfo.texture:SetWidth(pixel)
        else
            edgeInfo.texture:SetHeight(pixel)
        end
    end
    if frame.pathmakerDivider then frame.pathmakerDivider:SetHeight(pixel) end
    frame._pathmakerPixelSnapping = false
end

local function SetMapCloseButtonEnabled(enabled)
    local button = addon.MapFrame and addon.MapFrame.btnClose
    if not button then return end

    if enabled then
        button:Enable()
    else
        button:Disable()
    end

    if button.text then
        button.text:SetTextColor(enabled and 1 or 0.3, enabled and 1 or 0.3, enabled and 1 or 0.3)
    end
end

function addon.Settings:CreateFrame()
    if self.frame then return self.frame end

    local frame = CreateFrame("Frame", "PathmakerSettings", UIParent, "BackdropTemplate")
    frame.pathmakerStablePixels = addon.Compat and addon.Compat.isRetail == true
    frame:SetSize(SETTINGS_WIDTH, SETTINGS_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetMovable(true)
    frame:SetResizable(true)
    local saved = PathmakerDB and PathmakerDB.settings or {}
    local function SavedDimension(value, fallback)
        value = tonumber(value)
        return value and value > 0 and value < math.huge and value or fallback
    end
    frame:SetSize(SavedDimension(saved.settingsWindowWidth, SETTINGS_WIDTH),
        SavedDimension(saved.settingsWindowHeight, SETTINGS_HEIGHT))
    ApplyResizeBounds(frame)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    if frame.pathmakerStablePixels then
        frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            tile = false,
        })
    else
        frame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            tile = false,
            edgeSize = 1,
        })
        frame:SetBackdropBorderColor(0.45, 0.35, 0.12, 1)
    end
    frame:SetBackdropColor(0.025, 0.025, 0.025, 0.98)

    frame.pathmakerPixelEdges = {}
    local function CreatePixelEdge(pointA, pointB, orientation)
        local edge = StabilizeSettingsTexture(frame:CreateTexture(nil, "BORDER"))
        edge:SetColorTexture(0.45, 0.35, 0.12, 1)
        edge:SetPoint(unpack(pointA))
        edge:SetPoint(unpack(pointB))
        frame.pathmakerPixelEdges[#frame.pathmakerPixelEdges + 1] = {
            texture = edge,
            orientation = orientation,
        }
        return edge
    end
    if frame.pathmakerStablePixels then
        CreatePixelEdge({"TOPLEFT", frame, "TOPLEFT"}, {"BOTTOMLEFT", frame, "BOTTOMLEFT"}, "vertical")
        CreatePixelEdge({"TOPRIGHT", frame, "TOPRIGHT"}, {"BOTTOMRIGHT", frame, "BOTTOMRIGHT"}, "vertical")
        CreatePixelEdge({"TOPLEFT", frame, "TOPLEFT"}, {"TOPRIGHT", frame, "TOPRIGHT"}, "horizontal")
        CreatePixelEdge({"BOTTOMLEFT", frame, "BOTTOMLEFT"}, {"BOTTOMRIGHT", frame, "BOTTOMRIGHT"}, "horizontal")
    end

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function()
        frame:StartMoving()
    end)
    header:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SnapStandaloneSettingsToPixels(frame)
    end)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 14, 0)
    title:SetText(T("PathMaker Settings"))
    title:SetTextColor(1, 0.82, 0)

    local close = CreateFrame("Button", nil, header, "BackdropTemplate")
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -7, 0)
    close:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=1})
    close:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    close:SetBackdropBorderColor(0.32, 0.32, 0.32, 1)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    close.text:SetPoint("CENTER")
    close.text:SetText("X")
    close:SetScript("OnEnter", function(self) self:SetBackdropColor(0.32, 0.05, 0.05, 1); self:SetBackdropBorderColor(1, 0.22, 0.22, 1); self.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self:SetBackdropColor(0.08, 0.08, 0.08, 0.95); self:SetBackdropBorderColor(0.32, 0.32, 0.32, 1); self.text:SetTextColor(1, 1, 1) end)
    close:SetScript("OnClick", function()
        addon.Settings:Hide()
    end)

    local divider = StabilizeSettingsTexture(frame:CreateTexture(nil, "ARTWORK"))
    divider:SetColorTexture(0.45, 0.35, 0.12, 0.8)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 1, -35)
    divider:SetPoint("TOPRIGHT", -1, -35)
    frame.pathmakerDivider = divider

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 6, -40)
    content:SetPoint("BOTTOMRIGHT", -6, 16)
    frame.content = content

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local function FinishResize()
        if not frame.resizing then return end
        frame.resizing = nil
        frame:StopMovingOrSizing()
        SnapStandaloneSettingsToPixels(frame)
        ApplyResizeBounds(frame)
        SaveWindowSize(frame)
    end
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        -- Fix the opposite corner before sizing, including on Classic clients
        -- where the retail pixel-snapping path does not run.
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        ApplyResizeBounds(frame)
        frame.resizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", FinishResize)

    frame:SetScript("OnHide", function()
        FinishResize()
        frame:StopMovingOrSizing()
        addon.Settings:ReleaseOptionsPanel()
        SetMapCloseButtonEnabled(true)
        if addon.MapFrame then addon.MapFrame:RefreshSettingsControls() end
    end)
    frame:SetScript("OnShow", function(self)
        ApplyResizeBounds(self)
        if addon.MapFrame then addon.MapFrame:RefreshSettingsControls() end
        SnapStandaloneSettingsToPixels(self)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if self:IsShown() then SnapStandaloneSettingsToPixels(self) end
            end)
        end
    end)
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function(self)
        ApplyResizeBounds(self)
        if self:IsShown() then SnapStandaloneSettingsToPixels(self) end
    end)

    self.frame = frame
    SnapStandaloneSettingsToPixels(frame)
    if addon.MapFrame then addon.MapFrame.settingsFrame = frame end
    if UISpecialFrames then
        local alreadyRegistered = false
        for _, frameName in ipairs(UISpecialFrames) do
            if frameName == "PathmakerSettings" then
                alreadyRegistered = true
                break
            end
        end
        if not alreadyRegistered then
            table.insert(UISpecialFrames, "PathmakerSettings")
        end
    end
    frame:Hide()
    return frame
end

function addon.Settings:AttachOptionsPanel()
    local panel = addon.Options and addon.Options.panel
    local frame = self:CreateFrame()
    if not panel or not frame then return false end

    if not self.originalParent then
        self.originalParent = panel:GetParent()
        self.originalPoints = {}
        for index = 1, panel:GetNumPoints() do
            self.originalPoints[index] = { panel:GetPoint(index) }
        end
    end

    panel:SetParent(frame.content)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", frame.content, "BOTTOMRIGHT", 0, 0)
    if panel.SetStandaloneLayout then panel:SetStandaloneLayout(true) end
    panel:Show()

    if addon.Options.UpdateTabVisuals then addon.Options.UpdateTabVisuals() end
    if addon.Options.RefreshSettingsUI then addon.Options:RefreshSettingsUI() end
    return true
end

function addon.Settings:ReleaseOptionsPanel()
    local panel = addon.Options and addon.Options.panel
    if not panel or panel:GetParent() ~= (self.frame and self.frame.content) then return end

    panel:Hide()
    if panel.SetStandaloneLayout then panel:SetStandaloneLayout(false) end
    panel:ClearAllPoints()
    panel:SetParent(self.originalParent or UIParent)
    for _, point in ipairs(self.originalPoints or {}) do
        panel:SetPoint(unpack(point))
    end
end

function addon.Settings:Show()
    if not PathmakerDB or not PathmakerDB.isEnabled then
        addon:PrintMessage("disableMsgError", "|cffff0000PathMaker:|r Enable the addon first to change settings (/pm).")
        return
    end

    if not self:AttachOptionsPanel() then
        addon:PrintMessage("disableMsgError", "|cffff0000PathMaker:|r Settings are still loading. Please try again.")
        return
    end

    self.frame:Show()
    self.frame:Raise()
    SetMapCloseButtonEnabled(false)
end

function addon.Settings:Hide()
    if self.frame then self.frame:Hide() end
end

function addon.Settings:Toggle()
    if self.frame and self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function addon.MapFrame:CreateSettingsFrame()
    return addon.Settings:CreateFrame()
end

function addon.MapFrame:RefreshSettingsUI()
    if addon.Options and addon.Options.RefreshSettingsUI then
        addon.Options:RefreshSettingsUI()
    end
end

function addon.MapFrame:ToggleSettings()
    addon.Settings:Toggle()
end
