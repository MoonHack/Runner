local dgetmetatable = debug.getmetatable
local dsetmetatable = debug.setmetatable
local error = error
local type = type
local next = next
local pcall = pcall
local treadonly = table.setreadonly
local tisreadonly = table.isreadonly

local function freeze(tbl)
	if tisreadonly(tbl) then
		return tbl
	end
	local mt = dgetmetatable(tbl)
	if not mt then
		mt = {}
	end
	if not tisreadonly(mt) then
		mt.__metatable = "PROTECTED"
		mt = treadonly(mt)
	end
	dsetmetatable(tbl, mt)
	if type(tbl) == "table" then
		tbl = treadonly(tbl)
	end
	return tbl
end

local function _deepFreeze(tbl, exclude, tbls)
	tbls[tbl] = true
	if tisreadonly(tbl) then
		return tbl
	end

	for k, v in next, tbl do
		if type(v) == "table" and not tbls[v] then
			_deepFreeze(v, exclude, tbls)
		end
	end

	if tbl == exclude then
		return tbl
	end
	return freeze(tbl)
end

local function deepFreeze(tbl, exclude)
	if type(tbl) ~= "table" then
		return freeze(tbl)
	end

	return _deepFreeze(tbl, exclude and tbl or nil, {})
end

return deepFreeze({
	freeze = freeze,
	deepFreeze = deepFreeze
})
