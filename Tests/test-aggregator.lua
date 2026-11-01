-- test-aggregator.lua

--[[ Performs a simple test on the aggregator in a single-threaded environment suitable for IDE debugging
Assumes that the aggregator module exports a debug sub-table with the internal functions to be tested
--]]





local db = require("db")
local aggregator = require("aggregator")





local intervalSec = 15 * 60
local tableName = "ElectricityConsumptionAggregate15min"
local lmab = db.getLatestMissingAggregateBucket(tableName, intervalSec)
print("LatestMissingAggregateBucket = " .. lmab)

local startTs, endTs = aggregator.debug.findNextAggregationBucket(tableName, intervalSec)
assert(type(startTs) == "number")
print("startTs = " .. startTs)
print("endTs = " .. endTs)

local agg = aggregator.debug.calcAggregationForBucket(startTs, endTs)
for k, v in pairs(agg) do
	print(string.format("%s = %s", tostring(k), tostring(v)))
end
print("Finished.")
