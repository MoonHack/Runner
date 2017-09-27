local money = require("money")
return function(ctx, args)
	return money.logs(ctx.caller, args and args.skip, args and args.limit)
end
