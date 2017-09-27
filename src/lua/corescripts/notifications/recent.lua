local db = require("db")
local notificationDb = db.internal:getCollection("notifications")

return function (ctx, args)
	args = args or {}
	local limit = tonumber(args.limit or 0)
	local skip = tonumber(args.skip or 0)
	if not limit or limit > 50 or limit < 1 then
		limit = 50
	end
	if not skip or skip < 0 then
		skip = 0
	end
	return true, db.cursorToArray(notificationDb:find({
		to = ctx.caller
	}, {
		sort = { date = -1 },
		skip = skip,
		limit = limit
	}))
end
