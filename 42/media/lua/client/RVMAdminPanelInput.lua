-- RV Interior Manager — Admin Panel: input handling and actions.
-- Methods attach to the RVManagerPanel class defined in RVMAdminPanel.lua.

if isServer() then return end

require("RVMShared")

local UI     = RVMUI
local PAD    = UI.PAD
local ROW_H  = UI.ROW_H
local HDR_H  = UI.HDR_H
local TAB_H  = UI.TAB_H
local TAB_W  = UI.TAB_W
local LEFT_W = UI.LEFT_W

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
        -- Reset button (bottom of help box)
        local rb = self.resetBtnRect
        if rb and x >= rb.x and x < rb.x + rb.w and y >= rb.y and y < rb.y + rb.h then
            self:onResetTypes()
            return
        end

        -- Pagination buttons (left panel)
        if y >= self.typeListPageBtnY and y < self.typeListPageBtnY + self.typeListPageBtnH then
            for _, btn in ipairs(self.typeListPageBtns) do
                if x >= btn.x and x < btn.x + btn.w then
                    if btn.page == "prev" then
                        self.typeListPage = math.max(1, self.typeListPage - 1)
                    elseif btn.page == "next" then
                        self.typeListPage = math.min(self.typeListTotalPages, self.typeListPage + 1)
                    elseif type(btn.page) == "number" then
                        self.typeListPage = btn.page
                    end
                    return
                end
            end
        end

        -- Type list rows (left panel)
        if y >= self.typeListRegionY and y < self.typeListRegionY + self.typeListRegionH
            and x >= PAD and x < PAD + LEFT_W then
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
            local pageSize = math.max(1, math.floor(self.typeListRegionH / ROW_H))
            local startIdx = (self.typeListPage - 1) * pageSize + 1
            local relY     = y - self.typeListRegionY
            local rowIdx   = math.floor(relY / ROW_H) + startIdx
            if rowIdx >= 1 and rowIdx <= #filtered then
                local clicked = filtered[rowIdx]
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

        -- Per-row delete buttons in vehicle list
        for _, btn in ipairs(self.vehDelBtns or {}) do
            if x >= btn.x and x < btn.x + btn.w and y >= btn.y and y < btn.y + btn.h then
                if self.selectedSummaryType then
                    sendClientCommand(getPlayer(), RVM.MODULE, "removeVehicleScript",
                        { typeKey = self.selectedSummaryType, script = btn.script })
                    self.vehicleListSelected = nil
                    self:updateVehicleListButtons()
                end
                return
            end
        end

        -- Vehicle list body — select script (for Add entry pre-fill)
        if y >= self.vehicleListRegionY and y < self.vehicleListRegionY + self.vehicleListRegionH
            and x >= self.vehicleListX and x < self.vehicleListX + self.vehicleListW
            and self.selectedSummaryType then
            local ss = self.data and self.data.scriptsState
            local typeScripts = ss and ss[self.selectedSummaryType]
            if typeScripts then
                local srch = self.vehicleListLastSearch or ""
                local filtered = {}
                for _, s in ipairs(typeScripts) do
                    if srch == "" or s:lower():find(srch, 1, true) then table.insert(filtered, s) end
                end
                local relY   = y - self.vehicleListRegionY + self.vehicleListScrollY
                local rowIdx = math.floor(relY / ROW_H) + 1
                if rowIdx >= 1 and rowIdx <= #filtered then
                    local script = filtered[rowIdx]
                    self.vehicleListSelected = (self.vehicleListSelected == script) and nil or script
                    self:updateVehicleListButtons()
                end
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
        -- Vehicle list scroll (right panel)
        if my >= self.vehicleListRegionY and my < self.vehicleListRegionY + self.vehicleListRegionH
            and mx >= self.vehicleListX and self.selectedSummaryType then
            local ss = self.data and self.data.scriptsState
            local typeScripts = ss and ss[self.selectedSummaryType]
            if typeScripts then
                local srch  = self.vehicleListLastSearch or ""
                local count = 0
                for _, s in ipairs(typeScripts) do
                    if srch == "" or s:lower():find(srch, 1, true) then count = count + 1 end
                end
                local maxScroll = math.max(0, count * ROW_H - self.vehicleListRegionH)
                self.vehicleListScrollY = math.max(0, math.min(maxScroll, self.vehicleListScrollY + step))
            end

        -- Cross-search list scroll
        elseif my >= self.crossListRegionY and my < self.crossListRegionY + self.crossListRegionH
            and mx >= self.crossListRegionX then
            local maxScroll = math.max(0, #self.crossSearchResults * ROW_H - self.crossListRegionH)
            self.crossListScrollY = math.max(0, math.min(maxScroll, self.crossListScrollY + step))
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
-- Actions
-- ============================================================
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
