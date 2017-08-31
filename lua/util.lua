local load = load
local strdump = string.dump

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

local function compileScript(code, name)
	local _ENV = {}
	func = load("return " .. code, name, "t", {})
	return strdump(func), func
end

return {
	shallowCopy = shallowCopy,
	getUserFromScript = getUserFromScript,
	compileScript = compileScript
}
