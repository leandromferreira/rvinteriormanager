-- RV Interior Manager — Admin Panel (Client / SP)
-- Core: class definition, shared theme/constants (RVMUI namespace), lifecycle,
-- render dispatch and admin-panel integration. The per-tab rendering, data
-- helpers and input handling live in the RVMAdminPanel<Section>.lua files,
-- which load after this one (alphabetical order: '.' sorts before letters) and
-- attach their methods to the RVManagerPanel class defined here.

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

-- Tab 1 layout
local LEFT_W    = 268
local BADGE_W   = 100
local DEL_W     = 22
local PAGI_H    = 32
local HELP_H    = 108

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
-- Shared namespace — consumed by the RVMAdminPanel<Section>.lua files via
-- `local UI = RVMUI` aliases. Holds the theme, layout constants and the two
-- pure helpers so the split files can reference them without redefining.
-- ============================================================
RVMUI = RVMUI or {}
RVMUI.T          = T
RVMUI.styleBtn   = styleBtn
RVMUI.trimText   = trimText
RVMUI.PAD        = PAD
RVMUI.ROW_H      = ROW_H
RVMUI.HDR_H      = HDR_H
RVMUI.TITLE_H    = TITLE_H
RVMUI.FILTER_H   = FILTER_H
RVMUI.BTN_H      = BTN_H
RVMUI.BTN_W      = BTN_W
RVMUI.TAB_H      = TAB_H
RVMUI.TAB_W      = TAB_W
RVMUI.SUMMARY_MAX_H    = SUMMARY_MAX_H
RVMUI.VL_ADD_BTN_W     = VL_ADD_BTN_W
RVMUI.VL_REMOVE_BTN_W  = VL_REMOVE_BTN_W
RVMUI.VL_CTRL_H        = VL_CTRL_H
RVMUI.LEFT_W     = LEFT_W
RVMUI.BADGE_W    = BADGE_W
RVMUI.DEL_W      = DEL_W
RVMUI.PAGI_H     = PAGI_H
RVMUI.HELP_H     = HELP_H
RVMUI.SCOL       = SCOL
RVMUI.SCOL_TOTAL = SCOL_TOTAL
RVMUI.ACOL_FIXED = ACOL_FIXED
RVMUI.ACOL_FIXED_TOTAL = ACOL_FIXED_TOTAL

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

    o.typeListPage       = 1
    o.typeListPageBtns   = {}
    o.typeListPageBtnY   = 0
    o.typeListPageBtnH   = 0
    o.typeListTotalPages = 1
    o.typeListFilteredN  = 0
    o.typeListRegionY    = 0
    o.typeListRegionH    = 0
    o.typeListCOL1_W     = 0

    o.crossSearchLast    = ""
    o.crossSearchResults = {}
    o.crossListScrollY   = 0
    o.crossListRegionY   = 0
    o.crossListRegionH   = 0
    o.crossListRegionX   = 0
    o.crossListRegionW   = 0

    o.vehDelBtns         = {}
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
    close.tooltip = getText("IGUI_RVM_Close")
    styleBtn(close, T.btnDang)
    self:addChild(close)

    local refresh = ISButton:new(self.width - 97, 4, 70, 20,
        getText("IGUI_RVM_Refresh"), self, RVManagerPanel.requestData)
    refresh:initialise()
    refresh.tooltip = getText("IGUI_RVM_Refresh")
    styleBtn(refresh, T.btnPrim)
    self:addChild(refresh)

    -- Action buttons — parked until shown in Tab 2
    local oy = self.height + 50

    self.btnTpVeh = ISButton:new(PAD, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_TpVehicle"), self, RVManagerPanel.teleportToVehicle)
    self.btnTpVeh:initialise()
    self.btnTpVeh.tooltip = getText("IGUI_RVM_Tooltip_TpVehicle")
    styleBtn(self.btnTpVeh, T.btnDef)
    self:addChild(self.btnTpVeh)

    self.btnTpRoom = ISButton:new(PAD + BTN_W + PAD, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_TpRoom"), self, RVManagerPanel.teleportToRoom)
    self.btnTpRoom:initialise()
    self.btnTpRoom.tooltip = getText("IGUI_RVM_Tooltip_TpRoom")
    styleBtn(self.btnTpRoom, T.btnDef)
    self:addChild(self.btnTpRoom)

    self.btnDissoc = ISButton:new(PAD + (BTN_W + PAD) * 2, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_Dissociate"), self, RVManagerPanel.dissociate)
    self.btnDissoc:initialise()
    self.btnDissoc.tooltip = getText("IGUI_RVM_Tooltip_Dissociate")
    styleBtn(self.btnDissoc, T.btnDang)
    self:addChild(self.btnDissoc)

    self.btnForceIdle = ISButton:new(PAD + (BTN_W + PAD) * 3, oy, BTN_W, BTN_H,
        getText("IGUI_RVM_Btn_ForceIdle"), self, RVManagerPanel.forceIdleCleanup)
    self.btnForceIdle:initialise()
    self.btnForceIdle.tooltip = getText("IGUI_RVM_Tooltip_ForceIdle")
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
    self.vehicleAddEntry.tooltip = getText("IGUI_RVM_Tooltip_AddEntry")

    self.btnAddVehicle = ISButton:new(0, oy, VL_ADD_BTN_W, FILTER_H - 2,
        getText("IGUI_RVM_VehList_Add"), self, RVManagerPanel.onAddVehicle)
    self.btnAddVehicle:initialise()
    self.btnAddVehicle.tooltip = getText("IGUI_RVM_Tooltip_AddVehicle")
    styleBtn(self.btnAddVehicle, T.btnOk)
    self:addChild(self.btnAddVehicle)

    self.btnRemoveVehicle = ISButton:new(0, oy, VL_REMOVE_BTN_W, FILTER_H - 2,
        getText("IGUI_RVM_VehList_Remove"), self, RVManagerPanel.onRemoveVehicle)
    self.btnRemoveVehicle:initialise()
    self.btnRemoveVehicle.tooltip = getText("IGUI_RVM_Tooltip_RemoveVehicle")
    styleBtn(self.btnRemoveVehicle, T.btnDang)
    self:addChild(self.btnRemoveVehicle)

    -- Type search (Tab 1 left panel)
    self.typeSearchEntry = ISTextEntryBox:new("", 0, oy, 100, FILTER_H)
    self:addChild(self.typeSearchEntry)
    self.typeSearchEntry:initialise()
    self.typeSearchEntry:setEditable(true)
    self.typeSearchEntry:setPlaceholderText(getText("IGUI_RVM_TypeSearch_Placeholder"))

    -- Cross-type vehicle search (Tab 1 right panel bottom)
    self.crossSearchEntry = ISTextEntryBox:new("", 0, oy, 100, FILTER_H)
    self:addChild(self.crossSearchEntry)
    self.crossSearchEntry:initialise()
    self.crossSearchEntry:setEditable(true)
    self.crossSearchEntry:setPlaceholderText(getText("IGUI_RVM_CrossSearch_Placeholder"))

    self:updateButtons()
    self:requestData()
end

function RVManagerPanel:onClose()
    self:removeFromUIManager()
    RVManagerPanel.instance = nil
end

-- ============================================================
-- Render dispatch
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
        if self.typeSearchEntry    then self.typeSearchEntry:setVisible(false) end
        if self.crossSearchEntry   then self.crossSearchEntry:setVisible(false) end
    end
    local function showVehicleWidgets()
        if self.vehicleSearchEntry then self.vehicleSearchEntry:setVisible(true) end
        if self.vehicleAddEntry    then self.vehicleAddEntry:setVisible(true) end
        if self.btnAddVehicle      then self.btnAddVehicle:setVisible(true) end
        if self.typeSearchEntry    then self.typeSearchEntry:setVisible(true) end
        if self.crossSearchEntry   then self.crossSearchEntry:setVisible(true) end
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
-- Server response listener
-- ============================================================
local function onServerCommand(module, command, args)
    if module ~= RVM.MODULE then return end
    local panel = RVManagerPanel.instance
    if not panel then return end

    if command == "responseData" then
        if args and args.scriptsState and RV and RV.VehicleTypes then
            for tk, scripts in pairs(args.scriptsState) do
                if RV.VehicleTypes[tk] then
                    RV.VehicleTypes[tk].scripts = scripts
                end
            end
        end
        panel:receiveData(args, panel._pendingReceiveOpts)
        panel._pendingReceiveOpts = nil
    elseif command == "dissociateResult" or command == "associateResult" then
        if args and args.ok then
            panel._pendingReceiveOpts = { preserveTypeSelection = true }
            panel:requestData()
        end
    elseif command == "idleCheckResult" then
        panel:requestData()
    elseif command == "scriptOverrideResult" then
        panel._pendingReceiveOpts = { preserveTypeSelection = true }
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
