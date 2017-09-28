local config = require("config").mongo
local time = require("time").time
local tinsert = table.insert
local json_encode = require("json_patched").encode
local mongo = require("mongo")
local dbCore = mongo.Client(config.core):getDefaultDatabase()
local dbUsers = mongo.Client(config.users):getDefaultDatabase()

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
		return mt
	end

	local function __equalst(self, other)
		return mongo.type(self) == mongo.type(other)
	end

	local function __equals1(self, other)
		if not __equalst(self, other) then
			return false
		end
		return other and self:unpack() == other:unpack()
	end

	local function __equals2(self, other)
		if not __equalst(self, other) then
			return false
		end
		local a, b = self:unpack()
		local x, y = other:unpack()
		return other and a == x and b == y
	end

	local function __lt1(self, other)
		if not __equalst(self, other) then
			return false
		end
		return self:unpack() < other:unpack()
	end

	local function __le1(self, other)
		if not __equalst(self, other) then
			return false
		end
		return self:unpack() <= other:unpack()
	end

	local mt

	mt = make__tojson(mongo.Binary("", 0x80), function(self)
		local bin, typ = self:unpack()
		return { ["$binary"] = bin, ["$type"] = typ }
	end)
	mt.__eq = __equals2

	local _oid = mongo.ObjectID()
	if _oid.unpack then
		mt = make__tojson(_oid, function(self)
			return { ["$oid"] = self:unpack() }
		end)
		mt.__eq = __equals1
	else
		mt = make__tojson(_oid, function(self)
			return { ["$oid"] = tostring(self) }
		end)
		mt.__eq = function(self, other)
			if not __equalst(self, other) then
				return false
			end
			return tostring(self) == tostring(other)
		end
	end

	mt = make__tojson(mongo.DateTime(0), function(self)
		return { ["$date"] = { ["$numberLong"] = tostring(self:unpack()) } }
	end)
	mt.__eq = __equals1
	mt.__lt = __lt1
	mt.__le = __le1

	mt = make__tojson(mongo.Timestamp(0, 0), function(self)
		local t, i = self:unpack()
		return { ["$timestamp"] = { t = t, i = i } }
	end)
	mt.__eq = __equals2

	mt = make__tojson(mongo.Regex("", ""), function(self)
		local re, opt = self:unpack()
		return { ["$regex"] = re, ["$options"] = opt }
	end)
	mt.__eq = __equals2

	local _double = mongo.Double(0)
	mt = make__tojson(_double, _double.unpack)
	mt.__eq = __equals1
	mt.__lt = __lt1
	mt.__le = __le1
	
	local _int32 = mongo.Int32(0)
	mt = make__tojson(_int32, _int32.unpack)
	mt.__eq = __equals1
	mt.__lt = __lt1
	mt.__le = __le1

	mt = make__tojson(mongo.Int64(0), function (self)
		return { ["$numberLong"] = tostring(self:unpack()) }
	end)
	mt.__eq = __equals1
	mt.__lt = __lt1
	mt.__le = __le1

	mt = make__tojson(mongo.MinKey, function ()
		return { ["$minKey"] = 1 }
	end)
	mt.__eq = __equalst

	mt = make__tojson(mongo.MaxKey, function ()
		return { ["$maxKey"] = 1 }
	end)
	mt.__eq = __equalst

	mt = make__tojson(mongo.Null, function ()
		return nil
	end)
	mt.__eq = __equalst
end

patchMongo(mongo)

local function now()
	return mongo.DateTime(time())
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
