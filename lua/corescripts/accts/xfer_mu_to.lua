local money = require("money")
return function(ctx, args)
	return money.transfer(ctx.caller, args.target, args.amount)
end
