-- RV Interior Manager — Server: core mutations (associate / dissociate) and the
-- GetInToRV sandbox/type-selection wrapper.
-- Functions attach to the RVMServer namespace defined in RVMServer.lua.

if not isServer() then return end

require("RVMShared")

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
    RVMServer.posCache[rvId] = nil
    RVMServer.dirtySet[rvId] = nil

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
        RVMServer.posCache[rvId] = base.Vehicles[rvId]
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
