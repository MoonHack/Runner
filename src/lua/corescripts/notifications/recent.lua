local db = require("db")
local notificationDb = db.internal:getCollection("notifications")

return function (ctx, args)
	if not limit or limit > 50 then
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
