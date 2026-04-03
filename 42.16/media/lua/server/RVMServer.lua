-- RV Interior Manager - Server Side
-- Reads the base mod's ModData and responds to admin data requests.

if not isServer() then return end

require("RVMShared")

local BASE_MOD_KEY  = "RVServer"
local RVM_DATA_KEY  = "RVManagerData"

-- Returns the persistent link times table from ModData.
local function getLinkTimes()
    local d = ModData.getOrCreate(RVM_DATA_KEY)
    if not d.linkTimes then d.linkTimes = {} end
    return d.linkTimes
end

-- Build a lookup table of vehicleId → current live position from loaded cell vehicles.
-- Covers vehicles that moved while no player was inside (no UpdateVehPos sent).
local function buildLivePosMap(trackedIds)
    local livePos = {}
    local ok, vehicles = pcall(function() return getCell():getVehicles() end)
    if not ok or not vehicles then return livePos end

    for i = 0, vehicles:size() - 1 do
        local v   = vehicles:get(i)
        local vid = tostring(v:getId())
        if trackedIds[vid] then
            livePos[vid] = { x = v:getX(), y = v:getY(), z = v:getZ() }
        end
    end
    return livePos
end

-- Build the data payload to send to the requesting admin.
local function buildData()
    local modData = ModData.getOrCreate(BASE_MOD_KEY)

    -- Summary: count occupied rooms per RV type
    local summary = {}
    for typeName, dataKey in pairs(RVM.TypeDataKeys) do
        local assigned = modData[dataKey] or {}
        local occupied = 0
        for _ in pairs(assigned) do occupied = occupied + 1 end
        summary[typeName] = {
            total    = RVM.ROOMS_PER_TYPE,
            occupied = occupied,
        }
    end

    -- Collect IDs of all tracked vehicles so we scan the cell only once
    local players    = modData.Players or {}
    local trackedIds = {}
    for _, pData in pairs(players) do
        if pData.VehicleId then
            trackedIds[tostring(pData.VehicleId)] = true
        end
    end

    -- Live positions from currently loaded vehicles (overrides stale ModData)
    local livePos = buildLivePosMap(trackedIds)

    -- Assignment list: one entry per vehicle currently linked to an RV interior
    local assignments = {}

    for _, pData in pairs(players) do
        local vehicleId  = pData.VehicleId
        local roomType   = pData.RoomType or "?"
        local actualRoom = pData.ActualRoom or {}

        -- Prefer live position; fall back to last known position stored by base mod
        -- Base mod stores as {x=, y=, z=} named fields
        local stored     = (modData.Vehicles or {})[vehicleId] or {}
        local pos        = livePos[tostring(vehicleId)] or stored

        -- If live position differs from stored, update ModData so base mod stays in sync
        if livePos[tostring(vehicleId)] and (
            pos.x ~= stored.x or pos.y ~= stored.y or pos.z ~= stored.z
        ) then
            modData.Vehicles                  = modData.Vehicles or {}
            modData.Vehicles[vehicleId]       = modData.Vehicles[vehicleId] or {}
            modData.Vehicles[vehicleId].x     = pos.x
            modData.Vehicles[vehicleId].y     = pos.y
            modData.Vehicles[vehicleId].z     = pos.z
        end

        table.insert(assignments, {
            vehicleId = tostring(vehicleId),
            roomType  = roomType,
            linkDate  = getLinkTimes()[tostring(vehicleId)] or "?",
            carX = pos.x,
            carY = pos.y,
            carZ = pos.z,
            roomX = actualRoom.x or actualRoom[1],
            roomY = actualRoom.y or actualRoom[2],
            roomZ = actualRoom.z or actualRoom[3],
        })
    end

    return { summary = summary, assignments = assignments }
end

-- Intercept the base mod's "RVServer" commands to capture link timestamps.
-- Also handles our own "RVManager" requests.
local function onClientCommand(module, command, player, data)
    -- Track enter/exit from the base mod
    if module == "RVServer" then
        if command == "enterRV" then
            local vehicleId = data and tostring(data.vehicleId or data.VehicleId or "")
            if vehicleId and vehicleId ~= "" then
                local lt = getLinkTimes()
                -- Only record on first link; do not overwrite if already set
                if not lt[vehicleId] then
                    lt[vehicleId] = os.date("%d/%m/%Y %H:%M")
                    ModData.transmit(RVM_DATA_KEY)
                end
            end
        elseif command == "exitRV" then
            -- Remove link time when the vehicle is freed
            local modData = ModData.getOrCreate(BASE_MOD_KEY)
            local pData   = (modData.Players or {})[player:getOnlineID()]
                         or (modData.Players or {})[player:getUsername()]
            if pData and pData.VehicleId then
                local lt = getLinkTimes()
                lt[tostring(pData.VehicleId)] = nil
                ModData.transmit(RVM_DATA_KEY)
            end
        end
        return  -- let the base mod handle its own command
    end

    -- Handle our own admin data requests
    if module ~= RVM.MODULE then return end

    if command == "requestData" then
        if not player:isAccessLevel("admin") and not player:isAccessLevel("moderator") then
            return
        end
        local response = buildData()
        sendServerCommand(player, RVM.MODULE, "responseData", response)
    end
end

Events.OnClientCommand.Add(onClientCommand)

-- ============================================================
-- Bootstrap: mid-save installation recovery
-- ============================================================
-- Runs once per server start. Detects vehicles that were already
-- linked to an RV interior before this mod was installed and fills
-- in the missing data so the panel works immediately.
local function bootstrap()
    local rvm     = ModData.getOrCreate(RVM_DATA_KEY)
    local base    = ModData.getOrCreate(BASE_MOD_KEY)
    local players = base.Players or {}

    -- Count how many active assignments exist
    local activeCount = 0
    for _ in pairs(players) do activeCount = activeCount + 1 end

    if activeCount == 0 then
        -- Nothing linked yet; mark as bootstrapped and exit
        rvm.bootstrapped = true
        ModData.transmit(RVM_DATA_KEY)
        return
    end

    if rvm.bootstrapped then
        -- Already ran bootstrap; only fill gaps for vehicles added before
        -- this session (linkTimes entry missing but assignment exists).
        local lt      = getLinkTimes()
        local changed = false
        for _, pData in pairs(players) do
            local vid = tostring(pData.VehicleId or "")
            if vid ~= "" and not lt[vid] then
                lt[vid]  = "[anterior ao mod]"
                changed  = true
            end
        end
        if changed then ModData.transmit(RVM_DATA_KEY) end
        return
    end

    -- First run ever: populate linkTimes for all currently linked vehicles
    -- and record AssignedRooms that already exist.
    local lt = getLinkTimes()
    for _, pData in pairs(players) do
        local vid = tostring(pData.VehicleId or "")
        if vid ~= "" and not lt[vid] then
            lt[vid] = "[anterior ao mod]"
        end
    end

    rvm.bootstrapped = true
    ModData.transmit(RVM_DATA_KEY)

    print("[RVManager] Bootstrap concluido: " .. activeCount .. " vinculo(s) pre-existente(s) detectado(s).")
end

Events.OnInitWorld.Add(bootstrap)
