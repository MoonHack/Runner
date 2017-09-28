local db = require("db")
local scriptsDb = db.internal:getCollection("scripts")
local scriptUtil = require("script_util")

local CODE_BINARY_TYPE = db.CODE_BINARY_TYPE
local CODE_TEXT_TYPE = db.CODE_TEXT_TYPE

return function(ctx, args)
	local securityLevel = tonumber(args.securityLevel or 0)
	local accessLevel = tonumber(args.accessLevel or 0)
	local source = tostring(args.source)
	local name = tostring(args.name)

	if name:match("[^a-z0-9_]") or name:len() > 32 then
		return false, "Invalid script name"
	end

	name = ctx.caller .. "." .. name

	local ok, compiled = pcall(scriptUtil.compileScript, source, name)
	if not ok then
		return false, "Compile error\n" .. compiled
	end

	local now = db.now()

	local set = {
		code = db.mongo.Binary(source, CODE_TEXT_TYPE),
		codeDate = now,
		codeBinary = db.mongo.Binary(compiled, CODE_BINARY_TYPE),
		codeBinaryDate = now
	}

	if accessLevel > 0 and accessLevel <= 3 then
		set.accessLevel = accessLevel
	end

	local res = scriptsDb:findAndModify({
		name = name,
		locked = { ["$exists"] = false }
	}, {
		fields = {
			name = 1
		},
		update = {
			["$set"] = set
		}
	})
	if not res then
		set.accessLevel = set.accessLevel or 1
		set.name = name
		set.owner = ctx.caller
		scriptsDb:insert(set)
	end
	return true, "Script uploaded"
end
