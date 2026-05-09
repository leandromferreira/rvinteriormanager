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
local TAB_H    = 26
local TAB_W    = 180

local SUMMARY_MAX_H = 120

local VL_ADD_BTN_W    = 44
local VL_REMOVE_BTN_W = 68
local VL_CTRL_H       = FILTER_H + 1

local SCOL = { 160, 55, 55, 70, 55 }
local SCOL_TOTAL = 0
for _, w in ipairs(SCOL) do SCOL_TOTAL = SCOL_TOTAL + w end

local ACOL_FIXED = { 80, 90, 70, 90, 85, 80, 80 }
local ACOL_FIXED_TOTAL = 0
for _, w in ipairs(ACOL_FIXED) do ACOL_FIXED_TOTAL = ACOL_FIXED_TOTAL + w end

-- ============================================================
-- Theme
-- ============================================================
local T = {
    bg        = { r=0.06, g=0.06, b=0.08, a=0.96 },
    border    = { r=0.30, g=0.31, b=0.35, a=1.00 },
    hdrBg     = { r=0.12, g=0.12, b=0.16 },
    divider   = { r=0.26, g=0.27, b=0.31 },
    text      = { r=0.92, g=0.92, b=0.94 },
    muted     = { r=0.65, g=0.65, b=0.70 },
    accent    = { r=0.80, g=0.35, b=0.30 },
    rowA      = { r=0.08, g=0.08, b=0.10 },
    rowB      = { r=0.10, g=0.10, b=0.13 },
    rowSel    = { r=0.20, g=0.26, b=0.32 },
    btnDef    = { r=0.25, g=0.25, b=0.30 },
    btnPrim   = { r=0.28, g=0.45, b=0.70 },
    btnOk     = { r=0.25, g=0.55, b=0.35 },
    btnDang   = { r=0.65, g=0.25, b=0.25 },
    btnWarn   = { r=0.50, g=0.45, b=0.10 },
    tabActive = { r=0.12, g=0.12, b=0.16 },
    tabInact  = { r=0.07, g=0.07, b=0.09 },
}

local function styleBtn(btn, c)
    btn.backgroundColor          = { r=c.r, g=c.g, b=c.b, a=1 }
    btn.backgroundColorMouseOver = { r=math.min(c.r+0.12,1), g=math.min(c.g+0.12,1), b=math.min(c.b+0.12,1), a=1 }
    btn.borderColor              = { r=math.min(c.r+0.20,1), g=math.min(c.g+0.20,1), b=math.min(c.b+0.20,1), a=0.80 }
    btn.textColor                = { r=T.text.r, g=T.text.g, b=T.text.b, a=1 }
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

-- ============================================================
-- Constructor
-- ============================================================
function RVManagerPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor = T.bg
    o.borderColor     = T.border
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

    o.selectedSummaryType   = nil
    o.vehicleListScrollY    = 0
    o.vehicleListLastSearch = ""
    o.vehicleListSelected   = nil
    o.vehicleListRegionY    = 0
    o.vehicleListRegionH    = 0
    o.vehicleListX          = 0
    o.vehicleListW          = 0

    o.unallocScrollY  = 0
    o.unallocSelected = nil
    o.unallocRegionY  = 0
    o.unallocRegionH  = 0
    o.unallocRegionX  = 0
    o.unallocRegionW  = 0

    o.activeTab = 1
    o.tabBarY   = 0
    o.tab1X     = 0
    o.tab2X     = 0

    o.sortCol    = 0
    o.sortAsc    = true
    o.acolX      = {}
    o.acol       = {}
    o.assignHdrY = 0

    o.summarySortCol = 0
    o.summarySortAsc = true
    o.scolX          = {}
    o.summaryHdrY    = 0

    o.addDropdownOpen       = false
    o.addDropdownItems      = {}
    o.addDropdownScrollY    = 0
    o.addDropdownLastSearch = ""
    o.addDropdownX          = 0
    o.addDropdownW          = 0
    o.addDropdownEntryY     = 0
    o.addDropdownEntryH     = 0
    o.addDropdownRenderX    = 0
    o.addDropdownRenderY    = 0
    o.addDropdownRenderW    = 0
    o.addDropdownRenderH    = 0
    return o
end

function RVManagerPanel:prerender()
    self:drawRect(2, 2, self.width, self.height, 0.35, 0, 0, 0)
    ISPanel.prerender(self)
end

function RVManagerPanel:initialise()
    ISPanel.initialise(self)

    local close = ISButton:new(self.width - 22, 4, 18, 20,
        getText("IGUI_RVM_Close"), self, RVManagerPanel.onClose)
    close:initialise()
    styleBtn(close, T.btnDang)
    self:addChild(close)

    local refresh = ISButton:new(self.width - 96, 4, 70, 20,
        getText("IGUI_RVM_Refresh"), self, RVManagerPanel.requestData)
    refresh:initialise()
    styleBtn(refresh, T.btnPrim)
    self:addChild(refresh)

    -- Action buttons — parked until shown in Tab 2
    local oy = self.height + 50

    self.btnTpVeh = ISButton:new(PAD, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_TpVehicle"), self, RVManagerPanel.teleportToVehicle)
    self.btnTpVeh:initialise()
    styleBtn(self.btnTpVeh, T.btnDef)
    self:addChild(self.btnTpVeh)

    self.btnTpRoom = ISButton:new(PAD + BTN_W + PAD, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_TpRoom"), self, RVManagerPanel.teleportToRoom)
    self.btnTpRoom:initialise()
    styleBtn(self.btnTpRoom, T.btnDef)
    self:addChild(self.btnTpRoom)

    self.btnDissoc = ISButton:new(PAD + (BTN_W + PAD) * 2, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_Dissociate"), self, RVManagerPanel.dissociate)
    self.btnDissoc:initialise()
    styleBtn(self.btnDissoc, T.btnDang)
    self:addChild(self.btnDissoc)

    self.btnForceIdle = ISButton:new(PAD + (BTN_W + PAD) * 3, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_ForceIdle"), self, RVManagerPanel.forceIdleCleanup)
    self.btnForceIdle:initialise()
    styleBtn(self.btnForceIdle, T.btnWarn)
    self:addChild(self.btnForceIdle)

    -- Filter widgets (Tab 2)
    local labelW = 42
    local comboW = 110
    local gapX   = 4
    local entryX = PAD + labelW + gapX + comboW + gapX
    local entryW = self.width - entryX - PAD

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

    self.filterCombo = ISComboBox:new(PAD + labelW + gapX, oy, comboW, FILTER_H,
        self, RVManagerPanel.onFilterFieldChange)
    self:addChild(self.filterCombo)
    for _, f in ipairs(filterFields) do self.filterCombo:addOption(f) end

    self.filterEntry = ISTextEntryBox:new("", entryX, oy, entryW, FILTER_H)
    self:addChild(self.filterEntry)
    self.filterEntry:initialise()
    self.filterEntry:setEditable(true)
    self.filterEntry:setPlaceholderText(getText("IGUI_RVM_SearchPlaceholder"))

    -- Vehicle list widgets (Tab 1)
    self.vehicleSearchEntry = ISTextEntryBox:new("", 0, oy, 100, FILTER_H)
    self:addChild(self.vehicleSearchEntry)
    self.vehicleSearchEntry:initialise()
    self.vehicleSearchEntry:setEditable(true)
    self.vehicleSearchEntry:setPlaceholderText(getText("IGUI_RVM_VehSearch_Placeholder"))

    self.vehicleAddEntry = ISTextEntryBox:new("", 0, oy, 100, FILTER_H)
    self:addChild(self.vehicleAddEntry)
    self.vehicleAddEntry:initialise()
    self.vehicleAddEntry:setEditable(true)
    self.vehicleAddEntry:setPlaceholderText(getText("IGUI_RVM_VehList_AddPlaceholder"))

    self.btnAddVehicle = ISButton:new(0, oy, VL_ADD_BTN_W, FILTER_H - 2,
        getText("IGUI_RVM_VehList_Add"), self, RVManagerPanel.onAddVehicle)
    self.btnAddVehicle:initialise()
    styleBtn(self.btnAddVehicle, T.btnOk)
    self:addChild(self.btnAddVehicle)

    self.btnRemoveVehicle = ISButton:new(0, oy, VL_REMOVE_BTN_W, FILTER_H - 2,
        getText("IGUI_RVM_VehList_Remove"), self, RVManagerPanel.onRemoveVehicle)
    self.btnRemoveVehicle:initialise()
    styleBtn(self.btnRemoveVehicle, T.btnDang)
    self:addChild(self.btnRemoveVehicle)

    self.btnResetTypes = ISButton:new(0, oy, 120, FILTER_H - 2,
        getText("IGUI_RVM_Btn_ResetTypes"), self, RVManagerPanel.onResetTypes)
    self.btnResetTypes:initialise()
    styleBtn(self.btnResetTypes, T.btnWarn)
    self:addChild(self.btnResetTypes)

    self:updateButtons()
    self:requestData()
end

-- ============================================================
-- Filter field change
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
    self.loading             = false
    self.data                = data
    self.selectedRvId        = nil
    self.selectedSummaryType = nil
    self.vehicleListSelected = nil
    self.vehicleListScrollY  = 0
    self.unallocSelected     = nil
    self.unallocScrollY      = 0
    self.addDropdownOpen     = false
    self.addDropdownItems    = {}
    self.scrollY             = 0
    self.summaryScrollY      = 0
    self:updateButtons()
    self:updateVehicleListButtons()
end

-- ============================================================
-- Button state
-- ============================================================
function RVManagerPanel:updateButtons()
    local a = self:selectedAssignment()
    local function apply(btn, en)
        btn.enable    = en
        btn.textColor = en and { r=1, g=1, b=1, a=1 } or { r=0.4, g=0.4, b=0.4, a=1 }
    end
    apply(self.btnTpVeh,    a ~= nil and a.lastPos ~= nil)
    apply(self.btnTpRoom,   a ~= nil and a.room    ~= nil)
    apply(self.btnDissoc,   a ~= nil)
    apply(self.btnForceIdle, true)
end

function RVManagerPanel:updateVehicleListButtons()
    if not self.btnAddVehicle or not self.btnRemoveVehicle then return end
    local addText = ""
    if self.vehicleAddEntry then
        local raw = self.vehicleAddEntry:getText()
        if type(raw) == "string" then addText = raw:match("^%s*(.-)%s*$") or "" end
    end
    local addEnabled = self.selectedSummaryType ~= nil and addText ~= ""
    local rmEnabled  = self.vehicleListSelected ~= nil and self.selectedSummaryType ~= nil
    local function apply(btn, en)
        btn.enable    = en
        btn.textColor = en and { r=1, g=1, b=1, a=1 } or { r=0.4, g=0.4, b=0.4, a=1 }
    end
    apply(self.btnAddVehicle,    addEnabled)
    apply(self.btnRemoveVehicle, rmEnabled)
end

function RVManagerPanel:onClose()
    self:removeFromUIManager()
    RVManagerPanel.instance = nil
end

-- ============================================================
-- Add / Remove vehicle script
-- ============================================================
function RVManagerPanel:onAddVehicle()
    if not self.selectedSummaryType then return end
    local addText = ""
    if self.vehicleAddEntry then
        local raw = self.vehicleAddEntry:getText()
        if type(raw) == "string" then addText = raw:match("^%s*(.-)%s*$") or "" end
    end
    if addText == "" then return end
    sendClientCommand(getPlayer(), RVM.MODULE, "addVehicleScript",
        { typeKey = self.selectedSummaryType, script = addText })
    if self.vehicleAddEntry then self.vehicleAddEntry:setText("") end
    self.unallocSelected = nil
end

function RVManagerPanel:onRemoveVehicle()
    if not self.vehicleListSelected or not self.selectedSummaryType then return end
    sendClientCommand(getPlayer(), RVM.MODULE, "removeVehicleScript",
        { typeKey = self.selectedSummaryType, script = self.vehicleListSelected })
    self.vehicleListSelected = nil
    self:updateVehicleListButtons()
end

function RVManagerPanel:onResetTypes()
    sendClientCommand(getPlayer(), RVM.MODULE, "resetScriptOverrides", {})
end

-- ============================================================
-- Unallocated scripts helper
-- ============================================================
function RVManagerPanel:getUnallocatedScripts()
    if not self.data or not self.data.scriptOverrides then return {} end
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return {} end

    local inSomeType = {}
    for _, typeDef in pairs(RV.VehicleTypes) do
        if typeDef.scripts then
            for _, s in ipairs(typeDef.scripts) do inSomeType[s] = true end
        end
    end

    local unalloc = {}
    local seen    = {}
    for _, changes in pairs(self.data.scriptOverrides) do
        if changes.removed then
            for _, s in ipairs(changes.removed) do
                if not seen[s] and not inSomeType[s] then
                    table.insert(unalloc, s)
                    seen[s] = true
                end
            end
        end
    end
    table.sort(unalloc)
    return unalloc
end

-- ============================================================
-- Summary sort helper
-- ============================================================
function RVManagerPanel:getSortedSummaryTypes()
    if not self.data or not self.data.summary then return {} end
    local types = {}
    for k in pairs(self.data.summary) do table.insert(types, k) end

    if self.summarySortCol == 0 or self.summarySortCol == 1 then
        local asc = (self.summarySortCol == 0) or self.summarySortAsc
        table.sort(types, function(a, b) if asc then return a < b else return a > b end end)
    else
        local function summaryKey(typeKey)
            local s = self.data.summary[typeKey]
            if     self.summarySortCol == 2 then return (s.roomW or 0) * 1000 + (s.roomH or 0)
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
    return types
end

-- ============================================================
-- Render
-- ============================================================
function RVManagerPanel:render()
    ISPanel.render(self)

    local x = PAD
    local y = PAD

    self:drawText(getText("IGUI_RVM_PanelTitle"), x, y, T.text.r, T.text.g, T.text.b, 1, UIFont.Medium)
    y = y + TITLE_H

    self:renderTabBar(x, y)
    y = y + TAB_H

    local function hideVehicleWidgets()
        if self.vehicleSearchEntry then self.vehicleSearchEntry:setVisible(false) end
        if self.vehicleAddEntry    then self.vehicleAddEntry:setVisible(false) end
        if self.btnAddVehicle      then self.btnAddVehicle:setVisible(false) end
        if self.btnRemoveVehicle   then self.btnRemoveVehicle:setVisible(false) end
        if self.btnResetTypes      then self.btnResetTypes:setVisible(false) end
    end
    local function showVehicleWidgets()
        if self.vehicleSearchEntry then self.vehicleSearchEntry:setVisible(true) end
        if self.vehicleAddEntry    then self.vehicleAddEntry:setVisible(true) end
        if self.btnAddVehicle      then self.btnAddVehicle:setVisible(true) end
        if self.btnRemoveVehicle   then self.btnRemoveVehicle:setVisible(true) end
        if self.btnResetTypes      then self.btnResetTypes:setVisible(true) end
    end
    local function hideFilterWidgets()
        if self.filterCombo then self.filterCombo:setVisible(false) end
        if self.filterEntry then self.filterEntry:setVisible(false) end
    end
    local function showFilterWidgets()
        if self.filterCombo then self.filterCombo:setVisible(true) end
        if self.filterEntry then self.filterEntry:setVisible(true) end
    end
    local function hideActionButtons()
        if self.btnTpVeh     then self.btnTpVeh:setVisible(false) end
        if self.btnTpRoom    then self.btnTpRoom:setVisible(false) end
        if self.btnDissoc    then self.btnDissoc:setVisible(false) end
        if self.btnForceIdle then self.btnForceIdle:setVisible(false) end
    end
    local function showActionButtons()
        local by = self.height - PAD - BTN_H
        if self.btnTpVeh     then self.btnTpVeh:setY(by);     self.btnTpVeh:setVisible(true) end
        if self.btnTpRoom    then self.btnTpRoom:setY(by);    self.btnTpRoom:setVisible(true) end
        if self.btnDissoc    then self.btnDissoc:setY(by);    self.btnDissoc:setVisible(true) end
        if self.btnForceIdle then self.btnForceIdle:setY(by); self.btnForceIdle:setVisible(true) end
    end

    if self.loading then
        hideFilterWidgets(); hideVehicleWidgets(); hideActionButtons()
        self:drawText(getText("IGUI_RVM_Loading"), x, y + 20, 0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end

    if not self.data then
        hideFilterWidgets(); hideVehicleWidgets(); hideActionButtons()
        self:drawText(getText("IGUI_RVM_NoData"), x, y + 20, 0.8, 0.7, 0.3, 1, UIFont.Small)
        return
    end

    if self.activeTab == 1 then
        hideFilterWidgets()
        hideActionButtons()
        showVehicleWidgets()
        self:updateVehicleListButtons()
        self:renderTab1(x, y)
    else
        hideVehicleWidgets()
        showFilterWidgets()
        showActionButtons()
        self:updateButtons()
        self:renderTab2(x, y)
    end

    -- Add-entry dropdown (overlay, must be drawn after tab content)
    if self.activeTab == 1 then self:renderAddDropdown() end

    -- Tooltip overlay
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
        self:drawRect(tx, ty, tw, th, 0.97, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
        self:drawRectBorder(tx, ty, tw, th, 0.90, T.border.r, T.border.g, T.border.b)
        self:drawText(tip, tx + 5, ty + 3, T.text.r, T.text.g, T.text.b, 1, font)
    end
end

function RVManagerPanel:renderTabBar(x, y)
    local tm = getTextManager()
    self.tabBarY = y
    self.tab1X   = x
    self.tab2X   = x + TAB_W + 2

    local tabs = {
        { x = self.tab1X, active = self.activeTab == 1, label = getText("IGUI_RVM_Tab_Types")  },
        { x = self.tab2X, active = self.activeTab == 2, label = getText("IGUI_RVM_Tab_Linked") },
    }

    for _, tab in ipairs(tabs) do
        local bg = tab.active and T.tabActive or T.tabInact
        self:drawRect(tab.x, y, TAB_W, TAB_H, 1, bg.r, bg.g, bg.b)
        self:drawRectBorder(tab.x, y, TAB_W, TAB_H, 0.55, T.border.r, T.border.g, T.border.b)
        if tab.active then
            self:drawRect(tab.x, y + TAB_H - 2, TAB_W, 2, 1, T.accent.r, T.accent.g, T.accent.b)
        end
        local c  = tab.active and T.text or T.muted
        local lw = tm:MeasureStringX(UIFont.Small, tab.label)
        self:drawText(tab.label, tab.x + math.floor((TAB_W - lw) / 2), y + 5, c.r, c.g, c.b, 1, UIFont.Small)
    end
    self:drawRect(x, y + TAB_H - 1, self.width - PAD * 2, 1, 1, T.divider.r, T.divider.g, T.divider.b)
end

-- ============================================================
-- Add-entry dropdown helpers
-- ============================================================
function RVManagerPanel:getAddDropdownOptions(searchLower)
    -- Build script → current RV type lookup from in-memory VehicleTypes
    local scriptToType = {}
    local okRV, RV = pcall(require, "RVVehicleTypes")
    if okRV and RV and RV.VehicleTypes then
        for typeKey, typeDef in pairs(RV.VehicleTypes) do
            if typeDef.scripts then
                for _, s in ipairs(typeDef.scripts) do
                    scriptToType[s] = typeKey
                end
            end
        end
    end

    -- Mark unallocated (removed from a type but not in any current type)
    if self.data and self.data.scriptOverrides then
        for _, changes in pairs(self.data.scriptOverrides) do
            if changes.removed then
                for _, s in ipairs(changes.removed) do
                    if not scriptToType[s] then
                        scriptToType[s] = "—"
                    end
                end
            end
        end
    end

    local results = {}
    local seen    = {}

    -- Use the full list sent by the server (all game vehicle scripts)
    local allScripts = self.data and self.data.allVehicleScripts
    if allScripts and #allScripts > 0 then
        for _, name in ipairs(allScripts) do
            if not seen[name] then
                seen[name] = true
                if searchLower == "" or name:lower():find(searchLower, 1, true) then
                    table.insert(results, { script = name, typeKey = scriptToType[name] or "" })
                end
            end
        end
    else
        -- Fallback: only RV-known scripts (no server list available yet)
        for script, typeKey in pairs(scriptToType) do
            if searchLower == "" or script:lower():find(searchLower, 1, true) then
                table.insert(results, { script = script, typeKey = typeKey })
            end
        end
    end

    table.sort(results, function(a, b) return a.script < b.script end)
    return results
end

function RVManagerPanel:renderAddDropdown()
    if not self.vehicleAddEntry or not self.addDropdownOpen then return end

    local items = self.addDropdownItems
    if #items == 0 then return end

    local MAX_ROWS = 6
    local visRows  = math.min(MAX_ROWS, #items)
    local dropH    = visRows * ROW_H
    local dropX    = self.addDropdownX
    local dropW    = self.addDropdownW
    -- Open upward from the entry field; fall back to below if no room
    local dropY = self.addDropdownEntryY - dropH
    if dropY < 0 then dropY = self.addDropdownEntryY + self.addDropdownEntryH end

    self.addDropdownRenderX = dropX
    self.addDropdownRenderY = dropY
    self.addDropdownRenderW = dropW
    self.addDropdownRenderH = dropH

    local totalH    = #items * ROW_H
    local maxScroll = math.max(0, totalH - dropH)
    self.addDropdownScrollY = math.max(0, math.min(maxScroll, self.addDropdownScrollY))

    self:drawRect(dropX, dropY, dropW, dropH, 0.98, 0.10, 0.10, 0.13)
    self:drawRectBorder(dropX, dropY, dropW, dropH, 0.85, T.border.r, T.border.g, T.border.b)

    self:setStencilRect(dropX, dropY, dropW, dropH)
    local tm   = getTextManager()
    local rowY = dropY - self.addDropdownScrollY
    for idx, item in ipairs(items) do
        if rowY + ROW_H > dropY and rowY < dropY + dropH then
            local bg = idx % 2 == 0 and T.rowA or T.rowB
            self:drawRect(dropX, rowY, dropW, ROW_H, 1, bg.r, bg.g, bg.b)
            local display   = item.script:match("%.(.+)") or item.script
            local typeLabel = item.typeKey
            local labelW    = tm:MeasureStringX(UIFont.Small, typeLabel) + 6
            self:drawText(trimText(UIFont.Small, display, dropW - labelW - 8),
                          dropX + 3, rowY + 1, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
            self:drawText(typeLabel, dropX + dropW - labelW, rowY + 1,
                          T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
        end
        rowY = rowY + ROW_H
    end
    self:clearStencilRect()

    if totalH > dropH then
        local barH  = math.max(10, dropH * dropH / totalH)
        local ratio = maxScroll > 0 and self.addDropdownScrollY / maxScroll or 0
        local barY  = dropY + ratio * (dropH - barH)
        self:drawRect(dropX + dropW - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
    end
end

-- ============================================================
-- Tab 1: Room Types + Unallocated
-- ============================================================
function RVManagerPanel:renderTab1(x, y)
    local summaryBottomY = self:renderSummary(x, y)

    local divY = summaryBottomY + PAD
    self:drawRect(x, divY, self.width - PAD * 2, 1, 1, T.divider.r, T.divider.g, T.divider.b)

    local unallocY = divY + PAD
    local unallocH = self.height - PAD - unallocY
    if unallocH > HDR_H then
        self:renderUnallocated(x, unallocY, self.width - PAD * 2, unallocH)
    end
end

-- ============================================================
-- Tab 2: Linked Vehicles
-- ============================================================
function RVManagerPanel:renderTab2(x, y)
    if self.filterCombo then self.filterCombo:setY(y) end
    if self.filterEntry then self.filterEntry:setY(y) end
    self:drawText(getText("IGUI_RVM_FilterLabel"), x, y + 6, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    y = y + FILTER_H + PAD

    self:renderAssignments(x, y)
end

-- ============================================================
-- Summary table
-- ============================================================
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

    self:drawRect(x, y, SCOL_TOTAL, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, SCOL_TOTAL, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawRect(x, y, 4, HDR_H, 1, T.accent.r, T.accent.g, T.accent.b)

    local cx = x
    for i, h in ipairs(hdrs) do
        self.scolX[i] = cx
        local ind, ir, ig, ib
        if self.summarySortCol == i then
            ind = self.summarySortAsc and "^" or "v"
            ir, ig, ib = 1.0, 0.85, 0.2
        else
            ind = "^v"
            ir, ig, ib = T.muted.r, T.muted.g, T.muted.b
        end
        local indW = tm:MeasureStringX(UIFont.Small, ind) + 2
        self:drawText(trimText(UIFont.Small, h, SCOL[i] - indW - 6), cx + 2, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
        self:drawText(ind, cx + SCOL[i] - indW - 1, y + 2, ir, ig, ib, 1, UIFont.Small)
        cx = cx + SCOL[i]
    end
    y = y + HDR_H

    if not self.data.summary then
        local vlX = x + SCOL_TOTAL + PAD
        local vlW = self.width - PAD - vlX
        if vlW > 60 then self:renderVehicleList(vlX, self.summaryHdrY, vlW, HDR_H) end
        return y
    end

    local types    = self:getSortedSummaryTypes()
    local totalH   = #types * ROW_H
    local clampH   = math.min(totalH, SUMMARY_MAX_H)
    local maxScroll = math.max(0, totalH - clampH)
    self.summaryScrollY = math.max(0, math.min(maxScroll, self.summaryScrollY))

    self.summaryRegionY = y
    self.summaryRegionH = clampH

    self:setStencilRect(x, y, SCOL_TOTAL, clampH)

    local rowY = y - self.summaryScrollY
    local clr = {
        T.text,
        T.muted,
        T.text,
        { r=0.90, g=0.50, b=0.50 },
        { r=0.50, g=0.85, b=0.50 },
    }

    for idx, typeKey in ipairs(types) do
        if rowY + ROW_H > y and rowY < y + clampH then
            local selected = typeKey == self.selectedSummaryType
            local bg = selected and T.rowSel or ((idx % 2 == 0) and T.rowA or T.rowB)
            self:drawRect(x, rowY, SCOL_TOTAL, ROW_H, 1, bg.r, bg.g, bg.b)
            self:drawRect(x, rowY + ROW_H - 1, SCOL_TOTAL, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)

            local s       = self.data.summary[typeKey]
            local sizeStr = (s.roomW and s.roomH) and (s.roomW .. "x" .. s.roomH) or "-"
            local row     = { typeKey, sizeStr, tostring(s.totalRooms), tostring(s.occupied), tostring(s.free) }
            cx = x
            for i, val in ipairs(row) do
                local str = trimText(UIFont.Small, val, SCOL[i] - 4)
                self:drawText(str, cx + 2, rowY + 1, clr[i].r, clr[i].g, clr[i].b, 1, UIFont.Small)
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
        self:drawRect(x + SCOL_TOTAL - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
    end

    local vlX = x + SCOL_TOTAL + PAD
    local vlW = self.width - PAD - vlX
    if vlW > 60 then
        self:renderVehicleList(vlX, self.summaryHdrY, vlW, HDR_H + clampH)
    end

    return y + clampH
end

-- ============================================================
-- Vehicle list (right of summary)
-- ============================================================
function RVManagerPanel:renderVehicleList(x, y, w, totalH)
    local searchH   = FILTER_H
    local listAreaH = math.max(0, totalH - HDR_H - searchH - VL_CTRL_H)

    self:drawRect(x, y, w, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, w, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawRect(x, y, 4, HDR_H, 1, T.accent.r, T.accent.g, T.accent.b)

    local title = self.selectedSummaryType or getText("IGUI_RVM_VehList_SelectPrompt")
    self:drawText(trimText(UIFont.Small, title, w - 10), x + 6, y + 2,
                  T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + HDR_H

    if self.vehicleSearchEntry then
        self.vehicleSearchEntry:setX(x)
        self.vehicleSearchEntry:setY(y)
        self.vehicleSearchEntry:setWidth(w)
        self.vehicleSearchEntry:setHeight(searchH)
    end
    y = y + searchH

    self.vehicleListX       = x
    self.vehicleListW       = w
    self.vehicleListRegionY = y
    self.vehicleListRegionH = listAreaH

    local RESET_BTN_W = 120
    local ctrlY   = y + listAreaH + 1
    local entryW  = w - VL_ADD_BTN_W - VL_REMOVE_BTN_W - RESET_BTN_W - PAD * 4
    local addBtnX = x + entryW + PAD
    local rmBtnX  = addBtnX + VL_ADD_BTN_W + PAD
    local resetBtnX = rmBtnX + VL_REMOVE_BTN_W + PAD
    local entryH  = FILTER_H - 2

    -- Store position for dropdown rendering and click detection
    self.addDropdownX       = x
    self.addDropdownW       = entryW
    self.addDropdownEntryY  = ctrlY
    self.addDropdownEntryH  = entryH

    -- Update dropdown: rebuild options when search text changes
    local addSearch = ""
    if self.vehicleAddEntry then
        local raw = self.vehicleAddEntry:getText()
        if type(raw) == "string" then addSearch = raw:lower():match("^%s*(.-)%s*$") or "" end
    end
    if addSearch ~= self.addDropdownLastSearch then
        self.addDropdownLastSearch = addSearch
        self.addDropdownScrollY    = 0
        if addSearch ~= "" then
            self.addDropdownItems = self:getAddDropdownOptions(addSearch)
            self.addDropdownOpen  = #self.addDropdownItems > 0
        else
            self.addDropdownItems = {}
            self.addDropdownOpen  = false
        end
    end

    self:drawRect(x, y + listAreaH, w, 1, 1, T.divider.r, T.divider.g, T.divider.b)

    if self.vehicleAddEntry then
        self.vehicleAddEntry:setX(x)
        self.vehicleAddEntry:setY(ctrlY)
        self.vehicleAddEntry:setWidth(entryW)
        self.vehicleAddEntry:setHeight(entryH)
    end
    if self.btnAddVehicle then
        self.btnAddVehicle:setX(addBtnX)
        self.btnAddVehicle:setY(ctrlY)
        self.btnAddVehicle:setWidth(VL_ADD_BTN_W)
        self.btnAddVehicle:setHeight(FILTER_H - 2)
    end
    if self.btnRemoveVehicle then
        self.btnRemoveVehicle:setX(rmBtnX)
        self.btnRemoveVehicle:setY(ctrlY)
        self.btnRemoveVehicle:setWidth(VL_REMOVE_BTN_W)
        self.btnRemoveVehicle:setHeight(FILTER_H - 2)
    end
    if self.btnResetTypes then
        self.btnResetTypes:setX(resetBtnX)
        self.btnResetTypes:setY(ctrlY)
        self.btnResetTypes:setWidth(RESET_BTN_W)
        self.btnResetTypes:setHeight(FILTER_H - 2)
    end

    if not self.selectedSummaryType then
        self:drawRect(x, y, w, listAreaH, 0.25, T.rowA.r, T.rowA.g, T.rowA.b)
        return
    end

    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return end
    local typeDef = RV.VehicleTypes[self.selectedSummaryType]
    if not typeDef or not typeDef.scripts then return end

    local search = ""
    if self.vehicleSearchEntry then
        local raw = self.vehicleSearchEntry:getText()
        if type(raw) == "string" then search = raw:lower():match("^%s*(.-)%s*$") or "" end
    end
    if search ~= (self.vehicleListLastSearch or "") then
        self.vehicleListLastSearch = search
        self.vehicleListScrollY    = 0
    end

    local filtered = {}
    for _, script in ipairs(typeDef.scripts) do
        if search == "" or script:lower():find(search, 1, true) then
            table.insert(filtered, script)
        end
    end

    local totalScriptH = #filtered * ROW_H
    local maxScroll    = math.max(0, totalScriptH - listAreaH)
    self.vehicleListScrollY = math.max(0, math.min(maxScroll, self.vehicleListScrollY))

    if listAreaH > 0 then
        self:setStencilRect(x, y, w, listAreaH)
        local rowY = y - self.vehicleListScrollY
        for idx, script in ipairs(filtered) do
            if rowY + ROW_H > y and rowY < y + listAreaH then
                local sel = script == self.vehicleListSelected
                local bg  = sel and T.rowSel or ((idx % 2 == 0) and T.rowA or T.rowB)
                self:drawRect(x, rowY, w, ROW_H, 1, bg.r, bg.g, bg.b)
                self:drawRect(x, rowY + ROW_H - 1, w, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)
                local display = script:match("%.(.+)") or script
                self:drawText(trimText(UIFont.Small, display, w - 8), x + 3, rowY + 1,
                              T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
            end
            rowY = rowY + ROW_H
        end
        self:clearStencilRect()

        if totalScriptH > listAreaH then
            local barH  = math.max(12, listAreaH * listAreaH / totalScriptH)
            local ratio = maxScroll > 0 and self.vehicleListScrollY / maxScroll or 0
            local barY  = y + ratio * (listAreaH - barH)
            self:drawRect(x + w - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
        end
    end
end

-- ============================================================
-- Unallocated vehicles list
-- ============================================================
function RVManagerPanel:renderUnallocated(x, y, w, h)
    self:drawRect(x, y, w, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, w, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawRect(x, y, 4, HDR_H, 1, T.accent.r, T.accent.g, T.accent.b)
    self:drawText(getText("IGUI_RVM_Unalloc_Title"), x + 6, y + 2,
                  T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + HDR_H

    local listH = h - HDR_H
    if listH <= 0 then return end

    self.unallocRegionX = x
    self.unallocRegionY = y
    self.unallocRegionH = listH
    self.unallocRegionW = w

    local scripts = self:getUnallocatedScripts()

    if #scripts == 0 then
        self:drawRect(x, y, w, listH, 0.25, T.rowA.r, T.rowA.g, T.rowA.b)
        self:drawText(getText("IGUI_RVM_Unalloc_Empty"), x + 6, y + 4,
                      T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
        return
    end

    local totalH    = #scripts * ROW_H
    local maxScroll = math.max(0, totalH - listH)
    self.unallocScrollY = math.max(0, math.min(maxScroll, self.unallocScrollY))

    self:setStencilRect(x, y, w, listH)
    local rowY = y - self.unallocScrollY
    for idx, script in ipairs(scripts) do
        if rowY + ROW_H > y and rowY < y + listH then
            local sel = script == self.unallocSelected
            local bg  = sel and T.rowSel or ((idx % 2 == 0) and T.rowA or T.rowB)
            self:drawRect(x, rowY, w, ROW_H, 1, bg.r, bg.g, bg.b)
            self:drawRect(x, rowY + ROW_H - 1, w, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)
            local display = script:match("%.(.+)") or script
            self:drawText(trimText(UIFont.Small, display, w - 8), x + 3, rowY + 1,
                          T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
        end
        rowY = rowY + ROW_H
    end
    self:clearStencilRect()

    if totalH > listH then
        local barH  = math.max(12, listH * listH / totalH)
        local ratio = maxScroll > 0 and self.unallocScrollY / maxScroll or 0
        local barY  = y + ratio * (listH - barH)
        self:drawRect(x + w - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
    end
end

-- ============================================================
-- Assignment table
-- ============================================================
function RVManagerPanel:renderAssignments(x, y)
    local assignments = self:getFilteredAssignments()
    if not assignments then return end

    local nameW = math.max(80, self.width - PAD * 2 - ACOL_FIXED_TOTAL)
    local acol  = { ACOL_FIXED[1], nameW, ACOL_FIXED[2], ACOL_FIXED[3], ACOL_FIXED[4], ACOL_FIXED[5], ACOL_FIXED[6], ACOL_FIXED[7] }
    local ahdr  = {
        getText("IGUI_RVM_Col_VehicleID"),
        getText("IGUI_RVM_Col_Name"),
        getText("IGUI_RVM_Col_VehPos"),
        getText("IGUI_RVM_Col_RVType"),
        getText("IGUI_RVM_Col_RVPos"),
        getText("IGUI_RVM_Col_Linked"),
        getText("IGUI_RVM_Col_LastIn"),
        getText("IGUI_RVM_Col_LastOut"),
    }

    self.acol       = acol
    self.acolX      = {}
    self.assignHdrY = y

    self:drawRect(x, y, self.width - PAD * 2, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, self.width - PAD * 2, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawRect(x, y, 4, HDR_H, 1, T.accent.r, T.accent.g, T.accent.b)

    local tm = getTextManager()
    local cx = x
    for i, hdr in ipairs(ahdr) do
        self.acolX[i] = cx
        local ind, ir, ig, ib
        if self.sortCol == i then
            ind = self.sortAsc and "^" or "v"
            ir, ig, ib = 1.0, 0.85, 0.2
        else
            ind = "^v"
            ir, ig, ib = T.muted.r, T.muted.g, T.muted.b
        end
        local indW = tm:MeasureStringX(UIFont.Small, ind) + 2
        self:drawText(trimText(UIFont.Small, hdr, acol[i] - indW - 6), cx + 2, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
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
    local function fmt(v)    return v ~= nil and tostring(v) or "-" end
    local function fmtPos(p) if not p then return "-" end return string.format("%.0f, %.0f", p.x or 0, p.y or 0) end

    for idx, a in ipairs(assignments) do
        if rowY + ROW_H > y and rowY < y + contentH then
            local selected = tostring(a.rvVehicleUniqueId) == self.selectedRvId
            local bg = selected and T.rowSel or (idx % 2 == 0 and T.rowA or T.rowB)
            self:drawRect(x, rowY, self.width - PAD * 2, ROW_H, 1, bg.r, bg.g, bg.b)
            self:drawRect(x, rowY + ROW_H - 1, self.width - PAD * 2, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)

            local cols = {
                fmt(a.rvVehicleUniqueId), fmt(a.vehicleName),
                fmtPos(a.lastPos), fmt(a.typeKey), fmtPos(a.room),
                fmt(a.dateLinked), fmt(a.lastEnterDate), fmt(a.lastOutDate),
            }
            cx = x
            for i, val in ipairs(cols) do
                self:drawText(trimText(UIFont.Small, val, acol[i] - 4), cx + 2, rowY + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
                cx = cx + acol[i]
            end
        end
        rowY = rowY + ROW_H
    end

    self:clearStencilRect()

    local totalH = #assignments * ROW_H
    if totalH > contentH then
        local barH  = math.max(20, contentH * contentH / totalH)
        local ratio = (totalH - contentH > 0) and self.scrollY / (totalH - contentH) or 0
        local barY  = y + ratio * (contentH - barH)
        self:drawRect(self.width - PAD - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
    end
end

-- ============================================================
-- Input
-- ============================================================
function RVManagerPanel:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)

    -- Dropdown overlay (must be checked first — it sits on top)
    if self.activeTab == 1 and self.addDropdownOpen then
        local dx = self.addDropdownRenderX
        local dy = self.addDropdownRenderY
        local dw = self.addDropdownRenderW
        local dh = self.addDropdownRenderH
        if x >= dx and x < dx + dw and y >= dy and y < dy + dh then
            local relY   = y - dy + self.addDropdownScrollY
            local rowIdx = math.floor(relY / ROW_H) + 1
            if rowIdx >= 1 and rowIdx <= #self.addDropdownItems then
                local script = self.addDropdownItems[rowIdx].script
                if self.vehicleAddEntry then self.vehicleAddEntry:setText(script) end
                self.addDropdownOpen       = false
                self.addDropdownLastSearch = script
                self.addDropdownItems      = {}
                self:updateVehicleListButtons()
            end
            return
        else
            self.addDropdownOpen = false
        end
    end

    -- Tab bar
    if y >= self.tabBarY and y < self.tabBarY + TAB_H then
        if x >= self.tab1X and x < self.tab1X + TAB_W then
            if self.activeTab ~= 1 then
                self.activeTab    = 1
                self.selectedRvId = nil
                self:updateButtons()
            end
        elseif x >= self.tab2X and x < self.tab2X + TAB_W then
            if self.activeTab ~= 2 then
                self.activeTab           = 2
                self.selectedSummaryType = nil
                self.vehicleListSelected = nil
                self.unallocSelected     = nil
                self:updateVehicleListButtons()
            end
        end
        return
    end

    if not self.data then return end

    if self.activeTab == 1 then
        -- Summary header sort
        if y >= self.summaryHdrY and y < self.summaryHdrY + HDR_H and #self.scolX > 0 then
            for i, startX in ipairs(self.scolX) do
                if x >= startX and x < startX + (SCOL[i] or 0) then
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

        -- Summary body — select type
        if y >= self.summaryRegionY and y < self.summaryRegionY + self.summaryRegionH
            and x >= PAD and x < PAD + SCOL_TOTAL then
            local types  = self:getSortedSummaryTypes()
            local relY   = y - self.summaryRegionY + self.summaryScrollY
            local rowIdx = math.floor(relY / ROW_H) + 1
            if rowIdx >= 1 and rowIdx <= #types then
                local clicked = types[rowIdx]
                if self.selectedSummaryType == clicked then
                    self.selectedSummaryType = nil
                else
                    self.selectedSummaryType   = clicked
                    self.vehicleListScrollY    = 0
                    self.vehicleListLastSearch = ""
                    if self.vehicleSearchEntry then self.vehicleSearchEntry:setText("") end
                end
                self.vehicleListSelected = nil
                self:updateVehicleListButtons()
            end
            return
        end

        -- Vehicle list — select script
        if y >= self.vehicleListRegionY and y < self.vehicleListRegionY + self.vehicleListRegionH
            and x >= self.vehicleListX and x < self.vehicleListX + self.vehicleListW
            and self.selectedSummaryType then
            local ok, RV = pcall(require, "RVVehicleTypes")
            if ok and RV and RV.VehicleTypes then
                local typeDef = RV.VehicleTypes[self.selectedSummaryType]
                if typeDef and typeDef.scripts then
                    local search   = self.vehicleListLastSearch or ""
                    local filtered = {}
                    for _, s in ipairs(typeDef.scripts) do
                        if search == "" or s:lower():find(search, 1, true) then
                            table.insert(filtered, s)
                        end
                    end
                    local relY   = y - self.vehicleListRegionY + self.vehicleListScrollY
                    local rowIdx = math.floor(relY / ROW_H) + 1
                    if rowIdx >= 1 and rowIdx <= #filtered then
                        local script = filtered[rowIdx]
                        self.vehicleListSelected = (self.vehicleListSelected == script) and nil or script
                        self:updateVehicleListButtons()
                    end
                end
            end
            return
        end

        -- Unallocated list — select and pre-fill add entry
        if y >= self.unallocRegionY and y < self.unallocRegionY + self.unallocRegionH
            and x >= self.unallocRegionX and x < self.unallocRegionX + self.unallocRegionW then
            local scripts = self:getUnallocatedScripts()
            local relY    = y - self.unallocRegionY + self.unallocScrollY
            local rowIdx  = math.floor(relY / ROW_H) + 1
            if rowIdx >= 1 and rowIdx <= #scripts then
                local script = scripts[rowIdx]
                self.unallocSelected = (self.unallocSelected == script) and nil or script
                if self.unallocSelected and self.vehicleAddEntry then
                    self.vehicleAddEntry:setText(self.unallocSelected)
                end
                self:updateVehicleListButtons()
            end
            return
        end

    else -- Tab 2
        -- Assignment header sort
        if y >= self.assignHdrY and y < self.assignHdrY + HDR_H and #self.acolX > 0 then
            for i, startX in ipairs(self.acolX) do
                if x >= startX and x < startX + (self.acol[i] or 0) then
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
end

function RVManagerPanel:onMouseWheel(del)
    if not self.data then return false end

    local mx   = self:getMouseX()
    local my   = self:getMouseY()
    local step = del * ROW_H * 3

    -- Dropdown scroll takes priority
    if self.activeTab == 1 and self.addDropdownOpen then
        local dx = self.addDropdownRenderX
        local dy = self.addDropdownRenderY
        local dw = self.addDropdownRenderW
        local dh = self.addDropdownRenderH
        if mx >= dx and mx < dx + dw and my >= dy and my < dy + dh then
            local maxScroll = math.max(0, #self.addDropdownItems * ROW_H - dh)
            self.addDropdownScrollY = math.max(0, math.min(maxScroll, self.addDropdownScrollY + step))
            return true
        end
    end

    if self.activeTab == 1 then
        -- Summary scroll
        if my >= self.summaryRegionY and my < self.summaryRegionY + self.summaryRegionH
            and mx < PAD + SCOL_TOTAL then
            local count = 0
            if self.data.summary then for _ in pairs(self.data.summary) do count = count + 1 end end
            local maxScroll = math.max(0, count * ROW_H - self.summaryRegionH)
            self.summaryScrollY = math.max(0, math.min(maxScroll, self.summaryScrollY + step))

        -- Vehicle list scroll
        elseif my >= self.vehicleListRegionY and my < self.vehicleListRegionY + self.vehicleListRegionH
            and mx >= self.vehicleListX and self.selectedSummaryType then
            local ok, RV = pcall(require, "RVVehicleTypes")
            if ok and RV and RV.VehicleTypes then
                local typeDef = RV.VehicleTypes[self.selectedSummaryType]
                if typeDef and typeDef.scripts then
                    local search = self.vehicleListLastSearch or ""
                    local count  = 0
                    for _, s in ipairs(typeDef.scripts) do
                        if search == "" or s:lower():find(search, 1, true) then count = count + 1 end
                    end
                    local maxScroll = math.max(0, count * ROW_H - self.vehicleListRegionH)
                    self.vehicleListScrollY = math.max(0, math.min(maxScroll, self.vehicleListScrollY + step))
                end
            end

        -- Unallocated list scroll
        elseif my >= self.unallocRegionY and my < self.unallocRegionY + self.unallocRegionH
            and mx >= self.unallocRegionX then
            local scripts   = self:getUnallocatedScripts()
            local maxScroll = math.max(0, #scripts * ROW_H - self.unallocRegionH)
            self.unallocScrollY = math.max(0, math.min(maxScroll, self.unallocScrollY + step))
        end

    else -- Tab 2
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

    local carField     = getText("IGUI_RVM_FilterField_Car")
    local vidField     = getText("IGUI_RVM_FilterField_VehicleID")
    local rvTypeField  = getText("IGUI_RVM_FilterField_RVType")
    local roomLocField = getText("IGUI_RVM_FilterField_RoomLoc")
    local vehLocField  = getText("IGUI_RVM_FilterField_VehicleLoc")
    local linkedField  = getText("IGUI_RVM_FilterField_LinkedAt")
    local lastInField  = getText("IGUI_RVM_FilterField_LastIn")
    local lastOutField = getText("IGUI_RVM_FilterField_LastOut")

    local function fmt(v)    return v ~= nil and tostring(v) or "-" end
    local function fmtPos(p) if not p then return "-" end return string.format("%.0f, %.0f", p.x or 0, p.y or 0) end

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
        if include then table.insert(result, a) end
    end

    -- Convert "DD/MM/YYYY HH:MM" to a sortable integer (YYYYMMDDHHM).
    -- Returns 0 for missing/unparseable values so they sort first.
    local function dateToInt(s)
        if not s or s == "" or s == "-" then return 0 end
        local d, m, y, hh, mm = s:match("(%d+)/(%d+)/(%d+) (%d+):(%d+)")
        if not d then return 0 end
        return tonumber(y)*100000000 + tonumber(m)*1000000 + tonumber(d)*10000
             + tonumber(hh)*100 + tonumber(mm)
    end

    local sortKeys = {
        function(a) return tostring(a.rvVehicleUniqueId or "") end,
        function(a) return tostring(a.vehicleName or ""):lower() end,
        function(a) return a.lastPos and (a.lastPos.x or 0) or 0 end,
        function(a) return tostring(a.typeKey or ""):lower() end,
        function(a) return a.room and (a.room.x or 0) or 0 end,
        function(a) return dateToInt(a.dateLinked) end,
        function(a) return dateToInt(a.lastEnterDate) end,
        function(a) return dateToInt(a.lastOutDate) end,
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
-- Tooltip
-- ============================================================
function RVManagerPanel:getTooltipAt(mx, my)
    if not self.data then return nil end

    local function fmt(v)    return v ~= nil and tostring(v) or "-" end
    local function fmtPos(p) return p and string.format("%.0f, %.0f", p.x or 0, p.y or 0) or "-" end

    if self.activeTab == 2
        and my >= self.assignTableY and my < self.assignTableY + self.assignContentH
        and #self.acolX > 0 then
        local filtered = self:getFilteredAssignments()
        local relY     = my - self.assignTableY + self.scrollY
        local rowIdx   = math.floor(relY / ROW_H) + 1
        if rowIdx >= 1 and rowIdx <= #filtered then
            local a    = filtered[rowIdx]
            local cols = {
                fmt(a.rvVehicleUniqueId), fmt(a.vehicleName),
                fmtPos(a.lastPos), fmt(a.typeKey), fmtPos(a.room),
                fmt(a.dateLinked), fmt(a.lastEnterDate), fmt(a.lastOutDate),
            }
            for i, startX in ipairs(self.acolX) do
                if mx >= startX and mx < startX + (self.acol[i] or 0) then
                    return cols[i]
                end
            end
        end
    end

    if self.activeTab == 1
        and my >= self.summaryRegionY and my < self.summaryRegionY + self.summaryRegionH
        and self.data.summary then
        local types = self:getSortedSummaryTypes()
        local relY   = my - self.summaryRegionY + self.summaryScrollY
        local rowIdx = math.floor(relY / ROW_H) + 1
        if rowIdx >= 1 and rowIdx <= #types then
            local s       = self.data.summary[types[rowIdx]]
            local sizeStr = (s.roomW and s.roomH) and (s.roomW .. "x" .. s.roomH) or "-"
            local cols    = { types[rowIdx], sizeStr, tostring(s.totalRooms), tostring(s.occupied), tostring(s.free) }
            local cx = PAD
            for i, w in ipairs(SCOL) do
                if mx >= cx and mx < cx + w then return cols[i] end
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
        if tostring(a.rvVehicleUniqueId) == self.selectedRvId then return a end
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
        -- Prefer the authoritative scriptsState snapshot (handles reset correctly).
        -- Fall back to applyScriptOverrides for backward compatibility.
        if args and args.scriptsState then
            local ok, RV = pcall(require, "RVVehicleTypes")
            if ok and RV and RV.VehicleTypes then
                for tk, scripts in pairs(args.scriptsState) do
                    if RV.VehicleTypes[tk] then
                        RV.VehicleTypes[tk].scripts = scripts
                    end
                end
            end
        elseif args and args.scriptOverrides then
            RVM.applyScriptOverrides(args.scriptOverrides)
        end
        panel:receiveData(args)
    elseif command == "dissociateResult" or command == "associateResult" then
        if args and args.ok then panel:requestData() end
    elseif command == "idleCheckResult" then
        panel:requestData()
    elseif command == "scriptOverrideResult" then
        if args and args.ok then panel:requestData() end
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
    local pw = math.floor(sw * 0.65)
    local ph = math.floor(sh * 0.82)
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
