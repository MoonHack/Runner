local programs = require("programs")
local tinsert = table.insert
local next = next
return function(ctx, args)
	return programs.transfer(ctx.caller, args.target, args.i)
end
