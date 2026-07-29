-- RV Interior Manager — Admin Panel: data, filtering, sorting and button state.
-- Methods attach to the RVManagerPanel class defined in RVMAdminPanel.lua
-- (loaded first). Theme/constants come from the shared RVMUI namespace.

if isServer() then return end

require("RVMShared")

local UI         = RVMUI
local PAD        = UI.PAD
local ROW_H      = UI.ROW_H
local SCOL       = UI.SCOL

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

function RVManagerPanel:receiveData(data, opts)
    opts = opts or {}
    self.loading             = false
    self.data                = data
    self.selectedRvId        = nil
    -- Preserve Tab 1 context when caller requests it (e.g. dissociate/associate
    -- only affects Tab 2 counts; the user may be mid-edit on a type).
    if not opts.preserveTypeSelection then
        self.selectedSummaryType = nil
        self.vehicleListSelected = nil
        self.vehicleListScrollY  = 0
        self.typeListPage        = 1
    end
    self.unallocSelected     = nil
    self.unallocScrollY      = 0
    self.addDropdownOpen     = false
    self.addDropdownItems    = {}
    self.scrollY             = 0
    self.summaryScrollY      = 0
    self.crossSearchLast     = ""
    self.crossSearchResults  = {}
    self.crossListScrollY    = 0
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
    if not self.btnAddVehicle then return end
    local addText = ""
    if self.vehicleAddEntry then
        local raw = self.vehicleAddEntry:getText()
        if type(raw) == "string" then addText = raw:match("^%s*(.-)%s*$") or "" end
    end
    local addEnabled = self.selectedSummaryType ~= nil and addText ~= ""
    local function apply(btn, en)
        btn.enable    = en
        btn.textColor = en and { r=1, g=1, b=1, a=1 } or { r=0.4, g=0.4, b=0.4, a=1 }
    end
    apply(self.btnAddVehicle, addEnabled)
end

-- ============================================================
-- Unallocated scripts helper
-- ============================================================
function RVManagerPanel:getUnallocatedScripts()
    if not self.data or not self.data.scriptOverrides then return {} end

    local inSomeType = {}
    local ss = self.data.scriptsState
    if ss then
        for _, scripts in pairs(ss) do
            for _, s in ipairs(scripts) do inSomeType[s] = true end
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
-- Add-entry dropdown options
-- ============================================================
function RVManagerPanel:getAddDropdownOptions(searchLower)
    -- Build script → current RV type lookup from server-provided scriptsState
    local scriptToType = {}
    local ss = self.data and self.data.scriptsState
    if ss then
        for typeKey, scripts in pairs(ss) do
            for _, s in ipairs(scripts) do
                scriptToType[s] = typeKey
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

-- ============================================================
-- Cross-type vehicle search
-- ============================================================
function RVManagerPanel:getCrossSearchResults(search)
    if search == "" then return {} end

    -- Build script → RV types map
    local scriptTypes = {}
    local ss = self.data and self.data.scriptsState
    if ss then
        for tk, scripts in pairs(ss) do
            for _, s in ipairs(scripts) do
                if not scriptTypes[s] then scriptTypes[s] = {} end
                table.insert(scriptTypes[s], tk)
            end
        end
    end

    local sl      = search:lower()
    local results = {}
    local seen    = {}

    -- Use the full server-provided list so unassigned vehicles appear too
    local allScripts = self.data and self.data.allVehicleScripts
    if allScripts and #allScripts > 0 then
        for _, script in ipairs(allScripts) do
            if not seen[script] and script:lower():find(sl, 1, true) then
                seen[script] = true
                local types = scriptTypes[script] or {}
                table.sort(types)
                table.insert(results, {
                    script = script,
                    types  = #types > 0 and table.concat(types, ", ") or "—",
                })
            end
        end
    else
        -- Fallback before server list arrives: only VehicleTypes-known scripts
        for script, types in pairs(scriptTypes) do
            if script:lower():find(sl, 1, true) then
                table.sort(types)
                table.insert(results, { script = script, types = table.concat(types, ", ") })
            end
        end
    end

    table.sort(results, function(a, b) return a.script < b.script end)
    return results
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
-- Selected assignment lookup
-- ============================================================
function RVManagerPanel:selectedAssignment()
    if not self.selectedRvId or not self.data then return nil end
    for _, a in ipairs(self.data.assignments) do
        if tostring(a.rvVehicleUniqueId) == self.selectedRvId then return a end
    end
    return nil
end
