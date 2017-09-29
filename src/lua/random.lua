local ffi = require("ffi")
local error = error

-- This would be ssize, but that's not defined in LuaJIT, so we use the same-typed ptrdiff_t
ffi.cdef[[
	ptrdiff_t getrandom(void *buffer, size_t len, unsigned int flags);
]]

local function secureRandom(len)
	local res = ffi.new("char[?]", len)
	if ffi.C.getrandom(res, len, 0) ~= len then
		error("Could not get random")
	end
	return ffi.string(res, len)
end

return {
	secureRandom = secureRandom
}
