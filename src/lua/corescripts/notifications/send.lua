local notifyUser = notifyUser
return function (ctx, args)
	local source
	if ctx.callingScript then
		source = ctx.callingScript
	else
		source = ctx.caller
	end
	return notifyUser(args.target, source, msg)
end
