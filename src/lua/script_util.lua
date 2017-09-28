local load = load
local strdump = string.dump
local strfind = string.find
local error = error
local json = require("json_patched")
local writeln = require("writeln")

local function compileScript(code, name)
	local _ENV = {}
	if not strfind(code, "^function *%(") then
		error("Code must begin with \"function(\"")
	end
	if not strfind(code, "end$") then
		error("Code must end with \"end\"")
	end
	local func, err = load("local _L; return " .. code, name, "t", {})
	if not func then
		error(err)
	end
	return strdump(func), func
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
	compileScript = compileScript,
	scriptPrint = scriptPrint
}
