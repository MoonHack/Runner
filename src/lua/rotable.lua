local getmetatable = debug.getmetatable
local setmetatable = debug.setmetatable
local error = error
local type = type

local function errorReadOnly()
	error("Read-Only")
end

local function protectTblFunction(func)
	return function(tbl, ...)
		if tbl.__protected then
			_errorReadOnly()
		end
		return func(tbl, ...)
	end
end

local function freeze(tbl)
	local mt = getmetatable(tbl)
	if mt then
		if mt.__metatable == "PROTECTED" then
			return tbl
		end
	else
		mt = {}
	end

	if type(tbl) == "table" then
		tbl.__protected = true
	end

	mt.__metatable = "PROTECTED"
	mt.__newindex = errorReadOnly

	setmetatable(tbl, mt)
	return tbl
end

local function deepFreeze(tbl)
	local ret = {}

	for k, v in next, tbl do
		if v == tbl then
			ret[k] = ret
		elseif type(v) ~= "table" then
			ret[k] = freeze(v)
		else
			ret[k] = deepFreeze(v, true)
		end
	end

	return freeze(ret)
end

return deepFreeze({
	freeze = freeze,
	deepFreeze = deepFreeze,
	protectTblFunction = protectTblFunction,
	errorReadOnly = errorReadOnly
})
