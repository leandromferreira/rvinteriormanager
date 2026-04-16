-- RV Interior Manager — Admin Panel (Client / SP)

if isServer() then return end

require("RVMShared")

RVManagerPanel = ISPanel:derive("RVManagerPanel")

-- ============================================================
-- Layout constants
-- ============================================================
local PAD      = 8
local ROW_H    = 18
local HDR_H    = 20
local TITLE_H  = 28
local FILTER_H = 28
local BTN_H    = 26
local BTN_W    = 155

-- Summary section: fixed height cap so it never pushes the assignment table off screen.
local SUMMARY_MAX_H = 120   -- visible rows ~6; scrollable if more types exist

-- Summary columns: Type | Size | Total | Occupied | Free
local SCOL = { 160, 55, 55, 70, 55 }

-- Fixed-width assignment columns (all except Name)
-- VehicleID, VehPos, RVType, RVPos, Linked, LastIn, LastOut
local ACOL_FIXED = { 80, 90, 70, 90, 85, 80, 80 }
local ACOL_FIXED_TOTAL = 0
for _, w in ipairs(ACOL_FIXED) do ACOL_FIXED_TOTAL = ACOL_FIXED_TOTAL + w end

-- ============================================================
-- Text truncation helper
-- ============================================================
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

-- ============================================================
-- Constructor
-- ============================================================
function RVManagerPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor = { r = 0.08, g = 0.08, b = 0.10, a = 0.96 }
    o.borderColor     = { r = 0.35, g = 0.35, b = 0.42, a = 1.00 }
    o.moveWithMouse   = true

    o.loading        = false
    o.data           = nil
    o.scrollY        = 0
    o.summaryScrollY = 0
    o.selectedRvId   = nil

    o.summaryRegionY = 0
    o.summaryRegionH = 0
    o.assignTableY   = 0
    o.assignContentH = 0
    o.assignRowCount = 0

    -- Assignment table sort state
    o.sortCol    = 0     -- 0 = no sort; 1..8 = column index
    o.sortAsc    = true
    -- Assignment table column layout (filled during render, used for click/tooltip)
    o.acolX      = {}    -- column start X positions
    o.acol       = {}    -- column widths
    o.assignHdrY = 0     -- Y of header row

    -- Summary table sort state
    o.summarySortCol = 0   -- 0 = default (alphabetical); 1..5 = column index
    o.summarySortAsc = true
    -- Summary table column layout (filled during render, used for click/tooltip)
    o.scolX         = {}
    o.summaryHdrY   = 0
    return o
end

function RVManagerPanel:initialise()
    ISPanel.initialise(self)

    -- Close button (top-right)
    local close = ISButton:new(self.width - 22, 4, 18, 20,
        getText("IGUI_RVM_Close"), self, RVManagerPanel.onClose)
    close:initialise()
    close.backgroundColor = { r = 0.50, g = 0.10, b = 0.10, a = 1 }
    self:addChild(close)

    -- Refresh button
    local refresh = ISButton:new(self.width - 96, 4, 70, 20,
        getText("IGUI_RVM_Refresh"), self, RVManagerPanel.requestData)
    refresh:initialise()
    refresh.backgroundColor = { r = 0.15, g = 0.28, b = 0.15, a = 1 }
    self:addChild(refresh)

    -- Bottom action buttons
    local by = self.height - PAD - BTN_H

    self.btnTpVeh = ISButton:new(PAD, by, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_TpVehicle"), self, RVManagerPanel.teleportToVehicle)
    self.btnTpVeh:initialise()
    self:addChild(self.btnTpVeh)

    self.btnTpRoom = ISButton:new(PAD + BTN_W + PAD, by, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_TpRoom"), self, RVManagerPanel.teleportToRoom)
    self.btnTpRoom:initialise()
    self:addChild(self.btnTpRoom)

    self.btnDissoc = ISButton:new(PAD + (BTN_W + PAD) * 2, by, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_Dissociate"), self, RVManagerPanel.dissociate)
    self.btnDissoc:initialise()
    self.btnDissoc.backgroundColor = { r = 0.40, g = 0.10, b = 0.10, a = 1 }
    self:addChild(self.btnDissoc)

    self.btnForceIdle = ISButton:new(PAD + (BTN_W + PAD) * 3, by, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_ForceIdle"), self, RVManagerPanel.forceIdleCleanup)
    self.btnForceIdle:initialise()
    self.btnForceIdle.backgroundColor = { r = 0.18, g = 0.18, b = 0.08, a = 1 }
    self:addChild(self.btnForceIdle)

    -- Filter row: label + combo (field selector) + text entry (search term)
    local filterY    = PAD + TITLE_H + 2
    local labelW     = 42
    local comboW     = 110
    local gapX       = 4
    local entryX     = PAD + labelW + gapX + comboW + gapX
    local entryW     = self.width - entryX - PAD

    local filterFields = {
        getText("IGUI_RVM_FilterField_Car"),
        getText("IGUI_RVM_FilterField_VehicleID"),
        getText("IGUI_RVM_FilterField_RVType"),
        getText("IGUI_RVM_FilterField_RoomLoc"),
        getText("IGUI_RVM_FilterField_VehicleLoc"),
        getText("IGUI_RVM_FilterField_LinkedAt"),
        getText("IGUI_RVM_FilterField_LastIn"),
        getText("IGUI_RVM_FilterField_LastOut"),
    }

    self.filterCombo = ISComboBox:new(PAD + labelW + gapX, filterY, comboW, FILTER_H,
        self, RVManagerPanel.onFilterFieldChange)
    self:addChild(self.filterCombo)
    for _, f in ipairs(filterFields) do self.filterCombo:addOption(f) end

    self.filterEntry = ISTextEntryBox:new("", entryX, filterY, entryW, FILTER_H)
    self:addChild(self.filterEntry)
    self.filterEntry:initialise()
    self.filterEntry:setEditable(true)
    self.filterEntry:setPlaceholderText(getText("IGUI_RVM_SearchPlaceholder"))

    self:updateButtons()
    self:requestData()
end

-- ============================================================
-- Filter field change callback
-- ============================================================
function RVManagerPanel:onFilterFieldChange(combo)
    self.scrollY      = 0
    self.selectedRvId = nil
    self:updateButtons()
end

-- ============================================================
-- Data
-- ============================================================
function RVManagerPanel:requestData()
    self.loading      = true
    self.data         = nil
    self.selectedRvId = nil
    self:updateButtons()
    sendClientCommand(getPlayer(), RVM.MODULE, "requestData", {})
end

function RVManagerPanel:receiveData(data)
    self.loading        = false
    self.data           = data
    self.selectedRvId   = nil
    self.scrollY        = 0
    self.summaryScrollY = 0
    self:updateButtons()
end

-- ============================================================
-- Buttons
-- ============================================================
function RVManagerPanel:updateButtons()
    local a = self:selectedAssignment()

    local function apply(btn, enabled)
        btn.enable    = enabled
        btn.textColor = enabled
            and { r = 1.0, g = 1.0, b = 1.0, a = 1 }
            or  { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    end

    apply(self.btnTpVeh,   a ~= nil and a.lastPos ~= nil)
    apply(self.btnTpRoom,  a ~= nil and a.room    ~= nil)
    apply(self.btnDissoc,  a ~= nil)
    apply(self.btnForceIdle, true)
end

function RVManagerPanel:onClose()
    self:removeFromUIManager()
    RVManagerPanel.instance = nil
end

-- ============================================================
-- Rendering
-- ============================================================
function RVManagerPanel:render()
    ISPanel.render(self)

    local x = PAD
    local y = PAD

    -- Title
    self:drawText(getText("IGUI_RVM_PanelTitle"), x, y, 1, 1, 1, 1, UIFont.Medium)
    y = y + TITLE_H

    if self.loading then
        -- Park filter widgets off-screen while loading
        if self.filterCombo then self.filterCombo:setY(self.height + 50) end
        if self.filterEntry then self.filterEntry:setY(self.height + 50) end
        self:drawText(getText("IGUI_RVM_Loading"), x, y + 20, 0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end

    if not self.data then
        if self.filterCombo then self.filterCombo:setY(self.height + 50) end
        if self.filterEntry then self.filterEntry:setY(self.height + 50) end
        self:drawText(getText("IGUI_RVM_NoData"), x, y + 20, 0.8, 0.7, 0.3, 1, UIFont.Small)
        return
    end

    -- Summary table
    y = self:renderSummary(x, y)

    -- Divider
    y = y + PAD
    self:drawRect(x, y, self.width - PAD * 2, 1, 0.9, 0.3, 0.3, 0.35)
    y = y + PAD

    -- Filter bar — repositioned below summary (child widgets drawn on top)
    if self.filterCombo then self.filterCombo:setY(y) end
    if self.filterEntry then self.filterEntry:setY(y) end
    self:drawText(getText("IGUI_RVM_FilterLabel"), x, y + 6, 0.75, 0.75, 0.45, 1, UIFont.Small)
    y = y + FILTER_H + PAD

    -- Assignment table (fills remaining space above buttons)
    self:renderAssignments(x, y)

    -- Tooltip overlay — drawn last so it floats above everything
    local mx  = self:getMouseX()
    local my  = self:getMouseY()
    local tip = self:getTooltipAt(mx, my)
    if tip and tip ~= "" and tip ~= "-" then
        local font = UIFont.Small
        local tm   = getTextManager()
        local tw   = tm:MeasureStringX(font, tip) + 10
        local th   = tm:getFontHeight(font) + 6
        local tx   = math.min(mx + 14, self.width - tw - PAD)
        local ty   = math.max(my - th - 4, 0)
        self:drawRect(tx, ty, tw, th, 0.95, 0.08, 0.08, 0.12)
        self:drawRectBorder(tx, ty, tw, th, 0.9, 0.45, 0.45, 0.55)
        self:drawText(tip, tx + 5, ty + 3, 1, 1, 0.85, 1, font)
    end
end

function RVManagerPanel:renderSummary(x, y)
    local hdrs = {
        getText("IGUI_RVM_Col_Type"),
        getText("IGUI_RVM_Col_Size"),
        getText("IGUI_RVM_Col_Total"),
        getText("IGUI_RVM_Col_Occupied"),
        getText("IGUI_RVM_Col_Free"),
    }

    self.summaryHdrY = y
    self.scolX = {}
    local tm = getTextManager()
    local cx = x
    for i, h in ipairs(hdrs) do
        self.scolX[i] = cx
        self:drawRect(cx, y, SCOL[i] - 1, HDR_H, 1, 0.14, 0.14, 0.18)
        -- Sort indicator on right edge of header
        local ind, ir, ig, ib
        if self.summarySortCol == i then
            ind = self.summarySortAsc and "^" or "v"
            ir, ig, ib = 1.0, 0.85, 0.2
        else
            ind = "^v"
            ir, ig, ib = 0.35, 0.35, 0.35
        end
        local indW = tm:MeasureStringX(UIFont.Small, ind) + 2
        self:drawText(trimText(UIFont.Small, h, SCOL[i] - indW - 6), cx + 2, y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
        self:drawText(ind, cx + SCOL[i] - indW - 1, y + 2, ir, ig, ib, 1, UIFont.Small)
        cx = cx + SCOL[i]
    end
    y = y + HDR_H

    if not self.data.summary then return y end

    local types = {}
    for k in pairs(self.data.summary) do table.insert(types, k) end

    -- Apply column sort; default (col 0) = alphabetical by type name
    if self.summarySortCol == 0 or self.summarySortCol == 1 then
        local asc = (self.summarySortCol == 0) or self.summarySortAsc
        table.sort(types, function(a, b)
            if asc then return a < b else return a > b end
        end)
    else
        local function summaryKey(typeKey)
            local s = self.data.summary[typeKey]
            if self.summarySortCol == 2 then
                return (s.roomW or 0) * 1000 + (s.roomH or 0)
            elseif self.summarySortCol == 3 then return s.totalRooms or 0
            elseif self.summarySortCol == 4 then return s.occupied   or 0
            elseif self.summarySortCol == 5 then return s.free       or 0
            end
            return 0
        end
        local asc = self.summarySortAsc
        table.sort(types, function(a, b)
            local va, vb = summaryKey(a), summaryKey(b)
            if asc then return va < vb else return va > vb end
        end)
    end

    local totalH  = #types * ROW_H
    local clampH  = math.min(totalH, SUMMARY_MAX_H)

    local maxScroll = math.max(0, totalH - clampH)
    self.summaryScrollY = math.max(0, math.min(maxScroll, self.summaryScrollY))

    self.summaryRegionY = y
    self.summaryRegionH = clampH

    self:setStencilRect(0, y, self.width, clampH)

    local rowY = y - self.summaryScrollY
    local clr = {
        { 0.90, 0.90, 0.90 },
        { 0.70, 0.85, 0.70 },
        { 0.65, 0.65, 0.90 },
        { 0.90, 0.50, 0.50 },
        { 0.50, 0.90, 0.50 },
    }

    for idx, typeKey in ipairs(types) do
        if rowY + ROW_H > y and rowY < y + clampH then
            local bg = (idx % 2 == 0)
                and { 1, 0.10, 0.10, 0.13 }
                or  { 1, 0.13, 0.13, 0.16 }
            self:drawRect(x, rowY, self.width - PAD * 2, ROW_H,
                bg[1], bg[2], bg[3], bg[4])

            local s       = self.data.summary[typeKey]
            local sizeStr = (s.roomW and s.roomH) and (s.roomW .. "x" .. s.roomH) or "-"
            local row     = { typeKey, sizeStr, tostring(s.totalRooms), tostring(s.occupied), tostring(s.free) }
            cx = x
            for i, val in ipairs(row) do
                local c   = clr[i]
                local str = trimText(UIFont.Small, val, SCOL[i] - 4)
                self:drawText(str, cx + 2, rowY + 1, c[1], c[2], c[3], 1, UIFont.Small)
                cx = cx + SCOL[i]
            end
        end
        rowY = rowY + ROW_H
    end

    self:clearStencilRect()

    if totalH > clampH then
        local barH  = math.max(12, clampH * clampH / totalH)
        local ratio = maxScroll > 0 and self.summaryScrollY / maxScroll or 0
        local barY  = y + ratio * (clampH - barH)
        self:drawRect(self.width - PAD - 4, barY, 4, barH, 0.7, 0.5, 0.5, 0.6)
    end

    return y + clampH
end

function RVManagerPanel:renderAssignments(x, y)
    local assignments = self:getFilteredAssignments()
    if not assignments then return end

    -- Compute dynamic column widths: Name gets all remaining space
    local nameW = math.max(80, self.width - PAD * 2 - ACOL_FIXED_TOTAL)
    -- Order: VehicleID, Name, VehPos, RVType, RVPos, Linked, LastIn, LastOut
    local acol = { ACOL_FIXED[1], nameW, ACOL_FIXED[2], ACOL_FIXED[3], ACOL_FIXED[4], ACOL_FIXED[5], ACOL_FIXED[6], ACOL_FIXED[7] }
    local ahdr = {
        getText("IGUI_RVM_Col_VehicleID"),
        getText("IGUI_RVM_Col_Name"),
        getText("IGUI_RVM_Col_VehPos"),
        getText("IGUI_RVM_Col_RVType"),
        getText("IGUI_RVM_Col_RVPos"),
        getText("IGUI_RVM_Col_Linked"),
        getText("IGUI_RVM_Col_LastIn"),
        getText("IGUI_RVM_Col_LastOut"),
    }

    -- Store layout for click detection and tooltip
    self.acol       = acol
    self.acolX      = {}
    self.assignHdrY = y

    local tm = getTextManager()
    local cx = x
    for i, hdr in ipairs(ahdr) do
        self.acolX[i] = cx
        self:drawRect(cx, y, acol[i] - 1, HDR_H, 1, 0.14, 0.14, 0.18)
        -- Sort indicator on right edge: dim "^v" on all; bright "^"/"v" on active
        local ind, ir, ig, ib
        if self.sortCol == i then
            ind = self.sortAsc and "^" or "v"
            ir, ig, ib = 1.0, 0.85, 0.2
        else
            ind = "^v"
            ir, ig, ib = 0.35, 0.35, 0.35
        end
        local indW = tm:MeasureStringX(UIFont.Small, ind) + 2
        self:drawText(trimText(UIFont.Small, hdr, acol[i] - indW - 6), cx + 2, y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
        self:drawText(ind, cx + acol[i] - indW - 1, y + 2, ir, ig, ib, 1, UIFont.Small)
        cx = cx + acol[i]
    end
    y = y + HDR_H

    local bottomReserved = PAD + BTN_H + PAD
    local contentH       = self.height - y - bottomReserved
    self.assignTableY    = y
    self.assignContentH  = contentH
    self.assignRowCount  = #assignments

    self:setStencilRect(0, y, self.width, contentH)

    local rowY = y - self.scrollY

    local function fmt(v)
        return v ~= nil and tostring(v) or "-"
    end
    local function fmtPos(pos)
        if not pos then return "-" end
        return string.format("%.0f, %.0f", pos.x or 0, pos.y or 0)
    end

    for idx, a in ipairs(assignments) do
        if rowY + ROW_H > y and rowY < y + contentH then
            local selected = tostring(a.rvVehicleUniqueId) == self.selectedRvId
            local bg
            if selected then
                bg = { a=1, r=0.18, g=0.30, b=0.42 }
            elseif idx % 2 == 0 then
                bg = { a=1, r=0.10, g=0.10, b=0.13 }
            else
                bg = { a=1, r=0.13, g=0.13, b=0.16 }
            end
            self:drawRect(x, rowY, self.width - PAD * 2, ROW_H,
                bg.a, bg.r, bg.g, bg.b)

            local cols = {
                fmt(a.rvVehicleUniqueId),
                fmt(a.vehicleName),
                fmtPos(a.lastPos),
                fmt(a.typeKey),
                fmtPos(a.room),
                fmt(a.dateLinked),
                fmt(a.lastEnterDate),
                fmt(a.lastOutDate),
            }

            cx = x
            for i, val in ipairs(cols) do
                local str = trimText(UIFont.Small, val, acol[i] - 4)
                self:drawText(str, cx + 2, rowY + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)
                cx = cx + acol[i]
            end
        end
        rowY = rowY + ROW_H
    end

    self:clearStencilRect()

    local totalH = #assignments * ROW_H
    if totalH > contentH then
        local barH  = math.max(20, contentH * contentH / totalH)
        local ratio = (totalH - contentH > 0)
            and self.scrollY / (totalH - contentH) or 0
        local barY  = y + ratio * (contentH - barH)
        self:drawRect(self.width - PAD - 4, barY, 4, barH, 0.7, 0.5, 0.5, 0.6)
    end
end

-- ============================================================
-- Input
-- ============================================================
function RVManagerPanel:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)
    if not self.data then return end

    -- Summary header row click → toggle summary sort
    if y >= self.summaryHdrY and y < self.summaryHdrY + HDR_H and #self.scolX > 0 then
        for i, startX in ipairs(self.scolX) do
            local endX = startX + (SCOL[i] or 0)
            if x >= startX and x < endX then
                if self.summarySortCol == i then
                    self.summarySortAsc = not self.summarySortAsc
                else
                    self.summarySortCol = i
                    self.summarySortAsc = true
                end
                self.summaryScrollY = 0
                break
            end
        end
        return
    end

    -- Assignment header row click → toggle assignment sort
    if y >= self.assignHdrY and y < self.assignHdrY + HDR_H and #self.acolX > 0 then
        for i, startX in ipairs(self.acolX) do
            local endX = startX + (self.acol[i] or 0)
            if x >= startX and x < endX then
                if self.sortCol == i then
                    self.sortAsc = not self.sortAsc
                else
                    self.sortCol = i
                    self.sortAsc = true
                end
                self.scrollY = 0
                break
            end
        end
        return
    end

    if y < self.assignTableY or y > self.assignTableY + self.assignContentH then return end

    local filtered = self:getFilteredAssignments()
    local relY     = y - self.assignTableY + self.scrollY
    local idx      = math.floor(relY / ROW_H) + 1

    if idx >= 1 and idx <= #filtered then
        local rvId = tostring(filtered[idx].rvVehicleUniqueId)
        self.selectedRvId = (self.selectedRvId == rvId) and nil or rvId
        self:updateButtons()
    end
end

function RVManagerPanel:onMouseWheel(del)
    if not self.data then return false end

    local my   = self:getMouseY()
    local step = del * ROW_H * 3

    if my >= self.summaryRegionY and my < self.summaryRegionY + self.summaryRegionH then
        local types = self.data.summary and self.data.summary or {}
        local count = 0
        for _ in pairs(types) do count = count + 1 end
        local totalH    = count * ROW_H
        local maxScroll = math.max(0, totalH - self.summaryRegionH)
        self.summaryScrollY = math.max(0, math.min(maxScroll, self.summaryScrollY + step))
    else
        local filtered  = self:getFilteredAssignments()
        local totalH    = #filtered * ROW_H
        local maxScroll = math.max(0, totalH - self.assignContentH)
        self.scrollY    = math.max(0, math.min(maxScroll, self.scrollY + step))
    end

    return true
end

-- ============================================================
-- Filter helpers
-- ============================================================
function RVManagerPanel:getFilterField()
    if not self.filterCombo then return getText("IGUI_RVM_FilterField_Car") end
    return self.filterCombo:getSelectedText() or getText("IGUI_RVM_FilterField_Car")
end

function RVManagerPanel:getFilterText()
    if not self.filterEntry then return "" end
    local text = self.filterEntry:getText()
    if type(text) ~= "string" then return "" end
    return text
end

function RVManagerPanel:getFilteredAssignments()
    if not self.data or not self.data.assignments then return {} end

    local raw    = self:getFilterText()
    local filter = raw:lower():match("^%s*(.-)%s*$")

    local field  = self:getFilterField()

    local carField      = getText("IGUI_RVM_FilterField_Car")
    local vidField      = getText("IGUI_RVM_FilterField_VehicleID")
    local rvTypeField   = getText("IGUI_RVM_FilterField_RVType")
    local roomLocField  = getText("IGUI_RVM_FilterField_RoomLoc")
    local vehLocField   = getText("IGUI_RVM_FilterField_VehicleLoc")
    local linkedField   = getText("IGUI_RVM_FilterField_LinkedAt")
    local lastInField   = getText("IGUI_RVM_FilterField_LastIn")
    local lastOutField  = getText("IGUI_RVM_FilterField_LastOut")

    -- Use the same formatting as the render so that typing "-" matches empty cells.
    local function fmt(v)    return v ~= nil and tostring(v) or "-" end
    local function fmtPos(pos)
        if not pos then return "-" end
        return string.format("%.0f, %.0f", pos.x or 0, pos.y or 0)
    end

    local result = {}
    for _, a in ipairs(self.data.assignments) do
        local include = true
        if filter ~= "" then
            local val
            if     field == carField     then val = fmt(a.vehicleName)
            elseif field == vidField     then val = fmt(a.rvVehicleUniqueId)
            elseif field == rvTypeField  then val = fmt(a.typeKey)
            elseif field == roomLocField then val = fmtPos(a.room)
            elseif field == vehLocField  then val = fmtPos(a.lastPos)
            elseif field == linkedField  then val = fmt(a.dateLinked)
            elseif field == lastInField  then val = fmt(a.lastEnterDate)
            elseif field == lastOutField then val = fmt(a.lastOutDate)
            else                              val = fmt(a.vehicleName)
            end
            include = val:lower():find(filter, 1, true) ~= nil
        end
        if include then
            table.insert(result, a)
        end
    end

    -- Apply column sort
    local sortKeys = {
        function(a) return tostring(a.rvVehicleUniqueId or "") end,
        function(a) return tostring(a.vehicleName or ""):lower() end,
        function(a) return a.lastPos and (a.lastPos.x or 0) or 0 end,
        function(a) return tostring(a.typeKey or ""):lower() end,
        function(a) return a.room and (a.room.x or 0) or 0 end,
        function(a) return tostring(a.dateLinked or "") end,
        function(a) return tostring(a.lastEnterDate or "") end,
        function(a) return tostring(a.lastOutDate or "") end,
    }
    if self.sortCol >= 1 and sortKeys[self.sortCol] then
        local fn  = sortKeys[self.sortCol]
        local asc = self.sortAsc
        table.sort(result, function(a, b)
            local va, vb = fn(a), fn(b)
            if asc then return va < vb else return va > vb end
        end)
    end

    return result
end

-- ============================================================
-- Tooltip helper
-- ============================================================
function RVManagerPanel:getTooltipAt(mx, my)
    if not self.data then return nil end

    local function fmt(v)    return v ~= nil and tostring(v) or "-" end
    local function fmtPos(p) return p and string.format("%.0f, %.0f", p.x or 0, p.y or 0) or "-" end

    -- Assignment table rows
    if my >= self.assignTableY and my < self.assignTableY + self.assignContentH
        and #self.acolX > 0 then
        local filtered = self:getFilteredAssignments()
        local relY     = my - self.assignTableY + self.scrollY
        local rowIdx   = math.floor(relY / ROW_H) + 1
        if rowIdx >= 1 and rowIdx <= #filtered then
            local a    = filtered[rowIdx]
            local cols = {
                fmt(a.rvVehicleUniqueId),
                fmt(a.vehicleName),
                fmtPos(a.lastPos),
                fmt(a.typeKey),
                fmtPos(a.room),
                fmt(a.dateLinked),
                fmt(a.lastEnterDate),
                fmt(a.lastOutDate),
            }
            for i, startX in ipairs(self.acolX) do
                local w = self.acol[i] or 0
                if mx >= startX and mx < startX + w then
                    return cols[i]
                end
            end
        end
    end

    -- Summary table rows
    if my >= self.summaryRegionY and my < self.summaryRegionY + self.summaryRegionH
        and self.data.summary then
        local types = {}
        for k in pairs(self.data.summary) do table.insert(types, k) end
        table.sort(types)
        local relY   = my - self.summaryRegionY + self.summaryScrollY
        local rowIdx = math.floor(relY / ROW_H) + 1
        if rowIdx >= 1 and rowIdx <= #types then
            local s       = self.data.summary[types[rowIdx]]
            local sizeStr = (s.roomW and s.roomH) and (s.roomW .. "x" .. s.roomH) or "-"
            local cols    = { types[rowIdx], sizeStr, tostring(s.totalRooms), tostring(s.occupied), tostring(s.free) }
            local cx = PAD
            for i, w in ipairs(SCOL) do
                if mx >= cx and mx < cx + w then
                    return cols[i]
                end
                cx = cx + w
            end
        end
    end

    return nil
end

-- ============================================================
-- Actions
-- ============================================================
function RVManagerPanel:selectedAssignment()
    if not self.selectedRvId or not self.data then return nil end
    for _, a in ipairs(self.data.assignments) do
        if tostring(a.rvVehicleUniqueId) == self.selectedRvId then
            return a
        end
    end
    return nil
end

function RVManagerPanel:teleportToVehicle()
    local a = self:selectedAssignment()
    if not a or not a.lastPos then return end
    local p = getSpecificPlayer(0)
    p:setX(a.lastPos.x);      p:setLastX(a.lastPos.x)
    p:setY(a.lastPos.y);      p:setLastY(a.lastPos.y)
    p:setZ(a.lastPos.z or 0); p:setLastZ(a.lastPos.z or 0)
end

function RVManagerPanel:teleportToRoom()
    local a = self:selectedAssignment()
    if not a or not a.room then return end
    local p = getSpecificPlayer(0)
    p:setX(a.room.x);      p:setLastX(a.room.x)
    p:setY(a.room.y);      p:setLastY(a.room.y)
    p:setZ(a.room.z or 0); p:setLastZ(a.room.z or 0)
end

function RVManagerPanel:dissociate()
    local a = self:selectedAssignment()
    if not a then return end
    sendClientCommand(getPlayer(), RVM.MODULE, "dissociate",
        { rvVehicleUniqueId = a.rvVehicleUniqueId })
    local rvId = tostring(a.rvVehicleUniqueId)
    for i, entry in ipairs(self.data.assignments) do
        if tostring(entry.rvVehicleUniqueId) == rvId then
            table.remove(self.data.assignments, i)
            break
        end
    end
    self.selectedRvId = nil
    self:updateButtons()
end

function RVManagerPanel:forceIdleCleanup()
    sendClientCommand(getPlayer(), RVM.MODULE, "forceIdleCheck", {})
end

-- ============================================================
-- Server response listener
-- ============================================================
local function onServerCommand(module, command, args)
    if module ~= RVM.MODULE then return end
    local panel = RVManagerPanel.instance
    if not panel then return end

    if command == "responseData" then
        panel:receiveData(args)
    elseif command == "dissociateResult" or command == "associateResult" then
        if args and args.ok then
            panel:requestData()
        end
    elseif command == "idleCheckResult" then
        panel:requestData()
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- ============================================================
-- Open / toggle
-- ============================================================
function RVManagerPanel.open()
    if RVManagerPanel.instance then
        RVManagerPanel.instance:removeFromUIManager()
        RVManagerPanel.instance = nil
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local pw = math.min(950, math.floor(sw * 0.92))
    local ph = math.min(720, math.floor(sh * 0.88))
    local px = math.floor((sw - pw) / 2)
    local py = math.floor((sh - ph) / 2)

    local panel = RVManagerPanel:new(px, py, pw, ph)
    panel:initialise()
    panel:addToUIManager()
    RVManagerPanel.instance = panel
end

-- ============================================================
-- Admin panel integration
-- ============================================================
local ISAdminPanelUI_create = ISAdminPanelUI.create

function ISAdminPanelUI:create()
    local FONT_HGT_SMALL    = getTextManager():getFontHeight(UIFont.Small)
    local FONT_HGT_MEDIUM   = getTextManager():getFontHeight(UIFont.Medium)
    local UI_BORDER_SPACING = 10
    local BUTTON_HGT        = FONT_HGT_SMALL + 6

    local btnWid = 200
    local x = UI_BORDER_SPACING + 1
    local y = FONT_HGT_MEDIUM + UI_BORDER_SPACING * 2 + 1

    self.rvInteriorManagerBtn = ISButton:new(x, y, btnWid, BUTTON_HGT,
        getText("IGUI_RVM_Btn_AdminPanel"), self, RVManagerPanel.open)
    self.rvInteriorManagerBtn.internal = ""
    self.rvInteriorManagerBtn:initialise()
    self.rvInteriorManagerBtn:instantiate()
    self.rvInteriorManagerBtn.borderColor = self.buttonBorderColor
    self:addChild(self.rvInteriorManagerBtn)

    ISAdminPanelUI_create(self)
end
