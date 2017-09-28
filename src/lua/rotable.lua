local dgetmetatable = debug.getmetatable
local dsetmetatable = debug.setmetatable
local error = error
local type = type
local next = next

local function errorReadOnly()
	error("Read-Only")
end

local function protectTblFunction(func)
	return function(tbl, ...)
		if tbl.__protected then
			return errorReadOnly()
		end
		return func(tbl, ...)
	end
end

local function isFrozen(tbl, mt)
	mt = mt or dgetmetatable(tbl)
	return mt and (mt == "PROTECTED" or mt.__metatable == "PROTECTED")
end

local function freeze(tbl)
	local mt = dgetmetatable(tbl)

	if mt then
		if isFrozen(tbl, mt) then
			return tbl
		end
	else
		mt = {}
	end

	if type(tbl) == "table" and not tbl.__protected then
		tbl.__protected = true
	end

	mt.__metatable = "PROTECTED"
	mt.__newindex = errorReadOnly
	dsetmetatable(tbl, mt)

	return tbl
end

local function _deepFreeze(tbl, tbls)
	if isFrozen(tbl) then
		return tbl
	end

	for k, v in next, tbl do
		if type(v) ~= "table" then
			freeze(v)
		elseif not tbls[v] then
			tbls[v] = true
			_deepFreeze(v, tbls)
		end
	end

	return freeze(tbl)
end

local function deepFreeze(tbl)
	if type(tbl) ~= "table" then
		return freeze(tbl)
	end
	return _deepFreeze(tbl, {})
end

return deepFreeze({
	freeze = freeze,
	deepFreeze = deepFreeze,
	protectTblFunction = protectTblFunction,
	errorReadOnly = errorReadOnly
})
