-- db.upgrades store owner, can be updated atomically by serial
-- db.user stores array of serials that gets auto-fixed on every op

-- FIRST we find upgrades affected, LAST we insert the log
-- changes by position get serials from user, then push atomic updates by serial (race condition, so script access by serial preferred!)
-- changes by serial just update atomically

local db = require("db")
local user = require("user")
local uuid = require("uuid")
local userDb = db.internal:getCollection("users")
local programsDb = db.internal:getCollection("programs")
local logDb = db.internal:getCollection("program_log")
local timeLeft = timeLeft
local checkTimeout = checkTimeout
local tinsert = table.insert
local next = next
local type = type
local ObjectID = db.mongo.ObjectID

local function _fixSerials(name, _serials)
	local userObj = user:getByName(name, { programs = 1 })
	if not userObj then
		return {}, {}
	end
	userObj = userObj.programs
	local serials = {}
	for _, v in next, _serials do
		local tv = type(v)
		if tv == "number" then
			tinsert(serials, ObjectID(userObj[v].id))
		else
			tinsert(serials, ObjectID(tostring(v)))
		end
	end
	return serials, userObj
end

local function _save(name, programs)
	userDb:updateOne({ _id = tostring(name) }, { ['$set'] = { programs = programs }})
end

local function _fixUser(name, list, toFix)
	name = tostring(name)
	if not toFix then
		toFix = user:getByName(name, { programs = 1 })
		if not toFix then
			return false, 'User not found'
		end
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
		programsShould[tostring(v._id)] = v
	end

	local programsStored = {}
	for _,v in next, programsStored do
		if programsShould[v.id] then
			programsShould[v.id] = nil
			tinsert(programsStored, v)
		end
	end

	for k,v in next, programsShould do
		if v then
			dirty = true
			tinsert(programsStored, { id = k, loaded = false })
		end
	end

	if dirty then
		_save(name, programs)
	end

	return true, programsStored, programsShould
end

local function delete(name, serials)
	name = tostring(name)
	local userProgs
	serials, userProgs = _fixSerials(name, serials)
	if timeLeft() < 1 then
		checkTimeout()
		return false, 'Program deletions require 1 second of runtime'
	end

	local txn = uuid()

	programsDb:updateMany({ owner = from, _id = { ['$in'] = serials } }, { ['$set'] = { owner = "", lastTransaction = txn } })
	local affected = db.cursorToArray(programsDb:find({ lastTransaction = txn }, { projection = { _id = 1, name = 1 } }))
	programsDb:delete({ lastTransaction = txn })
	logDb:insert({ action = "delete", from = name, programs = affected, date = db.now() })
	_fixUser(name, userProgs)
	return true, 'Programs have been deleted', affected
end

local function transfer(from, to, serials)
	from = tostring(from)
	to = tostring(to)
	local userProgs
	serials, userProgs = _fixSerials(from, serials)
	if timeLeft() < 1 then
		checkTimeout()
		return false, 'Program transfers require 1 second of runtime'
	end

	local txn = uuid()
	
	programsDb:updateMany({ owner = from, _id = { ['$in'] = serials } }, { ['$set'] = { owner = to, lastTransaction = txn } })
	local affected = db.cursorToArray(programsDb:find({ lastTransaction = txn }, { projection = { _id = 1, name = 1 } }))
	logDb:insert({ action = "transfer", from = from, to = to, programs = affected, date = db.now() })
	_fixUser(from, userProgs)
	_fixUser(to)
	return true, 'Programs have been transferred', affected
end

local function load(name, serials, load)
	load = load and true or false

	serials, stored = _fixSerials(name, serials)
	local pMap = {}
	for _, v in next, serials do
		pMap[v] = true
	end
	local affectedSerials = {}
	for k, v in next, stored do
		if pMap[v.id] and v.loaded ~= load then
			tinsert(affectedSerials, v.id)
			v.loaded = load
		end
	end

	local affected = db.cursorToArray(programsDb:find({ owner = from, _id = { ['$in'] = affectedSerials } }, { projection = { _id = 1, name = 1 } }))
	logDb:insert({ action = load and "load" or "unload", from = name, programs = affected, date = db.now() })
	
	_save(ctx.caller, stored)
	
	return true, load and 'Programs have been loaded' or 'Programs have been unloaded', affected
end

local function list(name)
	return _fixUser(tostring(name), true)
end

return {
	load = makeProtectedFunc(load),
	transfer = makeProtectedFunc(transfer),
	list = makeProtectedFunc(list),
	delete = makeProtectedFunc(delete)
}