-- db.upgrades store owner, can be updated atomically by serial
-- db.user stores array of serials that gets auto-fixed on every op

-- FIRST we find upgrades affected, LAST we insert the log
-- changes by position get serials from user, then push atomic updates by serial (race condition, so script access by serial preferred!)
-- changes by serial just update atomically

local db = require("db")
local user = require("user")
local userDb = db.internal:getCollection("users")
local programsDb = db.internal:getCollection("programs")
local logDb = db.internal:getCollection("program_log")
local timeLeft = timeLeft
local checkTimeout = checkTimeout
local tinsert = table.insert
local next = next

function fixUser(name, list)
	local toFix = user:getByName(name, { _id = 1, programs = 1 })
	if not user then
		return false, 'User not found'
	end

	local options = {}
	if not list then
		options = { projection = { _id = 1 } }
	end
	local programsAuth = db.cursorToArray(programsDb:find(query, options))
	local programsStored = user.programs

	local dirty = #programsAuth ~= #programsStored

	local programsShould = {}
	for _,v in next, programsAuth do
		programsShould[v] = true
	end

	local programsStore = {}
	for _,v in next, programsStored do
		if programsShould[v] then
			programsShould[v] = nil
			tinsert(programsStore, v)
		end
	end

	for k,v in next, programsShould do
		if v then
			dirty = true
			tinsert(programsStore, k)
		end
	end

	if dirty then
		userDb:updateOne({ _id = user._id }, { ['$set'] = { programs = programs }})
	end

	return programsStore, programsAuth
end

function transfer(from, to, _serials)
	from = tostring(from)
	to = tostring(to)
	local serials = {}
	for _,v in next, _serials do
		tinsert(serials, tostring(v))
	end
	if timeLeft() < 1 then
		checkTimeout()
		return false, 'Program transfers require 1 second of runtime'
	end
	
	local query = { owner = from, _id = { ['$in'] = serials } }
	local affected = db.cursorToArray(programsDb:find(query, { projection = { _id = 1, name = 1 } }))
	programsDb:update(query, { ['$set'] = { owner = to, loaded = false } })
	logDb:insert({ action = "transfer", from = from, to = to, programs = affected, date = db.now() })
	fixUser(from)
	fixUser(to)
	return true, 'Programs have been transferred'
end

return {
	transfer = makeProtectedFunc(transfer),
	fixUser = makeProtectedFunc(fixUser)
}