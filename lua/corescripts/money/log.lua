local money = require("money")
return function(ctx, args)
	return money.log(ctx.caller, args and args.skip, args and args.limit)
end
