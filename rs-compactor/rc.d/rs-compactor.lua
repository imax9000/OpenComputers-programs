local event = require("event")
local shell = require("shell")

local timerHandle = nil

local function getInterval()
    local ok, interval = pcall(function() return args.interval end)
    if ok then
        return interval
    end
    return 60 -- default to one minute
end

local function run()
    shell.execute("rs-compactor --auto")
end

function start()
    timerHandle = event.timer(getInterval(), run, math.huge)
end

function stop()
    if not event.cancel(timerHandle) then
        error("failed to stop timer")
    end
end
