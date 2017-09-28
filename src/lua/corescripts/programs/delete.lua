local programs = require("programs")
return function(ctx, args)
	return programs.delete(ctx.caller, args.i)
end
