-- tariffPlan.lua

--[[
Implements scheduled electricity price multipliers.
Handles workday/weekend schedules with seasonal periods and exceptions.
The plan is stored in the DB, loaded into memory on startup and handled completely from memory in runtime.
The root plan is defined by individual seasons. Each season has a start date, end date and a default
day type for workday and weekend. A day type specifies the actual price multiplier
schedule (0:00 - 3:00 price 0.85 etc.)
An additional exceptionDates array stores specific days that have a different type than what they would
normally be based on workday / weekend. This is used for handling public holidays.
--]]





local db = require("db")
local utils = require("utils")





--- The module interface, returned by requiring this module:
local M = {
	seasons = {},  -- Array-table of {startDateYmd = "YYYY-MM-DD", endDateYmd = "YYYY-MM-DD", workdayType = dayType, weekendType = dayType, notes = ...}
	dayTypeSchedules = {},  -- Dict-table of dayType -> array-table of {startMinute = ..., endMinute = ..., multiplier = ...}
	exceptionDates = {},  -- Dict-table of "YYYY-MM-DD" -> {exceptionDateYmd = "YYYY-MM-DD", dayType = ...}
	SECONDS_PER_HOUR = 60 * 60,
	SECONDS_PER_DAY = 24 * 60 * 60,
}





--- Header expected at the start of the tariffPlan exported file (checked when importing):
local gExportFileHeader = "HomeEnergyHub-TariffPlan\n"





--- Adds a new dayType
-- The ID is auto-incremented in the DB
-- Returns the new DayType
function M.addNewDayType()
	local res = db.addNewTariffPlanDayType()
	M.reloadFromDB()
	return res
end





--- Adds a new time slot to the specified DayType's schedule
-- Modifies existing timeslots so that there's no overlap between them and the new slot
-- Ignores invalid requests (time out-of-bound)
function M.addNewDayTypeSlot(aDayType, aStartMinute, aEndMinute, aMultiplier)
	assert(type(aDayType) == "number")
	assert(type(aStartMinute) == "number")
	assert(type(aEndMinute) == "number")
	assert(type(aMultiplier) == "number")

	-- Check the time interval validity:
	if (aStartMinute > aEndMinute) then
		-- Swap the bounds:
		aStartMinute, aEndMinute = aEndMinute, aStartMinute
	end
	if ((aStartMinute > 24 * 60) or (aEndMinute <= 0)) then
		print(string.format(
			"[tariffPlan] Requested addition of an out-of-bound timeslot %d - %d into dayType %d",
			aStartMinute, aEndMinute, aDayType
		))
		return
	end

	-- First change our in-memory representation of the schedule:
	local numSlots = M.dayTypeSchedules[aDayType].n or #(M.dayTypeSchedules[aDayType])
	local slots = {}
	local n = 0
	for i = 1, numSlots do
		local slot = M.dayTypeSchedules[aDayType][i]
		if (slot.startMinute >= aStartMinute) then
			if (slot.endMinute <= aEndMinute) then
				-- This slot is completely contained in the new slot, remove it:
				M.dayTypeSchedules[aDayType][i] = nil
			elseif (slot.startMinute <= aEndMinute) then
				-- This slot's start is covered by the new slot, adjust it:
				slot.startMinute = aEndMinute
			end
		end
		if (slot.endMinute <= aEndMinute) then
			if (slot.endMinute >= aStartMinute) then
				-- This slot's end is covered by the new slot, adjust it:
				slot.endMinute = aStartMinute
			end
		end
		if ((slot.startMinute < aStartMinute) and (slot.endMinute > aEndMinute)) then
			-- The new slot is completely covered in the old slot, break the old slot in two:
			n = n + 1
			slots[n] = {
				startMinute = slot.startMinute,
				endMinute = aStartMinute,
				multiplier = slot.multiplier,
			}
			slot.startMinute = aEndMinute
		end
		if (M.dayTypeSchedules[aDayType][i]) then
			n = n + 1
			slots[n] = slot
		end
	end
	slots[n + 1] = {
		startMinute = aStartMinute,
		endMinute = aEndMinute,
		multiplier = aMultiplier,
	}
	slots.n = n + 1
	M.dayTypeSchedules[aDayType] = slots
	M.sortDayTypeSchedule(slots)

	-- Update in the DB:
	db.saveTariffPlanDayTypeSchedule(aDayType, slots)
end





--- Adds a new exceptionDate, or overwrites an existing one
function M.addNewExceptionDate(aExceptionDateYmd, aDayType)
	assert(type(aExceptionDateYmd) == "string")
	assert(type(aDayType) == "number")
	assert(utils.checkYmdDate(aExceptionDateYmd))  -- is date valid?
	assert(M.dayTypeSchedules[aDayType])           -- is daytype valid?

	db.addNewTariffPlanExceptionDate(aExceptionDateYmd, aDayType)
	M.reloadFromDB()
end





--- Adds a new season
-- Modifies existing seasons so that there's no overlap between them and the new season
function M.addNewSeason(aStartDateYmd, aEndDateYmd, aWorkdayDayType, aWeekendDayType)
	assert(type(aStartDateYmd) == "string")
	assert(type(aEndDateYmd) == "string")
	assert(aStartDateYmd < aEndDateYmd)
	assert(type(aWorkdayDayType) == "number")
	assert(type(aWeekendDayType) == "number")

	-- First change our representation of the seasons:
	local numSeasons = M.seasons.n
	local seasons = {}
	local n = 0
	for i = 1, numSeasons do
		local season = M.seasons[i]
		if (season.startDateYmd >= aStartDateYmd) then
			if (season.endDateYmd <= aEndDateYmd) then
				-- This season is completely contained in the new season, remove it:
				M.seasons[i] = nil
			elseif (season.startDateYmd <= aEndDateYmd) then
				-- This season's start is covered by the new season, adjust it:
				season.startDateYmd = utils.nextDayYmd(aEndDateYmd)
			end
		end
		if (season.endDateYmd <= aEndDateYmd) then
			if (season.endDateYmd >= aStartDateYmd) then
				-- This season's end is covered by the new season, adjust it:
				season.endDateYmd = utils.prevDayYmd(aStartDateYmd)
			end
		end
		if ((season.startDateYmd < aStartDateYmd) and (season.endDateYmd > aEndDateYmd)) then
			-- The new season is completely covered in the old season, break the old season in two:
			n = n + 1
			seasons[n] = {
				startDateYmd = season.startDateYmd,
				endDateYmd = utils.prevDayYmd(aStartDateYmd),
				workdayDayType = season.workdayDayType,
				weekendDayType = season.weekendDayType,
			}
			season.startDateYmd = utils.nextDayYmd(aEndDateYmd)
		end
		if (M.seasons[i]) then
			n = n + 1
			seasons[n] = season
		end
	end
	seasons[n + 1] = {
		startDateYmd = aStartDateYmd,
		endDateYmd = aEndDateYmd,
		workdayDayType = aWorkdayDayType,
		weekendDayType = aWeekendDayType,
	}
	seasons.n = n + 1
	M.seasons = seasons
	M.sortSeasons()

	-- Update in the DB:
	db.saveTariffPlanSeasons(M.seasons)
end





--- Returns true if the specified tariff plan is valid
-- Returns nil and an error message if not valid
-- This should be used before replacing the current global tariffPlan with completely new values
function M.checkValidity(aSeasons, aDayTypes, aExceptionDates)
	M.sortSeasons(aSeasons)

	-- Check if all seasons' dayTypes are defined
	for idx, season in ipairs(aSeasons) do
		if not(aDayTypes[season.workdayDayType]) then
			return nil, string.format("DayType %d is undefined, encountered in season %d: %s - %s",
				season.workdayDayType, idx, season.startDateYmd, season.endDateYmd
			)
		end
		if not(aDayTypes[season.weekendDayType]) then
			return nil, string.format("DayType %d is undefined, encountered in season %d: %s - %s",
				season.weekendDayType, idx, season.startDateYmd, season.endDateYmd
			)
		end
	end

	-- Check that seasons don't overlap:
	local lastEndDateYmd = ""
	local lastSeason = aSeasons[1]
	for idx, season in ipairs(aSeasons) do
		if (season.startDateYmd < lastEndDateYmd) then
			return nil, string.format(
				"Season %d (%s - %s) overlaps the previous season (%s - %s)",
				idx, season.startDateYmd, season.endDateYmd,
				lastSeason.startDateYmd, lastSeason.endDateYmd
			)
		end
		lastEndDateYmd = season.endDateYmd
		lastSeason = season
	end

	-- Check all exception dates for validity and their dayTypes:
	for excDate, def in pairs(aExceptionDates) do
		if not(utils.checkYmdDate(excDate)) then
			return nil, string.format("Exception date %s is not valid", tostring(excDate))
		end
		if not(def.dayType) then
			return nil, string.format("Exception date %s doesn't define a dayType", tostring(excDate))
		end
		if not(aDayTypes[def.dayType]) then
			return nil, string.format(
				"Exception date %s points to an unknown dayType %d",
				tostring(excDate), tostring(def.dayType)
			)
		end
	end

	-- All seems OK:
	return true
end





--- Exports the tariff plan, so that it can be imported at another instance
-- The returned string can be parsed with M.parseFile()
function M.export()
	local body = {gExportFileHeader, "v1\n"}
	local n = 2
	for _, season in ipairs(M.seasons) do
		n = n + 1
		body[n] = string.format(
			"s:%s:%s:%d:%d\n",
			season.startDateYmd, season.endDateYmd, season.workdayDayType, season.weekendDayType
		)
	end
	for dayType, schedule in pairs(M.dayTypeSchedules) do
		for _, slot in ipairs(schedule) do
			n = n + 1
			body[n] = string.format(
				"d:%d:%d:%d:%f\n",
				dayType, slot.startMinute, slot.endMinute, slot.multiplier
			)
		end
	end
	for exceptionDateYmd, def in pairs(M.exceptionDates) do
		n = n + 1
		body[n] = string.format("e:%s:%d\n", exceptionDateYmd, def.dayType)
	end
	return table.concat(body)
end





--- Produces a full multiplier schedule for the interval [startTs, endTs]
-- Returns an array-table of {startTimestamp = ..., endTimestamp = ..., multiplier = ...}
-- Timestamps for which there's no schedule are not included in the schedule
function M.generateSchedule(aStartTs, aEndTs)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")

	local schedule = {}
	local n = 0
	local interval = 15 * 60
	local currentTs = aStartTs - (aStartTs % interval)

	while (currentTs <= aEndTs) do
		local dailySchedule = M.getDailySchedule(currentTs)
		if (dailySchedule) then
			local dayStart = currentTs - (currentTs % M.SECONDS_PER_DAY)
			for _, period in ipairs(dailySchedule) do
				local periodStartTs = dayStart + period.startMinute * 60
				local periodEndTs = dayStart + period.endMinute * 60
				if ((periodEndTs >= aStartTs) and (periodStartTs <= aEndTs)) then
					n = n + 1
					schedule[n] = {startTimestamp = periodStartTs, endTimestamp = periodEndTs, multiplier = period.multiplier}
				end
			end
		end
		currentTs = currentTs + M.SECONDS_PER_DAY
	end
	schedule.n = n

	return schedule
end





--- Returns the daily schedule table for a given timestamp
-- Returns nil if no schedule for the specified day
function M.getDailySchedule(aTimestamp)
	local dayType = M.getDayType(aTimestamp)
	if not(dayType) then
		return nil
	end
	return M.dayTypeSchedules[dayType]
end





--- Returns the daytype for the day represented by the specified timestamp
-- Returns nil if no schedule for this day
function M.getDayType(aTimestamp)
	-- First check the exceptions:
	local ymd = os.date("%Y-%m-%d", aTimestamp)
	local exc = M.exceptionDates[ymd]
	if (exc) then
		return exc.dayType
	end

	-- Not an exception, go by the schedule:
	local weekday = os.date("*t", aTimestamp).wday
	local isWeekend = (weekday == 1) or (weekday == 7)
	for _, season in ipairs(M.seasons) do
		if ((season.startDateYmd <= ymd) and (ymd <= season.endDateYmd)) then
			if (isWeekend) then
				return season.weekendDayType
			else
				return season.workdayDayType
			end
		end
	end

	-- Not found at all:
	return nil
end





--- Returns the schedules, dayTypes and exceptionDates tables defining the tariff plan described in the input string
-- Used to import back data exported by getExport()
-- Returns nil and error message on failure
function M.parseFile(aTariffPlanFileContents)
	local hdrLen = gExportFileHeader:len()
	local hdr = aTariffPlanFileContents:sub(1, hdrLen)
	if (hdr ~= gExportFileHeader) then
		return nil, string.format(
			"Not an exported tariffPlan, header mismatch. Expected %s, got %s",
			gExportFileHeader, tostring(hdr)
		)
	end
	local version = aTariffPlanFileContents:sub(hdrLen + 1, hdrLen + 3)
	if (version ~= "v1\n") then
		return nil, string.format(
			"Bad export file version, expected %d, got %s",
			"v1\n", tostring(version)
		)
	end
	local seasons, dayTypes, exceptionDates = {}, {}, {}
	local n = 0
	aTariffPlanFileContents:sub(hdrLen + 4):gsub("(.-)\n", function (aLine)
		local t = aLine:sub(1, 2)
		if (t == "s:") then
			local startDateYmd, endDateYmd, workdayDayType, weekendDayType = aLine:match("s:([^:]*):([^:]*):(%d*):(%d*)")
			workdayDayType = tonumber(workdayDayType)
			weekendDayType = tonumber(weekendDayType)
			if (
				not(utils.checkYmdDate(startDateYmd)) or
				not(utils.checkYmdDate(endDateYmd)) or
				not(workdayDayType) or
				not(weekendDayType)
			) then
				return nil, "Failed to parse schedule line: " .. tostring(aLine)
			end
			n = n + 1
			seasons[n] =
			{
				startDateYmd = startDateYmd,
				endDateYmd = endDateYmd,
				workdayDayType = workdayDayType,
				weekendDayType = weekendDayType
			}
		elseif (t == "d:") then
			local dayType, startMinute, endMinute, multiplier = aLine:match("d:(%d*):(%d*):(%d*):(.*)")
			dayType = tonumber(dayType)
			startMinute = tonumber(startMinute)
			endMinute = tonumber(endMinute)
			multiplier = tonumber(multiplier)
			if not(dayType and startMinute and endMinute and multiplier) then
				return nil, "Failed to parse dayType line: " .. tostring(aLine)
			end
			dayTypes[dayType] = dayTypes[dayType] or {n = 0}
			dayTypes[dayType].n = dayTypes[dayType].n + 1
			dayTypes[dayType][dayTypes[dayType].n] =
			{
				dayType = dayType,
				startMinute = startMinute,
				endMinute = endMinute,
				multiplier = multiplier,
			}
		elseif (t == "e:") then
			local excDate, dayType = aLine:match("e:([^:]*):(%d*)")
			dayType = tonumber(dayType)
			if not(utils.checkYmdDate(excDate) and dayType) then
				return nil, "Failed to parse exceptionDates line: " .. tostring(aLine)
			end
			exceptionDates[excDate] =
			{
				exceptionDateYmd = excDate,
				dayType = dayType,
			}
		else
			return nil, "Corrupt file, unknown line type: " .. t
		end
	end)
	seasons.n = n
	local isOK, msg = M.checkValidity(seasons, dayTypes, exceptionDates)
	if not(isOK) then
		return nil, "Invalid tariff plan: " .. tostring(msg)
	end

	return seasons, dayTypes, exceptionDates
end





--- Loads the plan from the DB into memory
function M.reloadFromDB()
	M.seasons = db.getTariffPlanSeasons()
	M.sortSeasons()

	-- Convert dayTypeSchedules array returned from the DB into a dict-table
	-- The DB returns multiple rows of {dayType, startMinute, endMinute, multiplier}, we need to collapse
	-- those into a single array-table:
	local dtsch = {}
	local dbDayTypeSchedules = db.getTariffPlanDayTypeSchedules()
	for _, dt in ipairs(dbDayTypeSchedules) do
		local sch = dtsch[dt.dayType] or {n = 0}
		sch.n = sch.n + 1
		sch[sch.n] = dt
		dtsch[dt.dayType] = sch
	end
	M.dayTypeSchedules = dtsch

	-- Convert exceptionDates array returned from the DB into a dict-table:
	M.exceptionDates = {}
	local exceptionDates = db.getTariffPlanExceptionDates()
	for _, ed in ipairs(exceptionDates) do
		M.exceptionDates[ed.exceptionDateYmd] = ed
	end

	-- Sanity-check and log errors:
	local isOK, msg = M.checkValidity(M.seasons, M.dayTypeSchedules, M.exceptionDates)
	if not(isOK) then
		print("[tariffPlan] DB contains invalid plan: " .. tostring(msg))
	end
end





--- Replaces the current global tariff plan with the specified data
-- Refuses to replace with an invalid plan
-- Returns true on success, nil and error message on failure
function M.replace(aSeasons, aDayTypeSchedules, aExceptionDates)
	assert(type(aSeasons) == "table")
	assert(type(aDayTypeSchedules) == "table")
	assert(type(aExceptionDates) == "table")

	-- Check if the plan is valid:
	local isOK, msg = M.checkValidity(aSeasons, aDayTypeSchedules, aExceptionDates)
	if not(isOK) then
		return nil, "Cannot replace tariffPlan: " .. tostring(msg)
	end

	-- Replace the in-memory representation:
	M.seasons = aSeasons
	M.dayTypeSchedules = aDayTypeSchedules
	M.exceptionDates = aExceptionDates

	-- Replace in the DB:
	db.replaceTariffPlanSeasons(aSeasons)
	db.replaceTariffPlanDayTypeSchedules(aDayTypeSchedules)
	db.replaceTariffPlanExceptionDates(aExceptionDates)
end





--- Removes the specified exceptionDate
function M.removeExceptionDate(aExceptionDateYmd)
	assert(type(aExceptionDateYmd) == "string")

	db.removeTariffPlanExceptionDate(aExceptionDateYmd)
	M.exceptionDates[aExceptionDateYmd] = nil
end





--- Sorts the seasons representation, either the given one or the global
function M.sortSeasons(aSeasons)
	table.sort(aSeasons or M.seasons, function (aSeason1, aSeason2)
		return (aSeason1.startDateYmd < aSeason2.startDateYmd)
	end)
end





--- Sorts the in-memory daytype schedule representation
function M.sortDayTypeSchedule(aDayTypeSchedule)
	-- Check that all slots are valid:
	for _, slot in ipairs(aDayTypeSchedule) do
		assert(type(slot.startMinute) == "number")
		assert(type(slot.endMinute) == "number")
		assert(type(slot.multiplier) == "number")
	end

	-- Sort
	table.sort(aDayTypeSchedule, function (aSlot1, aSlot2)
		return (aSlot1.startMinute < aSlot2.startMinute)
	end)
end





-- Initialize: load from the DB
M.reloadFromDB()





return M
