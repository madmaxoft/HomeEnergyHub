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





--- Parses a "HHH:MM" or "MM" string into a number of minutes
-- Returns nil and error message on failure
local function parseMinutes(aMinutesStr)
	if not(aMinutesStr) then
		return nil, "Invalid minutes input"
	end
	assert(type(aMinutesStr) == "string")
	local hours, minutes = aMinutesStr:match("(%d+):(%d+)")
	if (hours and minutes) then
		return hours * 60 + minutes
	end
	minutes = tonumber(aMinutesStr)
	if not(minutes) then
		return nil, "Cannot parse number of minutes"
	end
	return minutes
end





local function getEditDayType(aClient, aPath, aRequestHeaders)
	local dayType = tonumber(string.match(aPath, "/tariffPlan/editDayType/(%d+)"))
	if not(dayType) then
		return httpResponse.sendError(aClient, 400, "Invalid dayType parameter")
	end
	if not(tariffPlan.dayTypeSchedules[dayType]) then
		return httpResponse.sendError(aClient, 400, "No such dayType")
	end
	local body = require("Templates").tariffPlanEditDayType({
		currentTime = os.time(),
		dayType = dayType,
		dayTypeSchedule = tariffPlan.dayTypeSchedules[dayType],
	})
	httpResponse.send(aClient, "200 OK", nil, body)
end





local function getTariffPlan(aClient)
	local body = require("Templates").tariffPlan({
		currentTime = os.time(),
		seasons = tariffPlan.seasons,
		dayTypeSchedules = tariffPlan.dayTypeSchedules,
		exceptionDates = tariffPlan.exceptionDates,
	})
	httpResponse.send(aClient, "200 OK", nil, body)
end





local function postAddNewDayType(aClient)
	tariffPlan.addNewDayType()
	return httpResponse.sendRedirect(aClient, "/tariffPlan")
end





local function postAddNewDayTypeSlot(aClient, aRequestHeaders)
	-- Parse the inputs:
	local body = httpRequest.readBody(aClient, aRequestHeaders)
	local m = multipart(body, aRequestHeaders["content-type"])
	local startMinute, errStartMinute = parseMinutes((m:get("startMinute") or {}).value)
	local endMinute, errEndMinute = parseMinutes((m:get("endMinute") or {}).value)
	local multiplier, errMultiplier = tonumber((m:get("multiplier") or {}).value)
	local dayType = tonumber((m:get("dayType") or {}).value)

	-- Check validity:
	if not(startMinute and endMinute and multiplier and dayType) then
		return httpResponse.sendError(aClient, 400, string.format(
			[[Missing required fields:<br />
			dayType = %s<br />
			startMinute = %s (%s)<br />
			endMinute = %s (%s)<br />
			multiplier = %s (%s)
			]],
			tostring(dayType),
			tostring(startMinute), errStartMinute or "no error",
			tostring(endMinute), errEndMinute or "no error",
			tostring(multiplier), errMultiplier or "no error"
		))
	end
	if not(tariffPlan.dayTypeSchedules[dayType]) then
		return httpResponse.sendError(aClient, 400, "No such dayType")
	end

	-- Add:
	tariffPlan.addNewDayTypeSlot(dayType, startMinute, endMinute, multiplier)
	return httpResponse.sendRedirect(aClient, "/tariffPlan/editDayType/" .. dayType)
end





local function postAddNewSeason(aClient, aRequestHeaders)
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
		if (aPath == "/tariffPlan") then
			return getTariffPlan(aClient)
		elseif (aPath:match("/tariffPlan/editDayType")) then
			return getEditDayType(aClient, aPath, aRequestHeaders)
		end
	end,


	post = function(aClient, aPath, aRequestHeaders)
		if (aPath == "/tariffPlan/addNewDayType") then
			return postAddNewDayType(aClient, aRequestHeaders)
		elseif (aPath == "/tariffPlan/addNewSeason") then
			return postAddNewSeason(aClient, aRequestHeaders)
		elseif (aPath == "/tariffPlan/editDayType/addNewSlot") then
			return postAddNewDayTypeSlot(aClient, aRequestHeaders)
		end
	end,
}
