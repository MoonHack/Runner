local programs = require("programs")
local tinsert = table.insert
local next = next
return function(ctx, args)
	return programs.load(ctx.caller, args.i, false)
end
