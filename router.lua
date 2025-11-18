-- router.lua

--[[
Implements the HTTP server's routing table.
The routes are listed statically in the table below
Route handlers live in the Handlers subfolder.
--]]





local router = {}





-- Define static routes:
router.routes = {
	{ method = "GET",  path = "/",        handler = require("Handlers.home") },
	{ method = "GET",  path = "/static/", handler = require("Handlers.static") },
	{ method = "GET",  path = "/Static/", handler = require("Handlers.static") },
}





--- Returns the handler matching the specified method and path
-- Returns nil if no match found
function router.match(aMethod, aPath)
	assert(type(aMethod) == "string")
	assert(type(aPath) == "string")

	for _, route in ipairs(router.routes) do
		if (
			(route.method == aMethod) and
			(route.path == string.sub(aPath, 1, #route.path))
		) then
			return route.handler
		end
	end
end





return router
