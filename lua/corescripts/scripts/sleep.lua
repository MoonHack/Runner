local sleep = sleep
return function(ctx, args)
	sleep(tonumber(args.time))
end
