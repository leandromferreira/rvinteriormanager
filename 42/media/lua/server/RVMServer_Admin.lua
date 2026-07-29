-- RV Interior Manager — Server: enter/exit event handling, admin command
-- dispatch, and the data queries that feed the context menu and admin panel.
-- Functions attach to / call the RVMServer namespace defined in RVMServer.lua.

if not isServer() then return end

require("RVMShared")

-- STANDARD_FILE is referenced in resetScriptOverrides log lines.
local STANDARD_FILE = RVMServer.STANDARD_FILE

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

        d.relationships = RVMServer.buildRelationships()

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
    local sent = 0
    local it = onlinePlayers:iterator()
    while it:hasNext() do
        local p = it:next()
        if p then
            local lvl = string.lower(p:getAccessLevel() or "")
            if lvl == "admin" or lvl == "moderator" then
                sendServerCommand(p, RVM.MODULE, "adminSync", payload)
                sent = sent + 1
            end
        end
    end
    print("[RVM] broadcastAdminSync: sent to " .. sent .. " admin(s)")
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
    local known = {}

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

    -- Use ScriptManager to get every vehicle script registered in loaded mods
    -- (same source used by the game's "Gerar Veículo" debug panel)
    local okSM, allTypes = pcall(function()
        return ScriptManager.instance:getAllVehicleScripts()
    end)
    if okSM and allTypes then
        local iter = allTypes:iterator()
        while iter:hasNext() do
            local vs = iter:next()
            if vs then
                local name = vs:getFullName()
                if name then known[tostring(name)] = true end
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
            RVMServer.writeRvmLog(msg)
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
        RVMServer.checkIdleRooms()
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

        RVMServer.applyAllOverridesClean(dPos.scriptOverrides)
        RVMServer.saveChangesFile(dPos.scriptOverrides)
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

        RVMServer.applyAllOverridesClean(dPos.scriptOverrides)
        RVMServer.saveChangesFile(dPos.scriptOverrides)
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
        local lvl = string.lower(player:getAccessLevel() or "")
        print("[RVM] resetScriptOverrides: player=" .. player:getUsername() .. " lvl=" .. lvl)
        if lvl ~= "admin" and lvl ~= "moderator" then return end

        local dPos = ModData.getOrCreate(RVM.POS_DATA_KEY)
        dPos.scriptOverrides = {}
        RVMServer.saveChangesFile({})  -- clear the changes file

        local standardTypes = RVMServer.loadStandardTypes()
        if standardTypes then
            local okRV, RV = pcall(require, "RVVehicleTypes")
            if okRV and RV and RV.VehicleTypes then
                local restored = 0
                for typeKey, scripts in pairs(standardTypes) do
                    if RV.VehicleTypes[typeKey] then
                        RV.VehicleTypes[typeKey].scripts = {}
                        for _, s in ipairs(scripts) do
                            table.insert(RV.VehicleTypes[typeKey].scripts, s)
                        end
                        restored = restored + 1
                    end
                end
                print("[RVM] resetScriptOverrides: restored " .. restored .. " type(s) from " .. STANDARD_FILE)
            end
        else
            print("[RVM] resetScriptOverrides: " .. STANDARD_FILE .. " not found — nothing restored")
        end
        sendServerCommand(player, RVM.MODULE, "scriptOverrideResult", { ok = true })
        broadcastAdminSync()
    end
end

Events.OnClientCommand.Add(onAdminCommand)
