local db = require("db")
local util = require("util")
local tinsert = table.insert
local checkTimeout = require("time").checkTimeout
local deepFreeze = require("rotable").deepFreeze
local strlen = string.len
local strmatch = string.match

local function performBulk(bulk)
	local res, err = bulk:execute()
	if res then
		res = res:value()
	end

	if not res then
		return false, { writeErrors = {err} }
	elseif res.writeErrors and #res.writeErrors > 0 then
		return false, res
	else
		return true, res
	end
end

local function makeSafeCursor(cursor)
	local _count = nil
	return {
		next = function()
			checkTimeout()
			local val = cursor:next()
			if val then
				return val:value()
			end
		end,
		array = function()
			checkTimeout()
			return db.cursorToArray(cursor)
		end,
		each = function(func)
			checkTimeout()
			local val = cursor:next()
			while val do
				func(val:value())
				val = cursor:next()
			end
		end,
		count = function()
			checkTimeout()
			if _count == nil then
				_count = collection:count(query)
			end
			return _count
		end
	}
end

return function(script, subcollection)
	local collectionName = "user." .. util.getUserFromScript(script)
	if subcollection then
		if strlen(subcollection) > 32 or strmatch(subcollection, "[^a-z_0-9]") then
			return nil
		end
		collectionName = collectionName .. "." .. subcollection
	end
	local collection = db.user:getCollection(collectionName)

	return deepFreeze({
		collectionName = collectionName,

		ObjectID = function(value)
			checkTimeout()
			return db.mongo.ObjectID(value)
		end,
		DateTime = function(value)
			checkTimeout()
			if not value then
				return db.now()
			end
			return db.mongo.DateTime(value)
		end,
		Timestamp = function(time, incr)
			return db.mongo.Timestamp(time, incr)
		end,
		Regex = function(regex, options)
			return db.mongo.Regex(regex, options)
		end,
		Double = function(value)
			return db.mongo.Double(value)
		end,
		Int32 = function(value)
			return db.mongo.Int32(value)
		end,
		Int64 = function(value)
			return db.mongo.Int64(value)
		end,
		MaxKey = function()
			return db.mongo.MaxKey
		end,
		MinKey = function()
			return db.mongo.MinKey
		end,
		Null = function()
			return db.mongo.Null
		end,
		typeOf = function(value)
			return db.mongo.type(value)
		end,

		insert = function(data)
			checkTimeout()
			local res, err
			local bulk = collection:createBulkOperation()
			if #data > 0 then
				for _, v in next, data do
					bulk:insert(v)
				end
			else
				bulk:insert(data)
			end
			return performBulk(bulk)
		end,
		updateMany = function(query, replace, upsert)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:updateMany(query, replace, {
				upsert = upsert
			})
			return performBulk(bulk)
		end,
		updateOne = function(query, replace, upsert)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:updateOne(query, replace, {
				upsert = upsert
			})
			return performBulk(bulk)
		end,
		count = function(query)
			checkTimeout()
			return collection:count(query)
		end,
		find = function(query, options)
			checkTimeout()
			local _options = {}
			if options then
				if options.skip ~= nil then
					_options.skip = options.skip
				end
				if options.limit ~= nil then
					_options.limit = options.limit
				end
				if options.sort ~= nil then
					_options.sort = options.sort
				end
			end
			local cursor = collection:find(query, _options)
			if not cursor then
				return nil, "Query error"
			end
			return makeSafeCursor(cursor)
		end,
		findOne = function(query)
			checkTimeout()
			local res = collection:findOne(query)
			if res then
				return res:value()
			end
		end,
		findAndModify = function(query, replace)
			checkTimeout()
			local res = collection:findAndModify(query, replace)
			if res then
				return res:value()
			end
		end,
		removeMany = function(query)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:removeMany(query)
			return performBulk(bulk)
		end,
		removeOne = function(query)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:removeOne(query)
			return performBulk(bulk)
		end
	})
end
