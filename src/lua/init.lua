local dtraceback = debug.traceback
local print = io.write
local error = error

local ok, res = xpcall(dofile, function(err)
	print(err .. "\n" .. dtraceback() .. "\n")
	return err
end, "main.luac")
if ok then
	return res
else
	error(res)
end
