local ffi = require("ffi")
local error = error

ffi.cdef[[
	size_t read_random(void *buffer, size_t len);
]]

local function secureRandom(len)
	local res = ffi.new("char[?]", len)
	if ffi.C.read_random(res, len) ~= 1 then
		error("Could not get random")
	end
	return ffi.string(res, len)
end

return {
	secureRandom = secureRandom
}
