local db = require("db")
local scriptsDb = db.internal:getCollection("scripts")

return function(ctx, args)
	local securityLevel = tonumber(args.securityLevel or 0)
	local accessLevel = tonumber(args.accessLevel or 0)
	local source = tostring(args.source)
	local name = ctx.caller .. "." .. tostring(args.name)

	local ok, compiled = pcall(util.compileScript, source, name)
	if not ok then
		return false, 'Compile error\n' .. compiled
	end

	local now = db.now()

	local set = {
		code = source,
		codeDate = now,
		codeBinary = compiled,
		codeBinaryDate = now
	}

	if securityLevel > 0 and securityLevel <= 5 then
		set.securityLevel = securityLevel
	end

	if accessLevel > 0 and accessLevel <= 3 then
		set.accessLevel = accessLevel
	end

	local res = scriptsDb:findAndModify({
		_id = name,
		locked = { ['$exists'] = false }
	}, {
		['$set'] = set
	})
	if not res then
		set.securityLevel = set.securityLevel or 5
		set.accessLevel = set.accessLevel or 1
		set._id = name
		set.owner = ctx.caller
		scriptsDb:insert(set)
	end
	return true, 'Script uploaded'
end
