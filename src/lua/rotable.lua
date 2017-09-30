local dgetmetatable = debug.getmetatable
local dsetmetatable = debug.setmetatable
local error = error
local type = type
local next = next
local pcall = pcall
local treadonly = table.setreadonly

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
	mt = treadonly(mt)
	dsetmetatable(tbl, mt)
	if type(tbl) == "table" then
		tbl = treadonly(tbl)
	end
	return tbl
end

local function _deepFreeze(tbl, tbls)
	tbls[tbl] = true
	if isFrozen(tbl) then
		return tbl
	end

	for k, v in next, tbl do
		--print(k)
		if type(v) == "table" and not tbls[v] then
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
	deepFreeze = deepFreeze
})
