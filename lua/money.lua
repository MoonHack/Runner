local db = require("db")
local userDb = db.internal:getCollection("users")
local timeLeft = timeLeft
local timeoutProtection = timeoutProtection
local checkTimeout = checkTimeout

local function give(user, amount)
	checkTimeout()
	local res = userDb:findAndModify({ name = user }, { update = { ['$inc'] = { balance = amount } } })
	if not res then
		return false, 'Target cannot store that much MU'
	end
	return true
end

local function take(user, amount)
	checkTimeout()
	local res = userDb:findAndModify({ name = user, balance = { ['$gte'] = amount } }, { update = { ['$inc'] = { balance = -amount } } })
	if not res then
		return false, 'Source does not have enough MU'
	end
	return true
end

local function transfer(from, to, amount)
	if timeLeft() < 1 then
		checkTimeout()
		return false, 'MU transfers require 1 second of runtime'
	end
	timeoutProtection(true)
	local ok, tr = take(from, amount)
	if not ok then
		timeoutProtection(false)
		return false, tr
	end
	ok, tr = give(to, amount)
	if not ok then
		give(from, amount)
		timeoutProtection(false)
		return false, tr
	end
	timeoutProtection(false)
	return true
end

return {
	give = give,
	take = take,
	transfer = transfer
}
