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





--- The module interface, returned by requiring this module:
local M = {
	seasons = {},  -- Array-table of {startDate = "YYYY-MM-DD", endDate = "YYYY-MM-DD", workdayType = dayType, weekendType = dayType, notes = ...}
	dayTypeSchedules = {},  -- Dict-table of dayType -> array-table of {startMinute = ..., endMinute = ..., multiplier = ...}
	exceptionDates = {},  -- Dict-table of "YYYY-MM-DD" -> dayType
	SECONDS_PER_HOUR = 60 * 60,
	SECONDS_PER_DAY = 24 * 60 * 60,
}





--- Loads the plan from the DB into memory
function M.reloadFromDB()
	M.seasons = db.getTariffPlanSeasons()

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





--- Returns the daily schedule table for a given timestamp
-- Returns nil if no schedule for the specified day
function M.getDailySchedule(aTimestamp)
	local dayType = M.getDayType(aTimestamp)
	if not(dayType) then
		return nil
	end
	return M.dayTypeSchedules[dayType]
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





--- Calculates cost ratio of this plan vs fixed cost over historical data
-- Returns multiplier like 0.85 for 15% savings
function M.evaluateSavings(aStartTs, aEndTs, aEnergyData)
	local schedule = M.generateSchedule(aStartTs, aEndTs)
	local totalCostPlan, totalCostFixed = 0, 0

	for ts, kWh in pairs(aEnergyData) do
		local multiplier = schedule[ts] or 1.0
		totalCostPlan = totalCostPlan + kWh * aFixedCostPerKWh * multiplier
		totalCostFixed = totalCostFixed + kWh * aFixedCostPerKWh
	end

	return totalCostPlan / totalCostFixed
end





-- Initialize: load from the DB
M.reloadFromDB()





return M
