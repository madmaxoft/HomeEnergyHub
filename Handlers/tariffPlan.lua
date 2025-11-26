-- Handlers/tariffPlan.lua

--[[
Implements the handler for the /tariffPlan endpoint, used to view and edit the tariff plan
--]]

local db = require("db")
local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")
local multipart = require("multipart")
local tariffPlan = require("tariffPlan")
local utils = require("utils")





local function handlePostAddNewDayType(aClient)
	tariffPlan.addNewDayType()
	return httpResponse.sendRedirect(aClient, "/tariffPlan")
end





local function handlePostAddNewSeason(aClient, aRequestHeaders)
	-- Parse the inputs:
	local body = httpRequest.readBody(aClient, aRequestHeaders)
	local m = multipart(body, aRequestHeaders["content-type"])
	local startDate = (m:get("startDate") or {}).value
	local endDate = (m:get("endDate") or {}).value
	local workdayDayType = tonumber((m:get("workdayDayType") or {}).value)
	local weekendDayType = tonumber((m:get("weekendDayType") or {}).value)

	-- Check validity:
	if not(startDate and endDate and workdayDayType and weekendDayType) then
		return httpResponse.sendError(aClient, 400, string.format(
			[[Missing required fields:<br />
			startDate = %s<br />
			endDate = %s<br />
			workdayDayType = %s<br />
			weekendDayType = %s
			]],
			startDate, endDate, workdayDayType, weekendDayType
		))
	end
	if not(utils.checkYmdDate(startDate) and utils.checkYmdDate(endDate)) then
		return httpResponse.sendError(aClient, 400, "Invalid startDate or endDate")
	end
	if not(tariffPlan.dayTypeSchedules[workdayDayType] and tariffPlan.dayTypeSchedules[weekendDayType]) then
		return httpResponse.sendError(aClient, 400, "Invalid day type")
	end

	-- Add:
	tariffPlan.addNewSeason(startDate, endDate, workdayDayType, weekendDayType)
	return httpResponse.sendRedirect(aClient, "/tariffPlan")
end





return {
	get = function(aClient, aPath, aRequestHeaders)
		local body = require("Templates").tariffPlan({
			currentTime = os.time(),
			seasons = tariffPlan.seasons,
			dayTypeSchedules = tariffPlan.dayTypeSchedules,
			exceptionDates = tariffPlan.exceptionDates,
		})
		httpResponse.send(aClient, "200 OK", nil, body)
	end,


	post = function(aClient, aPath, aRequestHeaders)
		if (aPath == "/tariffPlan/addNewDayType") then
			return handlePostAddNewDayType(aClient, aRequestHeaders)
		elseif (aPath == "/tariffPlan/addNewSeason") then
			return handlePostAddNewSeason(aClient, aRequestHeaders)
		end
	end,
}
