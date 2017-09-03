local programs = require("programs")
local tinsert = table.insert
local next = next
return function(ctx, args)
	return programs.delete(ctx.caller, args.i)
end
