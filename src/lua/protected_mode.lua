local ffi = require("ffi")
local timeUtil = require("time")
local tremove = table.remove
local unpack = unpack
local pcall = pcall
local error = error
local exit = os.exit
local roTable = require("rotable")

ffi.cdef[[
	void lua_enterprot();
	void lua_leaveprot();
]]

local PROTECTION_DEPTH = 0

local function enterProtectedSection()
	ffi.C.lua_enterprot()
	PROTECTION_DEPTH = PROTECTION_DEPTH + 1
	timeUtil.disableTimeout()
end

local function leaveProtectedSection()
	PROTECTION_DEPTH = PROTECTION_DEPTH - 1
	timeUtil.enableTimeout()
	if PROTECTION_DEPTH < 0 then
		exit(1)
	end
	timeUtil.checkTimeout()
	ffi.C.lua_leaveprot()
end

local function runProtected(...)
	enterProtectedSection()
	local res = {pcall(...)}
	leaveProtectedSection()
	if not res[1] then
		error(res[2])
	end
	tremove(res, 1)
	return unpack(res)
end

local function makeProtectedFunc(func)
	return function(...)
		return runProtected(func, ...)
	end
end

return roTable.deepFreeze({
	runProtected = runProtected,
	makeProtectedFunc = makeProtectedFunc
})
