-- Handlers/tariffPlanUI.lua

--[[
Implements the handlers for the /tariffPlan... endpoints, used to view and edit the tariff plan
--]]

local db = require("db")
local multipart = require("multipart")
local tariffPlan = require("tariffPlan")
local utils = require("utils")




--- Array-table of { multiplier, {r, g, b} } that defines the color scheme for the multiplier graph
-- MUST be sorted by multiplier
local gMultiplierColors =
{
	{ 0.5,  {0x00, 0x7f, 0x00}, },
	{ 0.9,  {0x7f, 0xff, 0x7f}, },
	{ 1.0,  {0xff, 0xff, 0xff}, },
	{ 1.1,  {0xff, 0x7f, 0x7f}, },
	{ 1.25, {0xff, 0x00, 0x00}, },
}
gMultiplierColors.n = #gMultiplierColors





--- Returns an SVG representation of the color specified as an array-table or {r, b, g}
-- Doesn't prepend the '#', returns just the RRGGBB hex value
local function formatColor(aColorTable)
	assert(type(aColorTable) == "table")
	assert(type(aColorTable[1]) == "number")
	assert(type(aColorTable[2]) == "number")
	assert(type(aColorTable[3]) == "number")

	return string.format("%02x%02x%02x", aColorTable[1], aColorTable[2], aColorTable[3])
end





--- Returns linear interpolation between the two values by the specified factor
local function lerp(aValue1, aValue2, aFactor)
	assert(type(aValue1) == "number")
	assert(type(aValue2) == "number")
	assert(type(aFactor) == "number")

	return aValue1 + aFactor * (aValue2 - aValue1)
end





--- Returns a color to be used for the specified multiplier in the graph
-- Uses lerp between gMultiplierColors[]
local function multiplierToGraphColor(aMultiplier)
	assert(type(aMultiplier) == "number")

	if (aMultiplier <= gMultiplierColors[1][1]) then
		-- Multiplier is smaller than the smallest in the colorscheme:
		return formatColor(gMultiplierColors[1][2])
	end
	local idx = 1
	while ((idx < gMultiplierColors.n) and (gMultiplierColors[idx][1] < aMultiplier)) do
		idx = idx + 1
	end
	if (idx >= gMultiplierColors.n) then
		-- Multiplier is larger than the largest in the colorscheme:
		return formatColor(gMultiplierColors[gMultiplierColors.n][2])
	end
	assert(idx > 1)
	assert(idx <= gMultiplierColors.n)
	local factor = (aMultiplier - gMultiplierColors[idx - 1][1]) / (gMultiplierColors[idx][1] - gMultiplierColors[idx - 1][1])
	return formatColor({
		lerp(gMultiplierColors[idx - 1][2][1], gMultiplierColors[idx][2][1], factor),
		lerp(gMultiplierColors[idx - 1][2][2], gMultiplierColors[idx][2][2], factor),
		lerp(gMultiplierColors[idx - 1][2][3], gMultiplierColors[idx][2][3], factor),
	})
end





return {
	--- Returns an SVG graph of the specified DayType
	getDayTypeGraph = function(aRequest, aResponse)
		-- Parse params from the URL:
		local path, query = aRequest:parsedPathAndQuery()
		local dayType = tonumber(query.dayType)
		local width = tonumber(query.width) or 500
		local height = tonumber(query.height) or 150
		if not(dayType) then
			return aResponse:sendError(400, "Missing 'dayTypeParam' parameter")
		end

		-- Draw the graph:
		if not(tariffPlan.dayTypeSchedules[dayType]) then
			return aResponse:sendError(400, "No such daytype")
		end
		local graph = {
			string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', width, height)
		}
		local n = 1
		for _, slot in ipairs(tariffPlan.dayTypeSchedules[dayType]) do
			local left = slot.startMinute * width / 1440
			local right = slot.endMinute * width / 1440
			n = n + 1
			graph[n] = string.format(
				'<rect x="%.2f" y="%d" width="%.2f" height="%d" fill="#%s"/>',
				left, 0, right - left, height, multiplierToGraphColor(slot.multiplier)
			)
		end
		for hr = 0, 24 do
			local x = hr * width / 24
			n = n + 1
			graph[n] = string.format(
				'<line x1="%.2f" y1="0" x2="%.2f" y2="%d" style="stroke:#7f7f7f;stroke-width:1px" />',
				x, x, height
			)
		end
		n = n + 1
		graph[n] = "</svg>"

		-- Send the resulting SVG data to the client:
		local svgString = table.concat(graph, "\n")
		aResponse:sendRawDataWithLength(svgString, "image/svg+xml")
	end,





	getEditDayType = function(aRequest, aResponse)
		local dayType = tonumber(string.match(aRequest:parsedPathAndQuery(), "/tariffPlan/editDayType/(%d+)"))
		if not(dayType) then
			return aResponse:sendError(400, "Invalid dayType parameter")
		end
		if not(tariffPlan.dayTypeSchedules[dayType]) then
			return aResponse:sendError(400, "No such dayType")
		end
		aResponse:sendTemplate("tariffPlanEditDayType", {
			currentTime = os.time(),
			dayType = dayType,
			dayTypeSchedule = tariffPlan.dayTypeSchedules[dayType],
		})
	end,





	--- Exports the entire tariffPlan data into a single source file that can then be imported using postImport()
	getExport = function(aRequest, aResponse)
		aResponse:setHeader("Content-Disposition", "attachment; filename=\"tariffPlan.txt\"")
		aResponse:sendRawDataWithLength(tariffPlan.export(), "text/plain")
	end,





	getImport = function(aRequest, aResponse)
		aResponse:sendTemplate("tariffPlanImport", {})
	end,





	getTariffPlan = function(aRequest, aResponse)
		aResponse:sendTemplate("tariffPlan", {
			currentTime = os.time(),
			seasons = tariffPlan.seasons,
			dayTypeSchedules = tariffPlan.dayTypeSchedules,
			exceptionDates = tariffPlan.exceptionDates,
		})
	end,





	postAddNewDayType = function(aRequest, aResponse)
		local dayType = tariffPlan.addNewDayType()
		if (dayType) then
			return aResponse:sendRedirect("/tariffPlan/editDayType/" .. dayType)
		end
		return aResponse:sendRedirect("/tariffPlan")
	end,





	postAddNewDayTypeSlot = function (aRequest, aResponse)
		-- Parse the inputs:
		local m = aRequest:formData() or {}
		local startMinute, errStartMinute = utils.parseMinutes(m.startMinute)
		local endMinute, errEndMinute = utils.parseMinutes(m.endMinute)
		local multiplier, errMultiplier = tonumber(m.multiplier)
		local dayType = tonumber(m.dayType)

		-- Check validity:
		if not(startMinute and endMinute and multiplier and dayType) then
			return aResponse:sendError(400, string.format(
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
			return aResponse:sendError(400, "No such dayType")
		end

		-- Add:
		tariffPlan.addNewDayTypeSlot(dayType, startMinute, endMinute, multiplier)
		return aResponse:sendRedirect("/tariffPlan/editDayType/" .. dayType)
	end,





	postAddNewExceptionDate = function(aRequest, aResponse)
		-- Parse the inputs:
		local m = aRequest:formData() or {}
		local exceptionDate = m.exceptionDate
		local dayType = tonumber(m.dayType)
		if not(exceptionDate and dayType) then
			return aResponse:sendError(400, "Missing required fields")
		end

		-- Check the validity:
		if not(utils.checkYmdDate(exceptionDate)) then
			return aResponse:sendError(400, "Invalid exception date")
		end
		if not(tariffPlan.dayTypeSchedules[dayType]) then
			return aResponse:sendError(400, "No such DayType")
		end

		-- Add the exception:
		tariffPlan.addNewExceptionDate(exceptionDate, dayType)
		return aResponse:sendRedirect("/tariffPlan")
	end,





	postAddNewSeason = function(aRequest, aResponse)
		-- Parse the inputs:
		local m = aRequest:formData() or {}
		local startDate = m.startDate
		local endDate = m.endDate
		local workdayDayType = tonumber(m.workdayDayType)
		local weekendDayType = tonumber(m.weekendDayType)

		-- Check validity:
		if not(startDate and endDate and workdayDayType and weekendDayType) then
			return aResponse:sendError(400, string.format(
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
			return aResponse:sendError(400, "Invalid startDate or endDate")
		end
		if not(tariffPlan.dayTypeSchedules[workdayDayType] and tariffPlan.dayTypeSchedules[weekendDayType]) then
			return aResponse:sendError(400, "Invalid day type")
		end

		-- Add:
		tariffPlan.addNewSeason(startDate, endDate, workdayDayType, weekendDayType)
		return aResponse:sendRedirect("/tariffPlan")
	end,





	postImport = function(aRequest, aResponse)
		-- Parse the inputs:
		local m = aRequest:formData() or {}
		local tariffPlanFileContents = m.tariffPlanFile
		if not(tariffPlanFileContents) then
			return aResponse.sendError(400, "No file contents")
		end

		-- Parse the file:
		local seasons, dayTypes, exceptionDates = tariffPlan.parseFile(tariffPlanFileContents)
		if not(seasons) then
			return aResponse:sendError(400, tostring(dayTypes))
		end

		-- Replace the plan:
		tariffPlan.replace(seasons, dayTypes, exceptionDates)
		return aResponse:sendRedirect("/tariffPlan")
	end,





	postRemoveExceptionDate = function(aRequest, aResponse)
		-- Parse the inputs:
		local m = aRequest:formData() or {}
		local exceptionDate = m.exceptionDate

		-- Check validity:
		if not(exceptionDate) then
			return aResponse:sendError(400, "Missing required fields")
		end
		if not(utils.checkYmdDate(exceptionDate)) then
			return aResponse:sendError(400, "Invalid exceptionDate")
		end
		if not(tariffPlan.exceptionDates[exceptionDate]) then
			return aResponse:sendError(400, "Not an exception date")
		end

		-- Remove:
		tariffPlan.removeExceptionDate(exceptionDate)
		return aResponse:sendRedirect("/tariffPlan")
	end,
}
