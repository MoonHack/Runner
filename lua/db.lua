local mongo = require("mongo")
-- TODO: CONFIG VARIABLE THIS
local client = mongo.Client("mongodb://127.0.0.1")

return {
	mongo = mongo,
	client = client,
	internal = client:getDatabase("moonhack_core"),
	user = client:getDatabase("moonhack_user")
}
