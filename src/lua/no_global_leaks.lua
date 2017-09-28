local next = next
local print = print
local roTable = require("rotable")
local util = require("util")

local function snapshotGTable(gTable)
	return util.deepCopy(gTable)
end

local function _fixLeaks(gSnapshot, gTable, tbls, path)
	tbls[gTable] = true
	local hasGlobalLeaks = false
	for k, v in next, gTable do
		if not gSnapshot[k] then
			--print("FIX GLOBAL LEAK", path..k)
			gTable[k] = nil
			hasGlobalLeaks = true
		elseif type(v) == "table" and not tbls[v] then
			if _fixLeaks(gSnapshot[k], v, tbls, path .. k .. ".") then
				hasGlobalLeaks = true
			end
		end
	end
	return hasGlobalLeaks
end

local function fixLeaks(gSnapshot, gTable)
	return _fixLeaks(gSnapshot, gTable, {}, "_G.")
end

return roTable.deepFreeze({
	snapshotGTable = snapshotGTable,
	fixLeaks = fixLeaks
})
