-- router.lua

--[[
Implements the HTTP server's routing table.
The routes are listed statically in the table below
Route handlers live in the Handlers subfolder.
--]]





local router = {}





--- Static routes:
-- NOTE: The matcher goes from top to bottom and uses the first substring match,
-- so the more generic URLs need to go at the bottom
router.routes = {
	GET =
	{
		{ path = "/static/",                            handler = require("Handlers.static") },
		{ path = "/Static/",                            handler = require("Handlers.static") },
		{ path = "/favicon",                            handler = require("Handlers.favicon") },
		{ path = "/graph?",                             handler = require("Handlers.graph") },
		{ path = "/tariffPlan/editDayType/",            handler = require("Handlers.tariffPlanUI").getEditDayType },
		{ path = "/tariffPlan/dayTypeGraph?",           handler = require("Handlers.tariffPlanUI").getDayTypeGraph },
		{ path = "/tariffPlan",                         handler = require("Handlers.tariffPlanUI").getTariffPlan },
		{ path = "/",                                   handler = require("Handlers.home") },
	},
	POST =
	{
		{ path = "/tariffPlan/addNewDayType",           handler = require("Handlers.tariffPlanUI").postAddNewDayType },
		{ path = "/tariffPlan/addNewSeason",            handler = require("Handlers.tariffPlanUI").postAddNewSeason },
		{ path = "/tariffPlan/editDayType/addNewSlot",  handler = require("Handlers.tariffPlanUI").postAddNewDayTypeSlot },
	},
}





--- Returns the handler matching the specified method and path
-- Returns nil if no match found
function router.match(aMethod, aPath)
	assert(type(aMethod) == "string")
	assert(type(aPath) == "string")

	for _, route in ipairs(router.routes[aMethod] or {}) do
		if (route.path == string.sub(aPath, 1, #route.path)) then
			return route.handler
		end
	end
end





return router
