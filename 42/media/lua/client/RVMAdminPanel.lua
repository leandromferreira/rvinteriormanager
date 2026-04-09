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
local FILTER_H = 24     -- height of the filter text-entry row
local BTN_H    = 26
local BTN_W    = 155

-- Summary section: fixed height cap so it never pushes the assignment table off screen.
local SUMMARY_MAX_H = 120   -- visible rows ≈ 6; scrollable if more types exist

-- Summary columns: Type | Total | Occupied | Free
local SCOL = { 160, 55, 70, 55 }

-- Assignment columns
local ACOL = { 85, 145, 105, 105, 105, 90, 80, 80 }
local AHDR = {
    "Vehicle ID", "Name", "Veh. Pos",
    "RV Type", "RV Pos", "Linked",
    "Last In", "Last Out",
}

local PANEL_W = PAD
for _, w in ipairs(ACOL) do PANEL_W = PANEL_W + w end
PANEL_W = PANEL_W + PAD   -- 813

local PANEL_H = 640

-- ============================================================
-- Constructor
-- ============================================================
function RVManagerPanel:new(x, y)
    local o = ISPanel.new(self, x, y, PANEL_W, PANEL_H)
    o.backgroundColor = { r = 0.08, g = 0.08, b = 0.10, a = 0.96 }
    o.borderColor     = { r = 0.35, g = 0.35, b = 0.42, a = 1.00 }
    o.moveWithMouse   = true

    o.loading        = false
    o.data           = nil      -- last responseData from server
    o.scrollY        = 0
    o.summaryScrollY = 0
    o.selectedRvId   = nil      -- rvVehicleUniqueId of selected row (stable across filter changes)

    -- Set by render so onMouseDown / onMouseWheel can hit-test regions
    o.summaryRegionY = 0
    o.summaryRegionH = 0
    o.assignTableY   = 0
    o.assignContentH = 0
    o.assignRowCount = 0
    return o
end

function RVManagerPanel:initialise()
    ISPanel.initialise(self)

    -- Close button (top-right)
    local close = ISButton:new(self.width - 22, 4, 18, 20, "X", self, RVManagerPanel.onClose)
    close:initialise()
    close.backgroundColor = { r = 0.50, g = 0.10, b = 0.10, a = 1 }
    self:addChild(close)

    -- Refresh button
    local refresh = ISButton:new(self.width - 96, 4, 70, 20, "Refresh", self, RVManagerPanel.requestData)
    refresh:initialise()
    refresh.backgroundColor = { r = 0.15, g = 0.28, b = 0.15, a = 1 }
    self:addChild(refresh)

    -- Bottom action buttons
    local by = self.height - PAD - BTN_H

    self.btnTpVeh = ISButton:new(PAD, by, BTN_W, BTN_H,
        "Teleport to Vehicle", self, RVManagerPanel.teleportToVehicle)
    self.btnTpVeh:initialise()
    self:addChild(self.btnTpVeh)

    self.btnTpRoom = ISButton:new(PAD + BTN_W + PAD, by, BTN_W, BTN_H,
        "Teleport to Room", self, RVManagerPanel.teleportToRoom)
    self.btnTpRoom:initialise()
    self:addChild(self.btnTpRoom)

    self.btnDissoc = ISButton:new(PAD + (BTN_W + PAD) * 2, by, BTN_W, BTN_H,
        "Dissociate", self, RVManagerPanel.dissociate)
    self.btnDissoc:initialise()
    self.btnDissoc.backgroundColor = { r = 0.40, g = 0.10, b = 0.10, a = 1 }
    self:addChild(self.btnDissoc)

    -- Filter text entry (below title row)
    local filterLabelW = 52
    local filterY      = PAD + TITLE_H + 2
    self.filterBox = ISTextEntryBox:new("",
        PAD + filterLabelW, filterY,
        self.width - PAD * 2 - filterLabelW, FILTER_H)
    -- addChild first so the Java parent exists when initialise creates javaObject.
    self:addChild(self.filterBox)
    self.filterBox:initialise()
    self.filterBox:setEditable(true)

    self:updateButtons()
    self:requestData()
end

-- ============================================================
-- Data
-- ============================================================
function RVManagerPanel:requestData()
    self.loading      = true
    self.data         = nil
    self.selectedRvId = nil
    self:updateButtons()
    sendClientCommand(RVM.MODULE, "requestData", {})
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

    apply(self.btnTpVeh,  a ~= nil and a.lastPos ~= nil)
    apply(self.btnTpRoom, a ~= nil and a.room    ~= nil)
    apply(self.btnDissoc, a ~= nil)
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
    self:drawText("RV Interior Manager", x, y, 1, 1, 1, 1, UIFont.Medium)
    y = y + TITLE_H

    -- Filter label (box is a child widget placed at the same y)
    self:drawText("Filter:", x, y + 5, 0.75, 0.75, 0.45, 1, UIFont.Small)
    y = y + FILTER_H + PAD

    if self.loading then
        self:drawText("Loading...", x, y + 20, 0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end

    if not self.data then
        self:drawText("No data — press Refresh.", x, y + 20, 0.8, 0.7, 0.3, 1, UIFont.Small)
        return
    end

    -- Summary table
    y = self:renderSummary(x, y)

    -- Divider
    y = y + PAD
    self:drawRect(x, y, self.width - PAD * 2, 1, 0.9, 0.3, 0.3, 0.35)
    y = y + PAD

    -- Assignment table (fills remaining space above buttons)
    self:renderAssignments(x, y)
end

function RVManagerPanel:renderSummary(x, y)
    -- Column headers (outside the clipped region)
    local cx   = x
    local hdrs = { "Type", "Total", "Occupied", "Free" }
    for i, h in ipairs(hdrs) do
        self:drawText(h, cx + 2, y, 0.75, 0.75, 0.45, 1, UIFont.Small)
        cx = cx + SCOL[i]
    end
    y = y + HDR_H

    if not self.data.summary then return y end

    -- Sort types for stable order
    local types = {}
    for k in pairs(self.data.summary) do table.insert(types, k) end
    table.sort(types)

    local totalH  = #types * ROW_H
    local clampH  = math.min(totalH, SUMMARY_MAX_H)

    -- Clamp scroll
    local maxScroll = math.max(0, totalH - clampH)
    self.summaryScrollY = math.max(0, math.min(maxScroll, self.summaryScrollY))

    -- Track region for mouse-wheel hit-test
    self.summaryRegionY = y
    self.summaryRegionH = clampH

    self:setStencilRect(0, y, self.width, clampH)

    local rowY = y - self.summaryScrollY
    local clr = {
        { 0.90, 0.90, 0.90 },
        { 0.65, 0.65, 0.90 },
        { 0.90, 0.50, 0.50 },
        { 0.50, 0.90, 0.50 },
    }

    for idx, typeKey in ipairs(types) do
        if rowY + ROW_H > y and rowY < y + clampH then
            -- Alternating row background
            local bg = (idx % 2 == 0)
                and { 1, 0.10, 0.10, 0.13 }
                or  { 1, 0.13, 0.13, 0.16 }
            self:drawRect(x, rowY, self.width - PAD * 2, ROW_H,
                bg[1], bg[2], bg[3], bg[4])

            local s   = self.data.summary[typeKey]
            local row = { typeKey, tostring(s.totalRooms), tostring(s.occupied), tostring(s.free) }
            cx = x
            for i, val in ipairs(row) do
                local c = clr[i]
                self:drawText(val, cx + 2, rowY + 1, c[1], c[2], c[3], 1, UIFont.Small)
                cx = cx + SCOL[i]
            end
        end
        rowY = rowY + ROW_H
    end

    self:clearStencilRect()

    -- Scrollbar
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

    -- Column headers
    local cx = x
    for i, hdr in ipairs(AHDR) do
        self:drawRect(cx, y, ACOL[i] - 1, HDR_H, 1, 0.14, 0.14, 0.18)
        self:drawText(hdr, cx + 2, y + 2, 0.75, 0.75, 0.45, 1, UIFont.Small)
        cx = cx + ACOL[i]
    end
    y = y + HDR_H

    -- Scrollable content area (stops above the action buttons)
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
            -- Row background — highlight by rvId so it survives filter changes.
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
                self:drawText(val, cx + 2, rowY + 2, 0.85, 0.85, 0.85, 1, UIFont.Small)
                cx = cx + ACOL[i]
            end
        end
        rowY = rowY + ROW_H
    end

    self:clearStencilRect()

    -- Scrollbar
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

    -- Hit-test only within the content area
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

    -- Route wheel to whichever section the cursor is over.
    local my = self:getMouseY()
    local step = del * ROW_H * 3

    if my >= self.summaryRegionY and my < self.summaryRegionY + self.summaryRegionH then
        -- Summary section
        local types = self.data.summary and self.data.summary or {}
        local count = 0
        for _ in pairs(types) do count = count + 1 end
        local totalH    = count * ROW_H
        local maxScroll = math.max(0, totalH - self.summaryRegionH)
        self.summaryScrollY = math.max(0, math.min(maxScroll, self.summaryScrollY - step))
    else
        -- Assignment section
        local filtered  = self:getFilteredAssignments()
        local totalH    = #filtered * ROW_H
        local maxScroll = math.max(0, totalH - self.assignContentH)
        self.scrollY    = math.max(0, math.min(maxScroll, self.scrollY - step))
    end

    return true
end

-- ============================================================
-- Filter helpers
-- ============================================================
function RVManagerPanel:getFilterText()
    if not self.filterBox then return "" end
    -- ISTextEntryBox exposes getText() directly in B42.
    local text = self.filterBox:getText()
    if type(text) ~= "string" then return "" end
    return text
end

function RVManagerPanel:getFilteredAssignments()
    if not self.data or not self.data.assignments then return {} end
    local raw = self.getFilterText and self:getFilterText() or ""
    local filter = raw:lower():match("^%s*(.-)%s*$")
    if filter == "" then return self.data.assignments end

    local result = {}
    for _, a in ipairs(self.data.assignments) do
        local function has(v)
            return v and tostring(v):lower():find(filter, 1, true)
        end
        if has(a.rvVehicleUniqueId) or has(a.vehicleName) or has(a.typeKey) then
            table.insert(result, a)
        end
    end
    return result
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
    sendClientCommand(RVM.MODULE, "dissociate",
        { rvVehicleUniqueId = a.rvVehicleUniqueId })
    -- Optimistic remove from full list; server will confirm and we refresh.
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
    local px = math.floor((sw - PANEL_W) / 2)
    local py = math.floor((sh - PANEL_H) / 2)

    local panel = RVManagerPanel:new(px, py)
    panel:initialise()
    panel:addToUIManager()
    RVManagerPanel.instance = panel
end

-- ============================================================
-- Admin panel integration
-- ============================================================
-- Adds an "RV Interior Manager" button to the in-game admin
-- panel (ISAdminPanelUI), which is only visible to admins/mods.
-- The hook runs once after the world loads so the class is
-- guaranteed to exist.
-- ============================================================
local function hookAdminPanel()
    if not ISAdminPanelUI then return end

    local original = ISAdminPanelUI.createChildren
    function ISAdminPanelUI.createChildren(self)
        original(self)

        local btnW = 220
        local btnH = 25
        -- Place centered, just above the FECHAR button (~35px from bottom).
        local bx = math.floor((self.width - btnW) / 2)
        local by = self.height - btnH - 35

        local btn = ISButton:new(bx, by, btnW, btnH,
            "RV Interior Manager", self, function()
                RVManagerPanel.open()
            end)
        btn:initialise()
        btn.backgroundColor = { r = 0.10, g = 0.20, b = 0.30, a = 1 }
        self:addChild(btn)
    end
end

Events.OnGameStart.Add(hookAdminPanel)
