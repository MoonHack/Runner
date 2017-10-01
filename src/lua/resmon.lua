local ffi = require("ffi")
local collectgarbage = collectgarbage

ffi.cdef[[
	uint32_t lua_get_memory_limit();
	uint32_t lua_get_memory_usage();
]]

local function mem_getLimit()
	return ffi.C.lua_get_memory_limit()
end

local function mem_getUsage()
	return ffi.C.lua_get_memory_usage()
end

return {
	memory = {
		getLimit = mem_getLimit,
		getUsage = mem_getUsage,
	},
}
