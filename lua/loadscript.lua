local db = require("db")
local dbintf = require("dbintf")
local util = require("util")
local setfenv = setfenv
local load = load
local next = next
local strdump = string.dump
local checkTimeout = checkTimeout
local io = io
local function flagSet(flags, flag)
	return bit.band(flags, flag) == flag
end

local scriptsDb = db.internal:getCollection("scripts")

local scriptCache = {}

local LOAD_AS_OWNER = 1
local LOAD_ONLY_INFORMATION = 2

local function loadCoreScript(name, securityLevel)
	local file = "corescripts/" .. name:gsub("%.", "/") .. ".lua"
	scriptCache[name] = {
		name = name,
		__func = dofile(file),
		accessLevel = 3,
		securityLevel = securityLevel,
		privileged = true
	}
end

loadCoreScript("scripts.lib", 5)

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

local loadscript

local function loadscriptInternal(script, compile)
	if type(script) ~= "string" then
		return false, "Script name must be a string"
	end

	local data = scriptCache[script]
	if not data then
		data = scriptsDb:findOne({
			_id = script
		})
		if not data then
			return false, "Script not found"
		end
		data = data:value()
		scriptCache[data._id] = data
	end

	if compile and not data.__func then
		local callingScript = data._id
		local callingScriptOwner = data.owner
		local secLevel = data.securityLevel

		local PROTECTED_SUB_ENV = util.shallowCopy(TEMPLATE_SUB_ENV)

		PROTECTED_SUB_ENV.game = {
			LOAD_AS_OWNER = LOAD_AS_OWNER,
			LOAD_ONLY_INFORMATION = LOAD_ONLY_INFORMATION,
			loadscript = function(script, flags)
				checkTimeout()
				flags = flags or 0
				return loadscript({
					thisScript = script,
					callingScript = callingScript,
					isScriptor = false,
					caller = flagSet(flags, LOAD_AS_OWNER) and callingScriptOwner or CORE_SCRIPT.caller
				}, secLevel, script, flagSet(flags, LOAD_ONLY_INFORMATION))
			end,
			db = dbintf(data._id),
			cache = {} -- Not protected on purpose, like #G
		}

		freeze(PROTECTED_SUB_ENV.game)
		freeze(PROTECTED_SUB_ENV)

		do
			local _ENV = {}
			local func

			if data.codeBinary and data.codeDate == data.codeBinaryDate then
				local ok, res = pcall(load, data.codeBinary, data._id, "b", {})
				if ok then
					func = res
				end
			end

			if not func then
				func = load("return " .. data.code, data._id, "t", {})
				data.codeBinary = strdump(func)
				scriptsDb:update({
					name = data._id
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

loadscript = function(ctx, parentSecLevel, script, onlyInformative)
	local runnable = ctx and not onlyInformative
	local ok, data = loadscriptInternal(script, runnable)
	if not ok then
		return false, data
	end
	local info = {
		securityLevel = data.securityLevel,
		accessLevel = data.accessLevel,
		privileged = data.privileged,
		name = data._id,
		owner = data.owner
	}
	if runnable then
		if data.securityLevel < parentSecLevel then
			return false, "Cannot load script with lower security level than parent script"
		end
		local parentOwner = ctx.caller
		if ctx.callingScript then
			parentOwner = util.getUserFromScript(ctx.callingScript)
		end
		if data.accessLevel < 2 and parentOwner ~= getUserFromScript(data._id) then
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

_G.loadscript = loadscript

return loadscript
