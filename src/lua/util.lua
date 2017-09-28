local load = load
local strdump = string.dump
local strmatch = string.match
local strfind = string.find
local error = error
local next = next
local type = type
local load = load
local bit = require("bit")
local json = require("json_patched")
local writeln = require("writeln")

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
				["$recursive"] = true
			}
			local _t = deepCopy(v)
			tbls[v] = _t
			ret[k] = _t
		end
	end
	return ret
end

local function getUserFromScript(script)
	return strmatch(script, "^(.+)%.")
end

local function compileScript(code, name)
	local _ENV = {}
	if not strfind(code, "^function *%(") then
		error("Code must begin with \"function(\"")
	end
	if not strfind(code, "end$") then
		error("Code must end with \"end\"")
	end
	local func, err = load("return " .. code, name, "t", {})
	if not func then
		error(err)
	end
	return strdump(func), func
end

local function flagSet(flags, flag)
	return bit.band(flags, flag) == flag
end

local function scriptPrint(script, initial)
	return function(...)
		local data = {...}
		if #data == 1 then
			data = data[1]
		end
		writeln(json.encodeAll({
			type = "print",
			initial = initial or false,
			script = script,
			data = data
		}))
	end
end

return {
	shallowCopy = shallowCopy,
	deepCopy = deepCopy,
	getUserFromScript = getUserFromScript,
	compileScript = compileScript,
	flagSet = flagSet,
	scriptPrint = scriptPrint
}
