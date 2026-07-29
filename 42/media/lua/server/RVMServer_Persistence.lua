-- RV Interior Manager — Server: vehicle-type file persistence + override application.
-- Functions attach to the RVMServer namespace defined in RVMServer.lua.

if not isServer() then return end

require("RVMShared")

-- File paths (defined in RVMServer.lua so _Admin can reference them too).
local STANDARD_FILE = RVMServer.STANDARD_FILE
local CHANGES_FILE  = RVMServer.CHANGES_FILE

local function saveStandardTypes()
    local ok, RV = pcall(require, "RVVehicleTypes")
    if not ok or not RV or not RV.VehicleTypes then return end
    local writer = getFileWriter(STANDARD_FILE, true, false)
    if not writer then
        print("[RVM] saveStandardTypes: cannot open " .. STANDARD_FILE)
        return
    end
    writer:write("-- RVM Default Vehicle Types (auto-generated on server start, do not edit)\n")
    local n = 0
    for typeKey, typeDef in pairs(RV.VehicleTypes) do
        local scripts = typeDef.scripts or {}
        writer:write(typeKey .. "=" .. table.concat(scripts, "|") .. "\n")
        n = n + 1
    end
    local _, err = pcall(function() writer:close() end)
    if err then print("[RVM] saveStandardTypes: close error: " .. tostring(err)) end
    print("[RVM] saveStandardTypes: saved " .. n .. " type(s) to " .. STANDARD_FILE)
end
RVMServer.saveStandardTypes = saveStandardTypes

local function loadStandardTypes()
    local reader = getFileReader(STANDARD_FILE, false)
    if not reader then return nil end
    local result = {}
    local line = reader:readLine()
    while line ~= nil do
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" and line:sub(1, 2) ~= "--" then
            local key, val = line:match("^([^=]+)=(.*)$")
            if key then
                local scripts = {}
                if val and val ~= "" then
                    for s in (val .. "|"):gmatch("([^|]+)|") do
                        table.insert(scripts, s)
                    end
                end
                result[key] = scripts
            end
        end
        line = reader:readLine()
    end
    pcall(function() reader:close() end)
    return result
end
RVMServer.loadStandardTypes = loadStandardTypes

local function saveChangesFile(overrides)
    local writer = getFileWriter(CHANGES_FILE, true, false)
    if not writer then
        print("[RVM] saveChangesFile: cannot open " .. CHANGES_FILE)
        return
    end
    writer:write("-- RVM Vehicle Type Changes (admin-configured, survives wipe)\n")
    local n = 0
    for typeKey, changes in pairs(overrides or {}) do
        local hasAdded   = changes.added   and #changes.added   > 0
        local hasRemoved = changes.removed and #changes.removed > 0
        if hasAdded then
            writer:write(typeKey .. ".added="   .. table.concat(changes.added,   "|") .. "\n")
            n = n + 1
        end
        if hasRemoved then
            writer:write(typeKey .. ".removed=" .. table.concat(changes.removed, "|") .. "\n")
            n = n + 1
        end
    end
    pcall(function() writer:close() end)
    print("[RVM] saveChangesFile: saved " .. n .. " override line(s) to " .. CHANGES_FILE)
end
RVMServer.saveChangesFile = saveChangesFile

local function loadChangesFile()
    local reader = getFileReader(CHANGES_FILE, false)
    if not reader then return nil end
    local result = {}
    local line = reader:readLine()
    while line ~= nil do
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" and line:sub(1, 2) ~= "--" then
            local typeKey, kind, val = line:match("^([^.]+)%.([^=]+)=(.*)$")
            if typeKey and kind and (kind == "added" or kind == "removed") then
                result[typeKey] = result[typeKey] or { added = {}, removed = {} }
                if val and val ~= "" then
                    for s in (val .. "|"):gmatch("([^|]+)|") do
                        table.insert(result[typeKey][kind], s)
                    end
                end
            end
        end
        line = reader:readLine()
    end
    pcall(function() reader:close() end)
    return result
end
RVMServer.loadChangesFile = loadChangesFile

-- Applies all overrides starting from the STANDARD scripts saved at server start.
-- Unlike applyScriptOverrides (which is incremental), this is always deterministic
-- regardless of how many add/remove cycles were performed.
local function applyAllOverridesClean(overrides)
    if not overrides then return end
    local okRV, RV = pcall(require, "RVVehicleTypes")
    if not okRV or not RV or not RV.VehicleTypes then
        print("[RVM] applyAllOverridesClean: RVVehicleTypes not available")
        return
    end

    local standardTypes = loadStandardTypes() or {}

    for typeKey, changes in pairs(overrides) do
        local typeDef = RV.VehicleTypes[typeKey]
        if typeDef then
            local baseScripts = standardTypes[typeKey] or {}
            local removeSet   = {}
            for _, s in ipairs(changes.removed or {}) do removeSet[s] = true end

            local result = {}
            local seen   = {}
            for _, s in ipairs(baseScripts) do
                if not removeSet[s] and not seen[s] then
                    table.insert(result, s); seen[s] = true
                end
            end
            for _, s in ipairs(changes.added or {}) do
                if not seen[s] then
                    table.insert(result, s); seen[s] = true
                end
            end

            typeDef.scripts = result
            print("[RVM] applyAllOverridesClean: type=" .. typeKey
                .. " base=" .. #baseScripts
                .. " added=" .. #(changes.added or {})
                .. " removed=" .. #(changes.removed or {})
                .. " result=" .. #result)
        else
            print("[RVM] applyAllOverridesClean: type=" .. typeKey .. " NOT FOUND in RV.VehicleTypes")
        end
    end
end
RVMServer.applyAllOverridesClean = applyAllOverridesClean
