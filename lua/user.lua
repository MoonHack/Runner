local db = require("db")
local userDb = db.internal:getCollection("users")

local function getByName(name, projection)
	if projection then
		projection = { projection = projection }
	end
	local user = userDb:findOne({ _id = name }, projection)
	if user then
		return user:value()
	end
end

return {
	getByName = getByName
}
