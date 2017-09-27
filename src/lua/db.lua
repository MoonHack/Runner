local mongo = require("mongo")
local config = require("config").mongo
local clientCore = mongo.Client(config.core)
local clientUsers = mongo.Client(config.users)
local time = os.time
local tinsert = table.insert
local dgetmetatable = debug.getmetatable
local dsetmetatable = debug.setmetatable
local json_quote = require("dkjson").quotestring

local function simple_tostr__tojson(pref, suff)
	suff = suff or '"}'
	return function(self)
		return pref .. tostring(self) .. suff
	end
end
local function simple_unpack__tojson(pref, suff)
	suff = suff or '"}'
	return function(self)
		return pref .. self:unpack() .. suff
	end
end
local function make__tojson(struct, func)
	local mt = dgetmetatable(struct)
	mt.__tojson = func
	table.foreach(mt, print)
	dsetmetatable(struct, mt)
end
local function make_simple_tostr__tojson(struct, pref, suff)
	make__tojson(struct, simple_tostr__tojson(pref, suff))
end
local function make_simple_unpack__tojson(struct, pref, suff)
	make__tojson(struct, simple_unpack__tojson(pref, suff))
end

make_simple_tostr__tojson(mongo.ObjectId, '{"$oid":"')
make_simple_unpack__tojson(mongo.DateTime, '{"$date":{"$numberLong": ', '"}}')
make__tojson(mongo.Timestamp, function(self)
	local t, i = self:unpack()
	return '{"$timestamp":{"t":'..t..',"i":'..i..'}}'
end)
make__tojson(mongo.Regex, function(self)
	local re, opt = self:unpack()
	return '{"$regex":'..json_quote(re)..',"$options":'..json_quote(opt)..'}'
end)

local function now()
	return time() * 1000
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
