local db = require("db")
local user = require("user")
local roTable = require("rotable")
local userDb = db.internal:getCollection("users")
local logDb = db.internal:getCollection("money_log")
local timeUtil = require("time")
local timeLeft = timeUtil.timeLeft
local checkTimeout = timeUtil.checkTimeout
local tinsert = table.insert
local makeProtectedFunc = require("protected_mode").makeProtectedFunc

local function logs(user, skip, limit)
	if not limit or limit > 50 then
		limit = 50
	end
	if not skip or skip < 0 then
		skip = 0
	end
	return true, db.cursorToArray(logDb:find({ ["$or"] = {{ from = user }, { to = user }} }, { sort = { date = -1 }, skip = skip, limit = limit }))
end

local function balance(user)
	user = tostring(user)
	local res = userDb:findOne({ name = user })
	if not res then
		return false, "User not found"
	end
	return true, res:value().balance or 0
end

local function give(user, amount)
	user = tostring(user)
	amount = tonumber(amount)
	local res = userDb:findAndModify({ name = user }, { fields = { balance = 1 }, update = { ["$inc"] = { balance = amount } } })
	if not res then
		return false, "Target cannot store that much MU"
	end
	return true
end

local function take(user, amount)
	user = tostring(user)
	amount = tonumber(amount)
	local res = userDb:findAndModify({ name = user, balance = { ["$gte"] = amount } }, { fields = { balance = 1 }, update = { ["$inc"] = { balance = -amount } } })
	if not res then
		return false, "Source does not have enough MU"
	end
	return true
end

local function transfer(from, to, amount)
	from = tostring(from)
	to = tostring(to)
	amount = tonumber(amount)
	if not from or not to or not amount then
		return false, "Missing parameters"
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
	logDb:insert({ action = "transfer", from = from, to = to, amount = amount, date = db.now() })
	return true
end

return roTable.deepFreeze({
	give = give,
	take = take,
	logs = logs,
	transfer = makeProtectedFunc(transfer),
	balance = balance
})
