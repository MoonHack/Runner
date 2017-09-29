local ffi = require("ffi")
local error = error

ffi.cdef[[
	typedef unsigned char uuid_t[16];

	void uuid_generate_random(uuid_t out);
	void uuid_unparse(uuid_t uu, char *out);
]]

local uuid_out = ffi.new("uuid_t")
local uuid_str_out = ffi.new("char[?]", 37)
local function random()
	ffi.C.uuid_generate_random(uuid_out)
	ffi.C.uuid_unparse(uuid_out, uuid_str_out)
	return ffi.string(uuid_str_out, 36)
end

return {
	random = random
}
