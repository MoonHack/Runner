local programs = require("programs")
return function(ctx, args)
	return programs.transfer(ctx.caller, args.target, args.i)
end
