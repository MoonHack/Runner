local db = require("db")
local scriptsDb = db.internal:getCollection("scripts")
local coreScripts = _G.coreScripts
local unpack = unpack
local tinsert = table.insert

return function(ctx, args)
	local name = ctx.caller .. "." .. tostring(args.name)
	local stype = "mine"
	local skip = 0
	local limit = 100
	if args then
		if args.type then
			stype = tostring(args.type)
		end
		if args.skip then
			skip = tonumber(args.skip)
			if skip < 0 then
				skip = 0
			end
		end
		if args.limit then
			limit = tonumber(args.limit)
			if limit > 1000 then
				limit = 1000
			end
			if limit < 1 then
				limit = 1
			end
		end
	end

	local query
	local addSystem = false
	if stype == "mine" then
		query = { owner = ctx.caller }
	elseif stype == "public" then
		query = { accessLevel = 3 }
		addSystem = true
	elseif stype == "system" then
		query = { accessLevel = 3, system = true }
		addSystem = true
	else
		return false, 'Unknown type'
	end

	local scripts = db.cursorToArray(scriptsDb:find(query, { projection = {
		_id = 1,
		accessLevel = 1,
		securityLevel = 1,
		owner = 1,
		locked = 1,
		system = 1
	}}))
	if addSystem then
		tinsert(scripts, unpack(coreScripts))
	end

	return true, scripts
end
