local component = require("component")
local shell = require("shell")

-- list of methods we look for on components
local requiredMethods = {
	"getPattern",
	"getItem",
	"scheduleTask",
}

local args, ops = shell.parse(...)

local function log(...)
	io.stderr:write(string.format(...))
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

local function autocraftItem(item)
	local rs = getComponent()
	local pattern = rs.getPattern({name=item})
	local inputs = {}
	for i, input in pairs(pattern.inputs) do
		local name = input[1].name
		local qty = input.n * input[1].size  -- I've no idea if this is correct
		if inputs[name] == nil then inputs[name] = 0 end
		inputs[name] = inputs[name] + qty
	end
	log("Found pattern for %q with inputs: %s", item, inputs)

	local maxQty = nil
	for item, qty in pairs(inputs) do
		local size = rs.getItem({name=item}).size
		local enoughFor = size // qty
		log("Input %q is present in quantity of %d, enough for %d items", item, size, enoughFor)
		if maxQty > enoughFor or maxQty == nil then
			maxQty = enoughFor
		end
	end

	if maxQty > 0 then
		log("Scheduling a task to craft %d of %q", maxQty, item)
		rs.scheduleTask({name=item}, maxQty)
	else
		log("Not enough inputs in storage to craft even one %q", item)
	end
end

autocraftItem(args[1])
