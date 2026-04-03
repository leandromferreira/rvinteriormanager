-- RV Interior Manager - Client Side / Admin Panel UI

if not isClient() then return end

require("RVMShared")

-- ============================================================
-- RVManagerPanel
-- ============================================================
RVManagerPanel = ISPanel:derive("RVManagerPanel")

local PAD       = 10
local ROW_H     = 20
local TITLE_H   = 28
local BOTTOM_H  = 45   -- reserved height for action buttons at the bottom

-- Summary table columns: Tipo (key) | Tamanho | Total | Ocupados | Disponiveis
local SCOL = { 120, 55, 50, 70, 70 }

-- Assignment table columns: Vehicle ID | Tipo (key) | Tamanho | Local Carro | Local RV | Linked em
local ACOL = { 75, 115, 50, 115, 115, 125 }

function RVManagerPanel:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor    = { r=0.08, g=0.08, b=0.10, a=0.96 }
    o.borderColor        = { r=0.40, g=0.40, b=0.45, a=1.00 }
    o.moveWithMouse      = true
    o.loading            = false
    o.data               = nil
    o.scrollY            = 0
    o.contentH           = 0
    o.selectedIndex      = nil   -- index into data.assignments
    o.assignRowsScreenTop = nil  -- screen Y of first assignment data row (set in render)
    o.assignRowCount      = 0
    return o
end

function RVManagerPanel:initialise()
    ISPanel.initialise(self)

    -- Top-right controls
    local rw = 70
    local rbtn = ISButton:new(self.width - rw - 28, 5, rw, 18, "Refresh", self, RVManagerPanel.requestData)
    rbtn:initialise()
    rbtn.backgroundColor = { r=0.2, g=0.35, b=0.2, a=1 }
    self:addChild(rbtn)

    local cbtn = ISButton:new(self.width - 22, 5, 16, 18, "X", self, RVManagerPanel.onClose)
    cbtn:initialise()
    cbtn.backgroundColor = { r=0.4, g=0.1, b=0.1, a=1 }
    self:addChild(cbtn)

    -- Bottom action buttons (disabled until a row is selected)
    local bw  = 160
    local bh  = 25
    local by  = self.height - BOTTOM_H + 10

    self.btnTpCar = ISButton:new(PAD, by, bw, bh, "Ir para o Carro", self, RVManagerPanel.teleportToCar)
    self.btnTpCar:initialise()
    self.btnTpCar.backgroundColor        = { r=0.25, g=0.20, b=0.05, a=1 }
    self.btnTpCar.backgroundColor2       = { r=0.35, g=0.28, b=0.08, a=1 }
    self.btnTpCar.textColor              = { r=0.60, g=0.60, b=0.60, a=1 }
    self:addChild(self.btnTpCar)

    self.btnTpRV = ISButton:new(PAD + bw + 10, by, bw, bh, "Ir para o Interior RV", self, RVManagerPanel.teleportToRV)
    self.btnTpRV:initialise()
    self.btnTpRV.backgroundColor        = { r=0.05, g=0.20, b=0.25, a=1 }
    self.btnTpRV.backgroundColor2       = { r=0.08, g=0.28, b=0.35, a=1 }
    self.btnTpRV.textColor              = { r=0.60, g=0.60, b=0.60, a=1 }
    self:addChild(self.btnTpRV)
end

function RVManagerPanel:onClose()
    self:removeSelf()
    RVManagerPanel.instance = nil
end

function RVManagerPanel:requestData()
    self.loading       = true
    self.data          = nil
    self.scrollY       = 0
    self.selectedIndex = nil
    self:updateButtons()
    sendClientCommand(RVM.MODULE, "requestData", {})
end

function RVManagerPanel:receiveData(data)
    self.loading       = false
    self.data          = data
    self.selectedIndex = nil
    self:updateButtons()
end

-- Enable/disable teleport buttons based on selection
function RVManagerPanel:updateButtons()
    local sel = self.selectedIndex
    local a   = sel and self.data and self.data.assignments and self.data.assignments[sel]

    local hasCar = a and a.carX ~= nil
    local hasRV  = a and a.roomX ~= nil

    self.btnTpCar.textColor = hasCar
        and { r=1.00, g=0.85, b=0.20, a=1 }
        or  { r=0.45, g=0.45, b=0.45, a=1 }

    self.btnTpRV.textColor = hasRV
        and { r=0.20, g=0.85, b=1.00, a=1 }
        or  { r=0.45, g=0.45, b=0.45, a=1 }
end

-- ---- Teleport ------------------------------------------------------

local function doTeleport(x, y, z)
    if not x then return end
    local player = getSpecificPlayer(0)
    if not player then return end

    -- Exit vehicle if seated
    local vehicle = player:getVehicle()
    if vehicle then vehicle:exit(player) end

    player:setX(x)
    player:setY(y)
    player:setZ(z or 0)
    player:setLastX(x)
    player:setLastY(y)
    player:setLastZ(z or 0)
end

function RVManagerPanel:teleportToCar()
    local a = self:getSelected()
    if not a or not a.carX then return end
    doTeleport(a.carX, a.carY, a.carZ)
end

function RVManagerPanel:teleportToRV()
    local a = self:getSelected()
    if not a or not a.roomX then return end
    doTeleport(a.roomX, a.roomY, a.roomZ)
end

function RVManagerPanel:getSelected()
    if not self.selectedIndex or not self.data then return nil end
    return (self.data.assignments or {})[self.selectedIndex]
end

-- ---- Mouse ---------------------------------------------------------

function RVManagerPanel:onMouseWheel(del)
    self.scrollY = self.scrollY - del * 20
    if self.scrollY < 0 then self.scrollY = 0 end
    local maxScroll = math.max(0, self.contentH - (self.height - TITLE_H - PAD - BOTTOM_H))
    if self.scrollY > maxScroll then self.scrollY = maxScroll end
    return true
end

function RVManagerPanel:onMouseDown(x, y)
    -- Check if click landed on an assignment row
    local top   = self.assignRowsScreenTop
    local count = self.assignRowCount
    if not top or count == 0 then return end

    if y >= top and y < top + count * ROW_H then
        local idx = math.floor((y - top) / ROW_H) + 1
        if idx >= 1 and idx <= count then
            self.selectedIndex = (self.selectedIndex == idx) and nil or idx
            self:updateButtons()
            return
        end
    end
    ISPanel.onMouseDown(self, x, y)
end

-- ---- Helpers -------------------------------------------------------

local function fmtCoord(x, y, z)
    if not x then return "?" end
    return string.format("%d,%d,%d", math.floor(x), math.floor(y), math.floor(z or 0))
end

-- ---- Render --------------------------------------------------------

local CLIP_BOTTOM_MARGIN = BOTTOM_H + PAD

function RVManagerPanel:render()
    ISPanel.render(self)

    local W        = self.width
    local clipYTop = TITLE_H
    local clipYBot = self.height - CLIP_BOTTOM_MARGIN

    -- Title bar
    self:drawRect(0, 0, W, TITLE_H, 1, 0.05, 0.05, 0.07)
    self:drawText("RV Interior Manager", PAD, 6, 0.95, 0.75, 0.20, 1, UIFont.Medium)

    -- Bottom bar background
    self:drawRect(0, self.height - BOTTOM_H, W, BOTTOM_H, 1, 0.05, 0.05, 0.07)
    self:drawRect(0, self.height - BOTTOM_H, W, 1, 1, 0.25, 0.25, 0.30)

    -- Selection label in bottom bar
    local selLabel = "Nenhum registro selecionado"
    local a = self:getSelected()
    if a then
        selLabel = string.format("Selecionado: Vehicle ID %s  [%s %s]",
            a.vehicleId or "?",
            a.roomType  or "?",
            RVM.TypeSizes[a.roomType] or "?"
        )
    end
    self:drawText(selLabel, PAD + 340, self.height - BOTTOM_H + 14, 0.65, 0.65, 0.65, 1, UIFont.Small)

    local cy = clipYTop + PAD - self.scrollY

    if self.loading then
        self:drawText("Solicitando dados ao servidor...", PAD, clipYTop + PAD, 0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end

    if not self.data then
        self:drawText("Nenhum dado. Clique em Refresh.", PAD, clipYTop + PAD, 0.6, 0.6, 0.6, 1, UIFont.Small)
        return
    end

    -- ----------------------------------------------------------------
    -- SECTION 1: Summary
    -- ----------------------------------------------------------------
    cy = self:renderSectionHeader("Resumo por Tipo de RV", PAD, cy, W, clipYTop, clipYBot)
    cy = self:renderSummaryHeader(PAD, cy, clipYTop, clipYBot)

    local summary  = self.data.summary or {}
    local typeList = {}
    for k in pairs(summary) do table.insert(typeList, k) end
    table.sort(typeList)

    for _, typeKey in ipairs(typeList) do
        local info      = summary[typeKey]
        local total     = info.total or RVM.ROOMS_PER_TYPE
        local occupied  = info.occupied or 0
        local available = total - occupied
        local sizeLabel = RVM.TypeSizes[typeKey] or "?"

        if cy + ROW_H > clipYTop and cy < clipYBot then
            local r, g
            if occupied == 0 then
                r, g = 0.3, 0.9
            elseif occupied >= total then
                r, g = 0.9, 0.2
            elseif occupied / total > 0.8 then
                r, g = 0.9, 0.55
            else
                r, g = 0.3, 0.85
            end

            local hx = PAD
            self:drawText(typeKey,             hx, cy, 0.95, 0.95, 0.95, 1, UIFont.Small) hx = hx + SCOL[1]
            self:drawText(sizeLabel,           hx, cy, 0.65, 0.85, 1.00, 1, UIFont.Small) hx = hx + SCOL[2]
            self:drawText(tostring(total),     hx, cy, 0.75, 0.75, 0.75, 1, UIFont.Small) hx = hx + SCOL[3]
            self:drawText(tostring(occupied),  hx, cy, r,    g,    0.2,  1, UIFont.Small) hx = hx + SCOL[4]
            self:drawText(tostring(available), hx, cy, g,    r,    0.2,  1, UIFont.Small)
        end
        cy = cy + ROW_H
    end

    cy = cy + PAD

    -- ----------------------------------------------------------------
    -- SECTION 2: Active Assignments
    -- ----------------------------------------------------------------
    cy = self:renderSectionHeader("Atribuicoes Ativas", PAD, cy, W, clipYTop, clipYBot)

    local assignments = self.data.assignments or {}
    self.assignRowCount = #assignments

    if #assignments == 0 then
        self.assignRowsScreenTop = nil
        if cy > clipYTop and cy < clipYBot then
            self:drawText("Nenhum veiculo vinculado a um RV no momento.", PAD, cy, 0.55, 0.55, 0.55, 1, UIFont.Small)
        end
        cy = cy + ROW_H
    else
        cy = self:renderAssignmentHeader(PAD, cy, clipYTop, clipYBot)

        -- Record where rows begin (screen Y of first data row)
        self.assignRowsScreenTop = cy

        for i, a in ipairs(assignments) do
            local selected = (self.selectedIndex == i)

            if cy + ROW_H > clipYTop and cy < clipYBot then
                if selected then
                    self:drawRect(PAD, cy, W - PAD*2, ROW_H, 1, 0.20, 0.35, 0.45)
                elseif i % 2 == 0 then
                    self:drawRect(PAD, cy, W - PAD*2, ROW_H, 1, 0.12, 0.12, 0.14)
                end

                local typeKey   = a.roomType or "?"
                local sizeLabel = RVM.TypeSizes[typeKey] or "?"
                local carLoc    = fmtCoord(a.carX, a.carY, a.carZ)
                local rvLoc     = fmtCoord(a.roomX, a.roomY, a.roomZ)
                local linkDate  = a.linkDate or "?"

                local cr, cg, cb = selected and 1 or 0.80, selected and 1 or 0.90, selected and 1 or 1.00

                local hx = PAD
                self:drawText(a.vehicleId or "?", hx, cy, cr,   cg,   cb,   1, UIFont.Small) hx = hx + ACOL[1]
                self:drawText(typeKey,             hx, cy, 0.95, 0.95, 0.95, 1, UIFont.Small) hx = hx + ACOL[2]
                self:drawText(sizeLabel,           hx, cy, 0.65, 0.85, 1.00, 1, UIFont.Small) hx = hx + ACOL[3]
                self:drawText(carLoc,              hx, cy, 0.95, 0.85, 0.50, 1, UIFont.Small) hx = hx + ACOL[4]
                self:drawText(rvLoc,               hx, cy, 0.50, 0.90, 0.85, 1, UIFont.Small) hx = hx + ACOL[5]
                self:drawText(linkDate,            hx, cy, 0.75, 0.75, 0.75, 1, UIFont.Small)
            end
            cy = cy + ROW_H
        end
    end

    self.contentH = (cy + self.scrollY) - clipYTop
end

-- ---- Sub-render helpers --------------------------------------------

function RVManagerPanel:renderSectionHeader(label, x, cy, W, yTop, yBot)
    if cy + ROW_H > yTop and cy < yBot + 40 then
        self:drawRect(x, cy, W - x*2, ROW_H, 1, 0.15, 0.15, 0.20)
        self:drawText(label, x + 4, cy + 1, 0.90, 0.70, 0.20, 1, UIFont.Small)
    end
    return cy + ROW_H + 2
end

function RVManagerPanel:renderSummaryHeader(x, cy, yTop, yBot)
    if cy + ROW_H > yTop and cy < yBot then
        self:drawRect(x, cy, self.width - x*2, 1, 1, 0.35, 0.35, 0.35)
        local hx = x
        self:drawText("Tipo",        hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + SCOL[1]
        self:drawText("Tamanho",     hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + SCOL[2]
        self:drawText("Total",       hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + SCOL[3]
        self:drawText("Ocupados",    hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + SCOL[4]
        self:drawText("Disponiveis", hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
    return cy + ROW_H + 2
end

function RVManagerPanel:renderAssignmentHeader(x, cy, yTop, yBot)
    if cy + ROW_H > yTop and cy < yBot then
        self:drawRect(x, cy, self.width - x*2, 1, 1, 0.35, 0.35, 0.35)
        local hx = x
        self:drawText("Vehicle ID",     hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + ACOL[1]
        self:drawText("Tipo",           hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + ACOL[2]
        self:drawText("Tamanho",        hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + ACOL[3]
        self:drawText("Local do Carro", hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + ACOL[4]
        self:drawText("Local do RV",    hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small) hx = hx + ACOL[5]
        self:drawText("Linked em",      hx, cy + 2, 0.65, 0.65, 0.65, 1, UIFont.Small)
    end
    return cy + ROW_H + 2
end

-- ============================================================
-- Server response handler
-- ============================================================
local function onServerCommand(module, command, data)
    if module ~= RVM.MODULE then return end
    if command == "responseData" and RVManagerPanel.instance then
        RVManagerPanel.instance:receiveData(data)
    end
end

Events.OnServerCommand.Add(onServerCommand)

-- ============================================================
-- Panel open / close
-- ============================================================
local function isAdminOrMod(player)
    return player:isAccessLevel("admin") or player:isAccessLevel("moderator")
end

local function openRVManager()
    local player = getSpecificPlayer(0)
    if not player or not isAdminOrMod(player) then return end

    if RVManagerPanel.instance then
        RVManagerPanel.instance:onClose()
        return
    end

    local W, H    = 650, 560
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local px      = math.floor((screenW - W) / 2)
    local py      = math.floor((screenH - H) / 2)

    local panel = RVManagerPanel:new(px, py, W, H)
    panel:initialise()
    panel:addToUIManager()
    RVManagerPanel.instance = panel

    panel:requestData()
end

-- ============================================================
-- Context menu hook (right-click in world) - Admin/Mod only
-- ============================================================
local function onFillWorldObjectContextMenu(playerIndex, context, worldObjects)
    local player = getSpecificPlayer(playerIndex)
    if not player or not isAdminOrMod(player) then return end

    context:addOption("RV Manager", nil, openRVManager)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

-- ============================================================
-- Admin panel button hook (ESC menu > Admin)
-- ============================================================
local function tryAddToAdminPanel()
    if not ISAdminPanel then return end

    local origCreate = ISAdminPanel.create
    ISAdminPanel.create = function(self, ...)
        origCreate(self, ...)
        local btn = ISButton:new(10, self.height - 30, 120, 20, "RV Manager", self, function() openRVManager() end)
        btn:initialise()
        self:addChild(btn)
    end
end

Events.OnGameStart.Add(tryAddToAdminPanel)
