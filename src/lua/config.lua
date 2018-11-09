local ffi = require("ffi")

ffi.cdef[[
	const char* getenv(const char* var);
]]

local function getenvstr(var)
	res = ffi.C.getenv(var)
	if not res then
		error("Missing environment variable "..var)
	end
	return ffi.string(res)
end

return {
	mongo = {
		core = getenvstr("MONGODB_CORE"),
		users = getenvstr("MONGODB_USERS")
	}
}


