--[[
	old = findAndModify -> upgradesLockedUntil = NOW + 10 where upgradesLockedUntil < now
	if old and old.upgradesLockedUntil < now then
		CAN DO
	else
		sleep(150ms)
		retry
	end
	update upgradesLockedUntil = NOW
]]
