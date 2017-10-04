package.path = "./?.luac;" .. package.path

local type = type

local deepFreeze = require("rotable").deepFreeze

do
	local _require = _G.require
	_G._require = _require
	_G.require = function(module)
		local mod = _require(module)
		if type(mod) ~= "table" then
			return mod
		end
		return deepFreeze(mod)
	end
end

local mrandomseed = math.randomseed
_G.strdump = string.dump
string.dump = nil

local require = require
local json = require("json_patched")
local bit = require("bit")
local util = require("util")
local timeUtil = require("time")
local checkTimeout = timeUtil.checkTimeout
local writeln = require("writeln")
local random = require("random")
local safePcall = require("safe_error").pcall
local loadScript = require("loadscript")
local killSwitch = require("killswitch")
local unpack = unpack
local error = error
local next = next
local tremove = table.remove
local treadonly = table.setreadonly
local load = load
local xpcall = xpcall
local exit = os.exit

do
	deepFreeze(_G, true)

	local NULL_ENV = treadonly(killSwitch.boobyTrap({}))

	local setfenv = setfenv
	local __G = _G
	for k, _ in next, __G do
		__G[k] = nil
	end
	killSwitch.boobyTrap(__G)
	treadonly(__G)

	setfenv(0, NULL_ENV)
	setfenv(1, NULL_ENV)
end

local function __run(caller, scriptName, args, info)
	local coreScript

	do
		mrandomseed(random.int64())

		if info and info ~= "" then
			loadScript.setInfo(json.decode(info))
		else
			loadScript.setInfo({})
		end

		local ok
		ok, coreScript =  loadScript.load({
			caller = caller,
			cli = true
		}, caller, scriptName, false)
		if not ok then
			writeln(json.encodeAll({
				type = "error",
				script = scriptName,
				data = coreScript
			}))
			return
		end

		if args and args ~= "" then
			args = json.decode(args)
		end
	end

	timeUtil.setTimes(timeUtil.time(), 5000)

	local res = {safePcall(coreScript.run, args)}
	local _res
	if res[1] then
		if #res == 1 then
			_res = {
				type = "return",
				script = coreScript.name
			}
		elseif #res == 2 then
			_res = {
				type = "return",
				script = coreScript.name,
				data = res[2]
			}
		else
			tremove(res, 1)
			_res = {
				type = "return",
				script = coreScript.name,
				data = res
			}
		end
	else
		_res = {
			type = "error",
			script = coreScript.name,
			data = res[2]
		}
	end
	local ok, _json = safePcall(json.encodeAll, _res)
	if not ok then
		_json = json.encodeAll({
			type = "error",
			script = coreScript.name,
			data = _json
		})
	end
	writeln(_json)
end

return __run