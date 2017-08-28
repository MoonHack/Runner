local function shallowCopy(tbl)
	local ret = {}
	for k, v in next, tbl do
		if v == tbl then
			ret[k] = ret
		else
			ret[k] = v
		end
	end
	return ret
end

local function getUserFromScript(script)
	return string.match(script, "^(.+)%.")
end

return {
	shallowCopy = shallowCopy,
	getUserFromScript = getUserFromScript
}
