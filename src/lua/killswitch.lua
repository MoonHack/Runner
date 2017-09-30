local exit = os.exit
local dsetmetatable = debug.setmetatable
local treadonly = table.setreadonly

local dtraceback = debug.traceback
local print = io.write

local function killSwitch(a,b)
	print(dtraceback())
	exit(7) -- EXIT_KILLSWITCH
end

local _trapMt = treadonly({
	__len = killSwitch,
	__add = killSwitch,
	__sub = killSwitch,
	__mul = killSwitch,
	__div = killSwitch,
	__mod = killSwitch,
	__pow = killSwitch,
	__unm = killSwitch,
	__concat = killSwitch,
	__len = killSwitch,
	__eq = killSwitch,
	__lt = killSwitch,
	__le = killSwitch,
	__index = killSwitch,
	__newindex = killSwitch,
	__call = killSwitch,
	__tostring = killSwitch,
	__tojson = killSwitch,
	__metatable = "PROTECTED"
})

local function boobyTrap(obj)
	dsetmetatable(obj, _trapMt)
	return obj
end

return {
	killSwitch = killSwitch,
	boobyTrap = boobyTrap
}
