local ffi = require("ffi")
local error = error
local exit = os.exit
local tonumber = tonumber
local roTable = require("rotable")

ffi.cdef[[
	typedef long time_t;
 
 	typedef struct timeval {
		time_t tv_sec;
		time_t tv_usec;
	} timeval;
 
	int gettimeofday(struct timeval* t, void* tzp);

	int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local START_TIME = 0
local KILL_TIME = 0
local CANT_TIMEOUT = 0

local gettimeofday_struct = ffi.new("timeval")
local function time()
 	ffi.C.gettimeofday(gettimeofday_struct, nil)
 	return (tonumber(gettimeofday_struct.tv_sec) * 1000) + (tonumber(gettimeofday_struct.tv_usec) / 1000)
end

local function timeLeft()
	return KILL_TIME - time()
end

local function checkTimeout()
	if CANT_TIMEOUT <= 0 and timeLeft() < 0 then
		exit(6) -- EXIT_SOFT_TIMEOUT
	end
end

local function setTimes(start, timeout)
	START_TIME = start
	KILL_TIME = start + timeout
end

local function getTimes()
	return START_TIME, KILL_TIME
end

local function disableTimeout()
	CANT_TIMEOUT = CANT_TIMEOUT + 1
end

local function enableTimeout()
	if CANT_TIMEOUT <= 0 then
		error("Timeout not disabled")
	end
	CANT_TIMEOUT = CANT_TIMEOUT - 1
end

local function sleep(milliseconds)
	ffi.C.poll(nil, 0, milliseconds)
	checkTimeout()
end

return roTable.deepFreeze({
	setTimes = setTimes,
	getTimes = getTimes,
	timeLeft = timeLeft,
	time = time,
	sleep = sleep,
	checkTimeout = checkTimeout,
	disableTimeout = disableTimeout,
	enableTimeout = enableTimeout
})
