local ffi = require("ffi")
local blshift = require("bit").lshift
local mrandomseed = math.randomseed
local error = error

local SYS_getrandom = 318

-- This would be ssize, but that's not defined in LuaJIT, so we use the same-typed ptrdiff_t
ffi.cdef[[
	int syscall(int syscall, void *buffer, size_t len, unsigned int flags);
]]

local function bytes(len)
	local res = ffi.new("char[?]", len)
	if ffi.C.syscall(SYS_getrandom, res, len, 0) ~= len then
		error("Could not get random")
	end
	return ffi.string(res, len)
end

local function int64()
	local b1, b2, b3, b4 = bytes(4):byte(1, 4)
	return b1 + blshift(b2, 8) + blshift(b3, 16) + blshift(b4, 24)
end

return {
	bytes = bytes,
	int64 = int64
}
