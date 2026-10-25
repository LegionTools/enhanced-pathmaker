local addonName, addon = ...

addon.Compat = addon.Compat or {}
local Compat = addon.Compat

-- A failed OnUpdate otherwise retries every rendered frame. Keep the first
-- traceback and stop only that callback until /reload; report it normally once.
Compat.updateErrors = {}
function Compat:SetGuardedUpdate(frame, label, callback)
    local updateFrame, updateElapsed
    local function Run() callback(updateFrame, updateElapsed) end
    local function Capture(message)
        local trace = tostring(message)
        if debugstack then trace = trace .. "\n" .. debugstack(2, 20, 20) end
        return trace
    end
    frame:SetScript("OnUpdate", function(owner, elapsed)
        if self.updateErrors[label] then return end
        updateFrame, updateElapsed = owner, elapsed
        local ok, trace = xpcall(Run, Capture)
        updateFrame, updateElapsed = nil, nil
        if ok then return end
        self.updateErrors[label] = trace
        print("|cffff6060PathMaker: " .. label .. " updates paused after a Lua error. Use /pmdebug copy before /reload.|r")
        local handler = geterrorhandler and geterrorhandler()
        if handler then pcall(handler, trace) end
    end)
end

function Compat:IsFiniteNumber(value)
    if issecretvalue and issecretvalue(value) then return false end
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local _, build, _, interfaceVersion = GetBuildInfo()
interfaceVersion = tonumber(interfaceVersion) or 0

Compat.interfaceVersion = interfaceVersion
Compat.build = build
Compat.isForever = interfaceVersion == 16001
Compat.isRetail = not Compat.isForever and (interfaceVersion >= 100000 or (WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE))
Compat.isClassicEra = not Compat.isForever and interfaceVersion >= 10000 and interfaceVersion < 20000
Compat.isTBC = interfaceVersion >= 20000 and interfaceVersion < 30000
-- Pre-Battle for Azeroth (no C_Map namespace at all, patch 7.0-7.3.x).
Compat.isLegion = interfaceVersion >= 70000 and interfaceVersion < 80000
Compat.flavor = Compat.isForever and "WoW Forever Beta" or Compat.isRetail and "Retail"
    or (Compat.isTBC and "Classic TBC" or (Compat.isLegion and "Legion" or (Compat.isClassicEra and "Classic Era" or "Classic")))

-- C_Map does not exist before Battle for Azeroth 8.0.1 - this client
-- (Legion and earlier) has no C_Map namespace at all. The rest of the addon
-- calls C_Map.* directly (120 call sites, confirmed), so rather than
-- rewriting every one of them, shim just the *position/identity* subset
-- that's actually load-bearing, backed by Legion's legacy global map API.
-- Map-art-texture functions (GetMapArtLayers etc.) are deliberately NOT
-- shimmed here - every real caller already guards them with
-- `if C_Map and C_Map.GetMapArtLayers then`, so they degrade gracefully,
-- and the one unguarded caller (Tools/RetailMapCapture.lua) is excluded
-- from this client's .toc entirely.
if not _G.C_Map then
    local LegionMap = {}
    _G.C_Map = LegionMap

    -- Flat WorldMapAreaIDs, reused from LEGION_MAP_IDS defined below this
    -- block logically but needed here first - duplicated as a small local
    -- zone->continent table since that's the only relationship this shim
    -- actually needs (not the full set membership check).
    local CONTINENT_FOR_ZONE = {
        -- Broken Isles zones -> Broken Isles continent
        [1014] = 1007, [1015] = 1007, [1017] = 1007, [1018] = 1007, [1021] = 1007,
        [1024] = 1007, [1033] = 1007, [1098] = 1007,
        -- Argus zones -> Argus continent
        [1135] = 1184, [1170] = 1184, [1171] = 1184,
    }
    local CONTINENT_IDS = { [1007] = true, [1184] = true }

    -- unit is accepted but ignored - every real call site in this addon
    -- passes "player" literally (confirmed via grep across all 11 files
    -- using C_Map), so there is no live-game need for party/raid support.
    function LegionMap.GetBestMapForUnit(unit)
        SetMapToCurrentZone()
        return GetCurrentMapAreaID()
    end

    function LegionMap.GetMapInfo(mapID)
        if not mapID then return nil end
        local name = GetMapNameByID(mapID)
        if not name then return nil end
        local parentMapID = CONTINENT_FOR_ZONE[mapID]
        local mapType = CONTINENT_IDS[mapID] and (Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2)
            or (Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3)
        return { mapID = mapID, name = name, parentMapID = parentMapID, mapType = mapType }
    end

    -- Legacy GetPlayerMapPosition is stateful: it reads whatever map was
    -- last set via SetMapByID/SetMapToCurrentZone, not an explicit mapID
    -- argument, and returns two plain 0-1 numbers rather than a Vector2D.
    function LegionMap.GetPlayerMapPosition(mapID, unit)
        if not mapID then return nil end
        SetMapByID(mapID)
        local x, y = GetPlayerMapPosition(unit or "player")
        if not x or not y or (x == 0 and y == 0) then return nil end
        return CreateVector2D(x, y)
    end

    -- Only continent -> zone enumeration is needed (recursive is ignored;
    -- there is no 3rd level in scope for Legion/Argus content).
    function LegionMap.GetMapChildren(mapID, mapType, recursive)
        local results = {}
        if mapID == 1007 or mapID == 1184 then
            for zoneID, continentID in pairs(CONTINENT_FOR_ZONE) do
                if continentID == mapID then results[#results + 1] = { mapID = zoneID } end
            end
        elseif mapID == 947 then
            -- Compat:GetMapCatalog's root call.
            results[#results + 1] = { mapID = 1007 }
            results[#results + 1] = { mapID = 1184 }
        end
        return results
    end

    -- No real inter-floor/cross-map world-position conversion exists
    -- pre-8.0.1. Returning nil makes every guarded caller (Compat's own
    -- GetUnitMapPosition, UI.lua's GetMapWorldScale) fall through to their
    -- existing "unavailable" paths, which they already handle correctly.
    function LegionMap.GetWorldPosFromMapPos(mapID, vector2D)
        return nil, nil
    end

    function LegionMap.GetMapPosFromWorldPos(continentID, worldPos, mapID)
        return nil, nil
    end
end

Compat.expansions = {
    { key = "Forever", label = "Forever (WoW Beta)" },
    { key = "Classic", label = "Classic" },
    { key = "TBC", label = "Burning Crusade" },
    { key = "Wrath", label = "Wrath" },
    { key = "Cataclysm", label = "Cataclysm" },
    { key = "Mists", label = "Mists" },
    { key = "Draenor", label = "Draenor" },
    { key = "Legion", label = "Legion" },
    { key = "BFA", label = "Battle for Azeroth" },
    { key = "Shadowlands", label = "Shadowlands" },
    { key = "Dragonflight", label = "Dragonflight" },
    { key = "TWW", label = "War Within" },
    { key = "Midnight", label = "Midnight" },
}

-- Flat WorldMapAreaIDs for Legion's two continents (Broken Isles and Argus,
-- the only ones in scope for 7.3.5) - confirmed against warcraft.wiki.gg's
-- WorldMapAreaID table, valid arguments to SetMapByID on this client.
local LEGION_MAP_IDS = {
    [1007] = true, [1014] = true, [1015] = true, [1017] = true, [1018] = true,
    [1021] = true, [1024] = true, [1033] = true, [1098] = true,
    [1184] = true, [1135] = true, [1170] = true, [1171] = true,
}

function Compat:GetMapExpansion(mapID)
    -- These UiMapIDs are the Burning Crusade additions on the Classic clients.
    -- Era still exposes metadata for some of them, so client map availability
    -- cannot be inferred from C_Map.GetMapInfo alone. Retail reuses UiMapIDs,
    -- so its node-data expansion table remains authoritative.
    if not self.isRetail and mapID and mapID >= 1941 and mapID <= 1958 then return "TBC" end
    if self.isLegion and mapID and LEGION_MAP_IDS[mapID] then return "Legion" end
    local PMNodes = _G.PathMakerNodes or _G.PathMaker_Nodes
    if PMNodes and type(PMNodes.GetMapExpansion) == "function" then
        local expansion = PMNodes:GetMapExpansion(mapID)
        if expansion then return expansion end
    end
    return self.isForever and "Forever" or "Classic"
end

function Compat:IsExpansionAvailable(expansion)
    if self.isForever then return expansion == "Forever" end
    if expansion == "Forever" then return false end
    if self.isRetail then return true end
    if self.isTBC then return expansion == "Classic" or expansion == "TBC" end
    if self.isLegion then return expansion == "Classic" or expansion == "TBC" or expansion == "Legion" end
    if self.isClassicEra then return expansion == "Classic" end
    return expansion == "Classic"
end

function Compat:IsExpansionVisible(expansion)
    if not self:IsExpansionAvailable(expansion) then return false end
    local visibility = PathmakerDB and PathmakerDB.settings and PathmakerDB.settings.expansionVisibility
    return not visibility or visibility[expansion] ~= false
end

function Compat:IsMapExpansionVisible(mapID)
    return self:IsExpansionVisible(self:GetMapExpansion(mapID))
end

function Compat:IsMapAvailable(mapID)
    return mapID ~= nil and self:IsExpansionAvailable(self:GetMapExpansion(mapID))
end

-- Lua 5.2 moved unpack into table; WoW clients have not all exposed the same alias.
if not _G.unpack and table.unpack then _G.unpack = table.unpack end

function Compat:GetItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    if _G.GetItemIcon then return _G.GetItemIcon(itemID) end
end

function Compat:GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then return info.name end
    end
    if _G.GetSpellInfo then return _G.GetSpellInfo(spellID) end
end

function Compat:IsSpellKnown(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(spellID) end
    if _G.IsSpellKnown then return _G.IsSpellKnown(spellID) end
    return false
end

function Compat:LoadAddOn(name)
    local loader = C_AddOns and C_AddOns.LoadAddOn or _G.LoadAddOn
    if loader then return loader(name) end
end

function Compat:RegisterOptionsPanel(panel)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        self.settingsCategory = category
        return category
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        return panel
    end
end

function Compat:GetNumTrackingTypes()
    local getter = C_Minimap and C_Minimap.GetNumTrackingTypes or _G.GetNumTrackingTypes
    return getter and getter() or 0
end

function Compat:GetTrackingInfo(index)
    local getter = C_Minimap and C_Minimap.GetTrackingInfo or _G.GetTrackingInfo
    if getter then return getter(index) end
end

function Compat:SetTracking(index, enabled)
    local setter = C_Minimap and C_Minimap.SetTracking or _G.SetTracking
    if setter then setter(index, enabled) end
end

function Compat:HasMinimapTracking()
    if _G.GetTrackingTexture then return true end
    local countGetter = C_Minimap and C_Minimap.GetNumTrackingTypes or _G.GetNumTrackingTypes
    local infoGetter = C_Minimap and C_Minimap.GetTrackingInfo or _G.GetTrackingInfo
    return type(countGetter) == "function" and type(infoGetter) == "function"
end

function Compat:GetTrackingTexture()
    if _G.GetTrackingTexture then return _G.GetTrackingTexture() end
    for index = 1, self:GetNumTrackingTypes() do
        local first, texture, active = self:GetTrackingInfo(index)
        if type(first) == "table" then
            if first.active then return first.texture end
        elseif active then
            return texture
        end
    end
end

local function IsUsableMapPosition(pos)
    if issecretvalue and issecretvalue(pos) then return false end
    if not pos then return false end
    local x, y = pos.x, pos.y
    if not Compat:IsFiniteNumber(x) or not Compat:IsFiniteNumber(y) then return false end
    -- The map API can return an empty (0, 0) vector for a map which does not
    -- currently contain the unit, most often after an indoor floor change.
    return x ~= 0 or y ~= 0
end

-- Get a unit position expressed in a specific UiMapID. GetBestMapForUnit can
-- change to a city, cave, or indoor floor while a route still belongs to its
-- original map. Asking for that route map first keeps its coordinate space
-- stable; the world-position conversion is a Retail fallback for maps on which
-- GetPlayerMapPosition temporarily returns nil.
function Compat:GetUnitMapPosition(mapID, unit)
    unit = unit or "player"
    if not mapID or not C_Map then return nil end

    if C_Map.GetPlayerMapPosition then
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, unit)
        if ok and IsUsableMapPosition(pos) then return pos end
    end

    if not (C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos
        and C_Map.GetMapPosFromWorldPos and CreateVector2D)
    then
        return nil
    end

    local sourceMapID = C_Map.GetBestMapForUnit(unit)
    if not sourceMapID or sourceMapID == mapID then return nil end

    local okSource, sourcePos = pcall(C_Map.GetPlayerMapPosition, sourceMapID, unit)
    if not okSource or not IsUsableMapPosition(sourcePos) then return nil end

    local okWorld, continentID, worldPos = pcall(
        C_Map.GetWorldPosFromMapPos,
        sourceMapID,
        CreateVector2D(sourcePos.x, sourcePos.y)
    )
    if not okWorld or not continentID or not worldPos then return nil end

    local okMap, resolvedMapID, convertedPos = pcall(
        C_Map.GetMapPosFromWorldPos,
        continentID,
        worldPos,
        mapID
    )
    if okMap and resolvedMapID == mapID and IsUsableMapPosition(convertedPos) then
        return convertedPos
    end
    return nil
end

-- Filter map-coordinate noise using the unit's world position. Indoor maps and
-- cities can report slowly drifting normalized coordinates while the character
-- is stationary. UnitPosition is available on Retail, Classic Era, and TBC
-- Anniversary and provides a stable movement signal on all three clients.
function Compat:GetStableUnitMapPosition(mapID, unit, state)
    unit = unit or "player"
    state = state or {}
    local sampleTime = GetTime and GetTime() or nil
    local sourceMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit(unit)
    local subZone = GetSubZoneText and GetSubZoneText() or ""
    if sampleTime and state.sampleTime == sampleTime and state.mapID == mapID
        and state.sourceMapID == sourceMapID and state.subZone == subZone
        and state.mapX ~= nil and state.mapY ~= nil
    then
        return { x = state.mapX, y = state.mapY }, state.moving == true
    end
    local pos = self:GetUnitMapPosition(mapID, unit)
    if not pos then return nil, false end

    local worldY, worldX, worldZ, instanceID
    if UnitPosition then
        worldY, worldX, worldZ, instanceID = UnitPosition(unit)
    end
    -- Invalid world samples must not poison the next movement delta. The map
    -- position is still usable, so fall back to it until world samples recover.
    if not self:IsFiniteNumber(worldX) or not self:IsFiniteNumber(worldY)
        or (worldZ ~= nil and not self:IsFiniteNumber(worldZ))
        or (instanceID ~= nil and not self:IsFiniteNumber(instanceID)) then
        worldX, worldY, worldZ, instanceID = nil, nil, nil, nil
    end

    local reset = state.mapID ~= mapID
        or state.sourceMapID ~= sourceMapID or state.subZone ~= subZone
        or state.instanceID ~= instanceID
        or state.mapX == nil or state.mapY == nil

    if reset then
        state.mapID = mapID
        state.sourceMapID, state.subZone = sourceMapID, subZone
        state.instanceID = instanceID
        state.worldX, state.worldY, state.worldZ = worldX, worldY, worldZ
        state.mapX, state.mapY = pos.x, pos.y
        state.sampleTime, state.moving = sampleTime, false
        return { x = state.mapX, y = state.mapY }, false
    end

    local moving = true
    if worldX and worldY and state.worldX and state.worldY then
        local dx = worldX - state.worldX
        local dy = worldY - state.worldY
        local dz = (worldZ or 0) - (state.worldZ or 0)
        moving = ((dx * dx) + (dy * dy) + (dz * dz)) > 0.0001
    end

    state.worldX, state.worldY, state.worldZ = worldX, worldY, worldZ
    if moving then
        state.mapX, state.mapY = pos.x, pos.y
    end
    state.sampleTime, state.moving = sampleTime, moving
    return { x = state.mapX, y = state.mapY }, moving
end

local function GetMapChildren(mapID, mapType, recursive)
    if not C_Map or not C_Map.GetMapChildren then return {} end
    local ok, maps = pcall(C_Map.GetMapChildren, mapID, mapType, recursive)
    return ok and maps or {}
end

local function AddCatalogContinent(catalog, continentID, name)
    if not continentID or not name then return end
    if not catalog.labels[continentID] then
        catalog.order[#catalog.order + 1] = continentID
        catalog.labels[continentID] = name
    end
    catalog.zones[continentID] = catalog.zones[continentID] or {}
end

local function FindCatalogContinent(catalog, mapID, continentType)
    local currentID = mapID
    local fallbackID, fallbackName
    for _ = 1, 24 do
        local info = currentID and C_Map.GetMapInfo(currentID)
        if not info then break end
        if catalog.labels[currentID] or info.mapType == continentType then
            AddCatalogContinent(catalog, currentID, info.name)
            return currentID
        end
        if info.parentMapID and info.parentMapID > 0 and info.parentMapID ~= 947 then
            fallbackID, fallbackName = info.parentMapID, nil
            local parentInfo = C_Map.GetMapInfo(info.parentMapID)
            fallbackName = parentInfo and parentInfo.name
        end
        if not info.parentMapID or info.parentMapID == 0 or info.parentMapID == currentID then break end
        currentID = info.parentMapID
    end
    if fallbackID and fallbackName then
        AddCatalogContinent(catalog, fallbackID, fallbackName)
        return fallbackID
    end
end

-- Add every map carrying bundled PathMaker node data, including cave/subzone
-- maps that C_Map.GetMapChildren(..., Zone) does not return.
local function MergeExternalNodeMaps(catalog, continentType)
    local PMNodes = _G.PathMakerNodes or _G.PathMaker_Nodes
    if not PMNodes or type(PMNodes.GetMapIDs) ~= "function" then return end

    catalog.nodeMapSeen = catalog.nodeMapSeen or {}
    local existingOwner = {}
    for continentID, zones in pairs(catalog.zones) do
        for _, zone in ipairs(zones) do existingOwner[zone.id] = continentID end
    end

    for _, mapID in ipairs(PMNodes:GetMapIDs()) do
        if Compat:IsMapAvailable(mapID) and not catalog.nodeMapSeen[mapID] then
            catalog.nodeMapSeen[mapID] = true
            local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            if info and info.name and not existingOwner[mapID] then
                local continentID = FindCatalogContinent(catalog, mapID, continentType)
                if continentID then
                    catalog.zones[continentID][#catalog.zones[continentID] + 1] = {
                        id = mapID,
                        mapID = mapID,
                        name = info.name,
                        hasNodeData = true,
                    }
                    existingOwner[mapID] = continentID
                end
            end
        end
    end

    for _, zones in pairs(catalog.zones) do
        table.sort(zones, function(a, b)
            if a.name == b.name then return a.id < b.id end
            return a.name < b.name
        end)
    end
    table.sort(catalog.order, function(a, b)
        return (catalog.labels[a] or "") < (catalog.labels[b] or "")
    end)
end

-- Builds a client-native map catalog. This preserves the Classic map IDs while
-- allowing Retail expansions to appear without maintaining a second route UI.
function Compat:GetMapCatalog()
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    if self.mapCatalog then
        MergeExternalNodeMaps(self.mapCatalog, continentType)
        return self.mapCatalog
    end

    local catalog = { order = {}, labels = {}, zones = {} }
    local worldMapID = 947
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local continents = GetMapChildren(worldMapID, continentType, true)

    for _, continent in ipairs(continents) do
        local continentID = continent.mapID
        local info = continentID and C_Map.GetMapInfo(continentID)
        if continentID and info and info.name then
            AddCatalogContinent(catalog, continentID, info.name)

            local seen = {}
            for _, zone in ipairs(GetMapChildren(continentID, zoneType, true)) do
                if zone.mapID and zone.name and not seen[zone.mapID] then
                    seen[zone.mapID] = true
                    catalog.zones[continentID][#catalog.zones[continentID] + 1] = {
                        id = zone.mapID,
                        mapID = zone.mapID,
                        name = zone.name,
                    }
                end
            end
            table.sort(catalog.zones[continentID], function(a, b) return a.name < b.name end)
        end
    end

    MergeExternalNodeMaps(catalog, continentType)
    table.sort(catalog.order, function(a, b) return (catalog.labels[a] or "") < (catalog.labels[b] or "") end)
    self.mapCatalog = catalog
    return catalog
end

function Compat:GetContinentForMap(mapID)
    if not mapID or not C_Map or not C_Map.GetMapInfo then return nil end
    local catalog = self:GetMapCatalog()
    local continents = {}
    for _, continentID in ipairs(catalog.order) do continents[continentID] = true end

    local currentID = mapID
    for _ = 1, 16 do
        if continents[currentID] then return currentID end
        local info = C_Map.GetMapInfo(currentID)
        if not info or not info.parentMapID or info.parentMapID == 0 or info.parentMapID == currentID then break end
        currentID = info.parentMapID
    end
end
