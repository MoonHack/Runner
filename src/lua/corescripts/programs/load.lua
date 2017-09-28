local programs = require("programs")
return function(ctx, args)
	return programs.load(ctx.caller, args.i, true)
end
