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
    local level = string.lower(player:getAccessLevel() or "")
    return level == "admin" or level == "moderator"
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
-- Checks both the string key ("12345") and numeric key (12345) because the base
-- mod may store assignments under a numeric key while we normalise to strings.
local function getAssignedRvId(vehicle, typeKey)
    local uid = vehicle:getModData().projectRV_uniqueId
    if not uid then return nil end
    local rvId    = tostring(uid)
    local numId   = tonumber(uid)
    local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local dataKey = (typeKey == "normal") and "AssignedRooms"
                                          or  ("AssignedRooms" .. typeKey)
    local assigned = base[dataKey]
    if assigned and (assigned[rvId] or (numId and assigned[numId])) then
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

-- Maps an X coordinate to a human-readable map region label.
local function getRoomRegion(x)
    return RVM.getRegionLabel(x)
end

-- Sends the dissociate command to the server.
local function sendDissociate(rvVehicleUniqueId)
    sendClientCommand(getPlayer(), RVM.MODULE, "dissociate",
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

-- ============================================================
-- Theme (shared with Room Picker)
-- ============================================================
local T = {
    bg      = { r=0.06, g=0.06, b=0.08, a=0.96 },
    border  = { r=0.30, g=0.31, b=0.35, a=1.00 },
    hdrBg   = { r=0.12, g=0.12, b=0.16 },
    divider = { r=0.26, g=0.27, b=0.31 },
    text    = { r=0.92, g=0.92, b=0.94 },
    muted   = { r=0.65, g=0.65, b=0.70 },
    accent  = { r=0.80, g=0.35, b=0.30 },
    rowA    = { r=0.08, g=0.08, b=0.10 },
    rowB    = { r=0.10, g=0.10, b=0.13 },
    rowSel  = { r=0.20, g=0.26, b=0.32 },
    btnDef  = { r=0.25, g=0.25, b=0.30 },
    btnOk   = { r=0.25, g=0.55, b=0.35 },
    btnDang = { r=0.65, g=0.25, b=0.25 },
}

local function styleBtn(btn, c)
    btn.backgroundColor          = { r=c.r, g=c.g, b=c.b, a=1 }
    btn.backgroundColorMouseOver = { r=math.min(c.r+0.12,1), g=math.min(c.g+0.12,1), b=math.min(c.b+0.12,1), a=1 }
    btn.borderColor              = { r=math.min(c.r+0.20,1), g=math.min(c.g+0.20,1), b=math.min(c.b+0.20,1), a=0.80 }
    btn.textColor                = { r=T.text.r, g=T.text.g, b=T.text.b, a=1 }
end

function RVMRoomPicker:new(typeKey, freeRooms, vehicle, roomW, roomH)
    local sw  = getCore():getScreenWidth()
    local sh  = getCore():getScreenHeight()
    local o   = ISPanel.new(self,
        math.floor((sw - RP_W) / 2),
        math.floor((sh - RP_H) / 2),
        RP_W, RP_H)

    o.backgroundColor = T.bg
    o.borderColor     = T.border
    o.moveWithMouse   = true

    o.typeKey           = typeKey
    o.freeRooms         = freeRooms
    o.vehicle           = vehicle
    o.roomW             = roomW
    o.roomH             = roomH
    o.selectedRoomIndex = nil
    o.filterRegion      = getText("IGUI_RVM_Region_All")
    o._lastSearch       = ""
    o.scrollY           = 0
    o.listY             = 0
    o.listH             = 0
    return o
end

function RVMRoomPicker:prerender()
    self:drawRect(2, 2, self.width, self.height, 0.35, 0, 0, 0)
    ISPanel.prerender(self)
end

function RVMRoomPicker:initialise()
    ISPanel.initialise(self)

    -- Close
    local close = ISButton:new(self.width - 22, 4, 18, 20,
        getText("IGUI_RVM_Close"), self, RVMRoomPicker.onClose)
    close:initialise()
    styleBtn(close, T.btnDang)
    self:addChild(close)

    -- Filter row: region dropdown + location search entry
    local filterY = RP_PAD + RP_HDR + 2
    local comboW  = 130
    local gapX    = 4
    local entryX  = RP_PAD + comboW + gapX
    local entryW  = self.width - entryX - RP_PAD

    -- Build unique region options from freeRooms
    local seen    = {}
    local regions = { getText("IGUI_RVM_Region_All") }
    for _, room in ipairs(self.freeRooms) do
        local r = getRoomRegion(room.x)
        if not seen[r] then
            seen[r] = true
            table.insert(regions, r)
        end
    end

    -- ISComboBox: addChild first (triggers instantiate internally), then addOption
    self.comboRegion = ISComboBox:new(RP_PAD, filterY, comboW, 24,
        self, RVMRoomPicker.onRegionChange)
    self:addChild(self.comboRegion)
    for _, r in ipairs(regions) do self.comboRegion:addOption(r) end

    -- ISTextEntryBox: addChild → initialise → setEditable
    self.searchEntry = ISTextEntryBox:new("", entryX, filterY, entryW, 24)
    self:addChild(self.searchEntry)
    self.searchEntry:initialise()
    self.searchEntry:setEditable(true)
    self.searchEntry:setPlaceholderText(getText("IGUI_RVM_Picker_SearchPlaceholder"))

    -- Confirm
    self.btnConfirm = ISButton:new(RP_PAD, self.height - RP_PAD - 26,
        self.width - RP_PAD * 2, 26,
        getText("IGUI_RVM_Picker_Confirm"), self, RVMRoomPicker.onConfirm)
    self.btnConfirm:initialise()
    styleBtn(self.btnConfirm, T.btnOk)
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

-- onChange receives (target, combo, ...) — second arg is the ISComboBox itself.
function RVMRoomPicker:onRegionChange(combo)
    self.filterRegion       = combo:getSelectedText()
    self.selectedRoomIndex  = nil
    self.scrollY            = 0
    self:updateConfirm()
end

-- Returns filtered subset of freeRooms based on region dropdown + search text.
function RVMRoomPicker:getFiltered()
    local raw    = (self.searchEntry and self.searchEntry:getText()) or ""
    local search = tostring(raw):lower()
    local allRegion = getText("IGUI_RVM_Region_All")
    local result = {}
    for _, room in ipairs(self.freeRooms) do
        local regionOk = (self.filterRegion == allRegion) or
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

    if self.typeKey then
        sendAssociate(tostring(uid), self.typeKey, self.vehicle, room)
    end
    self:onClose()
end

function RVMRoomPicker:render()
    ISPanel.render(self)

    local x = RP_PAD
    local y = RP_PAD

    local sizeStr = (self.roomW and self.roomH)
        and ("  [" .. self.roomW .. "x" .. self.roomH .. "]")
        or  ""
    local filtered = self:getFiltered()

    -- Detect search text change → deselect + reset scroll
    local curSearch = tostring((self.searchEntry and self.searchEntry:getText()) or "")
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
        getText("IGUI_RVM_Picker_Title") .. " - " .. (self.typeKey or "") .. sizeStr .. "  " .. countStr,
        x, y, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + RP_HDR

    -- Filter row background (child widgets draw on top)
    self:drawRect(x, y, self.width - RP_PAD * 2, RP_FILTER_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    y = y + RP_FILTER_H

    -- Column headers
    self:drawRect(x, y, self.width - RP_PAD * 2, RP_HDR, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + RP_HDR - 1, self.width - RP_PAD * 2, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawRect(x, y, 4, RP_HDR, 1, T.accent.r, T.accent.g, T.accent.b)
    self:drawText(getText("IGUI_RVM_Picker_Col_Num"),    x + 2,   y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Picker_Col_Region"), x + 38,  y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText("X",                                   x + 118, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText("Y",                                   x + 198, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText("Z",                                   x + 278, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + RP_HDR

    self.listY = y
    local bottomReserved = RP_PAD + 26 + RP_PAD
    self.listH = self.height - y - bottomReserved

    self:setStencilRect(0, y, self.width, self.listH)

    local rowY = y - self.scrollY
    for idx, room in ipairs(filtered) do
        if rowY + RP_ROW > y and rowY < y + self.listH then
            local selected = (room.index == self.selectedRoomIndex)
            local bg = selected and T.rowSel or (idx % 2 == 0 and T.rowA or T.rowB)
            self:drawRect(x, rowY, self.width - RP_PAD * 2, RP_ROW, 1, bg.r, bg.g, bg.b)
            -- row divider
            self:drawRect(x, rowY + RP_ROW - 1, self.width - RP_PAD * 2, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)
            local region = getRoomRegion(room.x)
            self:drawText(tostring(room.index), x + 2,   rowY + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
            self:drawText(region,               x + 38,  rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
            self:drawText(tostring(room.x),     x + 118, rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
            self:drawText(tostring(room.y),     x + 198, rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
            self:drawText(tostring(room.z),     x + 278, rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
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
        self:drawRect(self.width - RP_PAD - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
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
-- Patch ISVehicleMenu.FillMenuOutsideVehicle — the engine always calls this
-- when a player right-clicks a vehicle from outside, in both SP and MP.
-- OnFillWorldObjectContextMenu is NOT reliable for vehicles: when the clicked
-- tile has no other world objects, fetch.c == 0 and the event never fires.
local _origFillMenuOutside = ISVehicleMenu.FillMenuOutsideVehicle

function ISVehicleMenu.FillMenuOutsideVehicle(player, context, vehicle, test)
    _origFillMenuOutside(player, context, vehicle, test)

    local playerObj = getSpecificPlayer(player)
    if not playerObj or not isAdmin(playerObj) then return end

    local typeKey = getRVTypeKey(vehicle)
    if not typeKey then return end

    local uid          = vehicle:getModData().projectRV_uniqueId
    local assignedRvId = uid and getAssignedRvId(vehicle, typeKey)

    if assignedRvId then
        -- Vehicle already has a room — offer Dissociate
        local fn = function()
            sendDissociate(tostring(vehicle:getModData().projectRV_uniqueId))
        end
        context:addOption(getText("IGUI_RVM_Ctx_Dissociate"), fn, fn)
    else
        -- Vehicle has no room — offer Associate (random or choose)
        local freeRooms    = getFreeRooms(typeKey)
        local roomW, roomH = getRoomSize(typeKey)
        local sizeTag      = (roomW and roomH) and (" [" .. roomW .. "x" .. roomH .. "]") or ""

        if #freeRooms == 0 then
            local opt = context:addOption(getText("IGUI_RVM_Ctx_NoFreeRooms", typeKey, sizeTag), nil, nil)
            opt.notAvailable = true
            return
        end

        local addOpt = context:addOption(
            getText("IGUI_RVM_Ctx_Associate", typeKey, sizeTag), nil, nil)

        local subMenu = ISContextMenu:getNew(context)
        context:addSubMenu(addOpt, subMenu)

        -- Random assignment
        local fnRandom = function()
            local u = vehicle:getModData().projectRV_uniqueId
            if not u then
                u = ZombRand(1, 99999999)
                vehicle:getModData().projectRV_uniqueId = u
            end
            sendAssociate(tostring(u), typeKey, vehicle)
        end
        subMenu:addOption(getText("IGUI_RVM_Ctx_RandomRoom"), fnRandom, fnRandom)

        -- Same-type room picker
        local fnPicker = function()
            if RVMRoomPicker.instance then
                RVMRoomPicker.instance:removeFromUIManager()
            end
            local picker = RVMRoomPicker:new(typeKey, freeRooms, vehicle, roomW, roomH)
            picker:initialise()
            picker:addToUIManager()
            RVMRoomPicker.instance = picker
        end
        subMenu:addOption(getText("IGUI_RVM_Ctx_ChooseRoom", tostring(#freeRooms)), fnPicker, fnPicker)
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

    if command == "associateResult" then
        if args and args.ok then
            local rvId    = args.rvVehicleUniqueId
            local typeKey = args.typeKey
            local room    = args.room
            if rvId and typeKey and room then
                local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                local dataKey = (typeKey == "normal") and "AssignedRooms"
                                                      or  ("AssignedRooms" .. typeKey)
                base[dataKey] = base[dataKey] or {}
                local strId = tostring(rvId)
                local numId = tonumber(rvId)
                base[dataKey][strId] = { x = room.x, y = room.y, z = room.z }
                if numId then
                    base[dataKey][numId] = base[dataKey][strId]
                end
            end
        elseif args and not args.ok then
            rvm_notify(getText("IGUI_RVM_Err_AssocFailed", args.err or "unknown error"))
        end
    elseif command == "dissociateResult" then
        if args and args.ok then
            local rvId    = args.rvVehicleUniqueId
            local typeKey = args.typeKey
            if rvId and typeKey then
                local base    = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
                local dataKey = (typeKey == "normal") and "AssignedRooms"
                                                      or  ("AssignedRooms" .. typeKey)
                if base[dataKey] then
                    local strId = tostring(rvId)
                    local numId = tonumber(rvId)
                    base[dataKey][strId] = nil
                    if numId then base[dataKey][numId] = nil end
                end
            end
        elseif args and not args.ok then
            rvm_notify(getText("IGUI_RVM_Err_DissocFailed", args.err or "unknown error"))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)
