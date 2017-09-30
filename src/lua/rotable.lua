local dgetmetatable = debug.getmetatable
local dsetmetatable = debug.setmetatable
local error = error
local type = type
local next = next
local treadonly = table.setreadonly

local function errorReadOnly()
	return error("Read-Only")
end

local function protectTblFunction(func)
	return function(tbl, ...)
		if tbl.__protected ~= nil then
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
	elseif not mt then
		mt = {}
	end
	mt.__metatable = "PROTECTED"
	dsetmetatable(tbl, mt)
	tbl = treadonly(tbl)
	return tbl
end

local function _deepFreeze(tbl, tbls)
	if isFrozen(tbl) then
		return tbl
	end
	local ret = {}
	tbls[tbl] = ret

	for k, v in next, tbl do
		if type(v) ~= "table" then
			local mt = dgetmetatable(v) or {}
			mt.__metatable = "PROTECTED"
			ret[k] = v
		elseif tbls[v] then
			ret[k] = tbls[v]
		elseif isFrozen(v) then
			ret[k] = v
		else
			ret[k] = _deepFreeze(v, tbls)
		end
	end

	return freeze(ret)
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
