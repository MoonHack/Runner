local programs = require("programs")
local next = next
return function(ctx, args)
	local ok, list, info = programs.list(ctx.caller)
	if not ok then
		return false, list
	end
	local res = {}
	for k, v in next, list do
		local u = info[v.id]
		u.loaded = v.loaded
		res[k] = u
	end
	return true, res
end
