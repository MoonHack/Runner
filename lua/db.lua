local mongo = require("mongo")
-- TODO: CONFIG VARIABLE THIS
local client = mongo.Client(require("config").mongo.main)
local time = os.time
local tinsert = table.insert

local function now()
	return mongo.DateTime(time() * 1000)
end

local function cursorToArray(cursor)
	local res = {}
	if not cursor then
		return res
	end
	while true do
		local val = cursor:next()
		if not val then
			break
		end
		tinsert(res, val:value())
	end
	return res
end

return {
	now = now,
	cursorToArray = cursorToArray,
	mongo = mongo,
	client = client,
	internal = client:getDatabase("moonhack_core"),
	user = client:getDatabase("moonhack_user")
}
