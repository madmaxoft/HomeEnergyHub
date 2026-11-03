-- test-aggregator.lua

--[[ Performs a simple test on the aggregator in a single-threaded environment suitable for IDE debugging
Assumes that the aggregator module exports a debug sub-table with the internal functions to be tested
--]]





local db = require("db")
db.createSchema()
local aggregator = require("aggregator")
local perf = require("perf")





--- Test aggregating one historical bucket, same code as aggregator's aggregatorLoop() does:
local intervalSeconds = 15 * 60
local targetTable = "ElectricityConsumptionAggregate15min"
local now = os.time()
local currentBucket = now - now % intervalSeconds
local timer = perf.newTimer("test-aggregator")

local startTs, endTs = aggregator.debug.findNextAggregationBucket(targetTable, intervalSeconds, currentBucket)
timer("findNextAggregationBucket")

if (startTs) then
	print(string.format("Found bucket %d (%s)", startTs, os.date("!%Y-%m-%d %H:%M:%S", startTs)))
	local agg = aggregator.debug.calcAggregationForBucket(startTs, endTs)
	timer("calcAggregationForBucket")
	db.saveAggregateBucket(targetTable, startTs, agg, intervalSeconds)
	timer("saveAggregateBucket")
	if (agg) then
		print("Aggregated:")
		for k, v in pairs(agg) do
			print(string.format("\t%s = %s", tostring(k), tostring(v)))
		end
	else
		print("No aggregated data")
	end
else
	print("No unprocessed bucket found")
end






print("Finished.")
