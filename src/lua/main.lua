package.path = "./?.luac;" .. package.path

local runId = "UNKNOWN"
local unpack = unpack
local error = error
local type = type
local next = next
local tremove = table.remove
local load = load
local xpcall = xpcall
local json = require("json_patched")
local uuid = require("uuid")
local bit = require("bit")
local util = require("util")
local timeUtil = require("time")
local checkTimeout = timeUtil.checkTimeout
local roTable = require("rotable")
local writeln = require("writeln")
local random = require("random")
local safePcall = require("safe_error").pcall

local exit = os.exit

local SUB_ENV = {
	assert = assert,
	tostring = tostring,
	tonumber = tonumber,
	ipairs = ipairs,
	pcall = safePcall,
	pairs = pairs,
	bit = bit,
	error = error,
	rawequal = rawequal,
	rawget = rawget,
	rawset = roTable.protectTblFunction(rawset),
	unpack = unpack,
	json = {
		encode = function(obj)
			return json.encode(obj)
		end,
		decode = function(obj)
			return json.decode(obj)
		end,
		encodeAll = json.encodeAll,
		encodeAllSafe = json.encodeAllSafe,
		decodeSafe = json.decodeSafe,
		decodeSafe = json.encodeSafe
	},
	table = {
		foreach = table.foreach,
		sort = roTable.protectTblFunction(table.sort),
		remove = roTable.protectTblFunction(table.remove),
		insert = roTable.protectTblFunction(table.insert),
		foreachi = table.foreachi,
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
			"PRIVATE",
			"HIDDEN",
			"PUBLIC"
		}
	}
}

SUB_ENV._G = SUB_ENV

SUB_ENV.util = {
	freeze = roTable.freeze,
	deepFreeze = roTable.deepFreeze,
	timeLeft = timeUtil.timeLeft,
	shallowCopy = util.shallowCopy,
	deepCopy = util.deepCopy,
	secureRandom = random.secureRandom,
	microtime = timeUtil.time,
	sleep = timeUtil.sleep
}

TEMPLATE_SUB_ENV = roTable.deepFreeze(SUB_ENV, false)

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

local function __run(_runId, _caller, _script, args)
	do
		local a, b, c, d = random.secureRandom(4):byte(1,4)
		local seed = a*0x1000000 + b*0x10000 + c *0x100 + d
		uuid.randomseed(seed)

		runId = _runId or "UNKNOWN"
		CAN_SOFT_KILL = true
		timeUtil.setTimes(timeUtil.time(), 5000)

		local ok
		CALLER = _caller
		ok, CORE_SCRIPT = loadMainScript(_script, false)
		if not ok then
			writeln(json.encodeAll({
				type = "error",
				script = _script,
				data = CORE_SCRIPT
			}))
			return
		end

		if args and args ~= "" then
			args = json.decode(args)
		end

		if args and type(args) == "table" then
			for k, v in next, args do
				if type(v) == "table" and v["$scriptor"] then
					args[k] = loadMainScript(v["$scriptor"], true)
				end
			end
		end
	end

	local _ENV = {}
	local res = {safePcall(CORE_SCRIPT.run, args)}
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
	local ok, _json = safePcall(json.encodeAll, _res)
	if not ok then
		_json = json.encodeAll({
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