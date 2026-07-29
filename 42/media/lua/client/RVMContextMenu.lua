-- RV Interior Manager — Context Menu + server response listener
-- Injects admin-only options into the world context menu for
-- vehicles that support RV interiors.
-- The room-picker panel lives in RVMRoomPicker.lua (loaded after this file).

if isServer() then return end

require("RVMShared")

-- Cache tables declared here so all functions below can access them.
-- freeRoomCache: right-click pre-fetch of free rooms per typeKey combo
-- assignmentCache: server-authoritative rvId→{typeKey,room} state
-- clientScriptsState: server-authoritative typeKey→scripts, updated via adminSync
local freeRoomCache      = {}
local assignmentCache    = {}
local clientScriptsState = {}   -- populated on first adminSync, authoritative for type lookups

-- ============================================================
-- Helpers
-- ============================================================
local function isAdmin(player)
    if not isClient() then return true end   -- SP: always allowed
    local level = string.lower(player:getAccessLevel() or "")
    return level == "admin" or level == "moderator"
end

-- Returns all typeKeys a vehicle's script belongs to (may be multiple).
-- Uses server-synced clientScriptsState when available (avoids require cache issues).
local function getRVTypeKeys(vehicle)
    local script = vehicle:getScript()
    if not script then return {} end
    local scriptName = tostring(script:getFullName())
    local typeKeys = {}

    local hasState = false
    for _ in pairs(clientScriptsState) do hasState = true; break end

    if hasState then
        for typeKey, scripts in pairs(clientScriptsState) do
            for _, s in ipairs(scripts) do
                if s == scriptName then table.insert(typeKeys, typeKey); break end
            end
        end
    else
        local ok, RV = pcall(require, "RVVehicleTypes")
        if not ok or not RV or not RV.VehicleTypes then return {} end
        for typeKey, typeDef in pairs(RV.VehicleTypes) do
            if typeDef.scripts then
                for _, s in ipairs(typeDef.scripts) do
                    if s == scriptName then table.insert(typeKeys, typeKey); break end
                end
            end
        end
    end
    return typeKeys
end

-- Returns (rvId, typeKey) if the vehicle has an assigned room in ANY type table,
-- or (nil, nil) if it has no assignment.
-- Checks the server-synced assignmentCache first, then falls back to local ModData.
local function getAssignedRvId(vehicle)
    local uid = vehicle:getModData().projectRV_uniqueId
    if not uid then return nil, nil end
    local rvId = tostring(uid)

    if assignmentCache[rvId] then
        return rvId, assignmentCache[rvId].typeKey
    end

    local numId = tonumber(uid)
    local base  = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return nil, nil end
    for typeKey, _ in pairs(RV.VehicleTypes) do
        local dataKey  = (typeKey == "normal") and "AssignedRooms" or ("AssignedRooms" .. typeKey)
        local assigned = base[dataKey]
        if assigned and (assigned[rvId] or (numId and assigned[numId])) then
            return rvId, typeKey
        end
    end
    return nil, nil
end

-- Returns the room dimensions (tiles) for the given typeKey, or nil if not defined.
local function getRoomSize(typeKey)
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return nil, nil end
    local typeDef = RV.VehicleTypes[typeKey]
    if not typeDef then return nil, nil end
    return typeDef.roomWidth, typeDef.roomHeight
end

-- Sends the associate command to the server.
-- selectedRoom is optional { x, y, z }; when provided the server uses that
-- specific room instead of picking a random free one.
local function sendAssociate(rvVehicleUniqueId, typeKey, vehicle, selectedRoom)
    local script = vehicle:getScript()
    local data = {
        rvVehicleUniqueId = rvVehicleUniqueId,
        typeKey           = typeKey,
        vehicleName       = script and script:getFullName() or nil,
        vehicleWorldPos   = { x = vehicle:getX(),
                              y = vehicle:getY(),
                              z = vehicle:getZ() },
    }
    if selectedRoom then
        data.selectedRoom = { x = selectedRoom.x, y = selectedRoom.y, z = selectedRoom.z }
    end
    sendClientCommand(getPlayer(), RVM.MODULE, "associate", data)
end

-- Sends the dissociate command to the server.
local function sendDissociate(rvVehicleUniqueId)
    sendClientCommand(getPlayer(), RVM.MODULE, "dissociate",
        { rvVehicleUniqueId = rvVehicleUniqueId })
end

-- Shared namespace: RVMRoomPicker.lua (loaded after this file) reuses sendAssociate.
RVMContext = RVMContext or {}
RVMContext.sendAssociate = sendAssociate

local function freeRoomCacheKey(typeKeys)
    local sorted = {}
    for _, k in ipairs(typeKeys) do table.insert(sorted, k) end
    table.sort(sorted)
    return table.concat(sorted, "|")
end

-- ============================================================
-- Context Menu injection
-- ============================================================
-- Patch ISVehicleMenu.FillMenuOutsideVehicle — the engine always calls this
-- when a player right-clicks a vehicle from outside, in both SP and MP.
-- OnFillWorldObjectContextMenu is NOT reliable for vehicles: when the clicked
-- tile has no other world objects, fetch.c == 0 and the event never fires.
local _origFillMenuOutside = ISVehicleMenu.FillMenuOutsideVehicle

function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test)
    _origFillMenuOutside(player, context, vehicle, test)

    local playerObj = getSpecificPlayer(player)
    if not playerObj or not isAdmin(playerObj) then return end

    local assignedRvId, assignedTypeKey = getAssignedRvId(vehicle)
    local typeKeys = getRVTypeKeys(vehicle)

    -- Show nothing if vehicle has no assignment and is not in any type
    if not assignedRvId and #typeKeys == 0 then return end

    if assignedRvId then
        -- Vehicle has an active room — offer Dissociate even if script was removed from types
        local fn = function() sendDissociate(assignedRvId) end
        context:addOption(getText("IGUI_RVM_Ctx_Dissociate"), fn, fn)
    else
        -- Build a label: if only one type, show type+size; if multiple, just show types joined
        local labelTag
        if #typeKeys == 1 then
            local roomW, roomH = getRoomSize(typeKeys[1])
            labelTag = typeKeys[1] .. ((roomW and roomH) and (" [" .. roomW .. "x" .. roomH .. "]") or "")
        else
            labelTag = table.concat(typeKeys, "/")
        end

        -- Pre-fetch free rooms for all matching types
        local cacheKey = freeRoomCacheKey(typeKeys)
        sendClientCommand(getPlayer(), RVM.MODULE, "getFreeRooms", { typeKeys = typeKeys })
        local cached = freeRoomCache[cacheKey]

        if cached and cached.count == 0 then
            local opt = context:addOption(getText("IGUI_RVM_Ctx_NoFreeRooms", labelTag, ""), nil, nil)
            opt.notAvailable = true
            return
        end

        local addOpt = context:addOption(getText("IGUI_RVM_Ctx_Associate", labelTag, ""), nil, nil)
        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(addOpt, subMenu)

        -- Random assignment: randomly pick a matching type, then assign
        local fnRandom = function()
            local u = vehicle:getModData().projectRV_uniqueId
            if not u then
                u = ZombRand(1, 99999999)
                vehicle:getModData().projectRV_uniqueId = u
            end
            local tk = typeKeys[ZombRand(#typeKeys) + 1]
            sendAssociate(tostring(u), tk, vehicle)
        end
        subMenu:addOption(getText("IGUI_RVM_Ctx_RandomRoom"), fnRandom, fnRandom)

        -- Room picker — re-lookup cache at open time so data that arrived after
        -- the right-click is available immediately rather than stuck on loading.
        local fnPicker = function()
            if RVMRoomPicker.instance then
                RVMRoomPicker.instance:removeFromUIManager()
            end
            local picker = RVMRoomPicker:new(typeKeys, vehicle)
            picker:initialise()
            picker:addToUIManager()
            RVMRoomPicker.instance = picker
            local hit = freeRoomCache[freeRoomCacheKey(typeKeys)]
            if hit then picker:setFreeRooms(hit.rooms) end
        end
        local countLabel = cached and tostring(cached.count) or "?"
        subMenu:addOption(getText("IGUI_RVM_Ctx_ChooseRoom", countLabel), fnPicker, fnPicker)
    end
end

-- ============================================================
-- Server response listener (associate / dissociate feedback)
-- ============================================================
local function onServerCommand(module, command, args)
    if module ~= RVM.MODULE then return end

    local function rvm_notify(msg)
        local p = getSpecificPlayer(0)
        if p then p:Say(msg) end
        print(msg)
    end

    if command == "accessDenied" then
        rvm_notify(getText("IGUI_RVM_Err_AccessDenied"))
        return
    end

    if command == "adminSync" then
        -- Server sends this on connect and after any script-override change.
        -- Keeps VehicleTypes scripts and assignment state in sync.
        local scriptsState = args and args.scriptsState
        if scriptsState then
            -- Store authoritatively so getRVTypeKeys doesn't depend on require caching.
            clientScriptsState = {}
            for tk, scripts in pairs(scriptsState) do
                clientScriptsState[tk] = scripts
            end
            -- Patch via global RV and via require so the base mod's radial-menu
            -- check sees the updated scripts regardless of which reference it holds.
            local targets = {}
            if RV and RV.VehicleTypes then targets[#targets+1] = RV end
            local ok, RVreq = pcall(require, "RVVehicleTypes")
            if ok and RVreq and RVreq.VehicleTypes and RVreq ~= RV then
                targets[#targets+1] = RVreq
            end
            for _, rv in ipairs(targets) do
                for tk, scripts in pairs(scriptsState) do
                    if rv.VehicleTypes[tk] then
                        rv.VehicleTypes[tk].scripts = scripts
                    end
                end
            end
        end
        local assignments = args and args.assignments
        if assignments then
            assignmentCache = {}
            for rvId, info in pairs(assignments) do
                if info and info.typeKey then
                    assignmentCache[tostring(rvId)] = info
                end
            end
        end
        freeRoomCache = {}
        return
    end

    if command == "vehicleAssigned" then
        local rvId    = args and args.rvVehicleUniqueId
        local typeKey = args and args.typeKey
        local room    = args and args.room
        if rvId and typeKey and room then
            local strId   = tostring(rvId)
            local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
            local dataKey = (typeKey == "normal") and "AssignedRooms" or ("AssignedRooms" .. typeKey)
            base[dataKey] = base[dataKey] or {}
            local numId = tonumber(rvId)
            base[dataKey][strId] = { x = room.x, y = room.y, z = room.z }
            if numId then base[dataKey][numId] = base[dataKey][strId] end
            assignmentCache[strId] = { typeKey = typeKey, room = room }
            freeRoomCache = {}
        end
        return
    end

    if command == "vehicleDissociated" then
        local rvId = args and args.rvVehicleUniqueId
        if rvId then
            assignmentCache[tostring(rvId)] = nil
            freeRoomCache = {}
        end
        return
    end

    if command == "freeRoomsResponse" then
        local typeKeys = args and args.typeKeys
        local rooms    = (args and args.rooms) or {}
        if typeKeys then
            local ck = freeRoomCacheKey(typeKeys)
            freeRoomCache[ck] = { count = #rooms, rooms = rooms }
        end
        local picker = RVMRoomPicker.instance
        if picker then picker:setFreeRooms(rooms) end
        return
    end

    if command == "associateResult" then
        if args and args.ok then
            local rvId    = args.rvVehicleUniqueId
            local typeKey = args.typeKey
            local room    = args.room
            if rvId and typeKey and room then
                local strId   = tostring(rvId)
                local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                local dataKey = (typeKey == "normal") and "AssignedRooms"
                                                      or  ("AssignedRooms" .. typeKey)
                base[dataKey] = base[dataKey] or {}
                local numId = tonumber(rvId)
                base[dataKey][strId] = { x = room.x, y = room.y, z = room.z }
                if numId then base[dataKey][numId] = base[dataKey][strId] end
                assignmentCache[strId] = { typeKey = typeKey, room = room }
                freeRoomCache = {}
            end
        elseif args and not args.ok then
            -- If the server knows the vehicle is already assigned, sync so the
            -- context menu shows Dissociate on the next right-click.
            if args.existingTypeKey and args.existingRoom then
                local strId   = tostring(args.rvVehicleUniqueId)
                local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                local dataKey = (args.existingTypeKey == "normal") and "AssignedRooms"
                                or ("AssignedRooms" .. args.existingTypeKey)
                base[dataKey] = base[dataKey] or {}
                local numId = tonumber(args.rvVehicleUniqueId)
                base[dataKey][strId] = { x = args.existingRoom.x, y = args.existingRoom.y, z = args.existingRoom.z }
                if numId then base[dataKey][numId] = base[dataKey][strId] end
                assignmentCache[strId] = { typeKey = args.existingTypeKey, room = args.existingRoom }
                freeRoomCache = {}
            end
            rvm_notify(getText("IGUI_RVM_Err_AssocFailed", args.err or "unknown error"))
        end
    elseif command == "dissociateResult" then
        if args and args.ok then
            local rvId    = args.rvVehicleUniqueId
            local typeKey = args.typeKey
            if rvId then
                local strId = tostring(rvId)
                if typeKey then
                    local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                    local dataKey = (typeKey == "normal") and "AssignedRooms"
                                                          or  ("AssignedRooms" .. typeKey)
                    if base[dataKey] then
                        local numId = tonumber(rvId)
                        base[dataKey][strId] = nil
                        if numId then base[dataKey][numId] = nil end
                    end
                end
                assignmentCache[strId] = nil
                freeRoomCache = {}
            end
        elseif args and not args.ok then
            rvm_notify(getText("IGUI_RVM_Err_DissocFailed", args.err or "unknown error"))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- Request the initial sync from the server once the player object is available.
-- Runs every tick until an admin player is ready, then fires once and removes itself.
local function requestInitialSync()
    local p = getSpecificPlayer(0)
    if not p then return end
    Events.OnTick.Remove(requestInitialSync)
    if isAdmin(p) then
        sendClientCommand(p, RVM.MODULE, "requestAdminSync", {})
    end
end
Events.OnTick.Add(requestInitialSync)
