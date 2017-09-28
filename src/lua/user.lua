local db = require("db")
local userDb = db.internal:getCollection("users")

local function getByName(name, projection)
	if projection then
		projection = { projection = projection }
	end
	local user = userDb:findOne({ name = name }, projection)
	if user then
		return user:value()
	end
end

local function exists(name)
	local user = getByName(name, {
		_id = 1
	})
	if user then
		return true
	end
	return false
end

return {
	getByName = getByName,
	exists = exists
}
