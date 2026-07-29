-- RV Interior Manager — Admin Panel: Tab 2 rendering (linked vehicles).
-- Methods attach to the RVManagerPanel class defined in RVMAdminPanel.lua.

if isServer() then return end

require("RVMShared")

local UI               = RVMUI
local T                = UI.T
local trimText         = UI.trimText
local PAD              = UI.PAD
local ROW_H            = UI.ROW_H
local HDR_H            = UI.HDR_H
local FILTER_H         = UI.FILTER_H
local BTN_H            = UI.BTN_H
local SUMMARY_MAX_H    = UI.SUMMARY_MAX_H
local VL_ADD_BTN_W     = UI.VL_ADD_BTN_W
local VL_REMOVE_BTN_W  = UI.VL_REMOVE_BTN_W
local VL_CTRL_H        = UI.VL_CTRL_H
local SCOL             = UI.SCOL
local SCOL_TOTAL       = UI.SCOL_TOTAL
local ACOL_FIXED       = UI.ACOL_FIXED
local ACOL_FIXED_TOTAL = UI.ACOL_FIXED_TOTAL

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

    local ctrlY   = y + listAreaH + 1
    local entryW  = w - VL_ADD_BTN_W - VL_REMOVE_BTN_W - PAD * 3
    local addBtnX = x + entryW + PAD
    local rmBtnX  = addBtnX + VL_ADD_BTN_W + PAD
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

    if not self.selectedSummaryType then
        self:drawRect(x, y, w, listAreaH, 0.25, T.rowA.r, T.rowA.g, T.rowA.b)
        return
    end

    local ss = self.data and self.data.scriptsState
    local typeScripts = ss and ss[self.selectedSummaryType]
    if not typeScripts then return end

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
    for _, script in ipairs(typeScripts) do
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
