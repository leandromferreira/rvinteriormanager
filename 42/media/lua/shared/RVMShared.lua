-- RV Interior Manager — Shared module
-- Loaded on client (SP) and server (MP).
-- Provides RVM.readRoomData() which inspects ModData and returns
-- a structured snapshot of every interior type: how many rooms
-- exist, which are occupied (linked to a vehicle) and which are free.

if RVM then return end   -- already loaded
RVM = {}

RVM.MODULE            = "RVManager"
RVM.BASE_MOD_DATA_KEY = "modPROJECTRVInterior"
RVM.POS_DATA_KEY      = "RVInteriorManager"

-- ============================================================
-- local buildRvUniqueIdToEngineId()
-- ============================================================
-- Scans all vehicles currently loaded in the cell and builds a
-- lookup table:  rvVehicleUniqueId (string) → vehicleId (number, vehicles.db PK)
--
-- Only covers vehicles in loaded chunks.  Vehicles in unloaded
-- chunks will have vehicleId = nil in the room entries.
-- ============================================================
local function buildRvUniqueIdToEngineId()
    local lookup = {}
    local ok, cell = pcall(getCell)
    if not ok or not cell then return lookup end
    local ok2, vehicles = pcall(function() return cell:getVehicles() end)
    if not ok2 or not vehicles then return lookup end

    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        if v then
            local uid = v:getModData().projectRV_uniqueId
            if uid then
                lookup[tostring(uid)] = v:getId()
            end
        end
    end

    return lookup
end

-- ============================================================
-- RVM.readRoomData()
-- ============================================================
-- Returns a table indexed by typeKey.  Example:
--
--   data["normal"] = {
--       dataKey        = "AssignedRooms",
--       totalRooms     = 38,
--       occupied       = 5,
--       free           = 33,
--       rooms = {
--           {                                    -- occupied, vehicle in loaded chunk
--               x                  = 22560,
--               y                  = 12060,
--               z                  = 0,
--               rvVehicleUniqueId  = "47382910", -- projectRV_uniqueId (mod's own ID)
--               vehicleId          = 1234,        -- vehicles.db PK via vehicle:getId()
--           },
--           {                                    -- occupied, vehicle NOT in loaded chunk
--               x                  = 22620,
--               y                  = 12060,
--               z                  = 0,
--               rvVehicleUniqueId  = "88210034",
--               vehicleId          = nil,         -- chunk not loaded
--           },
--           {                                    -- free slot
--               x                  = 22680,
--               y                  = 12060,
--               z                  = 0,
--               rvVehicleUniqueId  = nil,
--               vehicleId          = nil,
--           },
--       },
--   }
--
-- Returns nil if the base mod's VehicleTypes table is unreachable.
-- ============================================================
function RVM.readRoomData()
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then
        return nil
    end

    local VehicleTypes    = RV.VehicleTypes
    local modData         = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local rvIdToEngineId  = buildRvUniqueIdToEngineId()
    local result          = {}

    for typeKey, typeDef in pairs(VehicleTypes) do
        -- The base mod stores assignments under "AssignedRooms" for the "normal"
        -- type, and "AssignedRooms" .. typeKey for every other type.
        local dataKey = (typeKey == "normal") and "AssignedRooms"
                                              or  ("AssignedRooms" .. typeKey)

        local assigned = modData[dataKey] or {}

        -- Inverted index: room-coord-key → rvVehicleUniqueId
        local roomToRvId = {}
        for rvUniqueId, roomCoords in pairs(assigned) do
            local roomKey = string.format("%d-%d-%d",
                roomCoords.x or 0,
                roomCoords.y or 0,
                roomCoords.z or 0)
            roomToRvId[roomKey] = tostring(rvUniqueId)
        end

        -- Walk every room slot defined by the type and annotate it.
        local rooms    = {}
        local occupied = 0
        local free     = 0

        for _, roomCoords in ipairs(typeDef.rooms or {}) do
            local roomKey        = string.format("%d-%d-%d",
                roomCoords.x or 0,
                roomCoords.y or 0,
                roomCoords.z or 0)
            local rvVehicleUniqueId = roomToRvId[roomKey]
            local vehicleId         = rvVehicleUniqueId and rvIdToEngineId[rvVehicleUniqueId]

            table.insert(rooms, {
                x                 = roomCoords.x,
                y                 = roomCoords.y,
                z                 = roomCoords.z,
                rvVehicleUniqueId = rvVehicleUniqueId,  -- string | nil
                vehicleId         = vehicleId,           -- number (vehicles.db PK) | nil
            })

            if rvVehicleUniqueId then
                occupied = occupied + 1
            else
                free = free + 1
            end
        end

        result[typeKey] = {
            dataKey    = dataKey,
            totalRooms = #typeDef.rooms,
            occupied   = occupied,
            free       = free,
            rooms      = rooms,
        }
    end

    return result
end
