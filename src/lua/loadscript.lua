local db = require("db")
local dbintf = require("dbintf")
local util = require("util")
local scriptUtil = require("script_util")
local setfenv = setfenv
local load = load
local next = next
local type = type
local pcall = pcall
local timeUtil = require("time")
local checkTimeout = timeUtil.checkTimeout
local tinsert = table.insert
local json = require("json_patched")
local roTable = require("rotable")
local TEMPLATE_SUB_ENV = require("subenv")
local bitand = require("bit").band

local CODE_BINARY_TYPE = db.CODE_BINARY_TYPE
local CODE_TEXT_TYPE = db.CODE_TEXT_TYPE

local scriptsDb = db.internal:getCollection("scripts")

local scriptCache = {}
_G.coreScripts = {}

local function flagSet(flags, flag)
	return bitand(flags, flag) == flag
end

local LOAD_AS_OWNER = 1
local LOAD_ONLY_INFORMATION = 2

local function loadCoreScript(name, accessLevel)
	accessLevel = accessLevel or 3

	local file = "corescripts/" .. name:gsub("%.", "/")

	scriptCache[name] = {
		name = name,
		__func = require(file),
		accessLevel = accessLevel,
		hookable = true,
		system = true
	}

	if accessLevel == 3 then
		tinsert(coreScripts, {
			name = name,
			accessLevel = accessLevel,
			hookable = true,
			system = true
		})
	end
end

loadCoreScript("notifications.send")
loadCoreScript("notifications.recent")

loadCoreScript("scripts.upload")
loadCoreScript("scripts.delete")
loadCoreScript("scripts.list")
loadCoreScript("scripts.sleep")

loadCoreScript("money.balance")
loadCoreScript("money.log")
loadCoreScript("money.transfer")

loadCoreScript("programs.delete")
loadCoreScript("programs.list")
loadCoreScript("programs.load")
loadCoreScript("programs.log")
loadCoreScript("programs.reorder")
loadCoreScript("programs.transfer")
loadCoreScript("programs.unload")

roTable.deepFreeze(_G.coreScripts)

_G.coreScripts = nil

local loadScript

local function loadScriptInternal(ctx, script, compile)
	if type(script) ~= "string" then
		return false, "Script name must be a string"
	end
	script = script:lower()

	local data = scriptCache[script]
	if not data then
		data = scriptsDb:findOne({
			name = script
		})
		if not data then
			return false, "Script not found"
		end
		data = data:value()
		script = data.name
		scriptCache[script] = data
	end

	if compile and not data.__func then
		local callingScriptOwner = data.owner
		local callingScriptCaller = ctx.caller
		local isRoot = (not ctx.callingScript)

		local PROTECTED_SUB_ENV = util.shallowCopy(TEMPLATE_SUB_ENV)

		PROTECTED_SUB_ENV.constants = util.deepCopy(TEMPLATE_SUB_ENV.constants)
		PROTECTED_SUB_ENV.constants.START_TIME, PROTECTED_SUB_ENV.constants.KILL_TIME = timeUtil.getTimes()

		PROTECTED_SUB_ENV._G = PROTECTED_SUB_ENV

		PROTECTED_SUB_ENV.print = scriptUtil.scriptPrint(script, isRoot)
		PROTECTED_SUB_ENV.loadstring = function(str)
			return load(str, script .. "->load", "t", PROTECTED_SUB_ENV)
		end
		if setfenv then
			setfenv(PROTECTED_SUB_ENV.loadstring, PROTECTED_SUB_ENV)
		end
		PROTECTED_SUB_ENV.load = PROTECTED_SUB_ENV.loadstring

		local function loadScriptGame(scriptName, flags)
			flags = flags or 0
			local asOwner = flagSet(flags, LOAD_AS_OWNER)
			checkTimeout()
			flags = flags or 0
			return loadScript({
				callingScript = script,
				cli = false,
				caller = asOwner and callingScriptOwner or callingScriptCaller
			}, callingScriptOwner, scriptName, flagSet(flags, LOAD_ONLY_INFORMATION))
		end

		PROTECTED_SUB_ENV.game = {
			script = {
				LOAD_AS_OWNER = LOAD_AS_OWNER,
				LOAD_ONLY_INFORMATION = LOAD_ONLY_INFORMATION,
				load = loadScriptGame,
				info = function(script)
					return loadScriptGame(script, LOAD_ONLY_INFORMATION)
				end,
				hook = function(script, cb)
					if not isRoot then
						return false, "Only root script can hook"
					end
					local script = loadScriptGame(script)
					if not script or not script.hookable then
						return false, "Script not hookable"
					end
					script.__origFunc = script.__origFunc or script.__func
					script.__func = function(ctx, args)
						local _r, _e = cb(util.deepCopy(ctx), util.deepCopy(args))
						if _r == false then
							return _r, _e
						end
						return script.__origFunc(ctx, args)
					end
					return true
				end,
			},
			db = dbintf(script),
			customDb = function(name)
				return dbintf(script, name)
			end
		}

		PROTECTED_SUB_ENV = roTable.deepFreeze(PROTECTED_SUB_ENV)

		do
			local _ENV = {}
			local func

			if data.codeBinary and data.codeDate == data.codeBinaryDate then
				local codeBinary, cbType = data.codeBinary:unpack()
				if cbType == CODE_BINARY_TYPE then
					local ok, res = pcall(load, codeBinary, script, "b", {})
					if ok then
						func = res
					end
				end
			end

			if not func then
				local ok
				local code, cType = data.code
				if type(code) ~= "string" then
					code = code:unpack()
					if cType ~= CODE_TEXT_TYPE then
						return false, "Invalid binary data for source"
					end
				end
				local codeBinary
				ok, codeBinary, func = pcall(scriptUtil.compileScript, code, script)
				if not ok then
					return false, "Compile error in " .. script
				end
				data.codeBinary = db.mongo.Binary(codeBinary, CODE_BINARY_TYPE)
				scriptsDb:update({
					name = script
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

loadScript = function(ctx, parentOwner, script, onlyInformative)
	local runnable = ctx and not onlyInformative
	local ok, data = loadScriptInternal(ctx, script, runnable)
	if not ok then
		return false, data
	end
	local info = {
		accessLevel = data.accessLevel,
		system = data.system or false,
		hookable = data.hookable or false,
		name = data.name,
		owner = data.owner
	}
	if runnable then
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

return loadScript
