local ffi = require("ffi")

ffi.cdef[[
	const char* getenv(const char* var);
]]

return {
	mongo = {
		core = ffi.string(ffi.C.getenv("MONGODB_CORE")),
		users = ffi.string(ffi.C.getenv("MONGODB_USERS"))
	}
}


