local mongo = require("mongo")
local config = require("config").mongo
local clientCore = mongo.Client(config.core)
local clientUsers = mongo.Client(config.users)
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
	internal = clientCore:getDatabase("moonhack_core"),
	user = clientUsers:getDatabase("moonhack_user")
}
