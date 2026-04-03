-- RV Interior Manager - Shared constants
-- Loaded on both client and server.

if not RVM then RVM = {} end

RVM.MODULE         = "RVManager"
RVM.ROOMS_PER_TYPE = 38

-- Build TypeSizes and TypeDataKeys dynamically from the base mod's VehicleTypes table.
-- Any type added by expansion mods is automatically included.
-- Falls back to empty tables if the base mod is not loaded yet.
local function buildFromVehicleTypes()
    local sizes    = {}   -- [typeKey] = "WxH"
    local dataKeys = {}   -- [typeKey] = ModData key used by the base mod

    local ok, RV = pcall(require, "RVVehicleTypes")
    if ok and RV and RV.VehicleTypes then
        for typeKey, typeDef in pairs(RV.VehicleTypes) do
            local w = typeDef.roomWidth  or "?"
            local h = typeDef.roomHeight or "?"
            sizes[typeKey] = w .. "x" .. h

            -- Pattern used by the base mod server:
            -- "AssignedRooms" for "normal", "AssignedRooms" .. typeKey for all others.
            if typeKey == "normal" then
                dataKeys[typeKey] = "AssignedRooms"
            else
                dataKeys[typeKey] = "AssignedRooms" .. typeKey
            end
        end
    end

    return sizes, dataKeys
end

-- RVM.TypeSizes[typeKey]    = "WxH"  (e.g. "3x6")
-- RVM.TypeDataKeys[typeKey] = ModData assigned-rooms key
RVM.TypeSizes, RVM.TypeDataKeys = buildFromVehicleTypes()
