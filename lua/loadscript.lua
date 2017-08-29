local db = require("db")
local dbintf = require("dbintf")
local util = require("util")
local setfenv = setfenv
local load = load
local next = next
local strdump = string.dump
local checkTimeout = checkTimeout
local io = io

local scriptsDb = db.internal:getCollection("scripts")

local scriptCache = {}

--[[function resetScriptCache()
	scriptCache = {}
end]]

local function loadCoreScript(name, securityLevel)
	local file = "corescripts/" .. name:gsub("%.", "/") .. ".lua"
	scriptCache[name] = {
		name = name,
		__func = dofile(file),
		accessLevel = 3,
		securityLevel = securityLevel,
		trust = true
	}
end

loadCoreScript("scripts.lib", 5)
loadCoreScript("accts.xfer_mu_to", 3)

local loadscript

local function loadscriptInternal(script, compile)
	if type(script) ~= "string" then
		return false, "Script name must be a string"
	end

	--[[io.write("[\"sc\"")
	for k,v in pairs(scriptCache) do
		io.write(",\"" .. k .. "\"")
	end
	io.write("]\n")]]

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
		local secLevel = data.securityLevel

		local PROTECTED_SUB_ENV = util.shallowCopy(TEMPLATE_SUB_ENV)

		PROTECTED_SUB_ENV.game = {
			loadscript = function(script, onlyInformative)
				checkTimeout()
				return loadscript({
					thisScript = script,
					callingScript = callingScript,
					isScriptor = false,
					caller = CORE_SCRIPT.caller
				}, secLevel, script, onlyInformative)
			end,
			db = dbintf(data.name),
			cache = {} -- Not protected on purpose, like #G
		}

		freeze(PROTECTED_SUB_ENV.game)
		freeze(PROTECTED_SUB_ENV)

		do
			local _ENV = {}
			local func

			--[[if data.codeBinary then
				local ok, res = pcall(load, data.codeBinary, data.name, "b", {})
				if ok then
					func = res
				end
			end]]

			if not func then
				func = load("return " .. data.code, data.name, "t", {})
				--[[data.codeBinary = strdump(func)
				scriptsDb:update({
					name = data.name
				}, {
					["$set"] = {
						codeBinary = data.codeBinary
					}
				})]]
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
		trust = data.trust,
		name = script
	}
	if runnable then
		if data.securityLevel < parentSecLevel then
			return false, "Cannot load script with lower security level than parent script"
		end
		local parentOwner = ctx.caller
		if ctx.callingScript then
			parentOwner = util.getUserFromScript(ctx.callingScript)
		end
		if data.accessLevel < 2 and parentOwner ~= getUserFromScript(data.name) then
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
