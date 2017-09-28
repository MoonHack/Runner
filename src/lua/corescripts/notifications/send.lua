local notifyUser = require("notifications").notifyUser
return function (ctx, args)
	local source
	if ctx.callingScript then
		source = ctx.callingScript
	else
		source = ctx.caller
	end
	return notifyUser(args.target, source, args.msg)
end
