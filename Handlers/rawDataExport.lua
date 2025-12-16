-- Handlers/rawDataExport.lua

--[[
Handles the HTTP rawDataExport endpoint, exporting the raw data in specified ranges and querying
the available ranges.

The handlers provide an API, rather than human-readable pages, so the returned data is formatted for
machine use.

There are multiple handlers: for the available range, complete days and day data; each is a named function
in the returned table.
--]]





local db = require("db")
local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local utils = require("utils")





local M = {}





--- Returns two timestamps, each on a separate line, specifying the start and end of raw data in the DB
function M.getAvailableRange(aClient, aPath, aRequestHeaders)
	local startTimeStamp, endTimeStamp = db.getElectricityConsumptionDataRange()
	return httpResponse.send(aClient, 200, "text/plain", string.format("%d\n%d\n", startTimeStamp, endTimeStamp))
end





--- Returns a list of days within the specified interval with their stats (num records, timestamp sum as a hash)
-- The interval is specified in fromTimeStamp and toTimeStamp parameters and is max 366 days long
function M.getDailyStats(aClient, aPath, aRequestHeaders)
	-- Parse query parameters:
	local path, query = httpRequest.parseRequestPath(aPath)
	local fromTimeStamp = tonumber(query.fromTimeStamp)
	local toTimeStamp = tonumber(query.toTimeStamp)
	if not(fromTimeStamp and toTimeStamp) then
		return httpResponse.sendError(aClient, 400, "Missing 'fromTimeStamp' or 'toTimeStamp' parameter")
	end

	-- Check parameters:
	if (toTimeStamp < fromTimeStamp) then
		toTimeStamp, fromTimeStamp = fromTimeStamp, toTimeStamp
	end
	if (toTimeStamp - fromTimeStamp > 366 * 24 * 60 * 60) then
		return httpResponse.sendError(aClient, 400, "Interval too large")
	end

	local dayStats = db.getElectricityConsumptionDailyStats(fromTimeStamp, toTimeStamp)
	local body = {}
	for idx, day in ipairs(dayStats) do
		body[idx] = string.format(
			"{timeStamp = %d, count = %d, sum = %d},",
			day.timeStamp, day.count, day.sum or 0
		)
	end
	return httpResponse.send(aClient, 200, "text/lua", "{" .. table.concat(body) .. "}")
end





--- Returns the raw data for the specified interval, as a Lua array-table of dict-tables
-- The interval is specified in fromTimeStamp and toTimeStamp parameters and is max 25 hours long
function M.getRawData(aClient, aPath, aRequestHeaders)
	-- Parse query parameters:
	local path, query = httpRequest.parseRequestPath(aPath)
	local fromTimeStamp = tonumber(query.fromTimeStamp)
	local toTimeStamp = tonumber(query.toTimeStamp)
	if not(fromTimeStamp and toTimeStamp) then
		return httpResponse.sendError(aClient, 400, "Missing 'fromTimeStamp' or 'toTimeStamp' parameter")
	end

	-- Check parameters:
	if (toTimeStamp < fromTimeStamp) then
		toTimeStamp, fromTimeStamp = fromTimeStamp, toTimeStamp
	end
	if (toTimeStamp - fromTimeStamp > 366 * 24 * 60 * 60) then
		return httpResponse.sendError(aClient, 400, "Interval too large")
	end

	local rawData = db.getElectricityConsumptionRawData(fromTimeStamp, toTimeStamp)
	local body = {}
	for idx, row in ipairs(rawData) do
		body[idx] = "{" .. utils.serializeTable(row) .. "},"
	end
	return httpResponse.send(aClient, 200, "text/lua", "{" .. table.concat(body) .. "}")
end





return M
