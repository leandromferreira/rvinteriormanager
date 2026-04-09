-- RV Interior Manager — Context Menu + Room Picker
-- Injects admin-only options into the world context menu for
-- vehicles that support RV interiors.

if isServer() then return end

require("RVMShared")

-- ============================================================
-- Helpers
-- ============================================================
local function isAdmin(player)
    if not isClient() then return true end   -- SP: always allowed
    return player:isAccessLevel("admin") or player:isAccessLevel("moderator")
end

-- Returns the typeKey for a vehicle, or nil if it is not a
-- supported RV type.
local function getRVTypeKey(vehicle)
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return nil end

    local scriptName = tostring(vehicle:getScript():getFullName())
    for typeKey, typeDef in pairs(RV.VehicleTypes) do
        if typeDef.scripts then
            for _, s in ipairs(typeDef.scripts) do
                if s == scriptName then return typeKey end
            end
        end
    end
    return nil
end

-- Returns the rvVehicleUniqueId assigned to this vehicle, or nil.
local function getAssignedRvId(vehicle, typeKey)
    local uid = vehicle:getModData().projectRV_uniqueId
    if not uid then return nil end
    local rvId    = tostring(uid)
    local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local dataKey = (typeKey == "normal") and "AssignedRooms"
                                          or  ("AssignedRooms" .. typeKey)
    local assigned = base[dataKey]
    if assigned and assigned[rvId] then
        return rvId
    end
    return nil
end

-- Returns the room dimensions (tiles) for the given typeKey, or nil if not defined.
local function getRoomSize(typeKey)
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return nil, nil end
    local typeDef = RV.VehicleTypes[typeKey]
    if not typeDef then return nil, nil end
    return typeDef.roomWidth, typeDef.roomHeight
end

-- Returns a list of free room coords for the given typeKey.
local function getFreeRooms(typeKey)
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return {} end
    local typeDef = RV.VehicleTypes[typeKey]
    if not typeDef then return {} end

    local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local dataKey = (typeKey == "normal") and "AssignedRooms"
                                          or  ("AssignedRooms" .. typeKey)
    local assigned = base[dataKey] or {}

    local occupied = {}
    for _, roomCoords in pairs(assigned) do
        local k = string.format("%d-%d-%d",
            roomCoords.x or 0, roomCoords.y or 0, roomCoords.z or 0)
        occupied[k] = true
    end

    local free = {}
    for idx, roomCoords in ipairs(typeDef.rooms) do
        local k = string.format("%d-%d-%d",
            roomCoords.x or 0, roomCoords.y or 0, roomCoords.z or 0)
        if not occupied[k] then
            table.insert(free, { index = idx, x = roomCoords.x,
                                  y = roomCoords.y, z = roomCoords.z })
        end
    end
    return free
end

-- Sends the associate command to the server.
local function sendAssociate(rvVehicleUniqueId, typeKey, vehicle)
    sendClientCommand(RVM.MODULE, "associate", {
        rvVehicleUniqueId = rvVehicleUniqueId,
        typeKey           = typeKey,
        vehicleWorldPos   = { x = vehicle:getX(),
                              y = vehicle:getY(),
                              z = vehicle:getZ() },
    })
end

-- Maps an X coordinate to a human-readable map region label.
local function getRoomRegion(x)
    if     x < 25000 then return "Main"
    elseif x < 29000 then return "Update 1"
    else                   return "Update 2"
    end
end

-- Sends the dissociate command to the server.
local function sendDissociate(rvVehicleUniqueId)
    sendClientCommand(RVM.MODULE, "dissociate",
        { rvVehicleUniqueId = rvVehicleUniqueId })
end

-- ============================================================
-- Room Picker Panel
-- ============================================================
RVMRoomPicker = ISPanel:derive("RVMRoomPicker")

local RP_W        = 420
local RP_H        = 400
local RP_ROW      = 20
local RP_PAD      = 8
local RP_HDR      = 22
local RP_FILTER_H = 30   -- height of the filter/search row

function RVMRoomPicker:new(typeKey, freeRooms, vehicle, roomW, roomH)
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local o  = ISPanel.new(self,
        math.floor((sw - RP_W) / 2),
        math.floor((sh - RP_H) / 2),
        RP_W, RP_H)

    o.backgroundColor = { r = 0.08, g = 0.08, b = 0.11, a = 0.97 }
    o.borderColor     = { r = 0.35, g = 0.35, b = 0.50, a = 1.00 }
    o.moveWithMouse   = true

    o.typeKey            = typeKey
    o.freeRooms          = freeRooms
    o.vehicle            = vehicle
    o.roomW              = roomW
    o.roomH              = roomH
    o.selectedRoomIndex  = nil   -- stores room.index (slot #), not list position
    o.filterRegion       = "All"
    o._lastSearch        = ""
    o.scrollY            = 0
    o.listY              = 0
    o.listH              = 0
    return o
end

function RVMRoomPicker:initialise()
    ISPanel.initialise(self)

    -- Close
    local close = ISButton:new(self.width - 22, 4, 18, 20, "X",
        self, RVMRoomPicker.onClose)
    close:initialise()
    close.backgroundColor = { r = 0.50, g = 0.10, b = 0.10, a = 1 }
    self:addChild(close)

    -- Filter row: region dropdown + location search entry
    local filterY = RP_PAD + RP_HDR + 2
    local comboW  = 130
    local gapX    = 4
    local entryX  = RP_PAD + comboW + gapX
    local entryW  = self.width - entryX - RP_PAD

    -- Build unique region options from freeRooms
    local seen    = {}
    local regions = { "All" }
    for _, room in ipairs(self.freeRooms) do
        local r = getRoomRegion(room.x)
        if not seen[r] then
            seen[r] = true
            table.insert(regions, r)
        end
    end

    self.comboRegion = ISComboBox:new(RP_PAD, filterY, comboW, 24,
        self, RVMRoomPicker.onRegionChange)
    self.comboRegion:initialise()
    for _, r in ipairs(regions) do self.comboRegion:addOption(r) end
    self:addChild(self.comboRegion)

    self.searchEntry = ISTextEntry:new(entryX, filterY, entryW, 24)
    self.searchEntry:initialise()
    self.searchEntry:setMaxLines(1)
    self.searchEntry.font = UIFont.Small
    self:addChild(self.searchEntry)

    -- Confirm
    self.btnConfirm = ISButton:new(RP_PAD, self.height - RP_PAD - 26,
        self.width - RP_PAD * 2, 26,
        "Assign Selected Room", self, RVMRoomPicker.onConfirm)
    self.btnConfirm:initialise()
    self.btnConfirm.backgroundColor = { r = 0.10, g = 0.28, b = 0.10, a = 1 }
    self:addChild(self.btnConfirm)

    self:updateConfirm()
end

function RVMRoomPicker:updateConfirm()
    local en = self.selectedRoomIndex ~= nil
    self.btnConfirm.enable    = en
    self.btnConfirm.textColor = en
        and { r = 1, g = 1, b = 1, a = 1 }
        or  { r = 0.4, g = 0.4, b = 0.4, a = 1 }
end

function RVMRoomPicker:onClose()
    self:removeFromUIManager()
    RVMRoomPicker.instance = nil
end

function RVMRoomPicker:onRegionChange(item)
    self.filterRegion       = item
    self.selectedRoomIndex  = nil
    self.scrollY            = 0
    self:updateConfirm()
end

-- Returns filtered subset of freeRooms based on region dropdown + search text.
function RVMRoomPicker:getFiltered()
    local search = (self.searchEntry and self.searchEntry:getText() or ""):lower()
    local result = {}
    for _, room in ipairs(self.freeRooms) do
        local regionOk = (self.filterRegion == "All") or
                         (getRoomRegion(room.x) == self.filterRegion)
        local searchOk = search == "" or
                         tostring(room.x):find(search, 1, true) or
                         tostring(room.y):find(search, 1, true) or
                         tostring(room.z):find(search, 1, true)
        if regionOk and searchOk then
            table.insert(result, room)
        end
    end
    return result
end

function RVMRoomPicker:onConfirm()
    if not self.selectedRoomIndex then return end
    -- Find the room in freeRooms by its original slot index.
    local room
    for _, r in ipairs(self.freeRooms) do
        if r.index == self.selectedRoomIndex then room = r; break end
    end
    if not room then return end

    local uid = self.vehicle:getModData().projectRV_uniqueId
    if not uid then
        uid = ZombRand(1, 99999999)
        self.vehicle:getModData().projectRV_uniqueId = uid
    end

    sendAssociate(tostring(uid), self.typeKey, self.vehicle)
    self:onClose()
end

function RVMRoomPicker:render()
    ISPanel.render(self)

    local x = RP_PAD
    local y = RP_PAD

    -- Title
    local sizeStr = (self.roomW and self.roomH)
        and ("  [" .. self.roomW .. "×" .. self.roomH .. "]")
        or  ""
    local filtered = self:getFiltered()

    -- Detect search text change → deselect + reset scroll
    local curSearch = self.searchEntry and self.searchEntry:getText() or ""
    if curSearch ~= self._lastSearch then
        self._lastSearch       = curSearch
        self.selectedRoomIndex = nil
        self.scrollY           = 0
        self:updateConfirm()
    end

    local countStr = (#filtered == #self.freeRooms)
        and ("(" .. #self.freeRooms .. " free)")
        or  ("(" .. #filtered .. " / " .. #self.freeRooms .. " free)")
    self:drawText(
        "Select Room — " .. self.typeKey .. sizeStr .. "  " .. countStr,
        x, y, 1, 1, 0.6, 1, UIFont.Small)
    y = y + RP_HDR

    -- Filter row background (child widgets draw on top)
    self:drawRect(x, y, self.width - RP_PAD * 2, RP_FILTER_H,
        1, 0.10, 0.10, 0.14)
    -- Draw placeholder hint inside search box if empty
    if curSearch == "" then
        local entryX = RP_PAD + 130 + 4
        self:drawText("Search X / Y / Z…",
            entryX + 4, y + 5, 0.4, 0.4, 0.4, 1, UIFont.Small)
    end
    y = y + RP_FILTER_H

    -- Column headers
    self:drawRect(x, y, self.width - RP_PAD * 2, RP_HDR, 1, 0.12, 0.12, 0.18)
    self:drawText("#",      x + 2,   y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
    self:drawText("Region", x + 38,  y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
    self:drawText("X",      x + 118, y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
    self:drawText("Y",      x + 198, y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
    self:drawText("Z",      x + 278, y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
    y = y + RP_HDR

    self.listY = y
    local bottomReserved = RP_PAD + 26 + RP_PAD
    self.listH = self.height - y - bottomReserved

    self:setStencilRect(0, y, self.width, self.listH)

    local rowY = y - self.scrollY
    for idx, room in ipairs(filtered) do
        if rowY + RP_ROW > y and rowY < y + self.listH then
            local selected = (room.index == self.selectedRoomIndex)
            local bg
            if selected then
                bg = { 1, 0.18, 0.30, 0.42 }
            elseif idx % 2 == 0 then
                bg = { 1, 0.10, 0.10, 0.13 }
            else
                bg = { 1, 0.13, 0.13, 0.16 }
            end
            self:drawRect(x, rowY,
                self.width - RP_PAD * 2, RP_ROW, bg[1], bg[2], bg[3], bg[4])
            local region = getRoomRegion(room.x)
            self:drawText(tostring(room.index), x + 2,   rowY + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)
            self:drawText(region,               x + 38,  rowY + 2, 0.65, 0.75, 0.65, 1, UIFont.Small)
            self:drawText(tostring(room.x),     x + 118, rowY + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)
            self:drawText(tostring(room.y),     x + 198, rowY + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)
            self:drawText(tostring(room.z),     x + 278, rowY + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)
        end
        rowY = rowY + RP_ROW
    end

    self:clearStencilRect()

    -- Scrollbar
    local totalH = #filtered * RP_ROW
    if totalH > self.listH then
        local barH  = math.max(16, self.listH * self.listH / totalH)
        local ratio = self.scrollY / math.max(1, totalH - self.listH)
        local barY  = self.listY + ratio * (self.listH - barH)
        self:drawRect(self.width - RP_PAD - 4, barY, 4, barH,
            0.7, 0.5, 0.5, 0.6)
    end
end

function RVMRoomPicker:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)
    if y < self.listY or y > self.listY + self.listH then return end
    local relY     = y - self.listY + self.scrollY
    local idx      = math.floor(relY / RP_ROW) + 1
    local filtered = self:getFiltered()
    if idx >= 1 and idx <= #filtered then
        local roomIndex = filtered[idx].index
        self.selectedRoomIndex = (self.selectedRoomIndex == roomIndex) and nil or roomIndex
        self:updateConfirm()
    end
end

function RVMRoomPicker:onMouseWheel(del)
    local filtered  = self:getFiltered()
    local totalH    = #filtered * RP_ROW
    local maxScroll = math.max(0, totalH - self.listH)
    self.scrollY    = math.max(0, math.min(maxScroll, self.scrollY - del * RP_ROW * 3))
    return true
end

-- ============================================================
-- Context Menu injection
-- ============================================================
local function onContextMenu(playerIndex, context, worldObjects)
    local player = getSpecificPlayer(playerIndex)
    if not player or not isAdmin(player) then return end

    -- Get the vehicle that was actually right-clicked from the world objects list.
    -- ISVehicleMenu.getVehicleToInteractWith uses proximity to the player, not
    -- the click position, so it can target the wrong vehicle.
    local vehicle = nil
    if worldObjects then
        -- B42 passes a Lua table; B41 passed a Java ArrayList.
        local isJavaList = type(worldObjects.size) == "function"
        local count = isJavaList and worldObjects:size() or #worldObjects
        for i = 0, count - 1 do
            local obj = isJavaList and worldObjects:get(i) or worldObjects[i + 1]
            if obj and instanceof(obj, "IsoVehicle") then
                vehicle = obj
                break
            end
        end
    end
    if not vehicle then return end

    local typeKey = getRVTypeKey(vehicle)
    if not typeKey then return end

    local uid      = vehicle:getModData().projectRV_uniqueId
    local assignedRvId = uid and getAssignedRvId(vehicle, typeKey)

    if assignedRvId then
        -- Vehicle already has a room — offer Dissociate
        context:addOption(
            "[RVM] Dissociate RV Interior",
            vehicle,
            function(veh)
                sendDissociate(tostring(veh:getModData().projectRV_uniqueId))
            end
        )
    else
        -- Vehicle has no room — offer Add (random or choose)
        local freeRooms = getFreeRooms(typeKey)
        local roomW, roomH = getRoomSize(typeKey)
        local sizeTag = (roomW and roomH) and (" [" .. roomW .. "×" .. roomH .. "]") or ""

        if #freeRooms == 0 then
            -- No slots available — add a greyed-out informational entry
            local opt = context:addOption("[RVM] No free rooms (" .. typeKey .. sizeTag .. ")", nil, nil)
            context:setOptionEnabled(opt, false)
            return
        end

        local addOption = context:addOption(
            "[RVM] Add RV Interior (" .. typeKey .. sizeTag .. ")",
            nil, nil)

        local subMenu = context:getNew(context)
        context:addSubMenu(addOption, subMenu)

        -- Random assignment
        subMenu:addOption(
            "Assign random room",
            vehicle,
            function(veh)
                local u = veh:getModData().projectRV_uniqueId
                if not u then
                    u = ZombRand(1, 99999999)
                    veh:getModData().projectRV_uniqueId = u
                end
                sendAssociate(tostring(u), typeKey, veh)
            end
        )

        -- Manual room selection
        subMenu:addOption(
            "Choose room... (" .. #freeRooms .. " available)",
            vehicle,
            function(veh)
                if RVMRoomPicker.instance then
                    RVMRoomPicker.instance:removeFromUIManager()
                end
                local picker = RVMRoomPicker:new(typeKey, freeRooms, veh, roomW, roomH)
                picker:initialise()
                picker:addToUIManager()
                RVMRoomPicker.instance = picker
            end
        )
    end
end

Events.OnFillWorldObjectContextMenu.Add(onContextMenu)

-- ============================================================
-- Server response listener (associate / dissociate feedback)
-- ============================================================
local function onServerCommand(module, command, args)
    if module ~= RVM.MODULE then return end

    if command == "associateResult" then
        if args and args.ok then
            -- Mirror the assignment into the client's ModData copy so the next
            -- context menu open sees the correct state without needing transmit().
            local rvId    = args.rvVehicleUniqueId
            local typeKey = args.typeKey
            local room    = args.room
            if rvId and typeKey and room then
                local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                local dataKey = (typeKey == "normal") and "AssignedRooms"
                                                      or  ("AssignedRooms" .. typeKey)
                base[dataKey] = base[dataKey] or {}
                base[dataKey][tostring(rvId)] = { x = room.x, y = room.y, z = room.z }
            end
        elseif args and not args.ok then
            local player = getSpecificPlayer(0)
            if player then
                player:Say("[RVM] Associate failed: " .. (args.err or "unknown error"))
            end
        end
    elseif command == "dissociateResult" then
        if args and args.ok then
            -- Remove from the client's ModData copy.
            local rvId    = args.rvVehicleUniqueId
            local typeKey = args.typeKey
            if rvId and typeKey then
                local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                local dataKey = (typeKey == "normal") and "AssignedRooms"
                                                      or  ("AssignedRooms" .. typeKey)
                if base[dataKey] then
                    base[dataKey][tostring(rvId)] = nil
                end
            end
        elseif args and not args.ok then
            local player = getSpecificPlayer(0)
            if player then
                player:Say("[RVM] Dissociate failed: " .. (args.err or "unknown error"))
            end
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
