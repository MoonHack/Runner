local mongo = require("mongo")
local config = require("config").mongo
local dbCore = mongo.Client(config.core):getDefaultDatabase()
local dbUsers = mongo.Client(config.users):getDefaultDatabase()
local time = time -- time in ms from main
local tinsert = table.insert
local json_encode = require("json_patched").encode

local function patchMongo(mongo)
	mongo.Javascript = nil -- we don"t even have this enabled!

	local function make__tojson(struct, func, raw)
		local mt = debug.getmetatable(struct)
		if raw then
			mt.__tojson = func
		else
			mt.__tojson = function(self, state)
				return json_encode(func(self), state)
			end
		end
	end

	make__tojson(mongo.Binary("",0x80), function(self)
		local bin, typ = self:unpack()
		return { ["$binary"] = bin, ["$type"] = typ }
	end)

	local _oid = mongo.ObjectID()
	if _oid.unpack then
		make__tojson(_oid, function(self)
			return { ["$oid"] = self:unpack() }
		end)
	else
		make__tojson(_oid, function(self)
			return { ["$oid"] = tostring(self) }
		end)
	end

	make__tojson(mongo.DateTime(0), function(self)
		return { ["$date"] = { ["$numberLong"] = tostring(self:unpack()) } }
	end)
	make__tojson(mongo.Timestamp(0, 0), function(self)
		local t, i = self:unpack()
		return { ["$timestamp"] = { t = t, i = i } }
	end)

	make__tojson(mongo.Regex("", ""), function(self)
		local re, opt = self:unpack()
		return { ["$regex"] = re, ["$options"] = opt }
	end)

	local _double = mongo.Double(0)
	make__tojson(_double, _double.unpack)
	local _int32 = mongo.Int32(0)
	make__tojson(_int32, _int32.unpack)
	make__tojson(mongo.Int64(0), function (self)
		return { ["$numberLong"] = tostring(self:unpack()) }
	end)

	make__tojson(mongo.MinKey, function ()
		return { ["$minKey"] = 1 }
	end)
	make__tojson(mongo.MaxKey, function ()
		return { ["$maxKey"] = 1 }
	end)
	make__tojson(mongo.Null, function ()
		return nil
	end)
end

patchMongo(mongo)

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
	internal = dbCore,
	user = dbUsers,
	CODE_BINARY_TYPE = 0x01,
	CODE_TEXT_TYPE = 0x80
}
