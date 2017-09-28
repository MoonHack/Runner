package.path = "./?.luac;" .. package.path

local noGlobalLeaks = require("no_global_leaks")
local DEF_G = noGlobalLeaks.snapshotGTable(_G)

local json = require("json_patched")
local uuid = require("uuid")
local bit = require("bit")
local util = require("util")
local timeUtil = require("time")
local checkTimeout = timeUtil.checkTimeout
local writeln = require("writeln")
local random = require("random")
local safePcall = require("safe_error").pcall
local loadscript = require("loadscript")
local unpack = unpack
local error = error
local type = type
local next = next
local tremove = table.remove
local load = load
local xpcall = xpcall
local exit = os.exit

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

noGlobalLeaks.fixLeaks(DEF_G, _G)

DEF_G = nil
noGlobalLeaks = nil

local function loadMainScript(script, caller, isScriptor)
	return loadscript({
		caller = caller,
		isScriptor = isScriptor
	}, caller, script, false)
end

local function __run(runId, caller, scriptName, args)
	local coreScript

	do
		local a, b, c, d = random.secureRandom(4):byte(1,4)
		local seed = a*0x1000000 + b*0x10000 + c *0x100 + d
		uuid.randomseed(seed)

		timeUtil.setTimes(timeUtil.time(), 5000)

		local ok
		ok, coreScript = loadMainScript(scriptName, caller, false)
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

		if args and type(args) == "table" then
			for k, v in next, args do
				if type(v) == "table" and v["$scriptor"] then
					args[k] = loadMainScript(v["$scriptor"], caller, true)
				end
			end
		end
	end

	local _ENV = {}
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
	exit(0)
end

collectgarbage()

return __run