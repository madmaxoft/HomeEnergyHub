-- router.lua

--[[
Implements the HTTP server's routing table.
The routes are listed statically in the table below
Route handlers live in the Handlers subfolder.
--]]





local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")
local socket = require("socket")
local log = require("logger").log





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
		{ path = "/rawDataExport/availableRange",       handler = require("Handlers.rawDataExport").getAvailableRange },
		{ path = "/rawDataExport/dailyStats",           handler = require("Handlers.rawDataExport").getDailyStats },
		{ path = "/rawDataExport/rawData",              handler = require("Handlers.rawDataExport").getRawData },
		{ path = "/remoteImport",                       handler = require("Handlers.remoteImport").getRemoteImport },
		{ path = "/savings?",                           handler = require("Handlers.savings").get },
		{ path = "/tariffPlan/dayTypeGraph?",           handler = require("Handlers.tariffPlanUI").getDayTypeGraph },
		{ path = "/tariffPlan/editDayType/",            handler = require("Handlers.tariffPlanUI").getEditDayType },
		{ path = "/tariffPlan/export",                  handler = require("Handlers.tariffPlanUI").getExport },
		{ path = "/tariffPlan/import",                  handler = require("Handlers.tariffPlanUI").getImport },
		{ path = "/tariffPlan",                         handler = require("Handlers.tariffPlanUI").getTariffPlan },
		{ path = "/",                                   handler = require("Handlers.home") },
	},
	POST =
	{
		{ path = "/remoteImport/start",                 handler = require("Handlers.remoteImport").postStart },
		{ path = "/remoteImport/cancel",                handler = require("Handlers.remoteImport").postCancel },
		{ path = "/tariffPlan/addNewDayType",           handler = require("Handlers.tariffPlanUI").postAddNewDayType },
		{ path = "/tariffPlan/addNewExceptionDate",     handler = require("Handlers.tariffPlanUI").postAddNewExceptionDate },
		{ path = "/tariffPlan/addNewSeason",            handler = require("Handlers.tariffPlanUI").postAddNewSeason },
		{ path = "/tariffPlan/editDayType/addNewSlot",  handler = require("Handlers.tariffPlanUI").postAddNewDayTypeSlot },
		{ path = "/tariffPlan/import",                  handler = require("Handlers.tariffPlanUI").postImport },
		{ path = "/tariffPlan/removeExceptionDate",     handler = require("Handlers.tariffPlanUI").postRemoveExceptionDate },
	},
}





--- Calls the specified handler safely - if an error is raised, an error page is served
function router.dispatchHandler(aClient, aPath, aHeaders, aHandler)
	assert(type(aPath) == "string")
	assert(type(aHeaders) == "table")
	assert(type(aHandler) == "function")

	-- Error handler that adds traceback
	local function onError(aErr)
		return debug.traceback(aErr, 2)
	end

	-- run handler safely
	local isOK, result = xpcall(function()
		return aHandler(aClient, aPath, aHeaders)
	end, onError)

	-- if an exception occurred
	if not(isOK) then
		local errText = result or "Unknown error"
		log("router", "ERROR during request:\n" .. errText)
		httpResponse.sendError(aClient, 500, errText)
	end
end





--- Handles a single HTTP client connection
function router.handleRequest(aClient)
	local method, path, headers = httpRequest.readRequestHeaders(aClient)
	if (not(method) or not(path)) then
		return
	end

	local handler = router.findHandler(method, path)
	if (handler) then
		local beginTime = socket.gettime()
		log("main", "%s Request for path \"%s\".", method, path)
		router.dispatchHandler(aClient, path, headers, handler)
		local endTime = socket.gettime()
		if (endTime - beginTime >= 0.5) then
			log("router", "  ^^ Request took %f seconds.", (endTime - beginTime))
		end
	else
		log("router", "UNHANDLED: %s Request for path \"%s\".", method, path)
		httpResponse.sendError(aClient, 404, "Not found")
	end
end





--- Returns the handler matching the specified method and path
-- Returns nil if no match found
function router.findHandler(aMethod, aPath)
	assert(type(aMethod) == "string")
	assert(type(aPath) == "string")

	for _, route in ipairs(router.routes[aMethod] or {}) do
		if (route.path == string.sub(aPath, 1, #route.path)) then
			return route.handler
		end
	end
end





return router
