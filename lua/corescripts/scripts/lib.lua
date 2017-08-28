local loadscript = loadscript

local res = deepFreeze({
	securityLevels = {
		"NULLSEC",
		"LOWSEC",
		"MIDSEC",
		"HIGHSEC",
		"FULLSEC"
	},
	accessLevels = {
		"PRIVATE",
		"HIDDEN",
		"PUBLIC"
	},
})

return function(ctx, args)
	return res
end
