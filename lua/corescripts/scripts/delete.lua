local db = require("db")
local scriptsDb = db.internal:getCollection("scripts")

return function(ctx, args)
	local name = ctx.caller .. "." .. tostring(args.name)
	scriptsDb:removeOne({
		_id = name,
		locked = { ['$exists'] = false }
	})
	return true, 'Script removed'
end
