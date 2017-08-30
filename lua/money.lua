local db = require("db")
local user = require("user")
local userDb = db.internal:getCollection("users")
local logDb = db.internal:getCollection("money_log")
local timeLeft = timeLeft
local checkTimeout = checkTimeout
local tinsert = table.insert

local function logs(user, skip, limit)
	if not limit or limit > 50 then
		limit = 50
	end
	if not skip or skip < 0 then
		skip = 0
	end
	local uid = user.getIdByName(user)
	if not uid then
		return
	end
	return db.cursorToArray(logDb:find({ ['$or'] = {{ from = uid }, { to = uid }} }, { sort = { date = -1 }, skip = skip, limit = limit }))
end

local function balance(user)
	user = tostring(user)
	checkTimeout()
	local res = userDb:findOne({ name = user })
	if not res then
		return false, 'User not found'
	end
	return res:value().balance
end

local function give(user, amount)
	user = tostring(user)
	amount = tonumber(amount)
	checkTimeout()
	local res = userDb:findAndModify({ name = user }, { fields = { balance = 1 }, update = { ['$inc'] = { balance = amount } } })
	if not res then
		return false, 'Target cannot store that much MU'
	end
	return true
end

local function take(user, amount)
	user = tostring(user)
	amount = tonumber(amount)
	checkTimeout()
	local res = userDb:findAndModify({ name = user, balance = { ['$gte'] = amount } }, { fields = { balance = 1 }, update = { ['$inc'] = { balance = -amount } } })
	if not res then
		return false, 'Source does not have enough MU'
	end
	return true
end

local function transfer(from, to, amount)
	from = tostring(from)
	to = tostring(to)
	amount = tonumber(amount)
	if timeLeft() < 1 then
		checkTimeout()
		return false, 'MU transfers require 1 second of runtime'
	end
	local ok, tr = take(from, amount)
	if not ok then
		return false, tr
	end
	ok, tr = give(to, amount)
	if not ok then
		give(from, amount)
		return false, tr
	end
	local uidFrom = user.getIdByName(from)
	local uidTo = user.getIdByName(to)
	logDb:insert({ action = "transfer", from = uidFrom, to = uidTo, amount = amount, date = db.now() })
	return true, 'Transferred ' .. amount .. ' MU from ' .. from .. ' to ' .. to
end

return {
	give = give,
	take = take,
	transfer = makeProtectedFunc(transfer),
	balance = balance
}
