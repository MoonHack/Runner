local strmatch = string.match
local next = next
local type = type
local sgsub = string.gsub

local escapes = require("rotable").deepFreeze({
	["<"] = "È",
	[">"] = "É",
})

local function escape(str)
	for k, v in next, escapes do
		str = sgsub(str, k, v)
	end
	return str
end

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

local function _deepCopy(tbl, tbls)
	local ret = {}
	tbls[tbl] = ret
	for k, v in next, tbl do
		if type(v) ~= "table" then
			ret[k] = v
		elseif tbls[v] then
			ret[k] = tbls[v]
		else
			tbls[v] = {
				["$recursive"] = true
			}
			local _t = _deepCopy(v, tbls)
			tbls[v] = _t
			ret[k] = _t
		end
	end
	return ret
end

local function deepCopy(tbl)
	return _deepCopy(tbl, {})
end

local function getUserFromScript(script)
	return strmatch(script, "^(.+)%.")
end

return {
	shallowCopy = shallowCopy,
	deepCopy = deepCopy,
	getUserFromScript = getUserFromScript,
	compileScript = compileScript,
	flagSet = flagSet,
	scriptPrint = scriptPrint,
	escape = escape,
	escapes = escapes
}
