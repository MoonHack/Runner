local db = require("db")
local dbintf = require("dbintf")
local util = require("util")
local setfenv = setfenv
local load = load
local next = next
local strdump = string.dump
local checkTimeout = checkTimeout
local io = io
local tinsert = table.insert
local writeln = writeln
local notifyUser = notifyUser
local function flagSet(flags, flag)
	return bit.band(flags, flag) == flag
end

local function scriptPrint(initial, script)
	return function(...)
		local data = {...}
		if #data == 1 then
			data = data[1]
		end
		writeln(cjson.encode({
			type = "print",
			initial = initial,
			script = script,
			data = data
		}))
	end
end

local scriptsDb = db.internal:getCollection("scripts")

local scriptCache = {}
_G.coreScripts = {}

local LOAD_AS_OWNER = 1
local LOAD_ONLY_INFORMATION = 2

local function loadCoreScript(name, securityLevel, accessLevel)
	accessLevel = accessLevel or 3

	local file = "corescripts/" .. name:gsub("%.", "/")

	scriptCache[name] = {
		name = name,
		__func = require(file),
		accessLevel = accessLevel,
		securityLevel = securityLevel,
		system = true
	}

	if accessLevel == 3 then
		tinsert(coreScripts, {
			name = name,
			accessLevel = accessLevel,
			securityLevel = securityLevel,
			system = true
		})
	end
end

loadCoreScript("notifications.recent", 4)

loadCoreScript("scripts.sleep", 5)
loadCoreScript("scripts.lib", 5)
loadCoreScript("scripts.upload", 1)
loadCoreScript("scripts.delete", 1)
loadCoreScript("scripts.list", 4)

loadCoreScript("money.balance", 3)
loadCoreScript("money.log", 4)
loadCoreScript("money.transfer", 4)

loadCoreScript("programs.delete", 2)
loadCoreScript("programs.list", 4)
loadCoreScript("programs.load", 3)
loadCoreScript("programs.log", 4)
loadCoreScript("programs.reorder", 3)
loadCoreScript("programs.transfer", 2)
loadCoreScript("programs.unload", 3)

_G.coreScripts = nil

local loadscript

local function loadscriptInternal(ctx, script, compile)
	if type(script) ~= "string" then
		return false, "Script name must be a string"
	end

	local data = scriptCache[script]
	if not data then
		data = scriptsDb:findOne({
			name = script
		})
		if not data then
			return false, "Script not found"
		end
		data = data:value()
		scriptCache[data.name] = data
	end

	if compile and not data.__func then
		local callingScript = data.name
		local callingScriptOwner = data.owner
		local secLevel = data.securityLevel

		local PROTECTED_SUB_ENV = util.shallowCopy(TEMPLATE_SUB_ENV)
		PROTECTED_SUB_ENV.print = scriptPrint(callingScript, (not ctx.callingScript) and (not ctx.isScriptor))

		local function loadScriptGame(script, flags)
			local asOwner = flagSet(flags, LOAD_AS_OWNER)
			checkTimeout()
			flags = flags or 0
			return loadscript({
				thisScript = script,
				callingScript = callingScript,
				isScriptor = false,
				caller = asOwner and callingScriptOwner or CORE_SCRIPT.caller
			}, asOwner and 0 or secLevel, callingScriptOwner, script, flagSet(flags, LOAD_ONLY_INFORMATION))
		end

		PROTECTED_SUB_ENV.game = {
			LOAD_AS_OWNER = LOAD_AS_OWNER,
			LOAD_ONLY_INFORMATION = LOAD_ONLY_INFORMATION,
			script = {
				load = loadScriptGame,
				info = function(script)
					return loadScriptGame(script, LOAD_ONLY_INFORMATION)
				end
			},
			db = dbintf(data.name),
			notify = {
				caller = function(msg)
					notifyUser(CORE_SCRIPT.caller, callingScript, msg)
				end,
				owner = function(msg)
					notifyUser(callingScriptOwner, callingScript, msg)
				end
			},
			cache = {} -- Not protected on purpose, like #G
		}

		freeze(PROTECTED_SUB_ENV.notify)
		freeze(PROTECTED_SUB_ENV.game.script)
		freeze(PROTECTED_SUB_ENV.game)
		freeze(PROTECTED_SUB_ENV)

		do
			local _ENV = {}
			local func

			if data.codeBinary and data.codeDate == data.codeBinaryDate then
				local ok, res = pcall(load, data.codeBinary, data.name, "b", {})
				if ok then
					func = res
				end
			end

			if not func then
				local ok
				ok, data.codeBinary, func = pcall(util.compileScript, data.code, data.name)
				if not ok then
					return false, 'Compile error in ' .. data.name
				end
				scriptsDb:update({
					name = data.name
				}, {
					["$set"] = {
						codeBinary = data.codeBinary,
						codeBinaryDate = data.codeDate
					}
				})
			end

			if setfenv then
				setfenv(func, _ENV)
			end
			data.__func = func()
		end
		data.__ENV = PROTECTED_SUB_ENV
		if setfenv then
			setfenv(data.__func, PROTECTED_SUB_ENV)
		end
	end
	return true, data
end

loadscript = function(ctx, parentSecLevel, parentOwner, script, onlyInformative)
	local runnable = ctx and not onlyInformative
	local ok, data = loadscriptInternal(ctx, script, runnable)
	if not ok then
		return false, data
	end
	local info = {
		securityLevel = data.securityLevel,
		accessLevel = data.accessLevel,
		system = data.system,
		name = data.name,
		owner = data.owner
	}
	if runnable then
		if data.securityLevel < parentSecLevel then
			return false, "Cannot load script with lower security level than parent script"
		end
		if data.accessLevel < 2 and parentOwner ~= data.owner then
			return false, "Cannot load private script of different user"
		end

		info.run = function(args)
			local _ENV = data.__ENV
			checkTimeout()
			return data.__func(ctx, args)
		end
	end
	return true, info
end

--_G.loadscript = loadscript

return loadscript
