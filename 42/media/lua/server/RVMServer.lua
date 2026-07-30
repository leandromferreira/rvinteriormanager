-- RV Interior Manager — Server side (core)
-- Reads the base mod's ModData and maintains a denormalized table of
-- vehicle↔room relationships, including the last known vehicle position.
-- Position updates use a dirty-flag + periodic-flush strategy:
--   - modData.Vehicles (base mod) is polled every ~1 s
--   - Only vehicles that moved > 0.5 tiles are marked dirty
--   - Dirty positions are flushed to our own ModData every ~10 s
--
-- This core file owns the RVMServer namespace, the shared mutable state
-- (posCache/dirtySet) and file-path constants, the bootstrap/ticker, and the
-- relationship builder. The remaining logic is split across the
-- RVMServer_<Section>.lua files, which load after this one (alphabetical:
-- '.' sorts before '_') and attach their functions to RVMServer:
--   _Tracking     — position tracking + idle cleanup + logging
--   _Persistence  — vehicle-type file I/O + override application
--   _Operations   — associate/dissociate + GetInToRV sandbox
--   _Admin        — enter/exit events + admin command dispatch + data queries
-- Convention: functions called from another file are exposed as RVMServer.fn
-- and invoked as RVMServer.fn() across file boundaries; same-file calls use the
-- plain local. Reassigned shared state (dirtySet) is always RVMServer.dirtySet.

if not isServer() then return end

require("RVMShared")

RVMServer = RVMServer or {}

-- ============================================================
-- In-memory state (shared across the RVMServer_* files)
-- ============================================================
RVMServer.posCache = RVMServer.posCache or {}   -- [rvId] = { x, y, z }   last position written to ModData
RVMServer.dirtySet = RVMServer.dirtySet or {}   -- [rvId] = true            needs flush

-- File-path constants (shared with _Persistence and _Admin).
-- standard_vehiclestype.txt  — clean defaults written once on each server start
--                              (before any admin overrides are applied)
-- vehicles_type_changes.txt  — admin overrides; survives world wipes
-- B42.20 added an extension allowlist to getFileWriter (ini/cfg/txt/log only);
-- both files used to be .lua and getFileWriter would silently return nil for
-- them. CHANGES_FILE_OLD is the pre-42.20 name, kept for one-time migration
-- of existing overrides in RVMServer_Persistence.loadChangesFile — it is only
-- ever read (getFileReader has no such restriction), never written.
RVMServer.STANDARD_FILE     = "RVM/standard_vehiclestype.txt"
RVMServer.CHANGES_FILE      = "vehicles_type_changes.txt"
RVMServer.CHANGES_FILE_OLD  = "vehicles_type_changes.lua"

local tickCount = 0
local idleTickCount = 0

local CHECK_TICKS        = 60       -- ~1 s at 60 ticks/s
local FLUSH_TICKS        = 600      -- ~10 s
local IDLE_CHECK_TICKS   = 216000   -- ~60 min at 60 ticks/s

-- ============================================================
-- buildRelationships()
-- ============================================================
-- Reads the base mod's ModData and returns a flat table of every
-- active vehicle↔room link, enriched with the last known position.
--
-- Shape of each entry:
--   {
--       rvVehicleUniqueId = "47382910",
--       typeKey           = "normal",
--       dataKey           = "AssignedRooms",
--       room              = { x, y, z },          -- interior room coords
--       lastPos           = { x, y, z } | nil,    -- from modData.Vehicles
--   }
-- ============================================================
local function buildRelationships()
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return {} end

    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local vehicles = base.Vehicles or {}
    local rels     = {}

    for typeKey, _ in pairs(RV.VehicleTypes) do
        local dataKey  = (typeKey == "normal") and "AssignedRooms"
                                               or  ("AssignedRooms" .. typeKey)
        local assigned = base[dataKey] or {}

        for rvId, roomCoords in pairs(assigned) do
            local rvIdStr = tostring(rvId)
            -- Skip: a numeric key may be a duplicate of an already-processed string key.
            if not rels[rvIdStr] then
                local lastPos = vehicles[rvIdStr] or vehicles[rvId]

                rels[rvIdStr] = {
                    rvVehicleUniqueId = rvIdStr,
                    typeKey           = typeKey,
                    dataKey           = dataKey,
                    room              = { x = roomCoords.x, y = roomCoords.y, z = roomCoords.z },
                    lastPos           = lastPos and { x = lastPos.x, y = lastPos.y, z = lastPos.z },
                }
            end
        end
    end

    return rels
end
RVMServer.buildRelationships = buildRelationships

-- ============================================================
-- OnTick handler
-- ============================================================
local function onTick()
    tickCount     = tickCount     + 1
    idleTickCount = idleTickCount + 1

    if tickCount % CHECK_TICKS == 0 then
        RVMServer.checkPositions()
    end

    if tickCount % FLUSH_TICKS == 0 then
        RVMServer.flushDirty()
        tickCount = 0
    end

    if idleTickCount >= IDLE_CHECK_TICKS then
        RVMServer.checkIdleRooms()
        idleTickCount = 0
    end
end

-- ============================================================
-- Bootstrap — runs once on world init
-- ============================================================
-- Builds the initial relationship table from whatever is already
-- in the base mod's ModData (handles pre-existing saves).
local function bootstrap()
    print("[RVM] bootstrap: starting")

    local rels = buildRelationships()
    local d    = ModData.getOrCreate(RVM.POS_DATA_KEY)

    -- Preserve dates and cached vehicle names from a previous session.
    local preserved = 0
    if d.relationships then
        for rvId, rel in pairs(d.relationships) do
            if rels[rvId] then
                rels[rvId].dateLinked    = rel.dateLinked
                rels[rvId].lastEnterDate = rel.lastEnterDate
                rels[rvId].lastOutDate   = rel.lastOutDate
                rels[rvId].vehicleName   = rel.vehicleName
                preserved = preserved + 1
            end
        end
    end

    d.relationships = rels
    d.knownVehicleScripts = nil   -- stale accumulator, no longer used

    -- Stamp dateLinked for any pre-existing entry that still has no date.
    -- This happens on mid-save installs: the base mod has assignments, but
    -- our mod has never seen them before.  Using server-start time as the
    -- reference ensures the idle-cleanup feature has a baseline for every
    -- vehicle from the moment this mod is first loaded.
    local now = os.date("%d/%m/%Y %H:%M")
    local stamped = 0
    for _, rel in pairs(rels) do
        if not rel.dateLinked then
            rel.dateLinked = now
            stamped = stamped + 1
        end
    end
    if stamped > 0 then
        print("[RVM] bootstrap: stamped dateLinked=" .. now .. " for " .. stamped .. " pre-existing assignment(s)")
    end

    -- Prime the position cache so the first check has a baseline.
    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local vehicles = base.Vehicles or {}
    local cached   = 0
    for rvId, pos in pairs(vehicles) do
        RVMServer.posCache[tostring(rvId)] = { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
        cached = cached + 1
    end

    local relCount = 0
    for _ in pairs(rels) do relCount = relCount + 1 end

    print("[RVM] bootstrap: relationships=" .. relCount
        .. " preserved=" .. preserved
        .. " posCache=" .. cached)

    -- Save clean defaults BEFORE applying any overrides.
    RVMServer.saveStandardTypes()
    RVMServer.initRvmLog()

    -- Load admin overrides: file takes priority (survives wipes), fall back to ModData.
    local fileOverrides = RVMServer.loadChangesFile()
    if fileOverrides then
        local n = 0; for _ in pairs(fileOverrides) do n = n + 1 end
        print("[RVM] bootstrap: loaded scriptOverrides from file (" .. n .. " type(s))")
        d.scriptOverrides = fileOverrides
    end
    if d.scriptOverrides then
        RVMServer.applyAllOverridesClean(d.scriptOverrides)
        local n = 0; for _ in pairs(d.scriptOverrides) do n = n + 1 end
        print("[RVM] bootstrap: applied scriptOverrides for " .. n .. " type(s)")
    end

    Events.OnTick.Add(onTick)

    -- Run idle cleanup once on world load (in addition to the periodic hourly check).
    RVMServer.checkIdleRooms()

    print("[RVM] bootstrap: done")
end

-- ModData is not available at OnInitWorld — the save data is loaded
-- after the world is initialised.  Poll each tick until the base mod's
-- AssignedRooms key exists (or 300 ticks have passed as a safety net),
-- then run bootstrap once and remove this listener.
local bootstrapWaitTicks = 0
local function waitForModData()
    bootstrapWaitTicks = bootstrapWaitTicks + 1
    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local hasData  = base.AssignedRooms ~= nil
    local timedOut = bootstrapWaitTicks >= 300   -- ~5 s safety net

    if hasData or timedOut then
        Events.OnTick.Remove(waitForModData)
        if timedOut and not hasData then
            print("[RVM] bootstrap: ModData not available after 300 ticks — running anyway (fresh save?)")
        end
        bootstrap()
    end
end

Events.OnInitWorld.Add(function()
    Events.OnTick.Add(waitForModData)
end)
