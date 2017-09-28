local sleep = require("time").sleep
return function(ctx, args)
	return sleep(args.t)
end
