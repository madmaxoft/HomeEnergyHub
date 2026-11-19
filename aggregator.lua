-- aggregator.lua

--[[
Implements the data aggregation.

The sensors should call require("aggregator").updateLatestAggregate() whenever a new datapoint has been
stored in the DB.

External tools can use require("aggregator").aggregate(startTimeStamp, endTimeStamp) to (re-)aggregate
all aggregated values within the specified timestamp range.
--]]





local db = require("db")
local log = require("logger").log





--- The API returned by this module
local aggregator = {}





--- All aggregators' descriptions:
local gAggregators =
{
	{tableName = "ElectricityConsumptionAggregate1min", interval = 60},
	{tableName = "ElectricityConsumptionAggregate15min", interval = 15 * 60},
	{tableName = "ElectricityConsumptionAggregateDay", interval = 24 * 60 * 60},
}





--- Computes the aggregation for a given bucket using energy deltas
-- Returns a table suitable for db.insertAggregate or nil if impossible
local function calcAggregationForBucket(aStartTs, aEndTs)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")

	local energy = db.aggregationBucketEnergyAndPower(aStartTs, aEndTs)
	if not(energy) then
		return nil
	end
	return {
		energyTotal = energy.energyTotal or 0,
		energyA = energy.energyA,
		energyB = energy.energyB,
		energyC = energy.energyC,
		minPowerTotal = energy.minPowerTotal,
		minPowerA = energy.minPowerA,
		minPowerB = energy.minPowerB,
		minPowerC = energy.minPowerC,
		maxPowerTotal = energy.maxPowerTotal,
		maxPowerA = energy.maxPowerA,
		maxPowerB = energy.maxPowerB,
		maxPowerC = energy.maxPowerC,
	}
end





--- (Re-)aggregates all the data in the specified interval
-- aProgressCallback is called periodically with parameters aStartTimeStamp, aEndTimeStamp, aCurrentTimeStamp, aIntervalSeconds
-- Note that the callback may be called with aCurrentTimeStamp below aStartTimeStamp
-- If the callback returns true, the aggregation is aborted
-- Returns true on success, nil and message on failure (or abort)
local function aggregateSingleInterval(aTableName, aIntervalSeconds, aStartTimeStamp, aEndTimeStamp, aProgressCallback)
	assert(type(aTableName) == "string")
	assert(type(aIntervalSeconds) == "number")
	assert(aIntervalSeconds > 0)
	assert(type(aStartTimeStamp) == "number")
	assert(type(aEndTimeStamp) == "number")

	local startTS = aStartTimeStamp - aStartTimeStamp % aIntervalSeconds
	local endTS = aEndTimeStamp - aEndTimeStamp % aIntervalSeconds
	for t = startTS, endTS, aIntervalSeconds do
		local agg = calcAggregationForBucket(t, t + aIntervalSeconds)
		if (agg) then
			db.insertAggregate(aTableName, t, agg, aIntervalSeconds)
		end
		if (aProgressCallback ~= nil) then
			if (aProgressCallback(aStartTimeStamp, aEndTimeStamp, t, aIntervalSeconds)) then
				return nil, "Aborted"
			end
		end
	end
	return true
end





--- (Re-)aggregates all the data in the specified interval
-- aProgressCallback is called periodically with parameters aStartTimeStamp, aEndTimeStamp, aCurrentTimeStamp, aCurrentInterval
-- Note that the callback may be called with aCurrentTimeStamp below aStartTimeStamp
-- If the callback returns true, the aggregation is aborted
-- Returns true on success, nil and message on failure (or abort)
function aggregator.aggregate(aStartTimeStamp, aEndTimeStamp, aProgressCallback)
	for _, target in ipairs(gAggregators) do
		local res, msg = aggregateSingleInterval(target.tableName, target.interval, aStartTimeStamp, aEndTimeStamp, aProgressCallback)
		if not(res) then
			return nil, tostring(msg)
		end
	end
	return true
end





--- Updates the latest aggregate in the DB based on the data already in the DB
-- Returns true on success, nil and message on failure
function aggregator.updateLastAggregate()
	local now = os.time()
	return aggregator.aggregate(now, now)
end





-- Export the local helper functions in order to facilitate testing:
aggregator.debug =
{
	calcAggregationForBucket = calcAggregationForBucket,
	aggregateSingleInterval = aggregateSingleInterval,
}

return aggregator
