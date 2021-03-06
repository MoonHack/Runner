local db = require("db")
local scriptsDb = db.internal:getCollection("scripts")
local tostring = tostring

return function(ctx, args)
	local name = ctx.caller .. "." .. tostring(args.name)
	scriptsDb:removeOne({
		name = name,
		locked = { ["$exists"] = false }
	})
	return true, "Script removed"
end
