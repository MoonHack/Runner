local ffi = require("ffi")
local checkTimeout = require("time").checkTimeout

ffi.cdef[[
	void lua_writeln(const char *str);
]]

local function writeln(str)
	ffi.C.lua_writeln(str .. "\n")
	checkTimeout()
end

return writeln
