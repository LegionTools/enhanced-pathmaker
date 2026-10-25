-- Opt-in development utility. Never runs until /pmcapture is entered.
if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

local frame, canvas, heading, loading
local textures, queue, run, pending = {}, {}, nil, nil
local index, elapsed, readyFor, waitFor = 0, 0, 0, 0
local previousFormat, previousQuality
local function say(message) print("PathMaker map capture: " .. message) end

local function stop(reason)
    if not run then return end
    run.status = reason
    run.finished = date("%Y-%m-%d %H:%M:%S")
    run = nil
    pending = nil
    frame:Hide()
    if previousFormat then SetCVar("screenshotFormat", previousFormat) end
    if previousQuality then SetCVar("screenshotQuality", previousQuality) end
    say(reason .. ". Screenshots are in _retail_/Screenshots. /reload to save the capture manifest.")
end

local function initialize()
    if frame then return end
    frame = CreateFrame("Frame", "PathMakerRetailCaptureFrame", UIParent)
    frame:Hide()
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(1000)
    frame:SetAllPoints(UIParent)
    frame:EnableMouse(true)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 1)
    canvas = CreateFrame("Frame", nil, frame)
    canvas:SetPoint("CENTER")
    heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOP", 0, -12)
    local help = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    help:SetPoint("BOTTOM", 0, 16)
    help:SetText("Retail map reference capture - Escape to stop. Do not take other screenshots during this pass.")
    loading = CreateFromMixins(TextureLoadingGroupMixin)
    loading:Reset()
    table.insert(UISpecialFrames, "PathMakerRetailCaptureFrame")
    frame:SetScript("OnHide", function() if run then stop("Stopped") end end)
    frame:RegisterEvent("SCREENSHOT_SUCCEEDED")
    frame:RegisterEvent("SCREENSHOT_FAILED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:SetScript("OnEvent", function(_, event)
        if not run then return end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_LOGOUT" or event == "DISPLAY_SIZE_CHANGED" then
            stop("Stopped: " .. event)
        elseif pending then
            if event == "SCREENSHOT_FAILED" then stop("Screenshot failed"); return end
            pending.completed = date("%m%d%y_%H%M%S")
            table.insert(run.captures, pending)
            pending = nil
            waitFor = 1.5 -- Avoid filename collisions and screenshot notification overlap.
        end
    end)
end

local function showNext()
    index = index + 1
    if index > #queue then stop("Complete for discovered maps in the current phase"); return end
    local info = queue[index]
    for _, texture in ipairs(textures) do texture:Hide() end
    loading:Reset()
    local layers = C_Map.GetMapArtLayers(info.mapID)
    local layer = layers and layers[1]
    local files = layer and C_Map.GetMapArtLayerTextures(info.mapID, 1)
    if not layer or not files or #files == 0 then
        table.insert(run.skipped, { mapID = info.mapID, name = info.name, reason = "No base artwork" })
        waitFor = .01
        return
    end
    local width, height = layer.layerWidth, layer.layerHeight
    local tileW, tileH = layer.tileWidth, layer.tileHeight
    local scale = math.min((frame:GetWidth() - 40) / width, (frame:GetHeight() - 100) / height)
    canvas:SetSize(width * scale, height * scale)
    local columns, rows = math.ceil(width / tileW), math.ceil(height / tileH)
    for row = 0, rows - 1 do
        for col = 0, columns - 1 do
            local n = row * columns + col + 1
            if not files[n] then stop("Missing map tile for " .. info.mapID); return end
            local texture = textures[n]
            if not texture then texture = canvas:CreateTexture(nil, "ARTWORK"); textures[n] = texture end
            -- Preserve the whole map rectangle, trimming only tile padding.
            local visibleW = math.min(tileW, width - col * tileW)
            local visibleH = math.min(tileH, height - row * tileH)
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * tileW * scale, -row * tileH * scale)
            texture:SetSize(visibleW * scale, visibleH * scale)
            texture:SetTexture(files[n])
            texture:SetTexCoord(0, visibleW / tileW, 0, visibleH / tileH)
            texture:Show()
            loading:AddTexture(texture)
        end
    end
    run.current = { mapID = info.mapID, name = info.name, artID = C_Map.GetMapArtID(info.mapID),
        layerIndex = 1, layerWidth = width, layerHeight = height, tileFileIDs = files }
    heading:SetText(string.format("%d / %d  |  %s  |  Retail map %d / art %s", index, #queue,
        info.name, info.mapID, tostring(run.current.artID)))
    elapsed, readyFor = 0, 0
end

local function update(_, dt)
    if not run then return end
    if waitFor > 0 then
        waitFor = waitFor - dt
        if waitFor <= 0 then showNext() end
        return
    end
    elapsed = elapsed + dt
    if pending then
        if elapsed > 20 then stop("Screenshot confirmation timed out") end
        return
    end
    if not loading:IsFullyLoaded() then
        readyFor = 0
        if elapsed > 30 then stop("Map textures did not finish loading") end
        return
    end
    readyFor = readyFor + dt
    if readyFor < 2 then return end
    local physicalW, physicalH = GetPhysicalScreenSize()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    local record = run.current
    record.screenWidth, record.screenHeight = physicalW, physicalH
    record.left = canvas:GetLeft() / screenW * physicalW
    record.top = (screenH - canvas:GetTop()) / screenH * physicalH
    record.width = canvas:GetWidth() / screenW * physicalW
    record.height = canvas:GetHeight() / screenH * physicalH
    record.requested = date("%m%d%y_%H%M%S")
    record.sequence = index
    pending = record
    elapsed = 0
    Screenshot()
end

SLASH_PATHMAKERRETAILCAPTURE1 = "/pmcapture"
SlashCmdList.PATHMAKERRETAILCAPTURE = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "stop" then stop("Stopped"); return end
    if run then say("Already running. Escape or /pmcapture stop cancels."); return end
    if InCombatLockdown() then say("Leave combat and stand somewhere safe first."); return end
    if message ~= "start" and message ~= "list" and not tonumber(message) then
        say("/pmcapture list, /pmcapture start, /pmcapture <mapID>, or /pmcapture stop."); return
    end
    if not C_Map or not C_Map.GetMapArtLayers or not TextureLoadingGroupMixin then
        say("Required retail map APIs are unavailable."); return
    end
    queue = {}
    local seen = {}
    local function add(info)
        if info and not seen[info.mapID] then
            seen[info.mapID] = true
            table.insert(queue, { mapID = info.mapID, name = info.name })
        end
    end
    local single = tonumber(message)
    if single then
        if single < 1 or single % 1 ~= 0 then say("Map ID must be a positive integer."); return end
        add(C_Map.GetMapInfo(single))
    else
        -- Runtime hierarchy plus orphan/alternate zone records. The scan ceiling is
        -- recorded explicitly; it is not a promise to enumerate every future map.
        for _, info in ipairs(C_Map.GetMapChildrenInfo(946, Enum.UIMapType.Zone, true) or {}) do add(info) end
        for mapID = 1, 10000 do
            local info = C_Map.GetMapInfo(mapID)
            if info and info.mapType == Enum.UIMapType.Zone then add(info) end
        end
    end
    table.sort(queue, function(a, b) return a.mapID < b.mapID end)
    if #queue == 0 then say("No maps found."); return end
    if message == "list" then say(#queue .. " zone records discovered; unavailable artwork will be logged separately."); return end
    initialize()
    PathmakerDB = PathmakerDB or {}
    PathmakerDB.retailMapCaptures = PathmakerDB.retailMapCaptures or {}
    local version, build, buildDate, interface = GetBuildInfo()
    run = { started = date("%Y-%m-%d %H:%M:%S"), version = version, build = build,
        buildDate = buildDate, interface = interface, locale = GetLocale(), projectID = WOW_PROJECT_ID,
        status = "Running", discoveryScanMaximum = 10000, total = #queue, captures = {}, skipped = {} }
    table.insert(PathmakerDB.retailMapCaptures, run)
    previousFormat, previousQuality = GetCVar("screenshotFormat"), GetCVar("screenshotQuality")
    SetCVar("screenshotFormat", "jpg")
    SetCVar("screenshotQuality", "10")
    index, pending, waitFor = 0, nil, 0
    frame:SetScript("OnUpdate", update)
    frame:Show()
    showNext()
end
