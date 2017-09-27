local programs = require("programs")
return function(ctx, args)
	return programs.logs(ctx.caller, args and args.skip, args and args.limit)
end
