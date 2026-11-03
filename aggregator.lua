-- aggregator.lua

--[[
Implements the data aggregation in background threads.
--]]





local copas = require("copas")
local db = require("db")
local log = require("logger").log
local perf = require("perf")





local aggregator =
{
	-- Pause switch, activated when remoteImport is underway
	shouldPause = false,

	--- Specifies whether to log performance in the aggregator loop
	shouldLogPerf = false,
}





--- Finds the next historical aggregation bucket
-- Returns startTs, endTs; or nil if no historical bucket remains
local function findNextAggregationBucket(aTargetTable, aIntervalSeconds, aCurrentBucket)
	assert(type(aTargetTable) == "string")
	assert(type(aIntervalSeconds) == "number")
	assert(type(aCurrentBucket) == "number")

	local minTs, maxTs = db.electricityConsumptionDataRange()
	if not(minTs) then
		return nil
	end

	local minBucket = minTs - minTs % aIntervalSeconds
	local nextBucket = db.aggregationProgress(aTargetTable)

	if not(nextBucket) then
		-- Initialize just before the current bucket, or at the latest raw bucket if older
		local maxBucket = maxTs - maxTs % aIntervalSeconds
		nextBucket = math.min(maxBucket, aCurrentBucket - aIntervalSeconds)
		db.setAggregationProgress(aTargetTable, nextBucket)
	end

	if ((nextBucket < minBucket) or (nextBucket >= aCurrentBucket)) then
		-- Nothing historical remains
		return nil
	end

	return nextBucket, nextBucket + aIntervalSeconds
end





--- Computes the aggregation for a given bucket using energy deltas
-- Returns a table suitable for db.insertAggregate or nil if impossible
local function calcAggregationForBucket(aStartTs, aEndTs)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")

	local energy = db.getBucketEnergyAndPower(aStartTs, aEndTs)
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





--- Core aggregator loop running in Copas thread
-- Loops from newest to oldest bucket
local function aggregatorLoop(aIntervalSeconds, aTargetTable)
	assert(type(aIntervalSeconds) == "number")
	assert(type(aTargetTable) == "string")

	local subsystemName = string.format("aggregator %d", aIntervalSeconds)
	local numLoops = 0
	local lastCurrentAggregationTs = nil
	while not(copas.exiting()) do
		if (aggregator.shouldPause) then
			copas.sleep(1)
		else
			local timer = aggregator.shouldLogPerf and perf.newTimer(subsystemName) or function() end
			local now = os.time()
			local currentBucket = now - now % aIntervalSeconds

			-- Refresh the current bucket at most once per second
			if (now ~= lastCurrentAggregationTs) then
				local agg = calcAggregationForBucket(currentBucket, currentBucket + aIntervalSeconds)
				timer("calcCurrentBucket")
				if (agg) then
					db.insertAggregate(aTargetTable, currentBucket, agg)
					timer("insertCurrentBucket")
				end
				lastCurrentAggregationTs = now
			end

			-- Process one historic bucket:
			local startTs, endTs = findNextAggregationBucket(aTargetTable, aIntervalSeconds, currentBucket)
			timer("findNextAggregationBucket")

			if (startTs) then
				local agg = calcAggregationForBucket(startTs, endTs)
				timer("calcAggregationForBucket")
				db.saveAggregateBucket(aTargetTable, startTs, agg, aIntervalSeconds)
				timer("saveAggregateBucket")

				-- Every 20 loops sleep for a longer time to give other threads a chance to run, too
				numLoops = (numLoops + 1) % 20
				if (numLoops == 0) then
					copas.sleep(1)
				else
					copas.sleep(0.1)
				end
			else
				log(subsystemName, "No more available buckets in DB")
				copas.sleep(30)
			end
		end
	end
end





--- Invalidates aggregation progress in the specified timestamp range (used mainly for historic import)
function aggregator.invalidateFrom(aStartTs, aEndTs)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")
	assert(aEndTs >= aStartTs)

	for _, target in ipairs({
		{"ElectricityConsumptionAggregate1min", 60},
		{"ElectricityConsumptionAggregate15min", 15 * 60},
		{"ElectricityConsumptionAggregateDay", 24 * 60 * 60},
	}) do
		local tableName = target[1]
		local interval = target[2]
		local lastAffectedBucket = aEndTs - aEndTs % interval

		db.setAggregationProgress(tableName, lastAffectedBucket)
	end
end





--- Starts the aggregator Copas threads
function aggregator.start()
	copas.addnamedthread(function()
		aggregatorLoop(60, "ElectricityConsumptionAggregate1min")
	end, "aggregator-1min")
	copas.addnamedthread(function()
		aggregatorLoop(15 * 60, "ElectricityConsumptionAggregate15min")
	end, "aggregator-15min")
	copas.addthread(function()
		aggregatorLoop(24 * 60 * 60, "ElectricityConsumptionAggregateDay")
	end, "aggregator-1day")
	log("aggregators", "Started aggregations")
end





-- Export the local helper functions in order to facilitate testing:
aggregator.debug =
{
	findNextAggregationBucket = findNextAggregationBucket,
	calcAggregationForBucket = calcAggregationForBucket,
}

return aggregator
