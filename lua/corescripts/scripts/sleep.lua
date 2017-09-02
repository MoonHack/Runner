local sleep = sleep
return function(ctx, args)
	notifyUser(ctx.caller, "meow")
	sleep(tonumber(args.time))
end
