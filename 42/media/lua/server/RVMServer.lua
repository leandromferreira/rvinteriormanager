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

local MOVE_THRESHOLD = 0.5   -- tiles
local CHECK_TICKS    = 60    -- ~1 s at 60 ticks/s
local FLUSH_TICKS    = 600   -- ~10 s

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
-- OnTick handler
-- ============================================================
local function onTick()
    tickCount = tickCount + 1

    if tickCount % CHECK_TICKS == 0 then
        checkPositions()
    end

    if tickCount % FLUSH_TICKS == 0 then
        flushDirty()
        tickCount = 0
    end
end

-- ============================================================
-- Bootstrap — runs once on world init
-- ============================================================
-- Builds the initial relationship table from whatever is already
-- in the base mod's ModData (handles pre-existing saves).
local function bootstrap()
    local rels = buildRelationships()
    local d    = ModData.getOrCreate(RVM.POS_DATA_KEY)

    d.relationships = rels

    -- Prime the position cache so the first check has a baseline.
    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local vehicles = base.Vehicles or {}
    for rvId, pos in pairs(vehicles) do
        posCache[tostring(rvId)] = { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
    end

    Events.OnTick.Add(onTick)
end

Events.OnInitWorld.Add(bootstrap)

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

    -- Capture the rvId and timestamp now (base mod already ran).
    local capturedRvId, capturedField
    local pmd = player:getModData()
    local playerId = pmd and pmd.projectRV_playerId
    if playerId then
        local base       = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
        local playerData = base.Players and base.Players[playerId]
        if playerData and playerData.VehicleId then
            capturedRvId  = tostring(playerData.VehicleId)
            capturedField = (command == "enterRV") and "lastEnterDate" or "lastOutDate"
        end
    end
    local capturedDate = os.date("%d/%m/%Y %H:%M")

    local function rebuild()
        local d = ModData.getOrCreate(RVM.POS_DATA_KEY)

        -- Preserve dates before wiping relationships.
        local savedDates = {}
        if d.relationships then
            for rvId, rel in pairs(d.relationships) do
                savedDates[rvId] = {
                    dateLinked    = rel.dateLinked,
                    lastEnterDate = rel.lastEnterDate,
                    lastOutDate   = rel.lastOutDate,
                }
            end
        end

        d.relationships = buildRelationships()

        -- Restore preserved dates.
        for rvId, dates in pairs(savedDates) do
            if d.relationships[rvId] then
                d.relationships[rvId].dateLinked    = dates.dateLinked
                d.relationships[rvId].lastEnterDate = dates.lastEnterDate
                d.relationships[rvId].lastOutDate   = dates.lastOutDate
            end
        end

        -- Apply the new date event.
        if capturedRvId and capturedField and d.relationships[capturedRvId] then
            d.relationships[capturedRvId][capturedField] = capturedDate
        end

        Events.OnTick.Remove(rebuild)
    end
    Events.OnTick.Add(rebuild)
end

Events.OnClientCommand.Add(onClientCommand)

-- ============================================================
-- Request/response handler — admin panel data
-- ============================================================
-- The client sends sendClientCommand(RVM.MODULE, "requestData", {})
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
-- Scan loaded vehicles once and build rvUniqueId → script full name.
local function buildNameMap()
    local names = {}
    local ok, cell = pcall(getCell)
    if not ok or not cell then return names end
    local ok2, vehicles = pcall(function() return cell:getVehicles() end)
    if not ok2 or not vehicles then return names end

    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
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

local function buildResponse()
    local roomData = RVM.readRoomData()
    if not roomData then return nil end

    local nameMap  = buildNameMap()
    local d        = ModData.getOrCreate(RVM.POS_DATA_KEY)
    local rels     = d.relationships or {}
    local summary  = {}
    local assignments = {}

    for typeKey, typeInfo in pairs(roomData) do
        summary[typeKey] = {
            totalRooms = typeInfo.totalRooms,
            occupied   = typeInfo.occupied,
            free       = typeInfo.free,
        }

        for _, room in ipairs(typeInfo.rooms) do
            if room.rvVehicleUniqueId then
                local rel = rels[room.rvVehicleUniqueId] or {}
                table.insert(assignments, {
                    rvVehicleUniqueId = room.rvVehicleUniqueId,
                    vehicleId         = room.vehicleId,
                    vehicleName       = nameMap[room.rvVehicleUniqueId],
                    typeKey           = typeKey,
                    room              = { x = room.x, y = room.y, z = room.z },
                    lastPos           = rel.lastPos,
                    dateLinked        = rel.dateLinked,
                    lastEnterDate     = rel.lastEnterDate,
                    lastOutDate       = rel.lastOutDate,
                })
            end
        end
    end

    return { summary = summary, assignments = assignments }
end

local function onAdminCommand(module, command, player, data)
    if module ~= RVM.MODULE then return end

    if command == "requestData" then
        if not player:isAccessLevel("admin") and not player:isAccessLevel("moderator") then
            return
        end
        local response = buildResponse()
        if response then
            sendServerCommand(player, RVM.MODULE, "responseData", response)
        end

    elseif command == "dissociate" then
        if not player:isAccessLevel("admin") then return end
        local rvId = data and data.rvVehicleUniqueId
        -- Capture typeKey BEFORE the relationship is deleted.
        local d2  = ModData.getOrCreate(RVM.POS_DATA_KEY)
        local rel = d2.relationships and d2.relationships[tostring(rvId or "")]
        local dissTypeKey = rel and rel.typeKey
        local ok, err = RVMServer.dissociate(rvId)
        sendServerCommand(player, RVM.MODULE, "dissociateResult",
            { ok = ok, err = err, rvVehicleUniqueId = rvId, typeKey = dissTypeKey })

    elseif command == "associate" then
        if not player:isAccessLevel("admin") then return end
        local rvId   = data and data.rvVehicleUniqueId
        local typeKey = data and data.typeKey
        local pos     = data and data.vehicleWorldPos
        local room, err = RVMServer.associate(rvId, typeKey, pos)
        sendServerCommand(player, RVM.MODULE, "associateResult",
            { ok = room ~= nil, err = err, rvVehicleUniqueId = rvId,
              typeKey = typeKey, room = room })
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

    if not rel then
        return false, "no relationship found for rvId " .. rvId
    end

    -- Remove from the base mod's assigned-rooms table.
    local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local assigned = base[rel.dataKey]
    if assigned then
        assigned[rvId]    = nil
        assigned[rvVehicleUniqueId] = nil   -- cover numeric key variant
    end

    -- Remove from base mod's vehicle-position table.
    if base.Vehicles then
        base.Vehicles[rvId]              = nil
        base.Vehicles[rvVehicleUniqueId] = nil
    end

    -- Remove from our relationship table and caches.
    d.relationships[rvId] = nil
    posCache[rvId]        = nil
    dirtySet[rvId]        = nil

    return true
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
function RVMServer.associate(rvVehicleUniqueId, typeKey, vehicleWorldPos)
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

    -- Reject if already assigned.
    if base[dataKey][rvId] then
        return nil, "vehicle " .. rvId .. " already has a room assigned"
    end

    -- Find a free room slot (same algorithm as the base mod).
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

    local room = free[ZombRand(#free) + 1]

    -- Write into the base mod's ModData.
    base[dataKey][rvId] = { x = room.x, y = room.y, z = room.z }

    -- Store the vehicle's world position so exitRV can teleport it back.
    if vehicleWorldPos then
        base.Vehicles        = base.Vehicles or {}
        base.Vehicles[rvId]  = {
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
        dateLinked        = os.date("%d/%m/%Y %H:%M"),
    }

    return room
end

