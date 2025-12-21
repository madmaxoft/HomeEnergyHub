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
}





--- Finds the next aggregation bucket for the target table
-- Returns startTs, endTs; or nil if at minimum timestamp
local function findNextAggregationBucket(aTargetTable, aIntervalSeconds)
	assert(type(aTargetTable) == "string")
	assert(type(aIntervalSeconds) == "number")

	local latestTs = db.getLatestMissingAggregateBucket(aTargetTable, aIntervalSeconds)
	if not(latestTs) then
		latestTs = os.time()
		latestTs = latestTs - (latestTs % aIntervalSeconds)
	end

	if (latestTs < 0) then
		return nil
	end
	return latestTs, latestTs + aIntervalSeconds
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
	local factor = 3600 / (aEndTs - aStartTs) * 1000  -- Convert kWh over interval to W
	return {
		avgPowerTotal = energy.energyTotal and (energy.energyTotal * factor),
		avgPowerA = energy.energyA and (energy.energyA * factor),
		avgPowerB = energy.energyB and (energy.energyB * factor),
		avgPowerC = energy.energyC and (energy.energyC * factor),
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
	while not copas.exiting() do
		if (aggregator.shouldPause) then
			copas.sleep(1)
		else
			local timer = perf.newTimer(subsystemName)
			local startTs, endTs = findNextAggregationBucket(aTargetTable, aIntervalSeconds)
			timer("findNextAggregationBucket")

			if (startTs) then
				local agg = calcAggregationForBucket(startTs, endTs)
				timer("calcAggregationForBucket")
				if (agg) then
					db.insertAggregate(aTargetTable, startTs, agg)
					timer("insertAggregate")
				else
					log(subsystemName,
						"Cannot aggregate bucket at %s",
						os.date("%Y-%m-%d %H:%M:%S", startTs)
					)
					copas.sleep(10)
				end

				-- Every 20 loops sleep for a longer time to give other threads a chance to run, too
				numLoops = (numLoops + 1) % 20
				if (numLoops == 0) then
					copas.sleep(1)
				else
					copas.sleep(0.01)
				end
			else
				log(subsystemName, "No more available buckets in DB")
				copas.sleep(30)
			end
		end
	end
end





--- Starts the aggregator Copas threads
function aggregator.start()
	copas.addthread(function()
		aggregatorLoop(60, "ElectricityConsumptionAggregate1min")
	end)
	--[[
	copas.addthread(function()
		aggregatorLoop(15 * 60, "ElectricityConsumptionAggregate15min")
	end)
	copas.addthread(function()
		aggregatorLoop(24 * 60 * 60, "ElectricityConsumptionAggregateDay")
	end)
	--]]
	log("aggregators", "Started aggregations")
end





-- Export the local helper functions in order to facilitate testing:
aggregator.debug =
{
	findNextAggregationBucket = findNextAggregationBucket,
	calcAggregationForBucket = calcAggregationForBucket,
}

return aggregator
