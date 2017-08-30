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

local function getIdByName(name)
	local uid = getByName(name, { _id = 1 })
	if uid then
		return uid._id
	end
end

return {
	getByName = getByName,
	getIdByName = getIdByName
}
