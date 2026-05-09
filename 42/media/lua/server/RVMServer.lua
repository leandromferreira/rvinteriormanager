-- RV Interior Manager — Server side
-- Reads the base mod's ModData and maintains a denormalized table of
-- vehicle↔room relationships, including the last known vehicle position.
-- Position updates use a dirty-flag + periodic-flush strategy:
--   - modData.Vehicles (base mod) is polled every ~1 s
--   - Only vehicles that moved > 0.5 tiles are marked dirty
--   - Dirty positions are flushed to our own ModData every ~10 s

if not isServer() then return end

require("RVMShared")

RVMServer = RVMServer or {}

-- ============================================================
-- In-memory state
-- ============================================================
local posCache  = {}   -- [rvId] = { x, y, z }   last position written to ModData
local dirtySet  = {}   -- [rvId] = true            needs flush
local tickCount = 0

local MOVE_THRESHOLD     = 0.5      -- tiles
local CHECK_TICKS        = 60       -- ~1 s at 60 ticks/s
local FLUSH_TICKS        = 600      -- ~10 s
local IDLE_CHECK_TICKS   = 216000   -- ~60 min at 60 ticks/s

local idleTickCount = 0

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

-- ============================================================
-- Position tracking — dirty flag + periodic flush
-- ============================================================
-- Compares modData.Vehicles (base mod, updated by base mod logic)
-- against in-memory cache and marks moved vehicles dirty.
local function checkPositions()
    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local vehicles = base.Vehicles or {}

    for rvId, pos in pairs(vehicles) do
        local last = posCache[rvId]

        if not last
            or math.abs((pos.x or 0) - last.x) > MOVE_THRESHOLD
            or math.abs((pos.y or 0) - last.y) > MOVE_THRESHOLD
        then
            posCache[rvId] = { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
            dirtySet[rvId] = true
        end
    end
end

-- Writes dirty positions into our own ModData.
local function flushDirty()
    -- Avoid next() which is nil in some PZ Kahlua builds.
    local hasAny = false
    for _ in pairs(dirtySet) do hasAny = true; break end
    if not hasAny then return end

    local d = ModData.getOrCreate(RVM.POS_DATA_KEY)
    d.relationships = d.relationships or {}

    for rvId in pairs(dirtySet) do
        if d.relationships[rvId] then
            d.relationships[rvId].lastPos = posCache[rvId]
        end
    end

    dirtySet = {}
end

-- ============================================================
-- Idle room cleaner
-- ============================================================
-- Appends msg to ~/Zomboid/lua/RVM/RVM_dissociate.log.
-- getFileWriter resolves paths relative to ~/Zomboid/ and creates subdirs as needed.
local function writeRvmLog(msg)
    local f = getFileWriter("RVM/RVM_dissociate.log", true, false)
    if f then f:write(msg .. "\n"); f:close() end
end

-- Parses "DD/MM/YYYY HH:MM" → os.time value, or nil.
local function parseDateToTime(dateStr)
    if not dateStr then return nil end
    local d, m, y, hh, mm = dateStr:match("(%d+)/(%d+)/(%d+) (%d+):(%d+)")
    if not d then return nil end
    return os.time({
        day   = tonumber(d),  month  = tonumber(m),  year = tonumber(y),
        hour  = tonumber(hh), min    = tonumber(mm),  sec  = 0,
        isdst = false,
    })
end

-- Returns whole days elapsed since dateStr, or nil if unparseable.
local function daysSince(dateStr)
    local t = parseDateToTime(dateStr)
    if not t then return nil end
    return math.floor((os.time() - t) / 86400)
end

local function checkIdleRooms()
    local svars    = SandboxVars and SandboxVars.RVM
    local idleDays = svars and svars.IdleCleanupDays or 0
    if not idleDays or idleDays <= 0 then return end

    local d = ModData.getOrCreate(RVM.POS_DATA_KEY)
    if not d.relationships then return end

    -- Collect candidates first to avoid modifying the table while iterating.
    local toClean = {}
    for rvId, rel in pairs(d.relationships) do
        local refDate = rel.lastEnterDate or rel.dateLinked
        local days    = daysSince(refDate)
        if days and days >= idleDays then
            table.insert(toClean, { rvId = rvId, rel = rel, days = days })
        end
    end

    if #toClean == 0 then return end

    local now = os.date("%d/%m/%Y %H:%M")
    local header = string.format(
        "[%s] [RVM] IdleCleaner: running — threshold=%d day(s), candidates=%d",
        now, idleDays, #toClean)
    print(header)
    writeRvmLog(header)

    for _, item in ipairs(toClean) do
        local rel     = item.rel
        local room    = rel.room
        local roomStr = room and string.format("%d,%d,%d", room.x or 0, room.y or 0, room.z or 0) or "?"
        local vpos    = rel.lastPos
        local vposStr = vpos and string.format("%.0f,%.0f,%.0f", vpos.x or 0, vpos.y or 0, vpos.z or 0) or "?"
        local msg = string.format(
            "[%s] [RVM] DISSOCIATE  trigger=idle  rvId=%s  name=%s  type=%s  room=%s  vehPos=%s  lastEnter=%s  linked=%s  idleDays=%d",
            now,
            tostring(item.rvId),
            tostring(rel.vehicleName  or "?"),
            tostring(rel.typeKey      or "?"),
            roomStr, vposStr,
            tostring(rel.lastEnterDate or "?"),
            tostring(rel.dateLinked    or "?"),
            item.days)
        print(msg)
        writeRvmLog(msg)
        RVMServer.dissociate(item.rvId)
    end

    local footer = string.format(
        "[%s] [RVM] IdleCleaner: done — dissociated=%d", now, #toClean)
    print(footer)
    writeRvmLog(footer)
end

-- ============================================================
-- OnTick handler
-- ============================================================
local function onTick()
    tickCount     = tickCount     + 1
    idleTickCount = idleTickCount + 1

    if tickCount % CHECK_TICKS == 0 then
        checkPositions()
    end

    if tickCount % FLUSH_TICKS == 0 then
        flushDirty()
        tickCount = 0
    end

    if idleTickCount >= IDLE_CHECK_TICKS then
        checkIdleRooms()
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
        posCache[tostring(rvId)] = { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
        cached = cached + 1
    end

    local relCount = 0
    for _ in pairs(rels) do relCount = relCount + 1 end

    print("[RVM] bootstrap: relationships=" .. relCount
        .. " preserved=" .. preserved
        .. " posCache=" .. cached)

    -- Apply script overrides persisted from previous sessions.
    if d.scriptOverrides then
        RVM.applyScriptOverrides(d.scriptOverrides)
        local n = 0; for _ in pairs(d.scriptOverrides) do n = n + 1 end
        print("[RVM] bootstrap: applied scriptOverrides for " .. n .. " type(s)")
    end

    Events.OnTick.Add(onTick)

    -- Run idle cleanup once on world load (in addition to the periodic hourly check).
    checkIdleRooms()

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

-- ============================================================
-- buildNameMap()
-- ============================================================
-- Scan loaded vehicles once and build rvUniqueId → script full name.
-- Must be defined before onClientCommand which calls it.
-- ============================================================
local function buildNameMap()
    local names = {}
    local ok, cell = pcall(getCell)
    if not ok or not cell then return names end
    local ok2, vehicles = pcall(function() return cell:getVehicles() end)
    if not ok2 or not vehicles then return names end

    local iter = vehicles:iterator()
    while iter:hasNext() do
        local v = iter:next()
        if v then
            local uid = v:getModData().projectRV_uniqueId
            if uid then
                local script = v:getScript()
                names[tostring(uid)] = script and script:getFullName() or "?"
            end
        end
    end
    return names
end

-- ============================================================
-- React to base mod enter/exit events
-- ============================================================
-- Both our handler and the base mod's handler run in the same tick.
-- Because the base mod registered OnClientCommand first, its handler
-- runs before ours, so modData.Players[playerId].VehicleId is already
-- set (enterRV) or VehicleId still present (exitRV — GetOutFromRV only
-- clears ActualRoom/RoomType, not VehicleId).
local function onClientCommand(module, command, player, data)
    if module ~= "RVServer" then return end
    if command ~= "enterRV" and command ~= "exitRV" then return end

    print("[RVM] onClientCommand: command=" .. tostring(command)
        .. " player=" .. tostring(player:getUsername()))

    -- Capture the rvId and timestamp now (base mod already ran).
    local capturedRvId, capturedField, capturedVehicleName
    local pmd = player:getModData()
    local playerId = pmd and pmd.projectRV_playerId
    print("[RVM]   playerId=" .. tostring(playerId))
    if playerId then
        local base       = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
        local playerData = base.Players and base.Players[playerId]
        if playerData and playerData.VehicleId then
            capturedRvId  = tostring(playerData.VehicleId)
            capturedField = (command == "enterRV") and "lastEnterDate" or "lastOutDate"
            -- Capture vehicle name while vehicle is still in loaded chunks.
            local nameMap = buildNameMap()
            capturedVehicleName = nameMap[capturedRvId]
            print("[RVM]   capturedRvId=" .. capturedRvId
                .. " capturedField=" .. capturedField
                .. " vehicleName=" .. tostring(capturedVehicleName))
        else
            print("[RVM]   WARNING: playerData or VehicleId missing for playerId=" .. tostring(playerId))
        end
    end
    local capturedDate = os.date("%d/%m/%Y %H:%M")
    print("[RVM]   capturedDate=" .. capturedDate)

    local function rebuild()
        local d = ModData.getOrCreate(RVM.POS_DATA_KEY)

        -- Preserve dates and cross-type marker before wiping relationships.
        local savedDates = {}
        if d.relationships then
            for rvId, rel in pairs(d.relationships) do
                savedDates[rvId] = {
                    dateLinked    = rel.dateLinked,
                    lastEnterDate = rel.lastEnterDate,
                    lastOutDate   = rel.lastOutDate,
                    vehicleName   = rel.vehicleName,
                }
            end
        end

        d.relationships = buildRelationships()

        -- Restore preserved dates and vehicle names.
        for rvId, dates in pairs(savedDates) do
            if d.relationships[rvId] then
                d.relationships[rvId].dateLinked    = dates.dateLinked
                d.relationships[rvId].lastEnterDate = dates.lastEnterDate
                d.relationships[rvId].lastOutDate   = dates.lastOutDate
                d.relationships[rvId].vehicleName   = dates.vehicleName
            end
        end

        -- For entries that appeared brand-new (base mod just assigned them),
        -- set dateLinked now since this is the first time we see them.
        for rvId, rel in pairs(d.relationships) do
            if not rel.dateLinked and not savedDates[rvId] then
                rel.dateLinked = capturedDate
            end
        end

        -- Persist the vehicle name captured while vehicle was still loaded.
        if capturedRvId and capturedVehicleName and d.relationships[capturedRvId] then
            d.relationships[capturedRvId].vehicleName = capturedVehicleName
        end

        -- Apply the new date event (lastEnterDate or lastOutDate).
        if capturedRvId and capturedField and d.relationships[capturedRvId] then
            d.relationships[capturedRvId][capturedField] = capturedDate
        end

        -- If this enterRV created a brand-new assignment (base mod auto-assigned a room),
        -- notify the entering client so their local ModData stays in sync and the context
        -- menu switches to "Dissociate" immediately without waiting for a ModData sync cycle.
        if capturedField == "lastEnterDate" and capturedRvId then
            local rel = d.relationships[capturedRvId]
            if rel and not savedDates[capturedRvId] then
                local notifData = {
                    rvVehicleUniqueId = capturedRvId,
                    typeKey           = rel.typeKey,
                    room              = rel.room,
                }
                -- Broadcast to all admins/moderators so their context menus stay
                -- in sync even when a different player triggered the auto-assign.
                local sent = false
                local okOp, onlinePlayers = pcall(getOnlinePlayers)
                if okOp and onlinePlayers then
                    local it = onlinePlayers:iterator()
                    while it:hasNext() do
                        local p = it:next()
                        if p then
                            local lvl = string.lower(p:getAccessLevel() or "")
                            if lvl == "admin" or lvl == "moderator" then
                                sendServerCommand(p, RVM.MODULE, "vehicleAssigned", notifData)
                                sent = true
                            end
                        end
                    end
                end
                if not sent then
                    sendServerCommand(player, RVM.MODULE, "vehicleAssigned", notifData)
                end
            end
        end

        Events.OnTick.Remove(rebuild)
    end
    Events.OnTick.Add(rebuild)
end

Events.OnClientCommand.Add(onClientCommand)

-- ============================================================
-- buildAdminSync() — lightweight payload sent to admins on connect
-- ============================================================
-- Contains only what the context menu needs: current scripts per type
-- and a flat rvId→{typeKey,room} map of all assignments.
-- ============================================================
local function buildAdminSync()
    local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)

    local scriptsState = {}
    local okRV, RV = pcall(require, "RVVehicleTypes")
    if okRV and RV and RV.VehicleTypes then
        for tk, td in pairs(RV.VehicleTypes) do
            local copy = {}
            for _, s in ipairs(td.scripts or {}) do table.insert(copy, s) end
            scriptsState[tk] = copy
        end
    end

    local assignments = {}
    for rvId, rel in pairs(dPos.relationships or {}) do
        if rel.typeKey and rel.room then
            assignments[tostring(rvId)] = { typeKey = rel.typeKey, room = rel.room }
        end
    end

    return { scriptsState = scriptsState, assignments = assignments }
end

-- Broadcasts the sync payload to every online admin/moderator.
local function broadcastAdminSync()
    local okOp, onlinePlayers = pcall(getOnlinePlayers)
    if not okOp or not onlinePlayers then return end
    local payload = buildAdminSync()
    local it = onlinePlayers:iterator()
    while it:hasNext() do
        local p = it:next()
        if p then
            local lvl = string.lower(p:getAccessLevel() or "")
            if lvl == "admin" or lvl == "moderator" then
                sendServerCommand(p, RVM.MODULE, "adminSync", payload)
            end
        end
    end
end

-- ============================================================
-- Request/response handler — admin panel data
-- ============================================================
-- The client sends sendClientCommand(getPlayer(), RVM.MODULE, "requestData", {})
-- The server responds with sendServerCommand(player, RVM.MODULE,
--   "responseData", payload) where payload has the shape:
--
--   {
--       summary = {
--           ["normal"] = { totalRooms=38, occupied=5, free=33 },
--           ...
--       },
--       assignments = {
--           {
--               rvVehicleUniqueId = "47382910",
--               vehicleId         = 1234,           -- nil if chunk unloaded
--               typeKey           = "normal",
--               room              = { x, y, z },
--               lastPos           = { x, y, z },    -- nil if never recorded
--           },
--           ...
--       },
--   }
-- ============================================================
-- Discovers vehicle script names from loaded world chunks and accumulates them
-- in ModData so the list grows over time across multiple requestData calls.
local function getAllVehicleScripts()
    local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)
    dPos.knownVehicleScripts = dPos.knownVehicleScripts or {}
    local known = dPos.knownVehicleScripts

    -- Scan currently loaded vehicles
    local okCell, cell = pcall(getCell)
    if okCell and cell then
        local okVeh, vehicles = pcall(function() return cell:getVehicles() end)
        if okVeh and vehicles then
            local iter = vehicles:iterator()
            while iter:hasNext() do
                local v = iter:next()
                if v then
                    local s = v:getScript()
                    if s then
                        local name = s:getFullName()
                        if name then known[tostring(name)] = true end
                    end
                end
            end
        end
    end

    -- Always include every script listed in VehicleTypes (covers all RV mods)
    local okRV, RV = pcall(require, "RVVehicleTypes")
    if okRV and RV and RV.VehicleTypes then
        for _, typeDef in pairs(RV.VehicleTypes) do
            if typeDef.scripts then
                for _, s in ipairs(typeDef.scripts) do known[s] = true end
            end
        end
    end

    local names = {}
    for name in pairs(known) do table.insert(names, name) end
    table.sort(names)
    return names
end

local function buildResponse()
    local roomData = RVM.readRoomData()
    if not roomData then return nil end

    local nameMap  = buildNameMap()
    local d        = ModData.getOrCreate(RVM.POS_DATA_KEY)
    local rels     = d.relationships or {}
    local summary  = {}
    local assignments = {}
    local seenRvIds = {}   -- deduplication guard: one row per vehicle

    print("[RVM] buildResponse: building response, relationships stored=" .. (function()
        local n = 0; for _ in pairs(rels) do n = n + 1 end; return n
    end)())

    for typeKey, typeInfo in pairs(roomData) do
        summary[typeKey] = {
            totalRooms = typeInfo.totalRooms,
            occupied   = typeInfo.occupied,
            free       = typeInfo.free,
            roomW      = typeInfo.roomW,
            roomH      = typeInfo.roomH,
        }

        for _, room in ipairs(typeInfo.rooms) do
            if room.rvVehicleUniqueId then
                local rvId = room.rvVehicleUniqueId
                if seenRvIds[rvId] then
                    print("[RVM]   SKIP duplicate rvId=" .. rvId .. " type=" .. typeKey)
                    -- fall through to next room
                else
                seenRvIds[rvId] = true
                local rel  = rels[rvId] or {}

                -- Use live name from loaded chunk, fall back to cached name in relationship.
                local vehicleName = nameMap[rvId] or rel.vehicleName
                -- Persist the name in relationship so it survives chunk unloads.
                if vehicleName and rel.vehicleName ~= vehicleName and rels[rvId] then
                    rels[rvId].vehicleName = vehicleName
                end

                print("[RVM]   record rvId=" .. tostring(rvId)
                    .. " type=" .. tostring(typeKey)
                    .. " name=" .. tostring(vehicleName)
                    .. " lastPos=" .. (rel.lastPos and
                        string.format("%.1f,%.1f", rel.lastPos.x or 0, rel.lastPos.y or 0)
                        or "nil")
                    .. " dateLinked=" .. tostring(rel.dateLinked)
                    .. " lastEnterDate=" .. tostring(rel.lastEnterDate)
                    .. " lastOutDate=" .. tostring(rel.lastOutDate))

                table.insert(assignments, {
                    rvVehicleUniqueId = rvId,
                    vehicleId         = room.vehicleId,
                    vehicleName       = vehicleName,
                    typeKey           = typeKey,
                    room              = { x = room.x, y = room.y, z = room.z },
                    lastPos           = rel.lastPos,
                    dateLinked        = rel.dateLinked,
                    lastEnterDate     = rel.lastEnterDate,
                    lastOutDate       = rel.lastOutDate,
                })
                end  -- else (not seenRvIds)
            end
        end
    end

    print("[RVM] buildResponse: total assignments=" .. #assignments)
    local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)

    -- Send the authoritative current scripts per type so the client can sync
    -- without relying on applyScriptOverrides (needed after reset).
    local scriptsState = {}
    local okRV2, RV2 = pcall(require, "RVVehicleTypes")
    if okRV2 and RV2 and RV2.VehicleTypes then
        for tk, td in pairs(RV2.VehicleTypes) do
            local copy = {}
            for _, s in ipairs(td.scripts or {}) do table.insert(copy, s) end
            scriptsState[tk] = copy
        end
    end

    return { summary = summary, assignments = assignments,
             scriptOverrides = dPos.scriptOverrides or {},
             allVehicleScripts = getAllVehicleScripts(),
             scriptsState = scriptsState }
end

local function onAdminCommand(module, command, player, data)
    if module ~= RVM.MODULE then return end

    if command == "requestAdminSync" then
        local lvl = string.lower(player:getAccessLevel() or "")
        if lvl ~= "admin" and lvl ~= "moderator" then return end
        sendServerCommand(player, RVM.MODULE, "adminSync", buildAdminSync())

    elseif command == "requestData" then
        local lvl = string.lower(player:getAccessLevel() or "")
        if lvl ~= "admin" and lvl ~= "moderator" then
            return
        end
        local response = buildResponse()
        if response then
            sendServerCommand(player, RVM.MODULE, "responseData", response)
        end

    elseif command == "dissociate" then
        if string.lower(player:getAccessLevel() or "") ~= "admin" then return end
        local rvId = data and data.rvVehicleUniqueId
        -- Capture relationship data BEFORE it is deleted.
        local d2  = ModData.getOrCreate(RVM.POS_DATA_KEY)
        local rel = d2.relationships and d2.relationships[tostring(rvId or "")]
        local dissTypeKey = rel and rel.typeKey
        local ok, err, resolvedTypeKey = RVMServer.dissociate(rvId)
        -- resolvedTypeKey may come from AssignedRooms scan when rel was missing
        dissTypeKey = dissTypeKey or resolvedTypeKey
        local now   = os.date("%d/%m/%Y %H:%M")
        local admin = player:getUsername() or "?"
        if ok then
            local name    = rel and rel.vehicleName or "?"
            local room    = rel and rel.room
            local roomStr = room and string.format("%d,%d,%d", room.x or 0, room.y or 0, room.z or 0) or "?"
            local vpos    = rel and rel.lastPos
            local vposStr = vpos and string.format("%.0f,%.0f,%.0f", vpos.x or 0, vpos.y or 0, vpos.z or 0) or "?"
            local msg = string.format(
                "[%s] [RVM] DISSOCIATE  admin=%s  rvId=%s  name=%s  type=%s  room=%s  vehPos=%s",
                now, admin, tostring(rvId or "?"), name, tostring(dissTypeKey or "?"), roomStr, vposStr)
            print(msg)
            writeRvmLog(msg)
            -- Broadcast to all admins so their context menus update immediately.
            local notifData = { rvVehicleUniqueId = tostring(rvId or ""), typeKey = dissTypeKey }
            local okOp, onlinePlayers = pcall(getOnlinePlayers)
            if okOp and onlinePlayers then
                local it = onlinePlayers:iterator()
                while it:hasNext() do
                    local p = it:next()
                    if p then
                        local lvl = string.lower(p:getAccessLevel() or "")
                        if lvl == "admin" or lvl == "moderator" then
                            sendServerCommand(p, RVM.MODULE, "vehicleDissociated", notifData)
                        end
                    end
                end
            end
        else
            print(string.format("[%s] [RVM] DISSOCIATE FAILED  admin=%s  rvId=%s  err=%s",
                now, admin, tostring(rvId or "?"), tostring(err or "?")))
        end
        sendServerCommand(player, RVM.MODULE, "dissociateResult",
            { ok = ok, err = err, rvVehicleUniqueId = rvId, typeKey = dissTypeKey })

    elseif command == "associate" then
        if string.lower(player:getAccessLevel() or "") ~= "admin" then return end
        local rvId        = data and data.rvVehicleUniqueId
        local typeKey     = data and data.typeKey
        local pos         = data and data.vehicleWorldPos
        local vehicleName = data and data.vehicleName
        local selRoom     = data and data.selectedRoom
        local room, err, existingTypeKey, existingRoom = RVMServer.associate(rvId, typeKey, pos, vehicleName, selRoom)
        sendServerCommand(player, RVM.MODULE, "associateResult",
            { ok = room ~= nil, err = err, rvVehicleUniqueId = rvId,
              typeKey = typeKey, room = room,
              existingTypeKey = existingTypeKey,
              existingRoom    = existingRoom })

    elseif command == "forceIdleCheck" then
        local lvl = string.lower(player:getAccessLevel() or "")
        if lvl ~= "admin" and lvl ~= "moderator" then return end
        print("[RVM] forceIdleCheck requested by " .. player:getUsername())
        checkIdleRooms()
        sendServerCommand(player, RVM.MODULE, "idleCheckResult", { ok = true })

    elseif command == "addVehicleScript" then
        if string.lower(player:getAccessLevel() or "") ~= "admin" then return end
        local typeKey = data and data.typeKey
        local script  = data and data.script
        if not typeKey or not script or script == "" then return end

        local okRV, RV = pcall(require, "RVVehicleTypes")
        if not okRV or not RV or not RV.VehicleTypes then return end

        local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)
        dPos.scriptOverrides = dPos.scriptOverrides or {}

        -- Add to the target type (a script may belong to multiple types simultaneously)
        dPos.scriptOverrides[typeKey] = dPos.scriptOverrides[typeKey]
            or { added = {}, removed = {} }
        local ov = dPos.scriptOverrides[typeKey]
        -- Un-remove if it was previously removed from this type
        for i = #ov.removed, 1, -1 do
            if ov.removed[i] == script then table.remove(ov.removed, i); break end
        end
        -- Add to "added" list if not already present
        local found = false
        for _, s in ipairs(ov.added) do if s == script then found = true; break end end
        if not found then table.insert(ov.added, script) end

        RVM.applyScriptOverrides(dPos.scriptOverrides)
        print("[RVM] addVehicleScript: admin=" .. player:getUsername()
            .. " type=" .. typeKey .. " script=" .. script)
        sendServerCommand(player, RVM.MODULE, "scriptOverrideResult", { ok = true })
        broadcastAdminSync()

    elseif command == "removeVehicleScript" then
        if string.lower(player:getAccessLevel() or "") ~= "admin" then return end
        local typeKey = data and data.typeKey
        local script  = data and data.script
        if not typeKey or not script or script == "" then return end

        local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)
        dPos.scriptOverrides = dPos.scriptOverrides or {}
        dPos.scriptOverrides[typeKey] = dPos.scriptOverrides[typeKey] or { added = {}, removed = {} }
        local ov = dPos.scriptOverrides[typeKey]

        -- Remove from "added" list if present
        for i = #ov.added, 1, -1 do
            if ov.added[i] == script then table.remove(ov.added, i); break end
        end
        -- Add to "removed" list if not already present
        local found = false
        for _, s in ipairs(ov.removed) do if s == script then found = true; break end end
        if not found then table.insert(ov.removed, script) end

        RVM.applyScriptOverrides(dPos.scriptOverrides)
        print("[RVM] removeVehicleScript: admin=" .. player:getUsername()
            .. " type=" .. typeKey .. " script=" .. script)
        sendServerCommand(player, RVM.MODULE, "scriptOverrideResult", { ok = true })
        broadcastAdminSync()

    elseif command == "getFreeRooms" then
        local lvl = string.lower(player:getAccessLevel() or "")
        if lvl ~= "admin" and lvl ~= "moderator" then return end
        -- Accept either typeKeys (array) or legacy single typeKey
        local typeKeys = data and data.typeKeys
        if not typeKeys and data and data.typeKey then typeKeys = { data.typeKey } end
        if not typeKeys or #typeKeys == 0 then return end
        local ok, RV = pcall(require, "RVVehicleTypes")
        if not ok or not RV or not RV.VehicleTypes then return end
        local base = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
        local free = {}
        for _, tk in ipairs(typeKeys) do
            local typeDef = RV.VehicleTypes[tk]
            if typeDef then
                local dataKey  = (tk == "normal") and "AssignedRooms" or ("AssignedRooms" .. tk)
                local assigned = base[dataKey] or {}
                local occupied = {}
                for _, roomCoords in pairs(assigned) do
                    local k = string.format("%d-%d-%d",
                        roomCoords.x or 0, roomCoords.y or 0, roomCoords.z or 0)
                    occupied[k] = true
                end
                for idx, roomCoords in ipairs(typeDef.rooms or {}) do
                    local k = string.format("%d-%d-%d",
                        roomCoords.x or 0, roomCoords.y or 0, roomCoords.z or 0)
                    if not occupied[k] then
                        table.insert(free, {
                            index  = idx,
                            x      = roomCoords.x, y = roomCoords.y, z = roomCoords.z,
                            typeKey = tk,
                            roomW  = typeDef.roomWidth,
                            roomH  = typeDef.roomHeight,
                        })
                    end
                end
            end
        end
        sendServerCommand(player, RVM.MODULE, "freeRoomsResponse", {
            typeKeys = typeKeys,
            rooms    = free,
        })

    elseif command == "resetScriptOverrides" then
        if string.lower(player:getAccessLevel() or "") ~= "admin" then return end
        local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)
        dPos.scriptOverrides = {}
        local okRV, RV = pcall(require, "RVVehicleTypes")
        if okRV and RV and RV.VehicleTypes then
            for typeKey, typeDef in pairs(RV.VehicleTypes) do
                if _originalScripts[typeKey] then
                    typeDef.scripts = {}
                    for _, s in ipairs(_originalScripts[typeKey]) do
                        table.insert(typeDef.scripts, s)
                    end
                end
            end
        end
        print("[RVM] resetScriptOverrides: admin=" .. player:getUsername() .. " — overrides cleared")
        sendServerCommand(player, RVM.MODULE, "scriptOverrideResult", { ok = true })
        broadcastAdminSync()
    end
end

Events.OnClientCommand.Add(onAdminCommand)

-- ============================================================
-- RVMServer.dissociate(rvVehicleUniqueId)
-- ============================================================
-- Frees the room linked to the given vehicle, removing the
-- assignment from the base mod's ModData and from our relationship
-- table.  The vehicle itself is not affected (no teleport).
--
-- Returns true on success, or false + error string on failure.
-- ============================================================
function RVMServer.dissociate(rvVehicleUniqueId)  ---@param rvVehicleUniqueId string
    if not rvVehicleUniqueId then
        return false, "rvVehicleUniqueId is nil"
    end

    local rvId = tostring(rvVehicleUniqueId)
    local d    = ModData.getOrCreate(RVM.POS_DATA_KEY)
    local rel  = d.relationships and d.relationships[rvId]

    local dataKey, foundTypeKey
    if rel then
        dataKey      = rel.dataKey
        foundTypeKey = rel.typeKey
    else
        -- Relationship not in our table (e.g. assigned before our mod was
        -- installed, or rebuild() missed the event).  Scan AssignedRooms
        -- directly so the admin can still clear stale assignments.
        local okRV, RV = pcall(require, "RVVehicleTypes")
        if okRV and RV and RV.VehicleTypes then
            local base2 = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
            local numId = tonumber(rvId)
            for tk, _ in pairs(RV.VehicleTypes) do
                local dk = (tk == "normal") and "AssignedRooms" or ("AssignedRooms" .. tk)
                if base2[dk] and (base2[dk][rvId] or (numId and base2[dk][numId])) then
                    dataKey      = dk
                    foundTypeKey = tk
                    break
                end
            end
        end
        if not dataKey then
            return false, "no relationship found for rvId " .. rvId
        end
        print("[RVM] dissociate: rvId=" .. rvId
            .. " not in relationships; cleared via AssignedRooms scan type=" .. tostring(foundTypeKey))
    end

    -- Remove from the base mod's assigned-rooms table.
    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local assigned = base[dataKey]
    if assigned then
        local numRvId = tonumber(rvId)
        assigned[rvId]              = nil
        assigned[rvVehicleUniqueId] = nil   -- cover original value (may be numeric)
        if numRvId then assigned[numRvId] = nil end
    end

    -- Remove from base mod's vehicle-position table.
    if base.Vehicles then
        base.Vehicles[rvId]              = nil
        base.Vehicles[rvVehicleUniqueId] = nil
    end

    -- Remove from our relationship table and caches.
    if d.relationships then d.relationships[rvId] = nil end
    posCache[rvId] = nil
    dirtySet[rvId] = nil

    return true, nil, foundTypeKey
end

-- ============================================================
-- RVMServer.associate(rvVehicleUniqueId, typeKey, vehicleWorldPos)
-- ============================================================
-- Links a vehicle to the next free room of the given typeKey.
-- Writes the assignment into the base mod's ModData exactly as
-- the base mod would, so the teleport logic works unchanged.
--
-- Parameters:
--   rvVehicleUniqueId  string   projectRV_uniqueId of the vehicle
--   typeKey            string   e.g. "normal", "bus", "Trailer"
--   vehicleWorldPos    table    { x, y, z } current world position
--                               (stored in modData.Vehicles)
--
-- Returns the assigned room { x, y, z } on success,
-- or nil + error string on failure.
-- ============================================================
function RVMServer.associate(rvVehicleUniqueId, typeKey, vehicleWorldPos, vehicleName, selectedRoom)
    if not rvVehicleUniqueId then return nil, "rvVehicleUniqueId is nil" end
    if not typeKey            then return nil, "typeKey is nil"            end

    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then
        return nil, "RVVehicleTypes not available"
    end

    local typeDef = RV.VehicleTypes[typeKey]
    if not typeDef then
        return nil, "unknown typeKey: " .. typeKey
    end

    local rvId   = tostring(rvVehicleUniqueId)
    local base   = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local dataKey = (typeKey == "normal") and "AssignedRooms"
                                          or  ("AssignedRooms" .. typeKey)

    base[dataKey] = base[dataKey] or {}

    -- Normalise: the base mod may have stored the assignment under a numeric key.
    local numId = tonumber(rvId)
    if numId and base[dataKey][numId] and not base[dataKey][rvId] then
        base[dataKey][rvId]  = base[dataKey][numId]
        base[dataKey][numId] = nil
    end

    -- Reject if already assigned in ANY type (prevents duplicate assignments when
    -- the vehicle is in multiple scripts lists).
    -- Returns existingTypeKey + existingRoom as extra values so the caller can
    -- propagate them to the client for ModData re-sync.
    for tk, _ in pairs(RV.VehicleTypes) do
        local dk = (tk == "normal") and "AssignedRooms" or ("AssignedRooms" .. tk)
        if base[dk] and (base[dk][rvId] or (numId and base[dk][numId])) then
            local existingRoom = base[dk][rvId] or (numId and base[dk][numId])
            return nil, "vehicle " .. rvId .. " already has a room assigned (type: " .. tk .. ")",
                   tk, existingRoom
        end
    end

    -- Build occupied set.
    local occupied = {}
    for _, roomCoords in pairs(base[dataKey]) do
        local k = string.format("%d-%d-%d",
            roomCoords.x or 0, roomCoords.y or 0, roomCoords.z or 0)
        occupied[k] = true
    end

    local free = {}
    for _, roomCoords in ipairs(typeDef.rooms) do
        local k = string.format("%d-%d-%d",
            roomCoords.x or 0, roomCoords.y or 0, roomCoords.z or 0)
        if not occupied[k] then
            table.insert(free, roomCoords)
        end
    end

    if #free == 0 then
        return nil, "no free rooms available for type " .. typeKey
    end

    -- Use the client-chosen room if provided and still free; otherwise random.
    local room
    if selectedRoom then
        local sk = string.format("%d-%d-%d",
            selectedRoom.x or 0, selectedRoom.y or 0, selectedRoom.z or 0)
        if occupied[sk] then
            return nil, "selected room is already occupied"
        end
        room = { x = selectedRoom.x, y = selectedRoom.y, z = selectedRoom.z }
    else
        room = free[ZombRand(#free) + 1]
    end

    -- Write into the base mod's ModData.
    -- Store under both string and numeric key so the base mod finds it regardless
    -- of which key format it uses internally.
    local coords = { x = room.x, y = room.y, z = room.z }
    base[dataKey][rvId] = coords
    local numRvId = tonumber(rvId)
    if numRvId then base[dataKey][numRvId] = coords end

    -- Force-set projectRV_uniqueId on the server-side vehicle ModData.
    -- In MP, the client sets this value and queues it for transmission, but there
    -- is no guarantee it has arrived by the time the player tries to enter the RV.
    -- The base mod's GetInToRV calls ensureVehiclePersistentId() which generates
    -- a *new* random id if it finds nil — causing a different key to be used for
    -- the ModData lookup, so the assigned room is never found.
    -- Scanning by position + type scripts is the only reliable way to reach the
    -- vehicle object server-side from a client command handler.
    if vehicleWorldPos then
        local okCell, cell = pcall(getCell)
        if okCell and cell then
            local okVeh, cellVehicles = pcall(function() return cell:getVehicles() end)
            if okVeh and cellVehicles then
                local vIter = cellVehicles:iterator()
                while vIter:hasNext() do
                    local v = vIter:next()
                    if v then
                        local dx = math.abs((v:getX() or 0) - (vehicleWorldPos.x or 0))
                        local dy = math.abs((v:getY() or 0) - (vehicleWorldPos.y or 0))
                        if dx <= 2 and dy <= 2 then
                            local vScript = tostring(v:getScript() and v:getScript():getFullName() or "")
                            local matched = false
                            if typeDef.scripts then
                                for _, s in ipairs(typeDef.scripts) do
                                    if s == vScript then matched = true; break end
                                end
                            else
                                matched = true  -- no scripts list: trust position alone
                            end
                            if matched then
                                local vmd = v:getModData()
                                vmd.projectRV_uniqueId = rvId
                                vmd.projectRV_type     = typeKey
                                print("[RVM] associate: set projectRV_uniqueId=" .. rvId
                                    .. " projectRV_type=" .. typeKey
                                    .. " on server vehicle " .. vScript)
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Store the vehicle's world position so exitRV can teleport it back.
    if vehicleWorldPos then
        base.Vehicles       = base.Vehicles or {}
        base.Vehicles[rvId] = {
            x = vehicleWorldPos.x or 0,
            y = vehicleWorldPos.y or 0,
            z = vehicleWorldPos.z or 0,
        }
        posCache[rvId] = base.Vehicles[rvId]
    end

    -- Add to our relationship table.
    local d = ModData.getOrCreate(RVM.POS_DATA_KEY)
    d.relationships = d.relationships or {}
    d.relationships[rvId] = {
        rvVehicleUniqueId = rvId,
        typeKey           = typeKey,
        dataKey           = dataKey,
        room              = { x = room.x, y = room.y, z = room.z },
        lastPos           = vehicleWorldPos and {
            x = vehicleWorldPos.x or 0,
            y = vehicleWorldPos.y or 0,
            z = vehicleWorldPos.z or 0,
        },
        vehicleName       = vehicleName,
        dateLinked        = os.date("%d/%m/%Y %H:%M"),
    }

    return room
end

-- ============================================================
-- Sandbox enforcement — wrap base mod's GetInToRV
-- ============================================================
-- GetInToRV is a global defined by RVServerMP_V3.lua (base mod).
-- Because the base mod loads before ours, we can wrap it here at
-- module-load time to intercept entry attempts BEFORE the player
-- is teleported into the room.
--
-- Also corrects projectRV_type on entry: since a vehicle may now
-- belong to multiple types, we pick the type that already has an
-- existing assignment (if any), otherwise randomly pick among
-- matching types so a fresh auto-assignment lands in the right table.
-- ============================================================

-- Snapshot of VehicleTypes.scripts captured at load time, before any
-- runtime overrides are applied.  Used by resetScriptOverrides to
-- restore the original state without reloading the module.
local _originalScripts = {}
do
    local okSnap, RVsnap = pcall(require, "RVVehicleTypes")
    if okSnap and RVsnap and RVsnap.VehicleTypes then
        for tk, td in pairs(RVsnap.VehicleTypes) do
            if td.scripts then
                _originalScripts[tk] = {}
                for _, s in ipairs(td.scripts) do
                    table.insert(_originalScripts[tk], s)
                end
            end
        end
    end
    local n = 0; for _ in pairs(_originalScripts) do n = n + 1 end
    print("[RVM] _originalScripts: captured " .. n .. " type(s) at load time")
end

local _origGetInToRV = GetInToRV
if _origGetInToRV then
    GetInToRV = function(player, vehicle)
        -- Only active on dedicated servers (isClient() is true on the host side in SP/listen).
        if not isClient() and vehicle then
            local okRV, RV = pcall(require, "RVVehicleTypes")
            if okRV and RV and RV.VehicleTypes then
                local script = vehicle:getScript()
                local vehicleScriptName = script and tostring(script:getFullName()) or nil
                local vmd        = vehicle:getModData()
                local rvUniqueId = vmd and vmd.projectRV_uniqueId
                local oldType    = vmd and vmd.projectRV_type

                -- Collect every typeKey this vehicle's script belongs to.
                local matchingTypes = {}
                if vehicleScriptName then
                    for tk, def in pairs(RV.VehicleTypes) do
                        if def.scripts then
                            for _, s in ipairs(def.scripts) do
                                if s == vehicleScriptName then
                                    table.insert(matchingTypes, tk); break
                                end
                            end
                        end
                    end
                end

                if #matchingTypes > 0 then
                    local base  = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                    local strId = rvUniqueId and tostring(rvUniqueId)
                    local numId = rvUniqueId and tonumber(rvUniqueId)

                    -- Prefer the typeKey recorded in our own relationships (explicitly
                    -- assigned by an admin via this mod) over scanning AssignedRooms.
                    -- The base mod's gen/OnTick can auto-assign rooms in OTHER matching
                    -- types, which would otherwise cause non-deterministic behaviour.
                    local assignedTypeKey = nil
                    if strId then
                        local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)
                        local rel  = dPos.relationships and dPos.relationships[strId]
                        if rel and rel.typeKey then
                            -- Verify the recorded type actually has a room entry.
                            local relDk = (rel.typeKey == "normal") and "AssignedRooms"
                                                                     or ("AssignedRooms" .. rel.typeKey)
                            local relA  = base[relDk]
                            if relA and (relA[strId] or (numId and relA[numId])) then
                                assignedTypeKey = rel.typeKey
                            end
                        end
                    end

                    -- Fall back to scanning AssignedRooms when our relationships don't
                    -- have an entry (e.g. assigned before this mod was installed).
                    if not assignedTypeKey and strId then
                        for _, tk in ipairs(matchingTypes) do
                            local dk = (tk == "normal") and "AssignedRooms" or ("AssignedRooms" .. tk)
                            local a  = base[dk]
                            if a and (a[strId] or (numId and a[numId])) then
                                assignedTypeKey = tk; break
                            end
                        end
                    end

                    -- If the vehicle has assignments in multiple types (base mod gen
                    -- auto-assigned extra types), clear the extras so the base mod can
                    -- only find the one we want it to use.
                    if assignedTypeKey and strId and #matchingTypes > 1 then
                        for _, tk in ipairs(matchingTypes) do
                            if tk ~= assignedTypeKey then
                                local dk = (tk == "normal") and "AssignedRooms" or ("AssignedRooms" .. tk)
                                if base[dk] then
                                    base[dk][strId] = nil
                                    if numId then base[dk][numId] = nil end
                                end
                            end
                        end
                    end

                    -- Use the assigned type; if none, randomly pick among matching types
                    -- (the base mod will auto-assign a room from whichever type we land on).
                    local typeKey = assignedTypeKey
                    if not typeKey then
                        typeKey = matchingTypes[ZombRand(#matchingTypes) + 1]
                    end

                    print("[RVM] GetInToRV: script=" .. tostring(vehicleScriptName)
                        .. " rvId=" .. tostring(rvUniqueId)
                        .. " oldType=" .. tostring(oldType)
                        .. " matching=" .. #matchingTypes
                        .. " assigned=" .. tostring(assignedTypeKey)
                        .. " final=" .. tostring(typeKey))

                    vmd.projectRV_type = typeKey

                    -- Sandbox enforcement: block non-admins from auto-assigning a room.
                    local svars = SandboxVars and SandboxVars.RVM
                    local requireAdmin = (svars ~= nil and svars.RequireAdminToAssociate == true)
                    if requireAdmin then
                        local base        = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                        local assignedKey = (typeKey == "normal") and "AssignedRooms"
                                                                   or  ("AssignedRooms" .. typeKey)
                        local vehicleId   = vmd.projectRV_uniqueId
                        local strId       = vehicleId and tostring(vehicleId)
                        local numId       = vehicleId and tonumber(vehicleId)
                        local a2          = base[assignedKey]
                        local hasRoom     = a2 and strId and (a2[strId] or (numId and a2[numId]))

                        if not hasRoom then
                            local lvl = string.lower(player:getAccessLevel() or "")
                            if lvl ~= "admin" and lvl ~= "moderator" then
                                print("[RVM] Sandbox: blocking non-admin '"
                                    .. player:getUsername() .. "' — no room assigned")
                                sendServerCommand(player, RVM.MODULE, "accessDenied", {})
                                return
                            end
                        end
                    end

                    -- Temporarily hide the vehicle script from all non-target types so
                    -- that the base mod's getVehicleTypeKeyByScript() (which uses pairs()
                    -- with non-deterministic iteration order) can only find typeKey.
                    if #matchingTypes > 1 and vehicleScriptName then
                        local VT          = RV.VehicleTypes
                        local savedScripts = {}
                        for _, tk in ipairs(matchingTypes) do
                            if tk ~= typeKey then
                                local td = VT[tk]
                                if td and td.scripts then
                                    savedScripts[tk] = td.scripts
                                    local filtered = {}
                                    for _, s in ipairs(td.scripts) do
                                        if s ~= vehicleScriptName then
                                            table.insert(filtered, s)
                                        end
                                    end
                                    td.scripts = filtered
                                end
                            end
                        end

                        _origGetInToRV(player, vehicle)

                        for _, tk in ipairs(matchingTypes) do
                            if tk ~= typeKey and savedScripts[tk] then
                                VT[tk].scripts = savedScripts[tk]
                            end
                        end
                        return
                    end
                end
            end
        end

        _origGetInToRV(player, vehicle)
    end
else
    print("[RVM] WARNING: GetInToRV not found at load time — base mod may not be loaded yet")
end

