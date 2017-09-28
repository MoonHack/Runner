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
local json = require("dkjson")
local xpcall = xpcall
local debug = debug
local uuid = require("uuid")
local ffi = require("ffi")
local db = require("db")
local bit = require("bit")
local notificationDb = db.internal:getCollection("notifications")

ffi.cdef[[
	void lua_enterprot();
	void lua_leaveprot();
	void notify_user(const char *name, const char *data);
	int poll(struct pollfd *fds, unsigned long nfds, int timeout);
	void lua_writeln(const char *str);
	size_t read_random(void *buffer, size_t len);
]]

local function json_encodeAll_exception(reason, value, state, defaultmessage)
	if reason ~= "unsupported type" then
		return nil, defaultmessage
	end
	return json.encode({ ["$error"] = defaultmessage }, state)
end

local function json_encodeAll(obj)
	return json.encode(obj, {
		exception = json_encodeAll_exception
	})
end
json.encode_all = json_encodeAll

local time = os.time
local exit = os.exit

local PROTECTION_DEPTH = 0
local START_TIME = 0
local KILL_TIME = 0
function timeLeft()
	return KILL_TIME - time()
end
local timeLeft = timeLeft

function checkTimeout()
	if PROTECTION_DEPTH <= 0 and timeLeft() < 0 then
		exit(6) -- EXIT_SOFT_TIMEOUT
	end
end
local checkTimeout = checkTimeout

function writeln(str)
	ffi.C.lua_writeln(str .. "\n")
	checkTimeout()
end
local writeln = writeln

function notifyUser(from, to, msg)
	msg = {
		to = to,
		from = from,
		msg = json_encodeAll(msg),
		date = db.now()
	}
	ffi.C.notify_user(to, json_encodeAll(msg))
	notificationDb:insert(msg)
	checkTimeout()
end

function secureRandom(len)
	local res = ffi.new("char[?]", len)
	if ffi.C.read_random(res, len) ~= 1 then
		error("Could not get random")
	end
	return ffi.string(res, len)
end

function sleep(seconds)
	ffi.C.poll(nil, 0, seconds * 1000)
	checkTimeout()
end

local function enterProtectedSection()
	ffi.C.lua_enterprot()
	PROTECTION_DEPTH = PROTECTION_DEPTH + 1
end

local function leaveProtectedSection()
	PROTECTION_DEPTH = PROTECTION_DEPTH - 1
	if PROTECTION_DEPTH < 0 then
		exit(1)
	end
	checkTimeout()
	ffi.C.lua_leaveprot()
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

local function makeSafe(func)
	return function(...)
		return xpcall(func, errorHandler, ...)
	end
end
local function makeSafeSingle(func)
	return function(arg)
		return xpcall(func, errorHandler, arg)
	end
end
json.encode_all_safe = makeSafeSingle(json.encode_all)
json.decode_safe = makeSafeSingle(json.decode)
json.encode_safe = makeSafeSingle(json.encode)

local SUB_ENV = {
	assert = assert,
	tostring = tostring,
	tonumber = tonumber,
	ipairs = ipairs,
	sleep = sleep,
	pcall = function(func, ...)
		checkTimeout()
		return xpcall(func, errorHandler, ...)
	end,
	pairs = pairs,
	bit = bit,
	error = error,
	rawequal = rawequal,
	rawget = rawget,
	rawset = _protectTblFunction(rawset),
	unpack = unpack,
	json = {
		encode = function(obj)
			return json.encode(obj)
		end,
		decode = function(obj)
			return json.decode(obj)
		end,
		encode_all = json.encode_all,
		encode_all_safe = json.encode_all_safe,
		decode_safe = json.decode_safe,
		encode_safe = json.encode_safe
	},
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
	bit = bit,
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
		accessLevels = {
			'PRIVATE',
			'HIDDEN',
			'PUBLIC'
		},
		startTime = START_TIME,
		killTime = KILL_TIME
	}
}
SUB_ENV.math.secureRandom = secureRandom

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

local CALLER

local writeln = writeln
local loadscript = require("loadscript")

local function loadMainScript(script, isScriptor)
	return loadscript({
		caller = CALLER,
		isScriptor = isScriptor
	}, CALLER, script, false)
end

uuid.seed()

string.dump = nil
_G.os = nil
_G.ffi = nil
_G.jit = nil
_G.debug = nil
_G.io = nil
_G.require = nil
_G.dofile = nil
_G.loadfile = nil
_G.load = nil
_G.package = nil
_G.print = nil
_G.writeln = nil
_G.print = nil
_G.notifyUser = nil

local function __run(_runId, _caller, _script, args)
	do
		local a, b, c, d = secureRandom(4):byte(1,4)
		local seed = a*0x1000000 + b*0x10000 + c *0x100 + d
		uuid.randomseed(seed)

		runId = _runId or "UNKNOWN"
		CAN_SOFT_KILL = true
		START_TIME = time()
		KILL_TIME = START_TIME + 6

		local ok
		CALLER = _caller
		ok, CORE_SCRIPT = loadMainScript(_script, false)
		if not ok then
			writeln(json_encodeAll({
				type = "error",
				script = _script,
				data = CORE_SCRIPT
			}))
			return
		end

		if args and args ~= '' then
			args = json.decode(args)
		end

		if args and type(args) == "table" then
			for k, v in next, args do
				if type(v) == "table" and v.__scriptor then
					args[k] = loadMainScript(v.__scriptor, true)
				end
			end
		end
	end

	local _ENV = {}
	local res = {xpcall(CORE_SCRIPT.run, errorHandler, args)}
	local _res
	if res[1] then
		if #res == 1 then
			_res = {
				type = "return",
				script = CORE_SCRIPT.name
			}
		elseif #res == 2 then
			_res = {
				type = "return",
				script = CORE_SCRIPT.name,
				data = res[2]
			}
		else
			tremove(res, 1)
			_res = {
				type = "return",
				script = CORE_SCRIPT.name,
				data = res
			}
		end
	else
		_res = {
			type = "error",
			script = CORE_SCRIPT.name,
			data = res[2]
		}
	end
	local ok, _json = xpcall(json_encodeAll, errorHandler, _res)
	if not ok then
		_json = json_encodeAll({
			type = "error",
			script = CORE_SCRIPT.name,
			data = _json
		})
	end
	writeln(_json)
	exit(0)
end

collectgarbage()

return __run