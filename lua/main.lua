package.path = "./?.luac;" .. package.path

local runId = "UNKNOWN"
local unpack = unpack
local error = error
local write = io.write
local flush = io.flush
local type = type
local next = next
local tinsert = table.insert
local tremove = table.remove
local strbyte = string.byte
local strgsub = string.gsub
local getmetatable = getmetatable
local setmetatable = setmetatable
local arg = arg
local load = load
local cjson = require("cjson")
local xpcall = xpcall
local debug = debug
local uuid = require("uuid")

local function noop()
end

local function writeln(str)
	write(str .. "\n")
	flush()
end

local time = os.time
local exit = os.exit

local PROTECTION_DEPTH = 0
local START_TIME = 0
local KILL_TIME = 0
function timeLeft()
	return KILL_TIME - time()
end

function checkTimeout()
	if PROTECTION_DEPTH <= 0 and timeLeft() < 0 then
		exit(6) -- EXIT_SOFT_TIMEOUT
	end
end

local extEnterProtected, extLeaveProtected
local function enterProtectedSection()
	extEnterProtected()
	PROTECTION_DEPTH = PROTECTION_DEPTH + 1
end

local function leaveProtectedSection()
	PROTECTION_DEPTH = PROTECTION_DEPTH - 1
	if PROTECTION_DEPTH < 0 then
		exit(1)
	end
	checkTimeout()
	extLeaveProtected()
end

function runProtected(...)
	enterProtectedSection()
	local res = {pcall(...)}
	leaveProtectedSection()
	if not res[1] then
		error(res[2])
	end
	tremove(res, 1)
	return unpack(res)
end

local runProtected = runProtected

function makeProtectedFunc(func)
	return function(...)
		return runProtected(func, ...)
	end
end


local function _errorReadOnly()
	error("Read-Only")
end

local function _protectTblFunction(func)
	return function(tbl, ...)
		if tbl.__protected then
			_errorReadOnly()
		end
		return func(tbl, ...)
	end
end

local AT = strbyte("@", 1)
local function errorHandler(err)
	local msg = "ERROR: " .. strgsub(err, ".+: ", "")
	for i=2,99 do
		local info = debug.getinfo(i)
		if not info or info.what == "main" or info.func == xpcall then
			break
		end
		if info.what ~= "Lua" or strbyte(info.source, 1) ~= AT then
			local sourceName
			if info.namewhat == "global" then
				sourceName = "global function " .. info.name
			elseif info.namewhat == "local" then
				sourceName = "local function " .. info.name
			elseif info.namewhat == "method" then
				sourceName = "method " .. info.name
			elseif info.namewhat == "field" then
				sourceName = "field " .. info.name
			else
				sourceName = "main chunk"
			end
			msg = msg .. "\n\t" .. info.source .. ":" .. tostring(info.linedefined) .. ": " .. sourceName
		else
			msg = msg .. "\n\t--hidden--"
		end
	end
	return msg
end

local SUB_ENV = {
	assert = assert,
	tostring = tostring,
	tonumber = tonumber,
	ipairs = ipairs,
	print = function(...)
		local data = {...}
		if #data == 1 then
			data = data[1]
		end
		writeln(cjson.encode(data))
		checkTimeout()
	end,
	pcall = function(func, ...)
		checkTimeout()
		return xpcall(func, errorHandler, ...)
	end,
	pairs = pairs,
	bit = bit,
	error = error,
	rawequal = rawequal,
	rawset = _protectTblFunction(rawset),
	unpack = unpack,
	json = require("cjson.safe"),
	table = {
		--foreach = table.foreach,
		sort = _protectTblFunction(table.sort),
		remove = _protectTblFunction(table.remove),
		insert = _protectTblFunction(table.insert),
		--foreachi = table.foreachi,
		maxn = table.maxn,
		getn = table.getn,
		concat = table.concat
	},
	newproxy = newproxy,
	next = next,
	math = math,
	os = {
		clock = os.clock,
		date = os.date,
		difftime = os.difftime,
		time = os.time
	},
	string = string,
	type = type,
	getmetatable = getmetatable,
	setmetatable = setmetatable,
	constants = {
		securityLevels = {
			'FULLSEC',
			'HIGHSEC',
			'MIDSEC',
			'LOWSEC',
			'NULLSEC'
		},
		accessLevels = {
			'PUBLIC',
			'HIDDEN',
			'PRIVATE'
		},
		startTime = START_TIME
	}
}

SUB_ENV._G = SUB_ENV

function freeze(tbl)
	tbl.__protected = true

	local mt = getmetatable(tbl)
	if not mt then
		mt = {}
	end

	mt.__metatable = "PROTECTED"
	mt.__newindex = _errorReadOnly

	return setmetatable(tbl, mt)
end

function deepFreeze(tbl)
	local ret = {}
	for k, v in next, tbl do
		if v == tbl then
			ret[k] = ret
		elseif type(v) ~= "table" then
			ret[k] = v
		elseif v.__protected and getmetatable(v) == "PROTECTED" then
			ret[k] = v
		else
			ret[k] = deepFreeze(v, true)
		end
	end

	return freeze(ret)
end

SUB_ENV.util = {
	freeze = freeze,
	deepFreeze = deepFreeze,
	timeLeft = timeLeft
}

TEMPLATE_SUB_ENV = deepFreeze(SUB_ENV, false)
local TEMPLATE_SUB_ENV = TEMPLATE_SUB_ENV

local CALLER

local loadscript = require("loadscript")

string.dump = nil

local function loadMainScript(script, isScriptor)
	return loadscript({
		thisScript = script,
		caller = CALLER,
		isScriptor = isScriptor
	}, -1, script, false)
end

_G.os = nil
_G.ffi = nil
_G.jit = nil
_G.debug = nil
_G.io = nil
_G.require = nil
_G.dofile = nil
_G.loadfile = nil
_G.load = nil

local function __run(_runId, _caller, _script, args, _extEnterProtected, _extLeaveProtected)
	uuid.seed()

	runId = _runId or "UNKNOWN"
	extEnterProtected = _extEnterProtected or noop
	extLeaveProtected = _extLeaveProtected or noop
	CAN_SOFT_KILL = true
	START_TIME = time()
	KILL_TIME = START_TIME + 6

	local ok
	CALLER = _caller
	ok, CORE_SCRIPT = loadMainScript(_script, false)
	if not ok then
		writeln(cjson.encode({
			ok = false,
			msg = CORE_SCRIPT
		}))
		return
	end

	if args and args ~= '' then
		args = cjson.decode(args)
	end

	if args and type(args) == "table" then
		for k, v in next, args do
			if type(v) == "table" and v.__scriptor then
				args[k] = loadMainScript(v.__scriptor, true)
			end
		end
	end

	local _ENV = {}
	local res = {xpcall(CORE_SCRIPT.run, errorHandler, args)}
	if res[1] then
		if #res == 2 then
			writeln(cjson.encode(res[2]))
		else
			tremove(res, 1)
			writeln(cjson.encode(res))
		end
	else
		writeln(cjson.encode({
			ok = false,
			msg = res[2]
		}))
	end
	exit(0)
end

--local resetScriptCache = resetScriptCache
--local collectgarbage = collectgarbage

return __run --[[, function()
	resetScriptCache()
	collectgarbage()
end]]
