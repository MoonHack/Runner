local money = require("money")
return function(ctx, args)
	return money.balance(ctx.caller)
end
