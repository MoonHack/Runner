local timeUtil = require("time")
local roTable = require("rotable")
local safeError = require("safe_error")
local json = require("json_patched")
local util = require("util")
local random = require("random")
local bit = require("bit")

return {
	assert = assert,
	tostring = tostring,
	tonumber = tonumber,
	ipairs = ipairs,
	pcall = safeError.pcall,
	pairs = pairs,
	bit = bit,
	error = error,
	rawequal = rawequal,
	rawget = rawget,
	rawset = rawset,
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
	table = table,
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
	},
	util = {
		freeze = roTable.freeze,
		deepFreeze = roTable.deepFreeze,
		timeLeft = timeUtil.timeLeft,
		shallowCopy = util.shallowCopy,
		deepCopy = util.deepCopy,
		secureRandom = random.secureRandom,
		microtime = timeUtil.time,
		sleep = timeUtil.sleep
	}
}
