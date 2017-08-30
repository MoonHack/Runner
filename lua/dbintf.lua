local db = require("db")
local util = require("util")
local tinsert = table.insert

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

return function(script)
	local collection = db.user:getCollection("user_" .. util.getUserFromScript(script))

	return freeze({
		ObjectID = function(value)
			checkTimeout()
			return db.mongo.ObjectID(value)
		end,
		i = function(data)
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
		u = function(query, replace, upsert)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:updateMany(query, replace, {
				upsert = upsert
			})
			return performBulk(bulk)
		end,
		u1 = function(query, replace, upsert)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:updateOne(query, replace, {
				upsert = upsert
			})
			return performBulk(bulk)
		end,
		c = function(query)
			checkTimeout()
			return collection:count(query)
		end,
		f = function(query, options)
			checkTimeout()
			local _options = {}
			if options then
				if options.skip ~= nil then
					_options.skip = options.skip
				end
				if options.limit ~= nil then
					_options.limit = options.limit
				end
			end
			local cursor = collection:find(query, _options)
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
		end,
		f1 = function(query)
			checkTimeout()
			local res = collection:findOne(query)
			if res then
				return res:value()
			end
		end,
		fm = function(query, replace)
			checkTimeout()
			local res = collection:findAndModify(query, replace)
			if res then
				return res:value()
			end
		end,
		r = function(query)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:removeMany(query)
			return performBulk(bulk)
		end,
		r1 = function(query)
			checkTimeout()
			local bulk = collection:createBulkOperation()
			bulk:removeOne(query)
			return performBulk(bulk)
		end
	})
end
