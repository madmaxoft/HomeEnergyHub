-- Handlers/backgroundAggregation.lua

--[[
Implements the HTTP endpoints needed for managing the background aggregation task.
--]]





local db = require("db")
local utils = require("utils")
local copas = require("copas")
local perf = require("perf")
local log = require("logger").log
local bat = require("backgroundAggregationTask")





--- The API returned by this module:
local M = {}





--- The HTTP handler for the base status page
function M.get(aRequest, aResponse)
	local minTS, maxTS = db.electricityConsumptionDataRange()
	local templateParams =
	{
		status = bat.status(),
		range = {minTimeStamp = minTS, maxTimeStamp = maxTS},
	}
	return aResponse:sendTemplate("backgroundAggregation", templateParams)
end





--- The HTTP handler for the setRange API endpoint
function M.postSetRange(aRequest, aResponse)
	-- Parse the inputs:
	local m = aRequest:formData()
	if not(m) then
		return aResponse:sendError(400, "Failed to parse form data.")
	end
	local startTS = tonumber(m.startts)
	if not(startTS) then
		return aResponse:sendError(400, "Missing or invalid 'startTS' field.")
	end
	local endTS = tonumber(m.endts)
	if not(endTS) then
		return aResponse:sendError(400, "Missing or invalid 'endTS' field.")
	end

	bat.setRange(startTS, endTS)

	return aResponse:sendRedirect("/backgroundAggregation")
end





return M
