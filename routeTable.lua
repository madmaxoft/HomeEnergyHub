-- routeTable.lua

--[[
Defines the static routing table, used by the HTTP router.
The matcher goes from top to bottom and uses the first substring match,
so the more generic URLs need to go at the bottom
Otherwise, the routes generally follow an alpha-sorted order
--]]




return {
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