local addonName, addon = ...
addon.Heatmap = {}

-- ----------------------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
-- ----------------------------------------------------------------------------
local MINIMAP_UPDATE_INTERVAL = 0.75
local MINIMAP_REBUILD_DISTANCE_YARDS = 24
local VISUAL_DIST_THRESHOLD = 5      
local VISUAL_SAME_NODE_GROUP_YARDS = 8
local RECORD_MERGE_DISTANCE_YARDS = 12
local DUPLICATE_MERGE_DISTANCE_YARDS = 3
local NODE_DATABASE_VERSION = 2
local CIRCLE_RANGE_YARDS = 145       
local RING_SIZE = 10                
local ICON_SCALE = 1              
local NODE_ICON_SIZE = RING_SIZE
local WORLD_NODE_ICON_SIZE = 13
local WORLD_NODE_HITBOX_SIZE = 16
local OVERLAP_OFFSET_RADIUS = 8
local OVERLAP_CELL_SIZE = VISUAL_DIST_THRESHOLD
local smoothedMinimapMapID = nil
local smoothedMinimapPlayerX = nil
local smoothedMinimapPlayerY = nil
local smoothedMinimapFacing = nil
local smoothedMinimapFrameTime = nil
local smoothedMinimapContext = nil

-- Indoor subzone contexts used to split nodes recorded on the same UiMapID.
-- That made ordinary area/cave transitions behave like a visibility boundary.
-- Nodes now belong only to their UiMapID; old mapContext metadata is ignored.
local function GetPlayerNodeContext(mapID)
    return nil
end

local function SnapOverlayPixel(value, frame)
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

local function StableNodeKey(node, mapID)
    local name = node and (node.specificName or node.name or node.id or node.type) or "node"
    local x = math.floor(((node and node.x) or 0) * 100000 + 0.5)
    local y = math.floor(((node and node.y) or 0) * 100000 + 0.5)
    return tostring(mapID or "") .. ":" .. tostring(name) .. ":" .. tostring(x) .. ":" .. tostring(y)
end

local function StableHash(text)
    local hash = 0
    text = tostring(text or "")
    for i = 1, string.len(text) do
        hash = (hash * 33 + string.byte(text, i)) % 9973
    end
    return hash
end

local function GetStableOverlapOffset(node, mapID, overlapCount)
    if not overlapCount or overlapCount <= 0 then return 0, 0 end
    local hash = StableHash(StableNodeKey(node, mapID))
    local angle = ((hash % 360) / 180) * math.pi
    local ring = 1 + (math.floor(hash / 360) % 2)
    local radius = OVERLAP_OFFSET_RADIUS * ring
    return math.cos(angle) * radius, math.sin(angle) * radius
end

local function CountNearbyDifferentNodes(points, px, py, normName)
    local overlapCount = 0
    for _, point in ipairs(points) do
        local d = math.sqrt((px - point.originalX)^2 + (py - point.originalY)^2)
        if d < VISUAL_DIST_THRESHOLD and point.name ~= normName then
            overlapCount = overlapCount + 1
        end
    end
    return overlapCount
end

local function IsCloseNodeFrame(frame, distYards)
    local hysteresis = 3
    if frame and frame.pmMinimapWasCloseNode then
        return distYards < (CIRCLE_RANGE_YARDS + hysteresis)
    end
    return distYards < CIRCLE_RANGE_YARDS
end

local function SmoothMinimapValue(current, target, elapsed, speed)
    if current == nil then return target end
    local factor = 1 - math.exp(-(speed or 18) * math.max(elapsed or 0, 0))
    return current + ((target - current) * factor)
end

local function SmoothMinimapAngle(current, target, elapsed, speed)
    if current == nil then return target end
    local delta = math.atan2(math.sin(target - current), math.cos(target - current))
    local factor = 1 - math.exp(-(speed or 22) * math.max(elapsed or 0, 0))
    return current + (delta * factor)
end

local function GetSmoothedMinimapRenderState(mapID, rawPos, elapsed)
    if not mapID or not rawPos then return rawPos, GetPlayerFacing and GetPlayerFacing() or 0 end
    local context = GetPlayerNodeContext(mapID)
    if addon.Compat and addon.Compat.isRetail and not context then
        -- Retail's outdoor position already tracks the native minimap closely.
        -- Keep smoothing for caves only, where map samples can be noisy.
        smoothedMinimapMapID = nil
        smoothedMinimapContext = nil
        return rawPos, GetPlayerFacing and GetPlayerFacing() or 0
    end

    local now = GetTime and GetTime() or 0
    local dt = elapsed
    if not dt and smoothedMinimapFrameTime then dt = now - smoothedMinimapFrameTime end
    smoothedMinimapFrameTime = now
    dt = math.max(0, math.min(dt or 0, 0.05))

    local reset = smoothedMinimapMapID ~= mapID or smoothedMinimapContext ~= context
        or not smoothedMinimapPlayerX or not smoothedMinimapPlayerY
    local jump = false
    if not reset then
        local dx = rawPos.x - smoothedMinimapPlayerX
        local dy = rawPos.y - smoothedMinimapPlayerY
        jump = ((dx * dx) + (dy * dy)) > 0.0004
    end

    if reset or jump then
        smoothedMinimapMapID = mapID
        smoothedMinimapContext = context
        smoothedMinimapPlayerX = rawPos.x
        smoothedMinimapPlayerY = rawPos.y
    else
        smoothedMinimapPlayerX = SmoothMinimapValue(smoothedMinimapPlayerX, rawPos.x, dt, 24)
        smoothedMinimapPlayerY = SmoothMinimapValue(smoothedMinimapPlayerY, rawPos.y, dt, 24)
    end

    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    if reset or jump then
        smoothedMinimapFacing = facing
    else
        smoothedMinimapFacing = SmoothMinimapAngle(smoothedMinimapFacing, facing, dt, 28)
    end
    return { x = smoothedMinimapPlayerX, y = smoothedMinimapPlayerY }, smoothedMinimapFacing or facing
end

local function GetMinimapScreenOffset(nodeX, nodeY, playerX, playerY, pixelsPerYard, uiScaleX, uiScaleY, facing)
    local screenX = (nodeX - playerX) * uiScaleX * pixelsPerYard
    local screenY = -((nodeY - playerY) * uiScaleY * pixelsPerYard)

    if GetCVar and GetCVar("rotateMinimap") == "1" then
        local rotation = -(facing or (GetPlayerFacing() or 0))
        local cosR, sinR = math.cos(rotation), math.sin(rotation)
        return (screenX * cosR) - (screenY * sinR), (screenX * sinR) + (screenY * cosR)
    end

    return screenX, screenY
end

local SPELLS = {
    [2575]  = "Mining", [2576]  = "Mining", [3564]  = "Mining", 
    [10248] = "Mining", [29354] = "Mining", [50310] = "Mining",
    [2366]  = "Herb Gathering", [2368]  = "Herb Gathering", [3570]  = "Herb Gathering", 
    [11993] = "Herb Gathering", [28695] = "Herb Gathering", [50309] = "Herb Gathering",
}

local function GetGatheringType(spellID)
    if SPELLS[spellID] then return SPELLS[spellID] end
    local spellName = addon.Compat and addon.Compat:GetSpellName(spellID)
    if not spellName then return nil end
    local lowerName = string.lower(spellName)
    if lowerName == "mining" or string.find(lowerName, "mining", 1, true) then return "Mining" end
    if lowerName == "herb gathering" or string.find(lowerName, "herbal", 1, true) then return "Herb Gathering" end
end

local function NormalizeGatheringType(nodeType)
    if nodeType == "Herbalism" or nodeType == "Herb Gathering" or nodeType == "Herb" then
        return "Herb"
    end
    if nodeType == "Mine" or nodeType == "Mining" then return "Mining" end
    return nodeType
end

local function ExactNodeCoordinateKey(node, mapID)
    local x = math.floor(((node and node.x) or 0) * 100000 + 0.5)
    local y = math.floor(((node and node.y) or 0) * 100000 + 0.5)
    return tostring(mapID or "") .. ":" .. tostring(x) .. ":" .. tostring(y)
end

local function BuildExactNodeClusterLayout(nodes, mapID)
    local groups, layout = {}, {}
    for _, node in ipairs(nodes or {}) do
        if node and node.x and node.y then
            local key = ExactNodeCoordinateKey(node, mapID)
            groups[key] = groups[key] or {}
            groups[key][#groups[key] + 1] = node
        end
    end

    for _, group in pairs(groups) do
        if #group > 1 then
            table.sort(group, function(a, b)
                return StableNodeKey(a, mapID) < StableNodeKey(b, mapID)
            end)
            local names, allNamesDistinct = {}, true
            for _, node in ipairs(group) do
                local name = node.specificName or node.name or node.id or node.type or "Unknown"
                if names[name] then allNamesDistinct = false break end
                names[name] = true
            end
            -- Same-resource records are import duplicates and remain stacked
            -- until the import cleanup removes them. Only distinct resources
            -- receive a cluster layout around their shared true coordinate.
            if allNamesDistinct then
                for index, node in ipairs(group) do
                    layout[node] = { index = index, count = #group }
                end
            end
        end
    end
    return layout
end

local function GetExactNodeClusterOffset(cluster, radius)
    if not cluster or not cluster.count or cluster.count < 2 then return 0, 0 end
    radius = tonumber(radius) or 7
    local count, index = cluster.count, cluster.index
    local angle
    if count == 2 then
        angle = index == 1 and math.pi or 0
    else
        angle = (-math.pi / 2) + (((index - 1) / count) * math.pi * 2)
    end
    return math.cos(angle) * radius, math.sin(angle) * radius
end

function addon.Heatmap:BuildExactNodeClusterLayout(nodes, mapID)
    return BuildExactNodeClusterLayout(nodes, mapID)
end

function addon.Heatmap:GetExactNodeClusterOffset(cluster, radius)
    return GetExactNodeClusterOffset(cluster, radius)
end

local function GetMapCoordinateScales(mapID)
    local scaleX, scaleY
    if addon.UI and addon.UI.GetMapWorldScale then
        scaleX, scaleY = addon.UI:GetMapWorldScale(mapID)
    end
    return scaleX or (addon.UI and addon.UI.scaleX) or 6000,
           scaleY or (addon.UI and addon.UI.scaleY) or 6000
end

-- Imported datasets can contain several samples for the same physical spawn.
-- Keep every saved sample intact, but render nearby same-name samples as one
-- logical node on the world map, PathMaker minimap, and Farm Mode.
local function GetLogicalNodeGroupKey(node, heatmap)
    local nodeName = node.specificName or node.name or node.id or node.type or "Unknown"
    local normalizedName = heatmap and heatmap.GetNormalizedName
        and heatmap:GetNormalizedName(nodeName) or nodeName
    local nodeType = node.type or "Unknown"
    if nodeType == "Herbalism" or nodeType == "Herb Gathering" then nodeType = "Herb" end
    if nodeType == "Mine" then nodeType = "Mining" end
    return nodeType .. "\031" .. tostring(normalizedName)
end

local function CollapseNearbySameNameNodes(nodes, mapID, heatmap)
    if #nodes < 2 then return nodes end

    local scaleX, scaleY = GetMapCoordinateScales(mapID)
    local cellSize = VISUAL_SAME_NODE_GROUP_YARDS
    local radiusSquared = cellSize * cellSize
    local gridsByName = {}
    local result = {}

    for _, node in ipairs(nodes) do
        local groupKey = GetLogicalNodeGroupKey(node, heatmap)
        local grid = gridsByName[groupKey]
        if not grid then
            grid = {}
            gridsByName[groupKey] = grid
        end

        local worldX, worldY = node.x * scaleX, node.y * scaleY
        local bucketX = math.floor(worldX / cellSize)
        local bucketY = math.floor(worldY / cellSize)
        local grouped = false

        for checkX = bucketX - 1, bucketX + 1 do
            if grouped then break end
            for checkY = bucketY - 1, bucketY + 1 do
                local bucket = grid[checkX .. ":" .. checkY]
                if bucket then
                    for _, point in ipairs(bucket) do
                        local dx, dy = worldX - point.x, worldY - point.y
                        if ((dx * dx) + (dy * dy)) <= radiusSquared then
                            grouped = true
                            break
                        end
                    end
                end
                if grouped then break end
            end
        end

        -- Index every sample, including visually grouped samples. This allows a
        -- tight chain of samples to behave as one group without deleting data.
        local ownKey = bucketX .. ":" .. bucketY
        grid[ownKey] = grid[ownKey] or {}
        grid[ownKey][#grid[ownKey] + 1] = { x = worldX, y = worldY }

        if not grouped then
            result[#result + 1] = node
        end
    end

    return result
end

local function RemoveExactNodeStack(nodes, targetNode, heatmap)
    if not targetNode or not targetNode.x or not targetNode.y then return 0 end
    local targetKey = GetLogicalNodeGroupKey(targetNode, heatmap)
    local removed = 0
    for index = #nodes, 1, -1 do
        local candidate = nodes[index]
        if candidate.x == targetNode.x and candidate.y == targetNode.y
            and GetLogicalNodeGroupKey(candidate, heatmap) == targetKey
        then
            table.remove(nodes, index)
            removed = removed + 1
        end
    end
    return removed
end

local function GetMinimapViewRadius()
    if addon.UI and addon.UI.GetMinimapViewRadius then
        return addon.UI:GetMinimapViewRadius()
    end
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    local ranges = {[0] = 230, [1] = 190, [2] = 150, [3] = 110, [4] = 80, [5] = 50}
    return ranges[zoom] or 100
end

local function GetOverlapCell(value)
    return math.floor(value / OVERLAP_CELL_SIZE)
end

local function GetOverlapCellKey(cellX, cellY)
    return cellX .. ":" .. cellY
end

local function CountNearbyDifferentNodesInGrid(grid, px, py, normName)
    local centerX, centerY = GetOverlapCell(px), GetOverlapCell(py)
    local overlapCount = 0
    for cellX = centerX - 1, centerX + 1 do
        for cellY = centerY - 1, centerY + 1 do
            for _, point in ipairs(grid[GetOverlapCellKey(cellX, cellY)] or {}) do
                local dx, dy = px - point.originalX, py - point.originalY
                if ((dx * dx) + (dy * dy)) < (VISUAL_DIST_THRESHOLD * VISUAL_DIST_THRESHOLD)
                    and point.name ~= normName
                then
                    overlapCount = overlapCount + 1
                end
            end
        end
    end
    return overlapCount
end

local function AddNodeToOverlapGrid(grid, px, py, normName)
    local key = GetOverlapCellKey(GetOverlapCell(px), GetOverlapCell(py))
    grid[key] = grid[key] or {}
    grid[key][#grid[key] + 1] = { originalX = px, originalY = py, name = normName }
end

local DEFAULT_ICONS = {
    ["Mining"] = "Interface\\Icons\\Trade_Mining",
    ["Herb"]   = "Interface\\Icons\\Trade_Herbalism",
    ["Treasure"] = "Interface\\AddOns\\PathMaker_Nodes\\Artwork\\Treasure\\treasure.tga",
}

local SPECIFIC_ICONS = {
    ["Copper Vein"] = "Interface\\Icons\\inv_ore_copper_01",
    ["Tin Vein"] = "Interface\\Icons\\inv_ore_tin_01",
    ["Silver Vein"] = "Interface\\Icons\\inv_ore_silver_01",
    ["Iron Deposit"] = "Interface\\Icons\\inv_ore_iron_01",
    ["Gold Vein"] = "Interface\\Icons\\inv_ore_gold_01",
    ["Mithril Deposit"] = "Interface\\Icons\\inv_ore_mithril_02",
    ["Truesilver Deposit"] = "Interface\\Icons\\inv_ore_truesilver_01",
    ["Small Thorium Vein"] = "Interface\\Icons\\inv_ore_thorium_02",
    ["Rich Thorium Vein"] = "Interface\\Icons\\inv_ore_thorium_01",
    ["Ooze Covered Rich Thorium Vein"] = "Interface\\Icons\\inv_ore_thorium_01",
    ["Dark Iron Deposit"] = "Interface\\Icons\\inv_ore_mithril_01",

    ["Fel Iron Deposit"] = "Interface\\Icons\\inv_ore_feliron",
    ["Adamantite Deposit"] = "Interface\\Icons\\inv_ore_adamantium", 
    ["Rich Adamantite Deposit"] = "Interface\\Icons\\inv_ore_adamantium",
    ["Khorium Vein"] = "Interface\\Icons\\inv_ore_khorium",

    ["Peacebloom"] = "Interface\\Icons\\inv_misc_flower_02",
    ["Silverleaf"] = "Interface\\Icons\\inv_misc_flower_10",
    ["Earthroot"] = "Interface\\Icons\\inv_misc_herb_07",
    ["Mageroyal"] = "Interface\\Icons\\Inv_jewelry_talisman_03",
    ["Briarthorn"] = "Interface\\Icons\\inv_misc_root_01",
    ["Bruiseweed"] = "Interface\\Icons\\inv_misc_herb_01",
    ["Wild Steelbloom"] = "Interface\\Icons\\inv_misc_flower_01",
    ["Grave Moss"] = "Interface\\Icons\\inv_misc_dust_02",
    ["Kingsblood"] = "Interface\\Icons\\inv_misc_herb_03",
    ["Liferoot"] = "Interface\\Icons\\inv_misc_root_02",
    ["Fadeleaf"] = "Interface\\Icons\\inv_misc_herb_12",
    ["Goldthorn"] = "Interface\\Icons\\inv_misc_herb_15",
    ["Khadgar's Whisker"] = "Interface\\Icons\\inv_misc_herb_08",
    ["Wintersbite"] = "Interface\\Icons\\inv_misc_flower_03",
    ["Stranglekelp"] = "Interface\\Icons\\inv_misc_herb_11",
    ["Firebloom"] = "Interface\\Icons\\inv_misc_herb_19",
    ["Purple Lotus"] = "Interface\\Icons\\inv_misc_herb_17",
    ["Arthas' Tears"] = "Interface\\Icons\\inv_misc_herb_13",
    ["Sungrass"] = "Interface\\Icons\\inv_misc_herb_18",
    ["Blindweed"] = "Interface\\Icons\\inv_misc_herb_14",
    ["Ghost Mushroom"] = "Interface\\Icons\\inv_mushroom_08",
    ["Gromsblood"] = "Interface\\Icons\\inv_misc_herb_16",
    ["Golden Sansam"] = "Interface\\Icons\\inv_misc_herb_sansamroot",
    ["Dreamfoil"] = "Interface\\Icons\\inv_misc_herb_dreamfoil",
    ["Mountain Silversage"] = "Interface\\Icons\\inv_misc_herb_mountainsilversage",
    ["Plaguebloom"] = "Interface\\Icons\\inv_misc_herb_plaguebloom",
    ["Icecap"] = "Interface\\Icons\\inv_misc_herb_icecap",
    ["Black Lotus"] = "Interface\\Icons\\inv_misc_herb_blacklotus",
    
    ["Felweed"] = "Interface\\Icons\\inv_misc_herb_felweed",
    ["Dreaming Glory"] = "Interface\\Icons\\inv_misc_herb_dreamingglory",
    ["Ragveil"] = "Interface\\Icons\\inv_misc_herb_ragveil",
    ["Terocone"] = "Interface\\Icons\\inv_misc_herb_terrocone",
    ["Netherbloom"] = "Interface\\Icons\\inv_misc_herb_netherbloom",
    ["Nightmare Vine"] = "Interface\\Icons\\inv_misc_herb_nightmarevine",
    ["Mana Thistle"] = "Interface\\Icons\\inv_misc_herb_manathistle",
    ["Flame Cap"] = "Interface\\Icons\\inv_misc_herb_flamecap",
}

-- These are the same deposit visual. Resolve Rich Thorium through the ooze-
-- covered registration first so both always use the same bundled node artwork.
local NODE_ICON_ALIASES = {
    ["Rich Thorium Vein"] = "Ooze Covered Rich Thorium Vein",
}

local function IsPlaceholderIcon(icon)
    return not icon or icon == "" or string.find(tostring(icon):lower(), "questionmark", 1, true) ~= nil
end

local function ResolveNodeIcon(node)
    if not node then return "Interface\\Icons\\INV_Misc_QuestionMark" end

    local searchName = node.specificName or node.name or node.id
    if searchName and addon.NODE_TRANSLATOR then
        searchName = addon.NODE_TRANSLATOR[searchName] or addon.NODE_TRANSLATOR[tostring(searchName)] or searchName
    end

    local iconName = NODE_ICON_ALIASES[searchName] or searchName

    -- Prefer the icon resolved from the resource item ID (or supplied by
    -- PathMaker_Nodes). Some clients do not expose every legacy icon under
    -- the same string path; Silver Vein is one such case.
    if iconName and addon.NODE_ICONS and not IsPlaceholderIcon(addon.NODE_ICONS[iconName]) then
        return addon.NODE_ICONS[iconName]
    end

    if iconName and SPECIFIC_ICONS[iconName] then
        return SPECIFIC_ICONS[iconName]
    end

    if not IsPlaceholderIcon(node.icon) then
        return node.icon
    end

    local nodeType = node.type
    if nodeType == "Herbalism" or nodeType == "Herb Gathering" then nodeType = "Herb" end
    if nodeType == "Mine" then nodeType = "Mining" end
    return DEFAULT_ICONS[nodeType] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ----------------------------------------------------------------------------
-- VARIABLES
-- ----------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local minimapOverlay
local worldMapOverlay
local minimapNodePool = {}
local worldMapNodePool = {}
local activeMinimapNodes = {}
local activeWorldMapNodes = {}
local lastGatherTarget = nil 
local lastGatherWasMob = false 
local ScheduleWorldMapRefresh
local WatchWorldMapSettling
local RefreshWorldMapNow
local UpdateActiveWorldMapNodeLayout

addon.Heatmap.ResolveNodeIcon = ResolveNodeIcon

local WORLD_MAP_STRATA_ORDER = {
    BACKGROUND = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    DIALOG = 5,
    FULLSCREEN = 6,
    FULLSCREEN_DIALOG = 7,
    TOOLTIP = 8,
}

local function GetHighestWorldMapStrata(canvas)
    local bestStrata = "HIGH"
    local bestOrder = WORLD_MAP_STRATA_ORDER[bestStrata] or 0

    local function ConsiderFrame(frameToCheck)
        if frameToCheck and frameToCheck.GetFrameStrata then
            local strata = frameToCheck:GetFrameStrata()
            local order = strata and WORLD_MAP_STRATA_ORDER[strata] or 0
            if order > bestOrder then
                bestStrata = strata
                bestOrder = order
            end
        end
    end

    ConsiderFrame(WorldMapFrame)
    ConsiderFrame(WorldMapFrame and WorldMapFrame.ScrollContainer)
    ConsiderFrame(canvas)

    return bestStrata
end

local function GetHighestWorldMapFrameLevel(canvas)
    local bestLevel = 0

    local function ConsiderFrame(frameToCheck)
        if frameToCheck and frameToCheck.GetFrameLevel then
            bestLevel = math.max(bestLevel, tonumber(frameToCheck:GetFrameLevel()) or 0)
        end
    end

    ConsiderFrame(WorldMapFrame)
    ConsiderFrame(WorldMapFrame and WorldMapFrame.ScrollContainer)
    ConsiderFrame(canvas)
    ConsiderFrame(_G["PathmakerDrawingOverlay"])
    ConsiderFrame(_G["PathmakerLines"])

    return bestLevel
end

local function GetWorldMapCanvas()
    if not WorldMapFrame then return nil end
    return (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child) or
           (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()) or
           WorldMapFrame
end

local function EnsureWorldMapOverlay()
    local canvas = GetWorldMapCanvas()
    if not canvas then return nil end

    if not worldMapOverlay then
        worldMapOverlay = CreateFrame("Frame", "PathmakerHeatmapWorld", canvas)
    elseif worldMapOverlay:GetParent() ~= canvas then
        worldMapOverlay:SetParent(canvas)
    end

    local function HookResizeRefresh(frameToHook)
        if frameToHook and frameToHook.HookScript and not frameToHook.pmPathmakerHeatmapSizeHooked then
            frameToHook.pmPathmakerHeatmapSizeHooked = true
            frameToHook:HookScript("OnSizeChanged", function()
                if WatchWorldMapSettling then WatchWorldMapSettling(0.7) end
            end)
        end
    end

    HookResizeRefresh(canvas)

    local scrollContainer = WorldMapFrame and WorldMapFrame.ScrollContainer
    HookResizeRefresh(scrollContainer)
    HookResizeRefresh(WorldMapFrame)

    local canvasW, canvasH = 0, 0
    if canvas.GetSize then
        canvasW, canvasH = canvas:GetSize()
        canvasW, canvasH = tonumber(canvasW) or 0, tonumber(canvasH) or 0
    end

    worldMapOverlay:ClearAllPoints()
    worldMapOverlay:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
    worldMapOverlay:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", 0, 0)
    if canvasW > 1 and canvasH > 1 then
        worldMapOverlay:SetSize(canvasW, canvasH)
    end
    if worldMapOverlay.SetScale then worldMapOverlay:SetScale(1) end
    if worldMapOverlay.SetAlpha then worldMapOverlay:SetAlpha(1) end
    if worldMapOverlay.SetIgnoreParentAlpha then worldMapOverlay:SetIgnoreParentAlpha(true) end
    if worldMapOverlay.EnableMouse then worldMapOverlay:EnableMouse(false) end
    worldMapOverlay:SetFrameStrata("TOOLTIP")
    local canvasLevel = GetHighestWorldMapFrameLevel(canvas) + 50
    worldMapOverlay:SetFrameLevel(math.min(math.max(canvasLevel, 9050), 9700))
    if worldMapOverlay.Raise then worldMapOverlay:Raise() end
    worldMapOverlay:Show()
    return worldMapOverlay, canvas
end

local worldMapRefreshSerial = 0
local worldMapRefreshTimer

ScheduleWorldMapRefresh = function()
    worldMapRefreshSerial = worldMapRefreshSerial + 1
    local serial = worldMapRefreshSerial

    local function run()
        if serial ~= worldMapRefreshSerial then return end
        if RefreshWorldMapNow then RefreshWorldMapNow() end
    end

    if worldMapRefreshTimer and worldMapRefreshTimer.Cancel then
        worldMapRefreshTimer:Cancel()
        worldMapRefreshTimer = nil
    end
    if C_Timer and C_Timer.NewTimer then
        worldMapRefreshTimer = C_Timer.NewTimer(0.06, function()
            worldMapRefreshTimer = nil
            run()
        end)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.06, run)
    else
        run()
    end
end

RefreshWorldMapNow = function(refreshMapData)
    if WorldMapFrame and WorldMapFrame.IsShown and not WorldMapFrame:IsShown() then return end

    if refreshMapData and WorldMapFrame then
        if type(WorldMapFrame.RefreshAllDataProviders) == "function" then
            WorldMapFrame:RefreshAllDataProviders()
        elseif type(WorldMapFrame.OnMapChanged) == "function" then
            WorldMapFrame:OnMapChanged()
        elseif type(_G.WorldMapFrame_Update) == "function" then
            WorldMapFrame_Update()
        end
    end

    if addon.Heatmap and addon.Heatmap.RefreshWorldMap then
        addon.Heatmap:RefreshWorldMap()
    end
end

WatchWorldMapSettling = function(duration)
    if not frame then return end
    frame.worldMapSettleUntil = GetTime() + (duration or 3)
    frame.worldMapSettleTimer = 0
end

-- ----------------------------------------------------------------------------
-- DB INITIALIZATION & MIGRATION
-- ----------------------------------------------------------------------------
-- One-time backfill so pre-existing saves get a verified/unverified flag:
-- nodes the player has actually gathered before ("learned") are trustworthy,
-- everything else (bundled "PathMaker_Nodes" imports) is not yet confirmed
-- to exist on this server.
local function MigrateVerifiedFlags()
    if PathmakerDB.verifiedMigrationDone then return end
    if PathmakerDB.nodes then
        for _, nodes in pairs(PathmakerDB.nodes) do
            for _, node in ipairs(nodes) do
                if node.verified == nil then
                    node.verified = (node.source == "learned")
                end
            end
        end
    end
    PathmakerDB.verifiedMigrationDone = true
end

function addon.Heatmap:InitDB()
    if not PathmakerDB then PathmakerDB = {} end
    if not PathmakerDB.nodes then PathmakerDB.nodes = {} end
    MigrateVerifiedFlags()
end

local function FixDatabaseIcons()
    if not PathmakerDB or not PathmakerDB.nodes then return end
    
    local count = 0
    for mapID, nodes in pairs(PathmakerDB.nodes) do
        for _, node in ipairs(nodes) do
            if node.name == "Unknown" or node.name == "unknown" or not node.name then
                if node.id and type(node.id) == "string" then
                    node.name = node.id
                    node.specificName = node.id
                else
                    node.name = node.type or "Unknown"
                end
            end
            
            local searchName = node.specificName or node.name or node.id
            if searchName and addon.NODE_TRANSLATOR then
                searchName = addon.NODE_TRANSLATOR[searchName] or addon.NODE_TRANSLATOR[tostring(searchName)] or searchName
                node.name = searchName
                if not node.specificName then node.specificName = searchName end
            end
            local registeredIcon = searchName and addon.NODE_ICONS and addon.NODE_ICONS[searchName]
            if registeredIcon and not IsPlaceholderIcon(registeredIcon) then
                if node.icon ~= registeredIcon then
                    node.icon = registeredIcon
                    count = count + 1
                end
            elseif searchName and SPECIFIC_ICONS[searchName] then
                if node.icon ~= SPECIFIC_ICONS[searchName] then
                    node.icon = SPECIFIC_ICONS[searchName]
                    count = count + 1
                end
            end
        end
    end
end

function addon.Heatmap:GetNormalizedName(name)
    if not name then return "Unknown" end
    local n = name
    n = string.gsub(n, "^Rich%s+", "")
    n = string.gsub(n, "^Small%s+", "")
    n = string.gsub(n, "^Ooze Covered%s+", "")
    n = string.gsub(n, "^Hulking%s+", "")
    return n
end

local function GetNodeIdentity(node, heatmap)
    local nodeType = NormalizeGatheringType(node and node.type)
    local name = node and (node.specificName or node.name or node.id or node.type)
    if name and addon.NODE_TRANSLATOR then
        name = addon.NODE_TRANSLATOR[name] or addon.NODE_TRANSLATOR[tostring(name)] or name
    end
    return tostring(nodeType or "Unknown") .. "\031" .. string.lower(tostring(name or "Unknown"))
end

local function MergeNodeHistory(keeper, duplicate)
    keeper.gatherCount = (tonumber(keeper.gatherCount) or 0) + (tonumber(duplicate.gatherCount) or 0)
    local duplicateGathered = tonumber(duplicate.lastGathered)
    local keeperGathered = tonumber(keeper.lastGathered)
    if duplicateGathered and (not keeperGathered or duplicateGathered > keeperGathered) then
        keeper.lastGathered = duplicateGathered
        keeper.time = duplicateGathered
    end
end

-- Merge only same-resource points that are close enough to represent the same
-- physical spawn. Learned points win over bundled imports, preserving the
-- player's more accurate coordinate and gathering history.
function addon.Heatmap:CleanupDuplicateNodes(mapID)
    self:InitDB()
    local removed = 0
    local mapIDs = {}
    if mapID then
        mapIDs[1] = mapID
    else
        for savedMapID in pairs(PathmakerDB.nodes) do mapIDs[#mapIDs + 1] = savedMapID end
    end

    for _, savedMapID in ipairs(mapIDs) do
        local nodes = PathmakerDB.nodes[savedMapID]
        if type(nodes) == "table" and #nodes > 1 then
            local scaleX, scaleY = GetMapCoordinateScales(savedMapID)
            local cellSize = DUPLICATE_MERGE_DISTANCE_YARDS
            local distanceSquared = cellSize * cellSize
            local grids, kept = {}, {}

            -- Learned nodes are considered first so imported points merge into
            -- them even when an older database stored imports before gathers.
            for pass = 1, 2 do
                local importedPass = pass == 2
                for _, node in ipairs(nodes) do
                    local isImported = node.source == "PathMaker_Nodes"
                    if isImported == importedPass and node.x and node.y then
                        local identity = GetNodeIdentity(node, self)
                        local grid = grids[identity]
                        if not grid then grid = {}; grids[identity] = grid end
                        local worldX, worldY = node.x * scaleX, node.y * scaleY
                        local bucketX, bucketY = math.floor(worldX / cellSize), math.floor(worldY / cellSize)
                        local keeper
                        for checkX = bucketX - 1, bucketX + 1 do
                            if keeper then break end
                            for checkY = bucketY - 1, bucketY + 1 do
                                for _, candidate in ipairs(grid[checkX .. ":" .. checkY] or {}) do
                                    local dx, dy = worldX - candidate.worldX, worldY - candidate.worldY
                                    if ((dx * dx) + (dy * dy)) <= distanceSquared then
                                        keeper = candidate.node
                                        break
                                    end
                                end
                                if keeper then break end
                            end
                        end

                        if keeper then
                            MergeNodeHistory(keeper, node)
                            removed = removed + 1
                        else
                            local key = bucketX .. ":" .. bucketY
                            grid[key] = grid[key] or {}
                            grid[key][#grid[key] + 1] = { node = node, worldX = worldX, worldY = worldY }
                            kept[#kept + 1] = node
                        end
                    elseif isImported == importedPass then
                        kept[#kept + 1] = node
                    end
                end
            end
            PathmakerDB.nodes[savedMapID] = kept
        end
    end

    if removed > 0 then self:InvalidateVisibleNodeCache() end
    return removed
end

-- Strictly checks the Options panel filters to see if the user has enabled this node
function addon.Heatmap:IsNodeAllowed(nodeName)
    if not nodeName then return false end
    if PathmakerDB and PathmakerDB.PMNodes_Filter then
        -- Exact match first (e.g., "Small Thorium Vein")
        if PathmakerDB.PMNodes_Filter[nodeName] ~= nil then return PathmakerDB.PMNodes_Filter[nodeName] == true end
        
        -- Normalized match fallback (e.g., "Thorium Vein")
        local normName = self:GetNormalizedName(nodeName)
        if PathmakerDB.PMNodes_Filter[normName] ~= nil then return PathmakerDB.PMNodes_Filter[normName] == true end
    end
    -- New Retail node names cannot be pre-enumerated. Enable them on first
    -- encounter; they become normal filter entries after being recorded.
    if addon.Compat and addon.Compat.isRetail then return true end
    -- If a node is unchecked (or Options were never initialized/opened), default to opt-in rules (Hidden)
    return false
end

local function IsValidNode(targetName)
    if not targetName then return false end
    local normName = addon.Heatmap:GetNormalizedName(targetName)
    if SPECIFIC_ICONS[targetName] or SPECIFIC_ICONS[normName] then
        return true
    end
    -- Retail adds gathering nodes every expansion. The gathering-spell gate and
    -- creature check still prevent arbitrary targets from being recorded.
    if addon.Compat and addon.Compat.isRetail then return targetName ~= "" end
    return false
end

local function PlayerHasProfession(nodeType)
    if nodeType == "Herb Gathering" or nodeType == "Herbalism" then
        nodeType = "Herb"
    elseif nodeType == "Mine" then
        nodeType = "Mining"
    end

    local profs = {GetProfessions()}
    if profs then
        for _, index in ipairs(profs) do
            if index then
                local name, icon, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(index)
                if nodeType == "Mining" then
                    if skillLine == 186 or name == "Mining" then return true end
                elseif nodeType == "Herb" then
                    if skillLine == 182 or name == "Herbalism" or name == "Herb Gathering" then return true end
                end
            end
        end
    end

    if nodeType == "Mining" then
        if addon.Compat and (addon.Compat:IsSpellKnown(2575) or addon.Compat:IsSpellKnown(2580)) then return true end
    elseif nodeType == "Herb" then
        if addon.Compat and (addon.Compat:IsSpellKnown(2366) or addon.Compat:IsSpellKnown(2383)) then return true end
    end

    return false
end

function addon.Heatmap:PlayerHasProfession(nodeType)
    return PlayerHasProfession(nodeType)
end

local function GetWorldMapNodeVisualSettings()
    local settings = PathmakerDB and PathmakerDB.settings or {}
    local iconSize = math.max(6, math.min(40, tonumber(settings.worldMapNodeIconSize) or WORLD_NODE_ICON_SIZE))
    local iconOpacity = math.max(0, math.min(1, tonumber(settings.worldMapNodeIconOpacity) or 1))
    return iconSize, iconOpacity
end

local function IsWorldMapNodeTypeEnabled(node, hasMining, hasHerbalism)
    local nodeType = node and node.type
    if nodeType == "Herbalism" or nodeType == "Herb Gathering" then nodeType = "Herb" end
    if nodeType == "Mine" then nodeType = "Mining" end

    local settings = PathmakerDB and PathmakerDB.settings or {}
    if nodeType == "Mining" then
        return settings.worldMapShowMining ~= false and hasMining
    end
    if nodeType == "Herb" then
        return settings.worldMapShowHerbalism ~= false and hasHerbalism
    end
    if nodeType == "Treasure" then
        return settings.worldMapShowTreasure ~= false
    end
    return false
end

local visibleNodeCache = {}
local visibleNodeCacheGeneration = 0

function addon.Heatmap:InvalidateVisibleNodeCache()
    visibleNodeCacheGeneration = visibleNodeCacheGeneration + 1
    wipe(visibleNodeCache)
end

function addon.Heatmap:GetVisibleNodeCacheGeneration()
    return visibleNodeCacheGeneration
end

local function IsPositionInsideMap(pos)
    if not pos then return false end
    local x, y = tonumber(pos.x), tonumber(pos.y)
    return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

local function GetPositionOnNodeMap(mapID)
    if not mapID then return nil end
    local pos
    if addon.Compat and addon.Compat.GetUnitMapPosition then
        pos = addon.Compat:GetUnitMapPosition(mapID, "player")
    elseif C_Map and C_Map.GetPlayerMapPosition then
        local ok, value = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
        if ok then pos = value end
    end
    return IsPositionInsideMap(pos) and pos or nil
end

local function MapHasNodeData(mapID)
    local nodes = mapID and PathmakerDB and PathmakerDB.nodes and PathmakerDB.nodes[mapID]
    return type(nodes) == "table" and #nodes > 0
end

local function IsNodeDisplayBlockedByInstance(playerMapID)
    -- IsInInstance changes before/with the minimap provider and prevents the
    -- entrance zone's last completed pin frame from leaking into an instance.
    if IsInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "scenario") then
            return true
        end
        -- Outdoor caves can use dungeon-like UI map types, so a known outdoor
        -- instance state must win over the map metadata fallback.
        return false
    end

    -- Compatibility fallback for clients without IsInInstance.
    local info = playerMapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(playerMapID)
    local dungeonMapType = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon or 4
    return info and info.mapType == dungeonMapType or false
end

function addon.Heatmap:IsNodeDisplayBlockedByInstance(playerMapID)
    return IsNodeDisplayBlockedByInstance(playerMapID)
end

-- City, cave, and micro maps often replace GetBestMapForUnit even though saved
-- nodes still use the surrounding zone's coordinates. Resolve a containing map
-- with node data instead of treating every area boundary as "no nodes". Dungeon
-- and raid maps are deliberately excluded from this inheritance.
function addon.Heatmap:ResolveNodeDisplayMap(playerMapID)
    if not PathmakerDB or not PathmakerDB.nodes then return playerMapID, nil end
    playerMapID = playerMapID or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if IsNodeDisplayBlockedByInstance(playerMapID) then
        return playerMapID, nil, true
    end
    if not playerMapID then return nil, nil end

    local now = GetTime and GetTime() or 0
    if self.nodeDisplayResolutionPlayerMapID == playerMapID
        and self.nodeDisplayResolutionGeneration == visibleNodeCacheGeneration
        and now < (self.nodeDisplayResolutionExpires or 0)
    then
        local cachedMapID = self.nodeDisplayResolutionMapID
        if cachedMapID then
            local cachedPos = GetPositionOnNodeMap(cachedMapID)
            if cachedPos then return cachedMapID, cachedPos end
        end
    end

    local candidates, seen = {}, {}
    local function AddCandidate(mapID)
        if mapID and not seen[mapID] then
            seen[mapID] = true
            candidates[#candidates + 1] = mapID
        end
    end

    -- A convertible position is not proof of zone membership: adjacent zone
    -- rectangles overlap. Always load the current map before its ancestors,
    -- and never inherit pins from an unrelated previous/selected route map.
    AddCandidate(playerMapID)

    local ancestor = playerMapID
    for _ = 1, 8 do
        local info = ancestor and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(ancestor)
        ancestor = info and info.parentMapID
        if not ancestor or ancestor == 0 then break end
        AddCandidate(ancestor)
    end

    local function TryCandidate(mapID)
        if not MapHasNodeData(mapID) then return nil end
        if addon.Compat and not addon.Compat:IsMapExpansionVisible(mapID) then return nil end
        local pos = GetPositionOnNodeMap(mapID)
        if pos then
            self.nodeDisplayResolutionPlayerMapID = playerMapID
            self.nodeDisplayResolutionGeneration = visibleNodeCacheGeneration
            self.nodeDisplayResolutionMapID = mapID
            self.nodeDisplayResolutionExpires = now + 0.25
            return mapID, pos
        end
    end

    for _, mapID in ipairs(candidates) do
        local resolvedMapID, pos = TryCandidate(mapID)
        if resolvedMapID then return resolvedMapID, pos end
        -- Retry a temporarily unavailable position on the next update. Do not
        -- lock onto another map while the current map provider is loading.
        if MapHasNodeData(mapID) and (not addon.Compat or addon.Compat:IsMapExpansionVisible(mapID)) then
            return mapID, nil
        end
    end

    -- An empty zone is still a completed handoff: return its position so both
    -- minimaps can clear the old pins. Missing positions are never cached.
    return playerMapID, GetPositionOnNodeMap(playerMapID)
end

function addon.Heatmap:GetVisibleNodesForMap(mapID)
    if not mapID or not PathmakerDB or not PathmakerDB.nodes then return {} end
    local source = PathmakerDB.nodes[mapID]
    if type(source) ~= "table" then return {} end
    if addon.Compat and not addon.Compat:IsMapExpansionVisible(mapID) then return {} end

    -- Profession ownership is mandatory on the world map, PathMaker minimap,
    -- and Farm Mode. Include it in the cache identity so learning or dropping
    -- a profession changes visibility immediately without requiring a reload.
    local hasMining = PlayerHasProfession("Mining")
    local hasHerbalism = PlayerHasProfession("Herb")
    local cached = visibleNodeCache[mapID]
    if cached and cached.generation == visibleNodeCacheGeneration
        and cached.source == source and cached.sourceCount == #source
        and cached.hasMining == hasMining and cached.hasHerbalism == hasHerbalism
    then
        return cached.nodes
    end

    local hiddenNodes = PathmakerDB.settings and PathmakerDB.settings.hiddenNodes or {}
    local result = {}

    for _, node in ipairs(source) do
        if node.x and node.y then
            local nodeType = node.type
            if nodeType == "Herbalism" or nodeType == "Herb Gathering" then nodeType = "Herb" end
            if nodeType == "Mine" then nodeType = "Mining" end
            local hasProfession = (nodeType == "Mining" and hasMining)
                or (nodeType == "Herb" and hasHerbalism)
                or nodeType == "Treasure"
            local searchName = node.specificName or node.name
            local normName = self:GetNormalizedName(searchName)
            if hasProfession and not hiddenNodes[normName] and self:IsNodeAllowed(searchName)
            then
                result[#result + 1] = node
            end
        end
    end

    result = CollapseNearbySameNameNodes(result, mapID, self)

    visibleNodeCache[mapID] = {
        generation = visibleNodeCacheGeneration,
        source = source,
        sourceCount = #source,
        hasMining = hasMining,
        hasHerbalism = hasHerbalism,
        nodes = result,
    }
    return result
end

-- ----------------------------------------------------------------------------
-- RECORDING LOGIC
-- ----------------------------------------------------------------------------
local function RecordNode(nodeType, specificName)
    nodeType = NormalizeGatheringType(nodeType)
    local nameToCheck = specificName or nodeType
    
    -- STRICT GATEKEEPER: Only record/update if checked in the Options Panel!
    if not addon.Heatmap:IsNodeAllowed(nameToCheck) then
        return 
    end

    local playerMapID = C_Map.GetBestMapForUnit("player")
    if not playerMapID then return end

    local mapID, pos, instanceBlocked = addon.Heatmap:ResolveNodeDisplayMap(playerMapID)
    if instanceBlocked then return end
    if not pos then
        mapID = playerMapID
        pos = C_Map.GetPlayerMapPosition(mapID, "player")
    end
    if not pos then return end

    addon.Heatmap:InitDB()
    if not PathmakerDB.nodes[mapID] then PathmakerDB.nodes[mapID] = {} end

    local iconPath = DEFAULT_ICONS[nodeType]
    if specificName and addon.NODE_ICONS and not IsPlaceholderIcon(addon.NODE_ICONS[specificName]) then
        iconPath = addon.NODE_ICONS[specificName]
    elseif specificName and SPECIFIC_ICONS[specificName] then
        iconPath = SPECIFIC_ICONS[specificName]
    end
    
    local targetName = specificName or nodeType
    if addon.NODE_TRANSLATOR then
        targetName = addon.NODE_TRANSLATOR[targetName] or addon.NODE_TRANSLATOR[tostring(targetName)] or targetName
    end
    targetName = string.lower(tostring(targetName))
    local scaleX, scaleY = GetMapCoordinateScales(mapID)
    local nearestNode, nearestDistanceSquared

    for _, node in ipairs(PathmakerDB.nodes[mapID]) do
        if node.x and node.y and NormalizeGatheringType(node.type) == nodeType then
            local existingName = node.specificName or node.name or node.id or node.type
            if addon.NODE_TRANSLATOR then
                existingName = addon.NODE_TRANSLATOR[existingName]
                    or addon.NODE_TRANSLATOR[tostring(existingName)] or existingName
            end
            local sameResource = string.lower(tostring(existingName)) == targetName
                or (not node.specificName and NormalizeGatheringType(existingName) == nodeType)
            if sameResource then
                local dx = (node.x - pos.x) * scaleX
                local dy = (node.y - pos.y) * scaleY
                local distanceSquared = (dx * dx) + (dy * dy)
                if distanceSquared <= (RECORD_MERGE_DISTANCE_YARDS * RECORD_MERGE_DISTANCE_YARDS)
                    and (not nearestDistanceSquared or distanceSquared < nearestDistanceSquared)
                then
                    nearestNode, nearestDistanceSquared = node, distanceSquared
                end
            end
        end
    end

    local gatheredAt = GetServerTime and GetServerTime() or time()
    if nearestNode then
        -- A confirmed gather promotes a bundled point to learned data. This
        -- preserves its history when the companion dataset is refreshed and
        -- lets future imports defer to the player's observed coordinate.
        nearestNode.x = pos.x
        nearestNode.y = pos.y
        nearestNode.icon = iconPath
        nearestNode.name = specificName or nodeType
        nearestNode.specificName = specificName
        nearestNode.lastGathered = gatheredAt
        nearestNode.time = gatheredAt
        nearestNode.gatherCount = (tonumber(nearestNode.gatherCount) or 0) + 1
        nearestNode.source = "learned"
        nearestNode.verified = true
        addon.Heatmap:InvalidateVisibleNodeCache()
        addon.Heatmap:RefreshWorldMap()
        return
    end

    table.insert(PathmakerDB.nodes[mapID], {
        x = pos.x,
        y = pos.y,
        type = nodeType,
        name = specificName or nodeType,
        specificName = specificName, 
        icon = iconPath,
        time = gatheredAt,
        lastGathered = gatheredAt,
        gatherCount = 1,
        source = "learned",
        verified = true,
    })
    addon.Heatmap:InvalidateVisibleNodeCache()
    
    local debugName = specificName or nodeType
    local hideRecMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgRecording
    if not hideRecMsg then
        print("|cff00ff00Pathmaker:|r Recorded New: " .. debugName)
    end
    addon.Heatmap:RefreshWorldMap()
end

-- ----------------------------------------------------------------------------
-- VISUALIZATION: POOL HANDLING
-- ----------------------------------------------------------------------------
local function GetNodeFrame(parent, useMinimapMask)
    local framePool = useMinimapMask and minimapNodePool or worldMapNodePool
    local f = table.remove(framePool)
    if not f then
        f = CreateFrame("Button", nil, parent) 
        f:SetSize(NODE_ICON_SIZE * ICON_SCALE, NODE_ICON_SIZE * ICON_SCALE)
        f:SetFrameStrata("LOW")
        
        f.icon = f:CreateTexture(nil, "OVERLAY", nil, 7)
        f.icon:SetAllPoints()
        if f.icon.SetTexCoord then
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if f.icon.SetSnapToPixelGrid then f.icon:SetSnapToPixelGrid(true) end
        if f.icon.SetTexelSnappingBias then f.icon:SetTexelSnappingBias(0) end
        
        f.ring = f:CreateTexture(nil, "OVERLAY", nil, 7)
        f.ring:SetPoint("CENTER")
        f.ring:SetSize(RING_SIZE, RING_SIZE)
        f.ring:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        f.ring:SetBlendMode("ADD")
        f.ring:Hide()
        f.pmNodeFramePool = framePool
    end
    f:SetParent(parent)
    if useMinimapMask then
        f:SetSize(NODE_ICON_SIZE * ICON_SCALE, NODE_ICON_SIZE * ICON_SCALE)
        if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end
    else
        f:SetSize(WORLD_NODE_HITBOX_SIZE, WORLD_NODE_HITBOX_SIZE)
        if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end
    end
    if f.SetScale then f:SetScale(1) end
    if f.SetAlpha then f:SetAlpha(1) end
    if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
    -- Pins must inherit the canvas transform so their anchors remain exactly
    -- on the map coordinate. World-map icon dimensions are compensated below.
    if f.SetIgnoreParentScale then f:SetIgnoreParentScale(false) end
    if f.Show then f:Show() end
    if parent and parent.GetFrameStrata then
        f:SetFrameStrata(parent:GetFrameStrata())
    end
    if f.icon then
        f.icon:ClearAllPoints()
        if useMinimapMask then
            f.icon:SetAllPoints()
        else
            f.icon:SetPoint("CENTER")
            f.icon:SetSize(WORLD_NODE_ICON_SIZE, WORLD_NODE_ICON_SIZE)
        end
        if f.icon.SetTexCoord then
            f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        f.icon:SetVertexColor(1, 1, 1, 1)
        f.icon:SetAlpha(1)
        f.icon:Show()
        if f.icon.SetDrawLayer then f.icon:SetDrawLayer("OVERLAY", 7) end
    end
    if f.ring and f.ring.SetDrawLayer then
        f.ring:SetDrawLayer("OVERLAY", 7)
    end
    if f.ring then
        f.ring:SetAlpha(1)
        f.ring:SetVertexColor(1, 1, 1, 1)
        f.ring:Hide()
    end
    f:Show()
    return f
end

local function RecycleNodeFrame(f)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(f) then
        GameTooltip:Hide()
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        if GameTooltip.SetAlpha then GameTooltip:SetAlpha(1) end
    end
    f:SetScript("OnEnter", nil)
    f:SetScript("OnLeave", nil)
    f:SetScript("OnClick", nil)
    f:EnableMouse(false)
    f.nodeData = nil
    f.pmNodeMapID = nil
    f.pmOverlapOffsetX = nil
    f.pmOverlapOffsetY = nil
    f.pmMinimapWasCloseNode = nil
    f.pmMinimapInsideDrawRange = nil
    f.pmWorldOverlapOffsetX = nil
    f.pmWorldOverlapOffsetY = nil
    f.pmExactNodeCluster = nil
    f.pmWorldDrawX = nil
    f.pmWorldDrawY = nil
    f.pmWorldIconSize = nil
    f:Hide()
    f:ClearAllPoints()
    table.insert(f.pmNodeFramePool or worldMapNodePool, f)
end

-- ----------------------------------------------------------------------------
-- MINIMAP RENDERING (WITH CIRCULAR HEADNOD LOGIC)
-- ----------------------------------------------------------------------------
function addon.Heatmap:UpdateMinimap(elapsed)
    local playerMapID = C_Map.GetBestMapForUnit("player")
    local mapID, pos, instanceBlocked = self:ResolveNodeDisplayMap(playerMapID)
    local source = mapID and PathmakerDB and PathmakerDB.nodes and PathmakerDB.nodes[mapID]
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    local context = mapID and GetPlayerNodeContext(mapID)
    local needsRebuild = instanceBlocked == true
        or self.minimapNodesDirty == true
        or self.minimapNodesMapID ~= mapID
        or self.minimapNodesSource ~= source
        or self.minimapNodesSourceCount ~= (source and #source or 0)
        or self.minimapNodesZoom ~= zoom
        or self.minimapNodesContext ~= context
        or (pos ~= nil and self.minimapNodesPlayerX == nil)

    if not needsRebuild and pos and self.minimapNodesPlayerX and self.minimapNodesPlayerY then
        local scaleX, scaleY = GetMapCoordinateScales(mapID)
        local dx = (pos.x - self.minimapNodesPlayerX) * scaleX
        local dy = (pos.y - self.minimapNodesPlayerY) * scaleY
        needsRebuild = ((dx * dx) + (dy * dy)) >= (MINIMAP_REBUILD_DISTANCE_YARDS * MINIMAP_REBUILD_DISTANCE_YARDS)
    end

    if not needsRebuild then return end
    if not minimapOverlay then return end

    if instanceBlocked then
        for _, f in ipairs(activeMinimapNodes or {}) do RecycleNodeFrame(f) end
        wipe(activeMinimapNodes)
        minimapOverlay:Hide()
        self.minimapNodesDirty = false
        self.minimapNodesMapID = mapID
        self.minimapNodesSource = nil
        self.minimapNodesSourceCount = 0
        self.minimapNodesPlayerX = nil
        self.minimapNodesPlayerY = nil
        return
    end

    if addon.isFarmMode then
        for _, f in ipairs(activeMinimapNodes or {}) do RecycleNodeFrame(f) end
        wipe(activeMinimapNodes)
        minimapOverlay:Hide()
        return
    end
    minimapOverlay:Show()
    
    if _G["PathmakerCanvas"] and minimapOverlay:GetParent() ~= _G["PathmakerCanvas"] then
        minimapOverlay:SetParent(_G["PathmakerCanvas"])
    end
    minimapOverlay:ClearAllPoints()
    if _G["PathmakerCanvas"] then
        minimapOverlay:SetAllPoints(_G["PathmakerCanvas"])
    else
        minimapOverlay:SetAllPoints(Minimap)
    end
    if minimapOverlay.SetAlpha then minimapOverlay:SetAlpha(1) end
    if minimapOverlay.SetScale then minimapOverlay:SetScale(1) end
    
    minimapOverlay:SetFrameStrata("LOW")
    if minimapOverlay:GetParent() then
        minimapOverlay:SetFrameLevel(minimapOverlay:GetParent():GetFrameLevel() + 50)
    end

    if PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.hideHeatmap then 
        for _, f in ipairs(activeMinimapNodes or {}) do f:Hide() end
        return 
    end

    -- Preserve pins only within the same coordinate space. A new zone must
    -- never show the old zone's pins while its position provider is loading.
    if not pos then
        if self.minimapNodesMapID ~= mapID then
            for _, f in ipairs(activeMinimapNodes or {}) do f:Hide() end
        end
        return
    end
    if not PathmakerDB or not PathmakerDB.nodes or not mapID then return end

    self.minimapNodesDirty = false
    self.minimapNodesMapID = mapID
    self.minimapNodesSource = source
    self.minimapNodesSourceCount = source and #source or 0
    self.minimapNodesZoom = zoom
    self.minimapNodesContext = context
    self.minimapNodesPlayerX = pos.x
    self.minimapNodesPlayerY = pos.y

    if not PathmakerDB.nodes[mapID]
        or (addon.Compat and not addon.Compat:IsMapExpansionVisible(mapID))
    then
        for _, f in ipairs(activeMinimapNodes or {}) do RecycleNodeFrame(f) end
        wipe(activeMinimapNodes)
        return
    end

    -- Reuse frames by node identity. Index-based reuse transfers visibility and
    -- range state between unrelated pins whenever the visible subset changes.
    local reusableMinimapNodes = activeMinimapNodes
    local reusableByNode, reusedFrames = {}, {}
    for _, reusableFrame in ipairs(reusableMinimapNodes or {}) do
        if reusableFrame.nodeData then reusableByNode[reusableFrame.nodeData] = reusableFrame end
    end
    local replacementMinimapNodes = {}
    local renderPos, renderFacing = GetSmoothedMinimapRenderState(mapID, pos, elapsed)
    local px, py = renderPos.x, renderPos.y

    local visibleRadius = GetMinimapViewRadius()
    
    local canvasSize = Minimap:GetWidth()
    local radiusPixels = canvasSize / 2
    
    local uiScaleX, uiScaleY = GetMapCoordinateScales(mapID)
    
    local drawnMinimapPixels = {}
    local visibleNodes = self:GetVisibleNodesForMap(mapID)
    local exactClusterLayout = BuildExactNodeClusterLayout(visibleNodes, mapID)

    for i, node in ipairs(visibleNodes) do
        do
            local dx = (node.x - px)
            local dy = (node.y - py)
            
            if math.abs(dx) < 0.1 and math.abs(dy) < 0.1 then
                local yardsX = dx * uiScaleX
                local yardsY = dy * uiScaleY
                local distYards = math.sqrt(yardsX*yardsX + yardsY*yardsY)
                
                local pxPerYard = radiusPixels / visibleRadius
                local pixelX, pixelY = GetMinimapScreenOffset(node.x, node.y, px, py, pxPerYard, uiScaleX, uiScaleY, renderFacing)

                local distPixels = math.sqrt(pixelX*pixelX + pixelY*pixelY)
                local maxPixelDist = radiusPixels * 0.95 

                local existingFrame = reusableByNode[node]
                local edgeThreshold = maxPixelDist + ((existingFrame and existingFrame.pmMinimapInsideDrawRange) and 2 or -2)
                if distPixels < edgeThreshold then
                    local normName = addon.Heatmap:GetNormalizedName(node.specificName or node.name)
                    do
                        local overlapCount = CountNearbyDifferentNodes(drawnMinimapPixels, pixelX, pixelY, normName)
                            local drawX = pixelX
                            local drawY = pixelY
                            local overlapOffsetX = 0
                            local overlapOffsetY = 0
                            
                            local exactCluster = exactClusterLayout[node]
                            if exactCluster then
                                overlapOffsetX, overlapOffsetY = GetExactNodeClusterOffset(exactCluster, NODE_ICON_SIZE * 0.75)
                                drawX = pixelX + overlapOffsetX
                                drawY = pixelY + overlapOffsetY
                            elseif overlapCount > 0 then
                                overlapOffsetX, overlapOffsetY = GetStableOverlapOffset(node, mapID, overlapCount)
                                drawX = pixelX + overlapOffsetX
                                drawY = pixelY + overlapOffsetY
                            end
                            local f = existingFrame
                            if f then
                                reusedFrames[f] = true
                                f:SetParent(minimapOverlay)
                                f:SetAlpha(1)
                                f:Show()
                            else
                                f = GetNodeFrame(minimapOverlay, true)
                            end
                            f:ClearAllPoints()
                            f:SetPoint("CENTER", minimapOverlay, "CENTER", drawX, drawY)
                            f.nodeData = node
                            f.pmNodeMapID = mapID
                            f.pmOverlapOffsetX = overlapOffsetX
                            f.pmOverlapOffsetY = overlapOffsetY
                            f.pmMinimapInsideDrawRange = true
                            
                            if minimapOverlay.GetFrameStrata then f:SetFrameStrata(minimapOverlay:GetFrameStrata()) end
                            -- Fixed flicker: Adding 'i' sets a distinct depth level per node so they never switch layers
                            f:SetFrameLevel(minimapOverlay:GetFrameLevel() + 10 + i) 
                            
                            f:EnableMouse(false)
                            f:SetScript("OnEnter", nil)
                            f:SetScript("OnLeave", nil)
                            f:SetScript("OnClick", nil)
                            
                            local texture = ResolveNodeIcon(node)
                            f.icon:SetTexture(texture)
                            
                            local isCloseNode = IsCloseNodeFrame(f, distYards)
                            f.pmMinimapWasCloseNode = isCloseNode
                            local hideNodeCircle = PathmakerDB and PathmakerDB.settings
                                and PathmakerDB.settings.farmHideCircle == true
                            local hideCloseNode = isCloseNode and hideNodeCircle
                            if hideCloseNode then
                                f.icon:Hide()
                                f.ring:Hide()
                            elseif isCloseNode then
                                f.icon:Hide()
                                f.ring:Show()
                                if node.type == "Mining" then f.ring:SetVertexColor(1, 0.5, 0, 1)
                                else f.ring:SetVertexColor(0, 1, 0, 1) end
                            else
                                f.icon:Show()
                                f.ring:Hide()
                            end
                            if hideCloseNode then f:Hide() else f:Show() end
                            
                            table.insert(replacementMinimapNodes, f)
                            if not hideCloseNode then
                                table.insert(drawnMinimapPixels, {originalX=pixelX, originalY=pixelY, name=normName})
                            end
                    end
                end
            end
        end
    end

    for _, reusableFrame in ipairs(reusableMinimapNodes or {}) do
        if not reusedFrames[reusableFrame] then RecycleNodeFrame(reusableFrame) end
    end
    activeMinimapNodes = replacementMinimapNodes
end

function addon.Heatmap:UpdateActiveMinimapNodePositions()
    if not minimapOverlay or addon.isFarmMode then return end
    if not activeMinimapNodes or #activeMinimapNodes == 0 then return end
    if PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.hideHeatmap then
        for _, f in ipairs(activeMinimapNodes) do f:Hide() end
        return
    end

    local playerMapID = C_Map.GetBestMapForUnit("player")
    local mapID, pos, instanceBlocked = self:ResolveNodeDisplayMap(playerMapID)
    if instanceBlocked then
        for _, f in ipairs(activeMinimapNodes) do f:Hide() end
        return
    end
    if not mapID or not pos then return end
    local facing = GetPlayerFacing and GetPlayerFacing() or 0
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    if self.activePositionMapID == mapID
        and self.activePositionX == pos.x and self.activePositionY == pos.y
        and self.activePositionFacing == facing and self.activePositionZoom == zoom
    then
        return
    end
    self.activePositionMapID = mapID
    self.activePositionX = pos.x
    self.activePositionY = pos.y
    self.activePositionFacing = facing
    self.activePositionZoom = zoom
    local renderPos, renderFacing = GetSmoothedMinimapRenderState(mapID, pos)

    local visibleRadius = GetMinimapViewRadius()
    local radiusPixels = (Minimap:GetWidth() or 0) / 2
    if radiusPixels <= 0 then return end

    local uiScaleX, uiScaleY = GetMapCoordinateScales(mapID)
    local maxPixelDist = radiusPixels * 0.95

    for _, f in ipairs(activeMinimapNodes) do
        local node = f.nodeData
        if node and f.pmNodeMapID == mapID and node.x and node.y then
            local dx = node.x - renderPos.x
            local dy = node.y - renderPos.y
            local yardsX = dx * uiScaleX
            local yardsY = dy * uiScaleY
            local distYards = math.sqrt((yardsX * yardsX) + (yardsY * yardsY))
            local pxPerYard = radiusPixels / visibleRadius
            local pixelX, pixelY = GetMinimapScreenOffset(node.x, node.y, renderPos.x, renderPos.y, pxPerYard, uiScaleX, uiScaleY, renderFacing)

            local distPixels = math.sqrt((pixelX * pixelX) + (pixelY * pixelY))
            local edgeThreshold = maxPixelDist + (f.pmMinimapInsideDrawRange and 2 or -2)
            if distPixels < edgeThreshold then
                f.pmMinimapInsideDrawRange = true
                local drawX = pixelX + (f.pmOverlapOffsetX or 0)
                local drawY = pixelY + (f.pmOverlapOffsetY or 0)
                f:ClearAllPoints()
                f:SetPoint("CENTER", minimapOverlay, "CENTER", drawX, drawY)
                f:SetAlpha(1)
                local isCloseNode = IsCloseNodeFrame(f, distYards)
                f.pmMinimapWasCloseNode = isCloseNode
                local hideNodeCircle = PathmakerDB and PathmakerDB.settings
                    and PathmakerDB.settings.farmHideCircle == true
                local hideCloseNode = isCloseNode and hideNodeCircle
                if hideCloseNode then
                    if f.icon then f.icon:Hide() end
                    if f.ring then f.ring:Hide() end
                elseif isCloseNode then
                    if f.icon then f.icon:Hide() end
                    if f.ring then
                        f.ring:Show()
                        if node.type == "Mining" then f.ring:SetVertexColor(1, 0.5, 0, 1)
                        else f.ring:SetVertexColor(0, 1, 0, 1) end
                    end
                else
                    if f.icon then f.icon:Show() end
                    if f.ring then f.ring:Hide() end
                end
                if hideCloseNode then f:Hide() else f:Show() end
            else
                f.pmMinimapInsideDrawRange = false
                f:Hide()
            end
        else
            f:Hide()
        end
    end
end

function addon.Heatmap:OnPlayerMapChanged()
    self.minimapNodesDirty = true
    self.activePositionMapID = nil
    smoothedMinimapMapID = nil
    smoothedMinimapContext = nil
    local playerMapID = C_Map.GetBestMapForUnit("player")
    local mapID, pos, instanceBlocked = self:ResolveNodeDisplayMap(playerMapID)
    if instanceBlocked then
        self:UpdateMinimap(0)
        return
    end
    -- Keep the previous completed frame visible while WoW briefly reports no
    -- map position during a transfer. The normal update atomically replaces it
    -- as soon as the new map is ready, avoiding a blank flash.
    if not mapID or not pos then return end
    self:UpdateMinimap(0)
end

local function GetWorldMapNodeRenderSize()
    local configuredSize, iconOpacity = GetWorldMapNodeVisualSettings()
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local overlayScale = worldMapOverlay and worldMapOverlay.GetEffectiveScale and worldMapOverlay:GetEffectiveScale() or uiScale
    local inheritedScale = math.max(overlayScale / math.max(uiScale, 0.01), 0.01)
    local iconSize = configuredSize / inheritedScale
    local hitboxSize = math.max(WORLD_NODE_HITBOX_SIZE, configuredSize) / inheritedScale
    return iconSize, hitboxSize, iconOpacity
end

-- Zooming and resizing only need an O(n) layout pass. Reusing the existing
-- frames avoids sorting, texture assignment, tooltip closure creation, and
-- pool churn for every intermediate zoom step.
UpdateActiveWorldMapNodeLayout = function()
    if not worldMapOverlay or not activeWorldMapNodes or #activeWorldMapNodes == 0 then return end
    if not WorldMapFrame or (WorldMapFrame.IsShown and not WorldMapFrame:IsShown()) then return end

    local mapID = WorldMapFrame:GetMapID()
    local canvas = GetWorldMapCanvas()
    if not mapID or not canvas then return end

    local w, h = canvas:GetSize()
    w, h = tonumber(w) or 0, tonumber(h) or 0
    if w <= 1 or h <= 1 then return end

    local oldW, oldH = worldMapOverlay:GetSize()
    if math.abs((oldW or 0) - w) > 0.01 or math.abs((oldH or 0) - h) > 0.01 then
        worldMapOverlay:SetSize(w, h)
    end

    local iconSize, hitboxSize, iconOpacity = GetWorldMapNodeRenderSize()
    local positionChanged = worldMapOverlay.pmLayoutMapID ~= mapID
        or worldMapOverlay.pmLayoutWidth ~= w
        or worldMapOverlay.pmLayoutHeight ~= h
    local visualChanged = worldMapOverlay.pmLayoutIconSize ~= iconSize
        or worldMapOverlay.pmLayoutHitboxSize ~= hitboxSize
        or worldMapOverlay.pmLayoutIconOpacity ~= iconOpacity
    if not worldMapOverlay.pmLayoutDirty and not positionChanged and not visualChanged then return end

    for _, nodeFrame in ipairs(activeWorldMapNodes) do
        local node = nodeFrame.nodeData
        if node and nodeFrame.pmNodeMapID == mapID and node.x and node.y then
            -- Keep the anchor in exact canvas coordinates. Rounding this point
            -- during animated zoom causes visible one-pixel pin jitter.
            local clusterOffsetX, clusterOffsetY = GetExactNodeClusterOffset(
                nodeFrame.pmExactNodeCluster, math.max(6, iconSize * 0.75))
            local drawX = (node.x * w) + clusterOffsetX
            local drawY = (-node.y * h) + clusterOffsetY
            if positionChanged or nodeFrame.pmWorldDrawX ~= drawX or nodeFrame.pmWorldDrawY ~= drawY then
                nodeFrame:ClearAllPoints()
                nodeFrame:SetPoint("CENTER", worldMapOverlay, "TOPLEFT", drawX, drawY)
                nodeFrame.pmWorldDrawX = drawX
                nodeFrame.pmWorldDrawY = drawY
            end
            if nodeFrame.pmWorldIconSize ~= iconSize then
                nodeFrame:SetSize(hitboxSize, hitboxSize)
                nodeFrame.icon:SetSize(iconSize, iconSize)
                nodeFrame.pmWorldIconSize = iconSize
            end
            if nodeFrame.pmWorldIconOpacity ~= iconOpacity then
                nodeFrame.icon:SetAlpha(iconOpacity)
                nodeFrame.pmWorldIconOpacity = iconOpacity
            end
            nodeFrame:Show()
        else
            nodeFrame:Hide()
        end
    end
    worldMapOverlay.pmLayoutMapID = mapID
    worldMapOverlay.pmLayoutWidth = w
    worldMapOverlay.pmLayoutHeight = h
    worldMapOverlay.pmLayoutIconSize = iconSize
    worldMapOverlay.pmLayoutHitboxSize = hitboxSize
    worldMapOverlay.pmLayoutIconOpacity = iconOpacity
    worldMapOverlay.pmLayoutDirty = nil
end

-- ----------------------------------------------------------------------------
-- WORLD MAP RENDERING (WITH CIRCULAR HEADNOD LOGIC)
-- ----------------------------------------------------------------------------
function addon.Heatmap:RefreshWorldMap()
    local canvas
    worldMapOverlay, canvas = EnsureWorldMapOverlay()
    if not worldMapOverlay then return end
    
    if not PathmakerDB or not PathmakerDB.nodes then
        if activeWorldMapNodes then
            for _, f in ipairs(activeWorldMapNodes) do RecycleNodeFrame(f) end
            wipe(activeWorldMapNodes)
        end
        return
    end

    if PathmakerDB.settings and PathmakerDB.settings.hideHeatmap then 
        if activeWorldMapNodes then
            for _, f in ipairs(activeWorldMapNodes) do RecycleNodeFrame(f) end
            wipe(activeWorldMapNodes)
        end
        return 
    end

    local mapID = WorldMapFrame:GetMapID()
    if not mapID or not PathmakerDB.nodes[mapID]
        or (addon.Compat and not addon.Compat:IsMapExpansionVisible(mapID))
    then
        if activeWorldMapNodes then
            for _, f in ipairs(activeWorldMapNodes) do RecycleNodeFrame(f) end
            wipe(activeWorldMapNodes)
        end
        return
    end

    local w, h = 0, 0
    if canvas and canvas.GetSize then
        w, h = canvas:GetSize()
    end
    if (not w or not h or w <= 1 or h <= 1) and worldMapOverlay.GetSize then
        w, h = worldMapOverlay:GetSize()
    end
    w, h = tonumber(w) or 0, tonumber(h) or 0
    if w <= 1 or h <= 1 then
        if C_Timer and C_Timer.After and not self.worldMapSizeRetry then
            self.worldMapSizeRetry = true
            C_Timer.After(0.2, function()
                self.worldMapSizeRetry = nil
                if ScheduleWorldMapRefresh then ScheduleWorldMapRefresh() end
            end)
        end
        return
    end

    if activeWorldMapNodes then
        for _, f in ipairs(activeWorldMapNodes) do RecycleNodeFrame(f) end
        wipe(activeWorldMapNodes)
    end

    worldMapOverlay:SetSize(w, h)
    if worldMapOverlay.SetAlpha then worldMapOverlay:SetAlpha(1) end
    if worldMapOverlay.SetScale then worldMapOverlay:SetScale(1) end
    
    local renderNodes = {}
    local worldMapHasMining = PlayerHasProfession("Mining")
    local worldMapHasHerbalism = PlayerHasProfession("Herb")

    for i, node in ipairs(self:GetVisibleNodesForMap(mapID)) do
        if IsWorldMapNodeTypeEnabled(node, worldMapHasMining, worldMapHasHerbalism) then
            renderNodes[#renderNodes + 1] = {
                node = node,
                sourceIndex = i,
                key = StableNodeKey(node, mapID),
            }
        end
    end

    table.sort(renderNodes, function(a, b)
        if a.key == b.key then return a.sourceIndex < b.sourceIndex end
        return a.key < b.key
    end)

    local clusteredNodes = {}
    for _, entry in ipairs(renderNodes) do clusteredNodes[#clusteredNodes + 1] = entry.node end
    local exactClusterLayout = BuildExactNodeClusterLayout(clusteredNodes, mapID)

    local worldMapIconSize, worldMapHitboxSize, worldMapIconOpacity = GetWorldMapNodeRenderSize()
    for renderIndex, entry in ipairs(renderNodes) do
        local node = entry.node
        do
            do
                local px = node.x * w
                local py = -node.y * h
                    local exactCluster = exactClusterLayout[node]
                    local offsetX, offsetY = GetExactNodeClusterOffset(
                        exactCluster, math.max(6, worldMapIconSize * 0.75))
                    local drawX = px + offsetX
                    local drawY = py + offsetY
                    local f = GetNodeFrame(worldMapOverlay, false)
                    f.nodeData = node
                    f.pmNodeMapID = mapID
                    f.pmExactNodeCluster = exactCluster
                    f.pmWorldOverlapOffsetX = offsetX
                    f.pmWorldOverlapOffsetY = offsetY
                    f.pmWorldDrawX = drawX
                    f.pmWorldDrawY = drawY
                    f:SetPoint("CENTER", worldMapOverlay, "TOPLEFT", drawX, drawY)
                    f:SetSize(worldMapHitboxSize, worldMapHitboxSize)
                    f.icon:SetSize(worldMapIconSize, worldMapIconSize)
                    f.icon:SetAlpha(worldMapIconOpacity)
                    f.pmWorldIconSize = worldMapIconSize
                    f.pmWorldIconOpacity = worldMapIconOpacity
                    
                    if worldMapOverlay.GetFrameStrata then f:SetFrameStrata(worldMapOverlay:GetFrameStrata()) end
                    -- Fixed flicker: Adding 'i' to guarantee deterministic overlapping depth per node
                    f:SetFrameLevel(math.min(worldMapOverlay:GetFrameLevel() + 1 + (renderIndex % 200), 9900)) 
                    if f.SetAlpha then f:SetAlpha(1) end
                    if f.Raise then f:Raise() end
                    
                    f.icon:Show()
                    f.ring:Hide()
                    
                    local texture = ResolveNodeIcon(node)
                    f.icon:SetTexture(texture)
                    
                    f:EnableMouse(true)
                    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(true) end
                    if f.SetMouseMotionEnabled then f:SetMouseMotionEnabled(true) end
                    f:RegisterForClicks("AnyDown")

                    f:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(node.name or node.specificName or node.type or "Unknown")
                        local gatherCount = tonumber(node.gatherCount) or 0
                        if gatherCount > 0 then
                            GameTooltip:AddLine("Gathered: " .. gatherCount .. (gatherCount == 1 and " time" or " times"), 0.7, 0.9, 1)
                        end
                        local lastGathered = tonumber(node.lastGathered)
                        if lastGathered and date then
                            GameTooltip:AddLine("Last gathered: " .. date("%Y-%m-%d %H:%M", lastGathered), 0.7, 0.7, 0.7)
                        end
                        GameTooltip:AddLine("Right-Click to Delete", 1, 0.2, 0.2)
                        GameTooltip:Show()
                    end)
                    f:SetScript("OnLeave", function(self)
                        if not GameTooltip.IsOwned or GameTooltip:IsOwned(self) then
                            GameTooltip:Hide()
                            if GameTooltip.ClearLines then GameTooltip:ClearLines() end
                            if GameTooltip.SetAlpha then GameTooltip:SetAlpha(1) end
                        end
                    end)
                    
                    f:SetScript("OnClick", function(self, button)
                        if button == "RightButton" then
                            local nodes = PathmakerDB.nodes[mapID]
                            local removed = RemoveExactNodeStack(nodes, node, addon.Heatmap)
                            if removed > 0 then
                                local logName = node.specificName or node.name or node.type or "Unknown"
                                local hideMsg = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.disableMsgNodeDelete
                                if not hideMsg then
                                    print("|cff00ff00PathMaker:|r Deleted Node: " .. logName .. " x1")
                                end
                                GameTooltip:Hide()
                                addon.Heatmap:InvalidateVisibleNodeCache()
                                addon.Heatmap:RefreshWorldMap() 
                            end
                        end
                    end)
                    
                    table.insert(activeWorldMapNodes, f)
            end
        end
    end
    worldMapOverlay.pmLayoutDirty = true
    if UpdateActiveWorldMapNodeLayout then UpdateActiveWorldMapNodeLayout() end
end

function addon.Heatmap:UpdateWorldMap()
    return self:RefreshWorldMap()
end

-- ----------------------------------------------------------------------------
-- EVENT HANDLING
-- ----------------------------------------------------------------------------
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        addon.Heatmap:InitDB()
        FixDatabaseIcons() 
        if PathmakerDB.nodeDatabaseVersion ~= NODE_DATABASE_VERSION then
            local removed = addon.Heatmap:CleanupDuplicateNodes()
            PathmakerDB.nodeDatabaseVersion = NODE_DATABASE_VERSION
            if removed > 0 and not (PathmakerDB.settings and PathmakerDB.settings.disableMsgDedupe) then
                print(string.format("|cff00ff00PathMaker:|r Merged %d duplicate node point(s).", removed))
            end
        end
        WatchWorldMapSettling(6)
        
        minimapOverlay = CreateFrame("Frame", "PathmakerHeatmapMini", Minimap)
        minimapOverlay:SetAllPoints()
        minimapOverlay:SetFrameStrata("LOW")
        minimapOverlay:SetFrameLevel(Minimap:GetFrameLevel() + 50)
        minimapOverlay:SetClipsChildren(true) 
        
        local canvas
        worldMapOverlay, canvas = EnsureWorldMapOverlay()
        if not worldMapOverlay then return end
        
        worldMapOverlay:SetScript("OnSizeChanged", function(self, width, height)
            if self.lastW == width and self.lastH == height then return end
            self.lastW = width
            self.lastH = height
            if WatchWorldMapSettling then WatchWorldMapSettling(0.7) end
        end)
        
        if WorldMapFrame.Maximize then
            hooksecurefunc(WorldMapFrame, "Maximize", function() 
                WatchWorldMapSettling(3)
                ScheduleWorldMapRefresh()
            end)
        end
        if WorldMapFrame.Minimize then
            hooksecurefunc(WorldMapFrame, "Minimize", function() 
                WatchWorldMapSettling(3)
                ScheduleWorldMapRefresh()
            end)
        end
        
        if WorldMapFrame.HookScript then
            WorldMapFrame:HookScript("OnShow", function()
                WatchWorldMapSettling(3)
                ScheduleWorldMapRefresh()
            end)
        end
        
        if type(WorldMapFrame.OnMapChanged) == "function" then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
                 WatchWorldMapSettling(2)
                 ScheduleWorldMapRefresh()
            end)
        end
        
        ScheduleWorldMapRefresh()
        
    elseif event == "SKILL_LINES_CHANGED" then
        local function RefreshProfessionVisibility()
            addon.Heatmap:InvalidateVisibleNodeCache()
            addon.Heatmap:ForceUpdate()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.1, RefreshProfessionVisibility)
        else RefreshProfessionVisibility() end

    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, castGUID, spellID = ...
        if unit == "player" then
            if GetGatheringType(spellID) then
                lastGatherTarget = target 
                lastGatherWasMob = false
                
                if target then
                    if UnitExists("target") and UnitName("target") == target then
                        local guid = UnitGUID("target")
                        if guid and (string.find(guid, "Creature") or string.find(guid, "Vehicle")) then
                            lastGatherWasMob = true
                        end
                    elseif UnitExists("mouseover") and UnitName("mouseover") == target then
                        local guid = UnitGUID("mouseover")
                        if guid and (string.find(guid, "Creature") or string.find(guid, "Vehicle")) then
                            lastGatherWasMob = true
                        end
                    end
                end
            end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellID = ...
        if unit == "player" then
            local typeName = GetGatheringType(spellID)
            
            if typeName then
                local specific = lastGatherTarget
                local wasMob = lastGatherWasMob
                lastGatherTarget = nil
                lastGatherWasMob = false
                
                if wasMob or not specific or not IsValidNode(specific) then
                    return 
                end
                
                if NormalizeGatheringType(typeName) == "Mining" then RecordNode("Mining", specific)
                elseif NormalizeGatheringType(typeName) == "Herb" then RecordNode("Herb", specific) end
            end
        end
    end
end)

addon.Compat:SetGuardedUpdate(frame, "Gathering nodes", function(self, elapsed)
    -- Canvas zoom animations can change effective scale every frame. The
    -- layout function exits immediately when nothing changed, but compensates
    -- icon dimensions on each animation step so pins never pulse or drift.
    if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
        and activeWorldMapNodes and #activeWorldMapNodes > 0
        and UpdateActiveWorldMapNodeLayout
    then
        UpdateActiveWorldMapNodeLayout()
    end

    if self.worldMapSettleUntil and GetTime() < self.worldMapSettleUntil then
        self.worldMapSettleTimer = (self.worldMapSettleTimer or 0) + elapsed
        if self.worldMapSettleTimer >= 0.08 then
            self.worldMapSettleTimer = 0
            if WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
                and UpdateActiveWorldMapNodeLayout
            then
                UpdateActiveWorldMapNodeLayout()
            end
        end
    elseif self.worldMapSettleUntil then
        self.worldMapSettleUntil = nil
        self.worldMapSettleTimer = nil
        if UpdateActiveWorldMapNodeLayout then UpdateActiveWorldMapNodeLayout() end
    end

    if addon.isFarmMode then
        if not self.farmHeatmapHidden then
            self.farmHeatmapHidden = true
            addon.Heatmap:UpdateMinimap(0)
        end
        return
    end

    self.farmHeatmapHidden = false
    -- Farm Mode keeps visible overlays locked to the terrain every rendered
    -- frame. Do the same for the normal minimap's small active node set.
    if activeMinimapNodes and #activeMinimapNodes > 0
        and addon.Heatmap and addon.Heatmap.UpdateActiveMinimapNodePositions
    then
        addon.Heatmap:UpdateActiveMinimapNodePositions()
    end
    self.updateTimer = (self.updateTimer or 0) + elapsed
    if self.updateTimer < MINIMAP_UPDATE_INTERVAL then return end
    self.updateTimer = 0
    addon.Heatmap:UpdateMinimap(elapsed)
end)

function addon.Heatmap:ForceUpdate()
    self:InvalidateVisibleNodeCache()
    self.minimapNodesDirty = true
    self.lastMapID = nil 
    self.drawnWorldPins = {}
    
    -- FIXED BUG: the original file called a non-existent function self:UpdateWorldMap()
    if type(self.RefreshWorldMap) == "function" then
        self:RefreshWorldMap()
    end
    if type(self.UpdateMinimap) == "function" then
        self:UpdateMinimap(1) 
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("SKILL_LINES_CHANGED")
frame:RegisterEvent("UNIT_SPELLCAST_SENT")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
