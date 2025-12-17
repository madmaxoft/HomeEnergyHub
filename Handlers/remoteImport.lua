-- Handlers/remoteImport.lua

--[[
Implements the HTTP endpoints needed for importing data from a remote instance.

Only a single import is allowed at a time. Since the iport is potentially a long operation, it is
stored as a state in this module and modified by various HTTP endpoints.
--]]





local db = require("db")
local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local multipart = require("multipart")
local utils = require("utils")
local copas = require("copas")





local M =
{
	isRunning = false,     -- Whether an import is currently running
	remoteAddress = "",    -- The remote "host:port" from which to import
	startTimeStamp = 0,    -- The remote's data range start timestamp
	endTimeStamp = 0,      -- The remote's data range end timestamp
	currentTimeStamp = 0,  -- The currently processed timestamp (used for progress report)
	lastResult = "",       -- The string describing the last result of an import, used to report errors
	shouldCancel = false,  -- If set to true, the import operation will cancel asap
	progress = {n = 0},    -- Messages to be displayed, related to the import progress (such as warnings)
}

local SECONDS_PER_DAY = 24 * 60 * 60





--- Adds the specified format-text to the progress messages
function M.addProgress(aFormatText, ...)
	assert(type(aFormatText) == "string")

	M.progress.n = M.progress.n + 1
	M.progress[M.progress.n] = string.format(aFormatText, ...)
end





--- Does the actual import.
-- Returns true on success
-- Returns nil and error message on failure
function M.doImport()
	assert(type(M.remoteAddress) == "string")

	-- Fetch the available range:
	M.addProgress("Fetching available range...")
	M.startTimeStamp, M.endTimeStamp = M.fetchRemoteAvailableRange()
	if not(M.startTimeStamp and M.endTimeStamp) then
		return nil, string.format("Cannot parse remote's availableRange response: %s", tostring(M.endTimeStamp))
	end
	M.currentTimeStamp = M.startTimeStamp

	-- Fetch the daily stats:
	M.addProgress("Fetching daily stats...")
	local firstDayTs = M.startTimeStamp - (M.startTimeStamp % SECONDS_PER_DAY)
	local lastDayTs = M.endTimeStamp - (M.endTimeStamp % SECONDS_PER_DAY)
	local remoteDailyStats, msg = M.fetchRemoteDailyStats(firstDayTs, lastDayTs)
	if not(remoteDailyStats) then
		return nil, msg
	end

	-- Iterate day-by-day, oldest first:
	for dayTs = firstDayTs, lastDayTs, SECONDS_PER_DAY do
		if (M.shouldCancel) then
			M.addProgress("Cancelled.")
			return nil, "Cancelled"
		end
		M.currentTimeStamp = dayTs
		copas.sleep(0.1)
		M.addProgress("Fetching day %s...", utils.timeStampToYmd(dayTs))
		local remoteStats = remoteDailyStats[dayTs] or {}
		local localStats = db.getElectricityConsumptionDailyStats(dayTs, dayTs + SECONDS_PER_DAY) or {{}}

		-- Only sync if counts differ:
		if (
			(remoteStats.count ~= localStats.count) or
			(remoteStats.sum ~= localStats.sum)
		) then
			local rawRows, msg = M.fetchRemoteDayRawData(dayTs)
			if (rawRows) then
				db.importElectricityConsumptionRows(rawRows)
			else
				M.progress.n = M.progress.n + 1
				M.progress[M.progress.n] = tostring(msg)
			end
		end
	end
	return true
end





--- Fetches and parses the available range from the remote.
-- Returns the startTimeStamp and endTimeStamp on success
-- Returns nil and error message on failure
function M.fetchRemoteAvailableRange()
	assert(type(M.remoteAddress) == "string")
	assert(M.remoteAddress ~= "")

	local isSuccess, httpCode, respHeaders, response = utils.httpRequest(string.format("http://%s/rawDataExport/availableRange", M.remoteAddress), "GET")
	if not(isSuccess) then
		return nil, string.format("Failed to connect to remote: %s", tostring(httpCode))
	end
	if (httpCode ~= 200) then
		return nil, string.format("The remote returned an HTTP error %d. %s", httpCode, tostring(response))
	end
	local startTimeStamp, endTimeStamp = response:match("^(%d+)%s+(%d+)%s*$")
	startTimeStamp, endTimeStamp = tonumber(startTimeStamp), tonumber(endTimeStamp)
	if not(startTimeStamp and endTimeStamp) then
		return nil, string.format("Cannot parse range response from the remote: %q", response)
	end
	return startTimeStamp, endTimeStamp
end





--- Fetches the daily stats from the remote
-- Returns a dict-table of dayTimeStamp -> stats parsed from the response
-- Returns nil and an error message on failure
function M.fetchRemoteDailyStats(aStartDayTs, aEndDayTs)
	assert(type(aStartDayTs) == "number")
	assert(type(aEndDayTs) == "number")

	-- Fetch and parse the remote daily stats:
	local isSuccess, httpCode, respHeaders, response = utils.httpRequest(string.format(
		"http://%s/rawDataExport/dailyStats?fromTimeStamp=%d&toTimeStamp=%d",
		M.remoteAddress, aStartDayTs, aEndDayTs
	), "GET")
	if not(isSuccess) then
		return nil, string.format("Failed to query daily stats from the remote: %s" .. tostring(httpCode))
	end
	if (httpCode ~= 200) then
		return nil, string.format("The remote returned an HTTP error %d. %s", httpCode, tostring(response))
	end

	local statsResponse, msg = utils.loadDataString(response)
	if not(statsResponse) then
		return nil, "Failed to parse daily stats from the remote: " .. tostring(msg)
	end
	print(string.format("[remoteImport] Received daily stats from remote %s", M.remoteAddress))

	-- Build lookup table: dayTs -> {count = ..., sum = ...}
	local remoteDailyStats = {}
	for _, row in ipairs(statsResponse) do
		if (row.timeStamp) then
			remoteDailyStats[row.timeStamp] = row
		end
	end
	return remoteDailyStats
end





--- Requests the specified day from the remote
-- Returns the table data for the day, or nil and error message on failure
function M.fetchRemoteDayRawData(aDayTimeStamp)
	assert(type(aDayTimeStamp) == "number")
	assert(aDayTimeStamp % SECONDS_PER_DAY == 0)

	local fromTs = aDayTimeStamp
	local toTs = aDayTimeStamp + SECONDS_PER_DAY - 1
	local isSuccess, httpCode, respHeaders, response = utils.httpRequest(string.format(
		"http://%s/rawDataExport/rawData?fromTimeStamp=%d&toTimeStamp=%d",
		M.remoteAddress, fromTs, toTs
	), "GET")
	if not(isSuccess) then
		return nil, string.format("Failed to query day data from the remote: %s", tostring(httpCode))
	end
	if (httpCode ~= 200) then
		return nil, string.format("The remote returned an HTTP error %d. %s", httpCode, tostring(response))
	end

	local rawRows, msg = utils.loadDataString(response)
	if not(rawRows) then
		return nil, string.format(
			"Import aborted, failed parsing data for day %s: %s",
			utils.timeStampToYmd(aDayTimeStamp), tostring(msg)
		)
	end
	print(string.format("[remoteImport] Received day %s from remote %s",
		utils.timeStampToYmd(aDayTimeStamp), M.remoteAddress
	))
	rawRows.n = #rawRows
	return rawRows
end





function M.getRemoteImport(aClient, aPath, aRequestHeaders)
	return httpResponse.send(aClient, 200, nil, require("Templates").remoteImport(M))
end





function M.postCancel(aClient, aPath, aRequestHeaders)
	M.shouldCancel = true
	return httpResponse.sendRedirect(aClient, "/remoteImport")
end





function M.postStart(aClient, aPath, aRequestHeaders)
	-- Do not allow running multiple instances:
	if (M.isRunning) then
		return httpResponse.sendError(aClient, 400, "An import is already running.")
	end

	-- Parse the inputs:
	local body = httpRequest.readBody(aClient, aRequestHeaders)
	local m = multipart(body, aRequestHeaders["content-type"])
	local remoteAddress = (m:get("remoteAddress") or {}).value
	if not(remoteAddress) then
		return httpResponse.sendError(aClient, 400, "Missing the 'remoteAddress' field.")
	end
	if (remoteAddress == "") then
		return httpResponse.sendError(aClient, 400, "The 'remoteAddress' field is empty.")
	end

	-- Start the import:
	M.remoteAddress = remoteAddress
	print(string.format("[remoteImport] Importing from %s", M.remoteAddress))

	copas.addthread(M.runImport)
	return httpResponse.sendRedirect(aClient, "/remoteImport")
end





--- Runs the import.
-- Calls doImport and handles its error conditions.
-- Handles the isRunning and lastResult manipulation
function M.runImport()
	M.shouldCancel = false
	M.progress = {n = 0}
	M.isRunning = true
	M.addProgress("Importing from %s...", M.remoteAddress)
	local isOK, msg = M.doImport()
	if not(isOK) then
		M.lastResult = tostring(msg)
		print(string.format("[remoteImport] Failed to import from %s: %s", M.remoteAddress, tostring(msg)))
	else
		print(string.format("[remoteImport] Finished importing from %s", M.remoteAddress))
	end
	M.isRunning = false
end





return M
