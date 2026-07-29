-- RV Interior Manager — Admin Panel: Tab 1 rendering (room types + vehicle panel).
-- Methods attach to the RVManagerPanel class defined in RVMAdminPanel.lua.

if isServer() then return end

require("RVMShared")

local UI       = RVMUI
local T        = UI.T
local trimText = UI.trimText
local PAD      = UI.PAD
local ROW_H    = UI.ROW_H
local HDR_H    = UI.HDR_H
local FILTER_H = UI.FILTER_H
local LEFT_W   = UI.LEFT_W
local BADGE_W  = UI.BADGE_W
local DEL_W    = UI.DEL_W
local PAGI_H   = UI.PAGI_H
local HELP_H   = UI.HELP_H

-- ============================================================
-- Add-entry dropdown (overlay)
-- ============================================================
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
-- Tab 1: Room Types (left) + Vehicle Panel (right)
-- ============================================================
function RVManagerPanel:renderTab1(x, y)
    local availH = self.height - y - PAD
    local rightX = x + LEFT_W + PAD + 1
    local rightW = self.width - PAD - rightX

    -- Vertical divider between left and right panels
    self:drawRect(x + LEFT_W + math.floor(PAD / 2), y, 1, availH, 0.7,
        T.divider.r, T.divider.g, T.divider.b)

    self:renderTypeListPanel(x, y, LEFT_W, availH)
    self:renderVehiclePanel(rightX, y, rightW, availH)
end

-- ============================================================
-- Tab 1 Left: type list with search, pagination, help box
-- ============================================================
function RVManagerPanel:renderTypeListPanel(x, y, w, availH)
    local ICON_W  = 20
    local COL_SZ  = 46
    local COL2_W  = 60
    local COL3_W  = 40
    local COL1_W  = w - COL_SZ - COL2_W - COL3_W

    -- Header: icon + title
    self:drawText(getText("IGUI_RVM_TypeList_Title"),
        x + ICON_W + 5, y + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + ICON_W + 2
    self:drawText(getText("IGUI_RVM_TypeList_Subtitle"),
        x, y, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Tiny)
    y = y + 14 + PAD

    -- Search
    if self.typeSearchEntry then
        self.typeSearchEntry:setX(x); self.typeSearchEntry:setY(y)
        self.typeSearchEntry:setWidth(w); self.typeSearchEntry:setHeight(FILTER_H)
    end
    y = y + FILTER_H + PAD

    -- Column headers
    self:drawRect(x, y, w, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, w, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawText(getText("IGUI_RVM_Col_Type"),      x + 4,                         y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Col_Size"),       x + COL1_W + 3,               y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Col_Available"),  x + COL1_W + COL_SZ + 3,     y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Col_Total"),      x + COL1_W + COL_SZ + COL2_W + 3, y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    y = y + HDR_H

    -- Help box and pagination are anchored to the panel bottom
    local helpY  = self.height - PAD - HELP_H
    local pagiY  = helpY - PAD - PAGI_H
    local listH  = pagiY - y - PAD
    self.typeListCOL1_W  = COL1_W
    self.typeListRegionY = y
    self.typeListRegionH = math.max(0, listH)

    -- Build filtered list
    local search = ""
    if self.typeSearchEntry then
        local raw = self.typeSearchEntry:getText()
        if type(raw) == "string" then search = raw:lower():match("^%s*(.-)%s*$") or "" end
    end
    local allTypes = self:getSortedSummaryTypes()
    local filtered = {}
    for _, tk in ipairs(allTypes) do
        if search == "" or tk:lower():find(search, 1, true) then table.insert(filtered, tk) end
    end

    local pageSize   = math.max(1, math.floor(listH / ROW_H))
    local totalPages = math.max(1, math.ceil(#filtered / pageSize))
    self.typeListPage        = math.max(1, math.min(totalPages, self.typeListPage))
    self.typeListTotalPages  = totalPages
    self.typeListFilteredN   = #filtered

    local startIdx = (self.typeListPage - 1) * pageSize + 1
    local endIdx   = math.min(#filtered, startIdx + pageSize - 1)

    if listH > 0 then
        self:setStencilRect(x, y, w, listH)
        local rowY = y
        for i = startIdx, endIdx do
            local tk = filtered[i]
            local s  = self.data.summary and self.data.summary[tk]
            local sel = tk == self.selectedSummaryType
            local alt = (i % 2 == 0)
            local bg  = sel and T.rowSel or (alt and T.rowA or T.rowB)
            self:drawRect(x, rowY, w, ROW_H, 1, bg.r, bg.g, bg.b)
            self:drawRect(x, rowY + ROW_H - 1, w, 1, 0.35, T.divider.r, T.divider.g, T.divider.b)
            self:drawText(trimText(UIFont.Small, tk, COL1_W - 4), x + 4, rowY + 1,
                T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
            if s then
                local sizeStr = (s.roomW and s.roomH) and (s.roomW .. "x" .. s.roomH) or "-"
                local fr = s.free or 0
                local fC = fr > 0 and { r=0.35, g=0.85, b=0.45 } or { r=0.85, g=0.35, b=0.35 }
                self:drawText(sizeStr,              x + COL1_W + 3,               rowY + 1, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
                self:drawText(tostring(fr),          x + COL1_W + COL_SZ + 3,     rowY + 1, fC.r, fC.g, fC.b, 1, UIFont.Small)
                self:drawText(tostring(s.totalRooms or 0), x + COL1_W + COL_SZ + COL2_W + 3, rowY + 1,
                    T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
            end
            rowY = rowY + ROW_H
        end
        self:clearStencilRect()
    end

    -- Pagination
    local BTN_W   = 24
    local BTN_H   = 20
    local maxShow = math.min(totalPages, 5)
    local startP  = math.max(1, math.min(self.typeListPage - 2, totalPages - maxShow + 1))
    local numBtns = maxShow + 2
    local rowW    = numBtns * BTN_W + (numBtns - 1) * 4
    local px      = x + math.floor((w - rowW) / 2)
    local by      = pagiY + math.floor((PAGI_H - BTN_H) / 2)

    self.typeListPageBtns  = {}
    self.typeListPageBtnY  = by
    self.typeListPageBtnH  = BTN_H

    local function pgBtn(bx, label, page, active)
        local bg = active and T.btnPrim or (page == "prev" or page == "next") and
            { r=0.15, g=0.15, b=0.18 } or T.btnDef
        self:drawRect(bx, by, BTN_W, BTN_H, 1, bg.r, bg.g, bg.b)
        self:drawRectBorder(bx, by, BTN_W, BTN_H, 0.45, T.border.r, T.border.g, T.border.b)
        local lw = getTextManager():MeasureStringX(UIFont.Small, label)
        local tc = (page == "prev" or page == "next") and (active and T.text or T.muted) or T.text
        self:drawText(label, bx + math.floor((BTN_W - lw) / 2), by + 2, tc.r, tc.g, tc.b, 1, UIFont.Small)
        table.insert(self.typeListPageBtns, { x = bx, w = BTN_W, page = page })
    end

    pgBtn(px, "<", "prev", self.typeListPage > 1)
    px = px + BTN_W + 4
    for i = startP, math.min(totalPages, startP + maxShow - 1) do
        pgBtn(px, tostring(i), i, i == self.typeListPage)
        px = px + BTN_W + 4
    end
    pgBtn(px, ">", "next", self.typeListPage < totalPages)

    -- Help box (anchored to bottom of left panel)
    self:drawRect(x, helpY, w, HELP_H, 1, 0.08, 0.08, 0.11)
    self:drawRectBorder(x, helpY, w, HELP_H, 0.65, T.border.r, T.border.g, T.border.b)
    local qW = 16
    self:drawRect(x + w - qW - PAD, helpY + PAD, qW, qW, 1, 0.30, 0.16, 0.55)
    self:drawText("?", x + w - qW - PAD + 4, helpY + PAD + 1, 1, 1, 1, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Help_Title"), x + PAD, helpY + PAD,
        T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    local hy = helpY + PAD + 18
    for _, k in ipairs({ "IGUI_RVM_Help_Line1", "IGUI_RVM_Help_Line2", "IGUI_RVM_Help_Line3" }) do
        self:drawText(trimText(UIFont.Tiny, getText(k), w - PAD * 2),
            x + PAD, hy, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Tiny)
        hy = hy + 14
    end

    -- Reset button drawn at bottom of help box
    local rbH  = 20
    local rbX  = x + PAD
    local rbY  = helpY + HELP_H - PAD - rbH
    local rbW  = w - PAD * 2
    local mx   = self:getMouseX()
    local my   = self:getMouseY()
    local hover = mx >= rbX and mx < rbX + rbW and my >= rbY and my < rbY + rbH
    local bc   = hover and T.btnWarn or { r = T.btnWarn.r * 0.8, g = T.btnWarn.g * 0.8, b = T.btnWarn.b * 0.8 }
    self:drawRect(rbX, rbY, rbW, rbH, 1, bc.r, bc.g, bc.b)
    self:drawRectBorder(rbX, rbY, rbW, rbH, 0.5, T.border.r, T.border.g, T.border.b)
    local lbl  = getText("IGUI_RVM_Btn_ResetTypes")
    local lblW = getTextManager():MeasureStringX(UIFont.Small, lbl)
    self:drawText(lbl, rbX + math.floor((rbW - lblW) / 2), rbY + 2,
        T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    self.resetBtnRect = { x = rbX, y = rbY, w = rbW, h = rbH }

    -- Hover tooltip for reset button
    if hover then
        local tip    = getText("IGUI_RVM_Tooltip_ResetTypes")
        local tm2    = getTextManager()
        local tipW   = tm2:MeasureStringX(UIFont.Tiny, tip) + 8
        local tipH   = 16
        local tipX   = rbX
        local tipY   = rbY - tipH - 2
        self:drawRect(tipX, tipY, tipW, tipH, 0.92, 0.12, 0.12, 0.16)
        self:drawRectBorder(tipX, tipY, tipW, tipH, 0.7, T.border.r, T.border.g, T.border.b)
        self:drawText(tip, tipX + 4, tipY + 2, T.text.r, T.text.g, T.text.b, 1, UIFont.Tiny)
    end
end

-- ============================================================
-- Tab 1 Right: vehicle list (top) + cross-type search (bottom)
-- ============================================================
function RVManagerPanel:renderVehiclePanel(x, y, w, availH)
    local vehicleH = math.floor(availH * 0.56)
    local crossH   = availH - vehicleH - PAD
    self:renderVehicleTypePanel(x, y, w, vehicleH)
    self:drawRect(x, y + vehicleH + math.floor(PAD / 2), w, 1, 0.5, T.divider.r, T.divider.g, T.divider.b)
    self:renderCrossSearchSection(x, y + vehicleH + PAD, w, crossH)
end

function RVManagerPanel:renderVehicleTypePanel(x, startY, w, totalH)
    local tm     = getTextManager()
    local ACT_W  = BADGE_W + DEL_W + PAD
    local VEH_W  = w - ACT_W
    local y      = startY

    -- Title
    local typeLabel = self.selectedSummaryType or ""
    local titleStr  = getText("IGUI_RVM_VehCompat_Title")
        .. (typeLabel ~= "" and (": " .. typeLabel) or "")
    self:drawText(trimText(UIFont.Medium, titleStr, w),
        x, y + 1, T.text.r, T.text.g, T.text.b, 1, UIFont.Medium)
    y = y + 22

    -- Search + count
    local searchW = w - 90 - PAD
    if self.vehicleSearchEntry then
        self.vehicleSearchEntry:setX(x); self.vehicleSearchEntry:setY(y)
        self.vehicleSearchEntry:setWidth(searchW); self.vehicleSearchEntry:setHeight(FILTER_H)
    end
    local scriptCount = 0
    if self.selectedSummaryType then
        local ss = self.data and self.data.scriptsState
        local typeScripts = ss and ss[self.selectedSummaryType]
        if typeScripts then scriptCount = #typeScripts end
    end
    local countStr = tostring(scriptCount) .. " " .. getText("IGUI_RVM_VehicleCount")
    local cw = tm:MeasureStringX(UIFont.Small, countStr)
    self:drawText(countStr, x + w - cw, y + math.floor((FILTER_H - tm:getFontHeight(UIFont.Small)) / 2),
        T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    y = y + FILTER_H + PAD

    -- Column headers
    self:drawRect(x, y, w, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, w, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawText(getText("IGUI_RVM_Col_Vehicle"), x + 4,         y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Col_Actions"), x + VEH_W + 4, y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    y = y + HDR_H

    local ADD_ROW_H = FILTER_H + PAD
    local usedAbove = 22 + FILTER_H + PAD + HDR_H
    local listH     = totalH - usedAbove - ADD_ROW_H - PAD

    self.vehicleListRegionY = y
    self.vehicleListRegionH = listH
    self.vehicleListX       = x
    self.vehicleListW       = w
    self.vehDelBtns         = {}

    if not self.selectedSummaryType then
        self:drawRect(x, y, w, listH, 0.20, T.rowA.r, T.rowA.g, T.rowA.b)
    else
        local scripts = {}
        local ss = self.data and self.data.scriptsState
        local typeScripts = ss and ss[self.selectedSummaryType]
        if typeScripts then
            local srch = ""
            if self.vehicleSearchEntry then
                local raw = self.vehicleSearchEntry:getText()
                if type(raw) == "string" then srch = raw:lower():match("^%s*(.-)%s*$") or "" end
            end
            if srch ~= (self.vehicleListLastSearch or "") then
                self.vehicleListLastSearch = srch
                self.vehicleListScrollY    = 0
            end
            for _, s in ipairs(typeScripts) do
                if srch == "" or s:lower():find(srch, 1, true) then table.insert(scripts, s) end
            end
        end

        local totalSH = #scripts * ROW_H
        local maxSc   = math.max(0, totalSH - listH)
        self.vehicleListScrollY = math.max(0, math.min(maxSc, self.vehicleListScrollY))

        -- Build lookup for server-known scripts
        local allScriptsSet = {}
        local hasServerList = self.data and self.data.allVehicleScripts ~= nil
        if hasServerList then
            for _, s in ipairs(self.data.allVehicleScripts) do allScriptsSet[s] = true end
        end

        if listH > 0 then
            self:setStencilRect(x, y, w, listH)
            local rowY = y - self.vehicleListScrollY
            for idx, script in ipairs(scripts) do
                if rowY + ROW_H > y and rowY < y + listH then
                    local sel = script == self.vehicleListSelected
                    local bg  = sel and T.rowSel or ((idx % 2 == 0) and T.rowA or T.rowB)
                    self:drawRect(x, rowY, w, ROW_H, 1, bg.r, bg.g, bg.b)
                    self:drawRect(x, rowY + ROW_H - 1, w, 1, 0.35, T.divider.r, T.divider.g, T.divider.b)
                    self:drawText(trimText(UIFont.Small, script, VEH_W - 4), x + 4, rowY + 1,
                        T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
                    -- Status badge
                    local bx   = x + VEH_W
                    local bh   = ROW_H - 4
                    local by2  = rowY + 2
                    local bfh  = tm:getFontHeight(UIFont.Tiny)
                    local tY   = by2 + math.floor((bh - bfh) / 2)
                    local modFound = not hasServerList or allScriptsSet[script]
                    if modFound then
                        self:drawRect(bx, by2, BADGE_W, bh, 1, 0.18, 0.45, 0.26)
                        self:drawRectBorder(bx, by2, BADGE_W, bh, 0.65, 0.28, 0.62, 0.36)
                        local bl  = getText("IGUI_RVM_Badge_Active")
                        local blw = tm:MeasureStringX(UIFont.Tiny, bl)
                        self:drawText(bl, bx + math.floor((BADGE_W - blw) / 2), tY,
                            0.50, 0.95, 0.62, 1, UIFont.Tiny)
                    else
                        self:drawRect(bx, by2, BADGE_W, bh, 1, 0.50, 0.28, 0.05)
                        self:drawRectBorder(bx, by2, BADGE_W, bh, 0.65, 0.70, 0.42, 0.10)
                        local bl  = getText("IGUI_RVM_Badge_NotFound")
                        local blw = tm:MeasureStringX(UIFont.Tiny, bl)
                        self:drawText(bl, bx + math.floor((BADGE_W - blw) / 2), tY,
                            1.0, 0.65, 0.20, 1, UIFont.Tiny)
                    end
                    -- Delete button
                    local dx = bx + BADGE_W + 4
                    self:drawRect(dx, by2, DEL_W, bh, 1, 0.55, 0.18, 0.18)
                    self:drawRectBorder(dx, by2, DEL_W, bh, 0.65, 0.75, 0.28, 0.28)
                    local xl = "X"
                    local xlw = tm:MeasureStringX(UIFont.Small, xl)
                    self:drawText(xl, dx + math.floor((DEL_W - xlw) / 2), by2 + 1, 1, 0.7, 0.7, 1, UIFont.Small)
                    table.insert(self.vehDelBtns, { x=dx, y=rowY, w=DEL_W, h=ROW_H, script=script })
                end
                rowY = rowY + ROW_H
            end
            self:clearStencilRect()
            if totalSH > listH then
                local barH  = math.max(12, listH * listH / totalSH)
                local ratio = maxSc > 0 and self.vehicleListScrollY / maxSc or 0
                local barY  = y + ratio * (listH - barH)
                self:drawRect(x + w - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
            end
        end
    end

    -- Add entry row
    local addY    = y + listH + PAD
    local entryW  = w - 94 - PAD
    self.addDropdownX      = x
    self.addDropdownW      = entryW
    self.addDropdownEntryY = addY
    self.addDropdownEntryH = FILTER_H - 2

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
    if self.vehicleAddEntry then
        self.vehicleAddEntry:setX(x); self.vehicleAddEntry:setY(addY)
        self.vehicleAddEntry:setWidth(entryW); self.vehicleAddEntry:setHeight(FILTER_H - 2)
    end
    if self.btnAddVehicle then
        self.btnAddVehicle:setX(x + entryW + PAD); self.btnAddVehicle:setY(addY)
        self.btnAddVehicle:setWidth(92); self.btnAddVehicle:setHeight(FILTER_H - 2)
    end
    if self.btnRemoveVehicle then self.btnRemoveVehicle:setVisible(false) end
    self:updateVehicleListButtons()
end

-- ============================================================
-- Tab 1 Right bottom: cross-type vehicle search
-- ============================================================
function RVManagerPanel:renderCrossSearchSection(x, y, w, totalH)
    local tm = getTextManager()

    -- Title
    self:drawText(getText("IGUI_RVM_CrossSearch_Title"),
        x, y + 1, T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
    y = y + 18
    self:drawText(trimText(UIFont.Tiny, getText("IGUI_RVM_CrossSearch_Subtitle"), w),
        x, y, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Tiny)
    y = y + 14 + PAD

    -- Search + count
    local search = ""
    if self.crossSearchEntry then
        self.crossSearchEntry:setX(x); self.crossSearchEntry:setY(y)
        self.crossSearchEntry:setWidth(w - 90 - PAD); self.crossSearchEntry:setHeight(FILTER_H)
        local raw = self.crossSearchEntry:getText()
        if type(raw) == "string" then search = raw:match("^%s*(.-)%s*$") or "" end
    end
    if search ~= self.crossSearchLast then
        self.crossSearchLast    = search
        self.crossSearchResults = self:getCrossSearchResults(search:lower())
        self.crossListScrollY   = 0
    end
    local results  = self.crossSearchResults
    local resCount = #results
    local countStr = tostring(resCount) .. " resultado" .. (resCount == 1 and "" or "s")
    local cw       = tm:MeasureStringX(UIFont.Small, countStr)
    self:drawText(countStr, x + w - cw,
        y + math.floor((FILTER_H - tm:getFontHeight(UIFont.Small)) / 2),
        T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    y = y + FILTER_H + PAD

    -- Column headers
    local TYPES_W = math.floor(w * 0.38)
    local VEH_W2  = w - TYPES_W
    self:drawRect(x, y, w, HDR_H, 1, T.hdrBg.r, T.hdrBg.g, T.hdrBg.b)
    self:drawRect(x, y + HDR_H - 1, w, 1, 1, T.divider.r, T.divider.g, T.divider.b)
    self:drawText(getText("IGUI_RVM_Col_Vehicle"),    x + 4,          y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    self:drawText(getText("IGUI_RVM_Col_CompatTypes"), x + VEH_W2 + 4, y + 2, T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
    y = y + HDR_H

    local headersUsed = 18 + 14 + PAD + FILTER_H + PAD + HDR_H
    local listH = totalH - headersUsed
    if listH <= 0 then return end

    self.crossListRegionY = y
    self.crossListRegionH = listH
    self.crossListRegionX = x
    self.crossListRegionW = w

    if search == "" then
        -- Empty state
        self:drawRect(x, y, w, listH, 0.20, T.rowA.r, T.rowA.g, T.rowA.b)
        local emptyH = tm:getFontHeight(UIFont.Small) * 2 + 8
        local ey     = y + math.floor((listH - emptyH) / 2)
        local et1    = getText("IGUI_RVM_CrossSearch_EmptyTitle")
        local et2    = getText("IGUI_RVM_CrossSearch_EmptySubtitle")
        local et1w   = tm:MeasureStringX(UIFont.Small, et1)
        local et2w   = tm:MeasureStringX(UIFont.Tiny, et2)
        self:drawText(et1, x + math.floor((w - et1w) / 2), ey,
            T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
        self:drawText(et2, x + math.floor((w - et2w) / 2), ey + tm:getFontHeight(UIFont.Small) + 4,
            T.muted.r * 0.7, T.muted.g * 0.7, T.muted.b * 0.7, 1, UIFont.Tiny)
        return
    end

    local totalRH = #results * ROW_H
    local maxSc   = math.max(0, totalRH - listH)
    self.crossListScrollY = math.max(0, math.min(maxSc, self.crossListScrollY))

    self:setStencilRect(x, y, w, listH)
    local rowY = y - self.crossListScrollY
    for idx, r in ipairs(results) do
        if rowY + ROW_H > y and rowY < y + listH then
            local bg = (idx % 2 == 0) and T.rowA or T.rowB
            self:drawRect(x, rowY, w, ROW_H, 1, bg.r, bg.g, bg.b)
            self:drawRect(x, rowY + ROW_H - 1, w, 1, 0.35, T.divider.r, T.divider.g, T.divider.b)
            self:drawText(trimText(UIFont.Small, r.script, VEH_W2 - 4), x + 4, rowY + 1,
                T.text.r, T.text.g, T.text.b, 1, UIFont.Small)
            self:drawText(trimText(UIFont.Small, r.types, TYPES_W - 4), x + VEH_W2 + 4, rowY + 1,
                T.muted.r, T.muted.g, T.muted.b, 1, UIFont.Small)
        end
        rowY = rowY + ROW_H
    end
    self:clearStencilRect()

    if totalRH > listH then
        local barH  = math.max(12, listH * listH / totalRH)
        local ratio = maxSc > 0 and self.crossListScrollY / maxSc or 0
        local barY  = y + ratio * (listH - barH)
        self:drawRect(x + w - 4, barY, 4, barH, 0.8, T.accent.r, T.accent.g, T.accent.b)
    end
end
