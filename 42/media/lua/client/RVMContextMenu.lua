-- RV Interior Manager — Context Menu + Room Picker
-- Injects admin-only options into the world context menu for
-- vehicles that support RV interiors.

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

-- Maps an X coordinate to a human-readable map region label.
local function getRoomRegion(x)
    return RVM.getRegionLabel(x)
end

local function trimText(font, txt, maxW)
    if not txt or txt == "" then return "" end
    local tm = getTextManager()
    if tm:MeasureStringX(font, txt) <= maxW then return txt end
    local ellW = tm:MeasureStringX(font, "...")
    local s = txt
    while #s > 0 and (tm:MeasureStringX(font, s) + ellW) > maxW do
        s = string.sub(s, 1, #s - 1)
    end
    return s .. "..."
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

-- typeKeys: array of typeKey strings; vehicle: the vehicle object
function RVMRoomPicker:new(typeKeys, vehicle)
    local sw  = getCore():getScreenWidth()
    local sh  = getCore():getScreenHeight()
    local rpW = math.floor(sw * 0.30)
    local rpH = math.floor(sh * 0.46)
    local o   = ISPanel.new(self,
        math.floor((sw - rpW) / 2),
        math.floor((sh - rpH) / 2),
        rpW, rpH)

    o.backgroundColor = T.bg
    o.borderColor     = T.border
    o.moveWithMouse   = true

    o.typeKeys          = typeKeys
    o.freeRooms         = {}
    o.vehicle           = vehicle
    o.loading           = true
    o.selectedRoomIndex = nil
    o.filterRegion      = getText("IGUI_RVM_Region_All")
    o._lastSearch       = ""
    o.scrollY           = 0
    o.listY             = 0
    o.listH             = 0
    return o
end

-- Called when the server responds with fresh free-room data.
-- rooms: array of { index, x, y, z, typeKey, roomW, roomH }
function RVMRoomPicker:setFreeRooms(rooms)
    self.freeRooms         = rooms
    self.loading           = false
    self.selectedRoomIndex = nil
    self.scrollY           = 0
    self:updateConfirm()
    local allLabel = getText("IGUI_RVM_Region_All")
    self.comboRegion.options = { allLabel }
    local seen = {}
    for _, room in ipairs(rooms) do
        local r = getRoomRegion(room.x)
        if not seen[r] then seen[r] = true; table.insert(self.comboRegion.options, r) end
    end
    self.comboRegion.selected = 1
    self.filterRegion = allLabel
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
        if r.index == self.selectedRoomIndex and r.typeKey == self.selectedTypeKey then
            room = r; break
        end
    end
    if not room then return end

    local uid = self.vehicle:getModData().projectRV_uniqueId
    if not uid then
        uid = ZombRand(1, 99999999)
        self.vehicle:getModData().projectRV_uniqueId = uid
    end

    sendAssociate(tostring(uid), room.typeKey, self.vehicle, room)
    self:onClose()
end

function RVMRoomPicker:render()
    ISPanel.render(self)

    local x = RP_PAD
    local y = RP_PAD

    if self.loading then
        local typeLabel = (self.typeKeys and #self.typeKeys == 1) and self.typeKeys[1] or "multi"
        self:drawText(getText("IGUI_RVM_Picker_Title") .. " - " .. typeLabel,
            x, y, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
        local midY = math.floor(self.height / 2) - 8
        self:drawText(getText("IGUI_RVM_Loading"),
            x, midY, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
        return
    end

    local filtered = self:getFiltered()

    local curSearch = tostring((self.searchEntry and self.searchEntry:getText()) or "")
    if curSearch ~= self._lastSearch then
        self._lastSearch       = curSearch
        self.selectedRoomIndex = nil
        self.selectedTypeKey   = nil
        self.scrollY           = 0
        self:updateConfirm()
    end

    local typeLabel = (self.typeKeys and #self.typeKeys == 1) and self.typeKeys[1] or "multi"
    local countStr  = (#filtered == #self.freeRooms)
        and ("(" .. #self.freeRooms .. " free)")
        or  ("(" .. #filtered .. " / " .. #self.freeRooms .. " free)")
    self:drawText(getText("IGUI_RVM_Picker_Title") .. " - " .. typeLabel .. "  " .. countStr,
        x, y, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + RP_HDR

    self:drawRect(x, y, self.width - RP_PAD * 2, RP_FILTER_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    y = y + RP_FILTER_H

    -- Column positions
    local C_NUM    = x + 2
    local C_TYPE   = x + 30   -- typeKey [WxH]
    local C_REGION = x + 175
    local C_X      = x + 258
    local C_Y      = x + 316
    local C_TYPE_W = 141      -- available width for type text

    self:drawRect(x, y, self.width - RP_PAD * 2, RP_HDR, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + RP_HDR - 1, self.width - RP_PAD * 2, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawRect(x, y, 4, RP_HDR, 1, T.accent.r, T.accent.g, T.accent.b)
    self:drawText(getText("IGUI_RVM_Picker_Col_Num"),    C_NUM,    y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Picker_Col_Type"),   C_TYPE,   y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Picker_Col_Region"), C_REGION, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText("X",                                   C_X,      y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self:drawText("Y",                                   C_Y,      y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + RP_HDR

    self.listY = y
    local bottomReserved = RP_PAD + 26 + RP_PAD
    self.listH = self.height - y - bottomReserved

    self:setStencilRect(0, y, self.width, self.listH)

    local rowY = y - self.scrollY
    for idx, room in ipairs(filtered) do
        if rowY + RP_ROW > y and rowY < y + self.listH then
            local selected = (room.index == self.selectedRoomIndex and room.typeKey == self.selectedTypeKey)
            local bg = selected and T.rowSel or (idx % 2 == 0 and T.rowA or T.rowB)
            self:drawRect(x, rowY, self.width - RP_PAD * 2, RP_ROW, 1, bg.r, bg.g, bg.b)
            self:drawRect(x, rowY + RP_ROW - 1, self.width - RP_PAD * 2, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)
            local typeStr = room.typeKey or "?"
            if room.roomW and room.roomH then typeStr = typeStr .. " " .. room.roomW .. "x" .. room.roomH end
            local region  = getRoomRegion(room.x)
            self:drawText(tostring(room.index),                         C_NUM,    rowY + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
            self:drawText(trimText(UIFont.Small, typeStr, C_TYPE_W),  C_TYPE,   rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
            self:drawText(region,                                       C_REGION, rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
            self:drawText(tostring(room.x),     C_X,      rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
            self:drawText(tostring(room.y),     C_Y,      rowY + 2, T.text.r,  T.text.g,  T.text.b,  1, UIFont.Small)
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
        local room = filtered[idx]
        if self.selectedRoomIndex == room.index and self.selectedTypeKey == room.typeKey then
            self.selectedRoomIndex = nil
            self.selectedTypeKey   = nil
        else
            self.selectedRoomIndex = room.index
            self.selectedTypeKey   = room.typeKey
        end
        self:updateConfirm()
    end
end

function RVMRoomPicker:onMouseWheel(del)
    local filtered  = self:getFiltered()
    local totalH    = #filtered * RP_ROW
    local step      = del * RP_ROW * 3
    local maxScroll = math.max(0, totalH - self.listH)
    self.scrollY    = math.max(0, math.min(maxScroll, self.scrollY + step))
    return true
end

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
            -- Patch RV.VehicleTypes directly via the global (same reference the base mod uses),
            -- so the base mod's own radial-menu check also sees the updated scripts list.
            if RV and RV.VehicleTypes then
                for tk, scripts in pairs(scriptsState) do
                    if RV.VehicleTypes[tk] then
                        RV.VehicleTypes[tk].scripts = scripts
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
            local strId = tostring(rvId)
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
