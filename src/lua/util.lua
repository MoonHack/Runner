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

local function deepCopy(tbl)
	local tbls = {}
	local ret = {}
	for k, v in next, tbl do
		if v == tbl then
			ret[k] = ret
		elseif type(v) ~= "table" then
			ret[k] = v
		elseif tbls[v] then
			ret[k] = tbls[v]
		else
			tbls[v] = {
				__recursive = true
			}
			local _t = deepCopy(v)
			tbls[v] = _t
			ret[k] = _t
		end
	end
end

local function getUserFromScript(script)
	return string.match(script, "^(.+)%.")
end

local function compileScript(code, name)
	local _ENV = {}
	if not code:find("^function *(") then
		error('Code must begin with "function("')
	end
	if not code:find("end$") then
		error('Code must end with "end"')
	end
	func = load("return " .. code, name, "t", {})
	return strdump(func), func
end

return {
	shallowCopy = shallowCopy,
	getUserFromScript = getUserFromScript,
	compileScript = compileScript
}
