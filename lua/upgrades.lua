-- db.upgrades store owner, can be updated atomically by serial
-- db.user stores array of serials that gets auto-fixed on every op

-- FIRST we find upgrades affected, LAST we insert the log
-- changes by position get serials from user, then push atomic updates by serial (race condition, so script access by serial preferred!)
-- changes by serial just update atomically

