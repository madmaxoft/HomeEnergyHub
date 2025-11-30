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
	seasons = {},  -- Array-table of {startDate = "YYYY-MM-DD", endDate = "YYYY-MM-DD", workdayType = dayType, weekendType = dayType, notes = ...}
	dayTypeSchedules = {},  -- Dict-table of dayType -> array-table of {startMinute = ..., endMinute = ..., multiplier = ...}
	exceptionDates = {},  -- Dict-table of "YYYY-MM-DD" -> dayType
	SECONDS_PER_HOUR = 60 * 60,
	SECONDS_PER_DAY = 24 * 60 * 60,
}





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
		if (season.startDate >= aStartDateYmd) then
			if (season.endDate <= aEndDateYmd) then
				-- This season is completely contained in the new season, remove it:
				M.seasons[i] = nil
			elseif (season.startDate <= aEndDateYmd) then
				-- This season's start is covered by the new season, adjust it:
				season.startDate = utils.nextDayYmd(aEndDateYmd)
			end
		end
		if (season.endDate <= aEndDateYmd) then
			if (season.endDate >= aStartDateYmd) then
				-- This season's end is covered by the new season, adjust it:
				season.endDate = utils.prevDayYmd(aStartDateYmd)
			end
		end
		if ((season.startDate < aStartDateYmd) and (season.endDate > aEndDateYmd)) then
			-- The new season is completely covered in the old season, break the old season in two:
			n = n + 1
			seasons[n] = {
				startDate = season.startDate,
				endDate = utils.prevDayYmd(aStartDateYmd),
				workdayDayType = season.workdayDayType,
				weekendDayType = season.weekendDayType,
			}
			season.startDate = utils.nextDayYmd(aEndDateYmd)
		end
		if (M.seasons[i]) then
			n = n + 1
			seasons[n] = season
		end
	end
	seasons[n + 1] = {
		startDate = aStartDateYmd,
		endDate = aEndDateYmd,
		workdayDayType = aWorkdayDayType,
		weekendDayType = aWeekendDayType,
	}
	seasons.n = n + 1
	M.seasons = seasons
	M.sortSeasons()

	-- Update in the DB:
	db.saveTariffPlanSeasons(M.seasons)
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
		if ((season.startDate <= ymd) and (ymd <= season.endDate)) then
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
		M.exceptionDates[ed.date] = ed
	end
end





--- Sorts the in-memory seasons representation
function M.sortSeasons()
	table.sort(M.seasons, function (aSeason1, aSeason2)
		return (aSeason1.startDate < aSeason2.startDate)
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
