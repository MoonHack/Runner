local strbyte = string.byte
local dgetinfo = debug.getinfo
local xpcall = xpcall
local strgsub = string.gsub
local tostring = tostring
local checkTimeout = require("time").checkTimeout
local roTable = require("rotable")

local AT = strbyte("@", 1)
local function errorHandler(err)
	local msg = "ERROR: " .. strgsub(err, ".+: ", "")
	for i=2,99 do
		local info = dgetinfo(i)
		if not info or info.what == "main" or info.func == xpcall then
			break
		end
		if info.what ~= "Lua" or strbyte(info.source, 1) ~= AT then
			local sourceName
			if info.namewhat == "global" then
				sourceName = "global function " .. info.name
			elseif info.namewhat == "local" then
				sourceName = "local function " .. info.name
			elseif info.namewhat == "method" then
				sourceName = "method " .. info.name
			elseif info.namewhat == "field" then
				sourceName = "field " .. info.name
			else
				sourceName = "main chunk"
			end
			msg = msg .. "\n\t" .. info.source .. ":" .. tostring(info.linedefined) .. ": " .. sourceName
		else
			msg = msg .. "\n\t--hidden--"
		end
	end
	return msg
end

return roTable.deepFreeze({
	errorHandler = errorHandler,
	pcall = function(func, ...)
		checkTimeout()
		return xpcall(func, errorHandler, ...)
	end
})
