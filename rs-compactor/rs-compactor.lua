local component = require("component")
local shell = require("shell")
local serialization = require("serialization")

local usageString = [[Automatic compactor for Refined Storage.
 
This computer needs to be connected to at least one Refined Storage component.
This program will query for crafting patterns and quantities of their inputs,
and schedule corresponding crafting tasks.
 
Only compaction patterns are considered (heuristic for deciding if pattern is
a compaction is "consumes 9 of the same item"), and only stored items are
counted for inputs (i.e. it won't try to recursively craft stuff).
 
Usage:
  rs-compactor [options]
 
Without any options will run in interactive mode.
 
Options:
  -h, --help - show this help message
  --auto - run in non-interactive mode
  --genConfig - generate configuration file based on patterns present in
                Refined Storage network
  -v, --verbose - enable more verbose logging
  --config=file - override path to config file, default is /etc/rs-compactor.cfg
]]

-- list of methods we look for on components
local requiredMethods = {
    "getPattern",
    "getPatterns",
    "getItem",
    "scheduleTask",
}

local args, opts = shell.parse(...)
local verbose = opts.v or opts.verbose
local configPath = opts.config or "/etc/rs-compactor.cfg"

local function log(...)
    io.stderr:write(string.format(...) .. "\n")
end

local function vlog(...)
    if verbose then
        log(...)
    end
end

--[[--
Looks for a suitable Refined Storage components and returns a proxy for
one of them. 
]]
local function getComponent()
    for id in component.list("refinedstorage", false) do
        local methods = component.methods(id)
        local ok = true
        for _, method in pairs(requiredMethods) do
            if methods[method] == nil then
                ok = false
                break
            end
        end
        if ok then
            return component.proxy(id)
        end
    end
    error("couldn't find any attached Refined Storage components")
end

local function patternSlotsEqual(slot1, slot2)
    local fmt = function(item)
        return string.format("%s@%d@%d", item.name, item.damage, item.size)
    end
    local slot1opts = {}
    for _, item in ipairs(slot1) do
        slot1opts[fmt(item)] = true
    end
    for _, item in ipairs(slot2) do
        if not slot1opts[fmt(item)] then
            -- Slot 2 has something that isn't present in slot 1.
            return false
        end
        -- Holy fuck, there is no way to delete items with non-numeric keys.
        slot1opts[fmt(item)] = nil
    end
    for _, item in pairs(slot1opts) do
        if item ~= nil then
            -- Some of the slot 1 items were not present in slot 2.
            return false
        end
    end
    return true
end

local function isCompactionPattern(pattern)
    if pattern.inputs.n ~= 9 then
        return false
    end
    local allSlotsEqual = true
    for i, slot in ipairs(pattern.inputs) do
        if not patternSlotsEqual(pattern.inputs[1], slot) then
            allSlotsEqual = false
            break
        end
    end
    return allSlotsEqual
end

--[[--
Finds all compaction patterns present in the system.
 
Criteria is "consists of 9 identical items".
]]
local function findCompactionPatterns(rs)
    return fetchCompactionPatterns(rs, rs.getPatterns())
end

local function fetchCompactionPatterns(rs, patterns)
    local compactionPatterns = {}
    for _, info in ipairs(patterns) do
        local pat = rs.getPattern(info)
        if pat ~= nil and isCompactionPattern(pat) then
            vlog("Found compaction pattern: %s (%s)", info.label, info.name)
            table.insert(compactionPatterns, {
                info = info,
                inputs = pat.inputs[1],
                inputs_per_output = 9
            })
        end
    end
    return compactionPatterns
end

local function findPatternsWithConfig(rs, config)
    if config.whitelist == nil then
        return fetchCompactionPatterns(rs, rs.getPatterns())
    end
    return fetchCompactionPatterns(rs, config.whitelist)
end

local function calculateTasks(rs, patterns)
    local tasks = {}
    for _, pattern in ipairs(patterns) do
        vlog("Trying to craft %s...", pattern.info.label)
        local totalInputs = 0
        for _, input in ipairs(pattern.inputs) do
            local info = rs.getItem(input)
            if info ~= nil then
                vlog("Found %d of %s", info.size, input.label)
                totalInputs = totalInputs + info.size
            end
        end
        local canCraft = totalInputs // pattern.inputs_per_output
        vlog("Can craft %d %s", canCraft, pattern.info.label)
        if canCraft > 0 then
            table.insert(tasks, {
                pattern = pattern.info,
                quantity = canCraft,
                slots_saved = canCraft * pattern.inputs_per_output - canCraft,
            })
        end
    end
    return tasks
end

local function scheduleTasks(rs, tasks)
    for _, task in ipairs(tasks) do
        rs.scheduleTask(task.pattern, task.quantity)
    end
end

local function genConfig(rs)
    local compactionPatterns = findPatternsWithConfig(rs, {})
    local config = {whitelist = {}}
    for _, pattern in ipairs(compactionPatterns) do
        table.insert(config.whitelist, {
            label = pattern.info.label,
            name = pattern.info.name,
            damage = pattern.info.damage,
        })
    end
    return serialization.serialize(config)
end

if opts.h or opts.help then
    print(usageString)
    return
end

local function loadConfig(path)
    local file, msg = io.open(path, "rb")
    if not file then
        if opts.config ~= nil then
            -- Config path was specified explicitly, so we better
            -- report the error.
            error("Failed to open config file: " .. msg)
        end
        vlog("Failed to open config file, going with defaults.")
        return {}
    end
    local content = file:read("*a")
    file:close()
    return serialization.unserialize(content)
end

local config = loadConfig(configPath)
local rs = getComponent()

if not rs.isConnected() then
    log("Component %q is not connected to storage controller", rs.address)
    return
end

if opts.genConfig then
    print(genConfig(rs))
else
    local patterns = findPatternsWithConfig(rs, config)
    local tasks = calculateTasks(rs, patterns)
    if #tasks == 0 then
        if not opts.auto then
            print("Nothing to craft.")
        end
        return
    end
    print("Will schedule the following crafting tasks:")
    local savedSpace = 0
    for _, task in ipairs(tasks) do
        print(string.format(" * %d of %s (%s)", task.quantity, task.pattern.label, task.pattern.name))
        savedSpace = savedSpace + task.slots_saved
    end
    print(string.format("This will free %d slots in storage.", savedSpace))
    if not opts.auto then
        print("Proceed? [Y/n]")
        if not ((io.read() or "n") .. "y"):match("^%s*[Yy]") then
            return
        end
    end
    scheduleTasks(rs, tasks)
end

