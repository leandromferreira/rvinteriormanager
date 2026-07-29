-- RV Interior Manager — Server: position tracking + idle room cleanup + logging.
-- Functions attach to the RVMServer namespace defined in RVMServer.lua.

if not isServer() then return end

require("RVMShared")

local MOVE_THRESHOLD = 0.5      -- tiles

-- ============================================================
-- Position tracking — dirty flag + periodic flush
-- ============================================================
-- Compares modData.Vehicles (base mod, updated by base mod logic)
-- against in-memory cache and marks moved vehicles dirty.
local function checkPositions()
    local base     = ModData.getOrCreate(RVM.BASE_MOD_DATA_KEY)
    local vehicles = base.Vehicles or {}

    for rvId, pos in pairs(vehicles) do
        local last = RVMServer.posCache[rvId]

        if not last
            or math.abs((pos.x or 0) - last.x) > MOVE_THRESHOLD
            or math.abs((pos.y or 0) - last.y) > MOVE_THRESHOLD
        then
            RVMServer.posCache[rvId] = { x = pos.x or 0, y = pos.y or 0, z = pos.z or 0 }
            RVMServer.dirtySet[rvId] = true
        end
    end
end
RVMServer.checkPositions = checkPositions

-- Writes dirty positions into our own ModData.
local function flushDirty()
    -- Avoid next() which is nil in some PZ Kahlua builds.
    local hasAny = false
    for _ in pairs(RVMServer.dirtySet) do hasAny = true; break end
    if not hasAny then return end

    local d = ModData.getOrCreate(RVM.POS_DATA_KEY)
    d.relationships = d.relationships or {}

    for rvId in pairs(RVMServer.dirtySet) do
        if d.relationships[rvId] then
            d.relationships[rvId].lastPos = RVMServer.posCache[rvId]
        end
    end

    RVMServer.dirtySet = {}
end
RVMServer.flushDirty = flushDirty

-- ============================================================
-- Idle room cleaner
-- ============================================================
-- Session idle log
-- ============================================================
-- One file per server start, handle kept open for the whole session so
-- every writeRvmLog call actually appends (getFileWriter always creates
-- a new file on each open, so we must never reopen).
local rvmLogHandle = nil

local function writeRvmLog(msg)
    if not rvmLogHandle then return end
    local ok, err = pcall(function() rvmLogHandle:write(msg .. "\n") end)
    if not ok then print("[RVM] writeRvmLog error: " .. tostring(err)) end
end
RVMServer.writeRvmLog = writeRvmLog

local function initRvmLog()
    local ts = os.date("%Y-%m-%d_%H-%M-%S")
    local path = "RVM/idle_" .. ts .. ".txt"
    rvmLogHandle = getFileWriter(path, true, false)
    if rvmLogHandle then
        rvmLogHandle:write("-- RVM Idle Log -- server start " .. os.date("%d/%m/%Y %H:%M:%S") .. "\n")
        print("[RVM] log file: " .. path)
    else
        print("[RVM] WARNING: could not create log file " .. path)
    end
end
RVMServer.initRvmLog = initRvmLog

-- Parses "DD/MM/YYYY HH:MM" → os.time value, or nil.
local function parseDateToTime(dateStr)
    if not dateStr then return nil end
    local d, m, y, hh, mm = dateStr:match("(%d+)/(%d+)/(%d+) (%d+):(%d+)")
    if not d then return nil end
    return os.time({
        day   = tonumber(d),  month  = tonumber(m),  year = tonumber(y),
        hour  = tonumber(hh), min    = tonumber(mm),  sec  = 0,
        isdst = false,
    })
end

-- Returns whole days elapsed since dateStr, or nil if unparseable.
local function daysSince(dateStr)
    local t = parseDateToTime(dateStr)
    if not t then return nil end
    return math.floor((os.time() - t) / 86400)
end

local function checkIdleRooms()
    local svars    = SandboxVars and SandboxVars.RVM
    local idleDays = svars and svars.IdleCleanupDays or 0
    if not idleDays or idleDays <= 0 then return end

    local d = ModData.getOrCreate(RVM.POS_DATA_KEY)
    if not d.relationships then return end

    -- Collect candidates first to avoid modifying the table while iterating.
    local toClean = {}
    for rvId, rel in pairs(d.relationships) do
        local refDate = rel.lastEnterDate or rel.dateLinked
        local days    = daysSince(refDate)
        if days and days >= idleDays then
            table.insert(toClean, { rvId = rvId, rel = rel, days = days })
        end
    end

    local now = os.date("%d/%m/%Y %H:%M")
    local header = string.format(
        "[%s] [RVM] IdleCleaner: running — threshold=%d day(s), candidates=%d",
        now, idleDays, #toClean)
    print(header)
    writeRvmLog(header)

    if #toClean == 0 then
        writeRvmLog(string.format("[%s] [RVM] IdleCleaner: nothing to dissociate", now))
        return
    end

    for _, item in ipairs(toClean) do
        local rel     = item.rel
        local room    = rel.room
        local roomStr = room and string.format("%d,%d,%d", room.x or 0, room.y or 0, room.z or 0) or "?"
        local vpos    = rel.lastPos
        local vposStr = vpos and string.format("%.0f,%.0f,%.0f", vpos.x or 0, vpos.y or 0, vpos.z or 0) or "?"
        local msg = string.format(
            "[%s] [RVM] DISSOCIATE  trigger=idle  rvId=%s  name=%s  type=%s  room=%s  vehPos=%s  lastEnter=%s  linked=%s  idleDays=%d",
            now,
            tostring(item.rvId),
            tostring(rel.vehicleName  or "?"),
            tostring(rel.typeKey      or "?"),
            roomStr, vposStr,
            tostring(rel.lastEnterDate or "?"),
            tostring(rel.dateLinked    or "?"),
            item.days)
        print(msg)
        writeRvmLog(msg)
        RVMServer.dissociate(item.rvId)
    end

    local footer = string.format(
        "[%s] [RVM] IdleCleaner: done — dissociated=%d", now, #toClean)
    print(footer)
    writeRvmLog(footer)
end
RVMServer.checkIdleRooms = checkIdleRooms
