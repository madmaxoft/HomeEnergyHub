-- Handlers/tariffPlanUI.lua

--[[
Implements the handlers for the /tariffPlan... endpoints, used to view and edit the tariff plan
--]]

local db = require("db")
local httpResponse = require("httpResponse")
local httpRequest = require("httpRequest")
local multipart = require("multipart")
local tariffPlan = require("tariffPlan")
local utils = require("utils")





return {
	getTariffPlan = function(aClient, aPath, aRequestHeaders)
		local body = require("Templates").tariffPlan({
			currentTime = os.time(),
			seasons = tariffPlan.seasons,
			dayTypeSchedules = tariffPlan.dayTypeSchedules,
			exceptionDates = tariffPlan.exceptionDates,
		})
		httpResponse.send(aClient, "200 OK", nil, body)
	end,





	getEditDayType = function(aClient, aPath, aRequestHeaders)
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
	end,





	postAddNewDayType = function(aClient, aPath, aRequestHeaders)
		tariffPlan.addNewDayType()
		return httpResponse.sendRedirect(aClient, "/tariffPlan")
	end,





	postAddNewDayTypeSlot = function (aClient, aPath, aRequestHeaders)
		-- Parse the inputs:
		local body = httpRequest.readBody(aClient, aRequestHeaders)
		local m = multipart(body, aRequestHeaders["content-type"])
		local startMinute, errStartMinute = utils.parseMinutes((m:get("startMinute") or {}).value)
		local endMinute, errEndMinute = utils.parseMinutes((m:get("endMinute") or {}).value)
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
	end,





	postAddNewSeason = function(aClient, aPath, aRequestHeaders)
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
	end,
}
