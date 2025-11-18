-- aggregator.lua

--[[ Implements the data aggregation in background threads
--]]





local copas = require("copas")
local db = require("db")





local aggregator = {}





--- Public kill switch:
aggregator.shouldPause = false





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
		avgPowerTotal = (energy.energyTotal or 0) * factor,
		avgPowerA = (energy.energyA or 0) * factor,
		avgPowerB = (energy.energyB or 0) * factor,
		avgPowerC = (energy.energyC or 0) * factor,
		energyTotal = energy.energyTotal or 0,
		energyA = energy.energyA or 0,
		energyB = energy.energyB or 0,
		energyC = energy.energyC or 0,
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

	while not(copas.exiting()) do
		if (aggregator.shouldPause) then
			copas.sleep(5)
			goto continueLoop
		end

		local startTs, endTs = findNextAggregationBucket(aTargetTable, aIntervalSeconds)
		if (startTs) then
			local agg = calcAggregationForBucket(startTs, endTs)
			if (agg) then
				db.insertAggregate(aTargetTable, startTs, agg)
			else
			end
			copas.sleep(0.01)  -- Avoid busy loop
		else
			copas.sleep(30)
		end
		::continueLoop::
	end
end



--- Starts a new aggregator Copas thread
-- aIntervalSeconds: length of aggregation bucket
-- aTargetTable: table name as string
function aggregator.start(aIntervalSeconds, aTargetTable)
	assert(type(aIntervalSeconds) == "number")
	assert(type(aTargetTable) == "string")

	copas.addthread(function()
		aggregatorLoop(aIntervalSeconds, aTargetTable)
	end)
end





-- Export the local helper functions in order to facilitate testing:
aggregator.debug = {
	findNextAggregationBucket = findNextAggregationBucket,
	calcAggregationForBucket = calcAggregationForBucket,
}
return aggregator
