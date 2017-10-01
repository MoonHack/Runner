local timeUtil = require("time")
local roTable = require("rotable")
local safeError = require("safe_error")
local json = require("json_patched")
local util = require("util")

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
		encodeSafe = json.encodeSafe
	},
	table = table,
	newproxy = newproxy,
	next = next,
	math = math,
	bit = require("bit"),
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
	collectgarbage = collectgarbage,
	constants = {
		accessLevels = {
			[1] = "PRIVATE",
			[2] = "HIDDEN",
			[3] = "PUBLIC",
			PUBLIC = 3,
			HIDDEN = 2,
			PRIVATE = 1,
		}
	},
	resources = require("resmon"),
	secureRandom = require("random"),
	util = {
		freeze = roTable.freeze,
		deepFreeze = roTable.deepFreeze,
		timeLeft = timeUtil.timeLeft,
		shallowCopy = util.shallowCopy,
		deepCopy = util.deepCopy,
		microtime = timeUtil.time,
		sleep = timeUtil.sleep
	}
}
