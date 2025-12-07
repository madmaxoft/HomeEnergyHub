-- Handlers/savings.lua

--[[
Handles the "/savings" HTTP endpoint for displaying the savings based on the tariff plan
Accepts parameters:
	- "from": the timestamp from which to go into the past (or "now"). Default: "now"
	- "numdays": number of days to calculate. Default: 31
--]]





local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local db = require("db")
local tariffPlan = require("tariffPlan")





local M = {}
local SECONDS_PER_DAY = 24 * 60 * 60





--- Returns the energy value at the specified timestamp, as best approximated from the raw energy usage table
function M.energyStatusAt(aRawEnergyUsage, aTimeStamp)
	assert(type(aRawEnergyUsage) == "table")
	assert(type(aRawEnergyUsage[1]) == "table")

	-- If outside the data, return the end value:
	if (aTimeStamp <= aRawEnergyUsage[1].timeStamp) then
		return aRawEnergyUsage[1].energyTotal
	end
	local n = aRawEnergyUsage.n
	if (aTimeStamp >= aRawEnergyUsage[n].timeStamp) then
		return aRawEnergyUsage[n].energyTotal
	end

	-- Find the best value by binary-search:
	local lo = 1
	local hi = n
	while (hi - lo > 1) do
		local mid = math.floor((hi + lo) / 2)
		local ts = aRawEnergyUsage[mid].timeStamp
		if (ts < aTimeStamp) then
			lo = mid
		elseif (ts == aTimeStamp) then
			return aRawEnergyUsage[mid].energyTotal
		else
			hi = mid
		end
	end
	if (aRawEnergyUsage[lo].timeStamp == aTimeStamp) then
		return aRawEnergyUsage[lo].energyTotal
	end
	if (aRawEnergyUsage[hi].timeStamp == aTimeStamp) then
		return aRawEnergyUsage[hi].energyTotal
	end
	assert(aRawEnergyUsage[lo].timeStamp < aTimeStamp)
	assert(aRawEnergyUsage[hi].timeStamp > aTimeStamp)
	local tsDiff = aRawEnergyUsage[hi].timeStamp - aRawEnergyUsage[lo].timeStamp
	local enDiff = aRawEnergyUsage[hi].energyTotal - aRawEnergyUsage[lo].energyTotal
	return aRawEnergyUsage[lo].energyTotal + enDiff * (aTimeStamp - aRawEnergyUsage[lo].timeStamp) / tsDiff
end





--- Collects a per-day usage of electricity, based on the raw 15-minute data from the DB
-- aRawEnergyUsage is the DB-loaded array table of {timeStamp = ..., energyTotal = ...} sorted by timeStamp
-- Returns an array-table of {timeStamp = ..., dayYmd = ..., energyUsed = ...}
function M.collectDailyUsage(aFrom, aNumDays, aRawEnergyUsage)
	assert(type(aRawEnergyUsage) == "table")
	assert(type(aRawEnergyUsage[1]) == "table")

	local res = {}
	local n = 0
	local highestDayStart = aFrom - aFrom % SECONDS_PER_DAY
	local lowestDayStart = highestDayStart - aNumDays * SECONDS_PER_DAY
	local lastEnergyStatus = aRawEnergyUsage[aRawEnergyUsage.n].energyTotal
	for dayStart = highestDayStart, lowestDayStart, -SECONDS_PER_DAY do
		local nextDayStart = dayStart + SECONDS_PER_DAY
		n = n + 1
		res[n] =
		{
			timeStamp = dayStart,
			energyStatusAtStart = M.energyStatusAt(aRawEnergyUsage, dayStart),
			energyStatusAtEnd = lastEnergyStatus,
			dayYmd = os.date("%Y-%m-%d", dayStart + 10000),
		}
		res[n].energyUsed = res[n].energyStatusAtEnd - res[n].energyStatusAtStart
		lastEnergyStatus = res[n].energyStatusAtStart
	end
	res.n = n
	return res
end





--- Enriches aDailyUsage with the tariffPlanEnergyUsed member for each day
-- If there's no schedule for the day, assumes no tariff changes, gives same energy usage and adds a `hasNoSchedule` flag to the day
function M.applyTariffPlan(aDailyUsage, aRawEnergyUsage)
	for _, day in ipairs(aDailyUsage) do
		local dayStart = day.timeStamp
		local adjustedEnergyUsed = 0
		local schedule = tariffPlan.getDailySchedule(day.timeStamp)
		if (schedule) then
			for _, slot in ipairs(schedule) do
				local startEnergyStatus = M.energyStatusAt(aRawEnergyUsage, dayStart + slot.startMinute * 60)
				local endEnergyStatus   = M.energyStatusAt(aRawEnergyUsage, dayStart + slot.endMinute * 60)
				adjustedEnergyUsed = adjustedEnergyUsed + slot.multiplier * (endEnergyStatus - startEnergyStatus)
			end
			day.tariffPlanEnergyUsed = adjustedEnergyUsed
		else
			day.tariffPlanEnergyUsed = day.energyUsed
			day.hasNoSchedule = true
		end
	end
end





function M.get(aClient, aPath, aRequestHeaders)
	-- Parse path and query:
	local path, query = httpRequest.parseRequestPath(aPath)
	local from = tonumber(query.from) or os.time()
	local numDays = tonumber(query.numdays) or 31
	from = from - (from % SECONDS_PER_DAY)

	-- Process the energy usage from the DB:
	local rawEnergyUsage = db.load15MinEnergyUsage(from, numDays)
	local dailyUsage = M.collectDailyUsage(from, numDays, rawEnergyUsage)
	M.applyTariffPlan(dailyUsage, rawEnergyUsage)

	local body = require("Templates").savings({
		currentTime = os.time(),
		from = from,
		numDays = numDays,
		dailyUsage = dailyUsage,
	})
	httpResponse.send(aClient, "200 OK", nil, body)

end




return M
