local ffi = require("ffi")
local checkTimeout = require("time").checkTimeout
local db = require("db")
local notificationDb = db.internal:getCollection("notifications")

ffi.cdef[[
	void notify_user(const char *name, const char *data);
]]

local function notifyUser(from, to, msg)
	msg = {
		to = to,
		from = from,
		msg = json_encodeAll(msg),
		date = db.now()
	}
	ffi.C.notify_user(to, json_encodeAll(msg))
	notificationDb:insert(msg)
	checkTimeout()
end

return {
	notifyUser = notifyUser
}
