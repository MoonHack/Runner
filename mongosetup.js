// notifications
db.notifications.createIndex({
	date: 1,
}, {
	expiresAfterSeconds: 2592000,
});
db.notifications.createIndex({
	to: 1,
});

// scripts
db.scripts.createIndex({
	name: 1,
}, {
	unique: true,
});
db.scripts.createIndex({
	owner: 1,
});
db.scripts.createIndex({
	securityLevel: 1,
});
db.scripts.createIndex({
	accessLevel: 1,
});
db.scripts.createIndex({
	system: 1,
});

// programs
db.programs.createIndex({
	owner: 1,
});
db.programs.createIndex({
	lastTransaction: 1,
}, {
	sparse: true,
});

// money_log
db.money_log.createIndex({
	to: 1,
});
db.money_log.createIndex({
	from: 1,
});
db.money_log.createIndex({
	date: 1,
}, {
	expiresAfterSeconds: 2592000,
});

// program_log
db.program_log.createIndex({
	to: 1,
});
db.program_log.createIndex({
	from: 1,
});
db.program_log.createIndex({
	date: 1,
}, {
	expiresAfterSeconds: 2592000,
});
