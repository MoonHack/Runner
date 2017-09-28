local json = require("dkjson")
local safePcall = require("safe_error").pcall

local function json_encodeAll_exception(reason, value, state, defaultmessage)
	if reason ~= "unsupported type" then
		return nil, defaultmessage
	end
	return json.encode({ ["$error"] = defaultmessage }, state)
end

local function json_encodeAll(obj)
	return json.encode(obj, {
		exception = json_encodeAll_exception
	})
end

local function makeSafeSingle(func)
	return function(arg)
		return safePcall(func, arg)
	end
end

return {
	encode = function(tbl)
		return json.encode(tbl)
	end,
	decode = function(str)
		return json.decode(str)
	end,
	encodeAll = json_encodeAll,
	encodeAllSafe = makeSafeSingle(json_encodeAll),
	decodeSafe = makeSafeSingle(json.decode),
	encodeSafe = makeSafeSingle(json.encode)
}
