-- test-aggregator.lua

--[[ Performs a simple test on the aggregator in a single-threaded environment suitable for IDE debugging.
--]]





local db = require("db")
local aggregator = require("aggregator")
local perf = require("perf")





local function progressCallback(aStartTimeStamp, aEndTimeStamp, aCurrentTimeStamp, aCurrentInterval)
	local percentage = 100 * (aCurrentTimeStamp - aStartTimeStamp) / (aEndTimeStamp - aStartTimeStamp)
	print(string.format("[%ds] Progress: %d within %d to %d, %.2f%%", aCurrentInterval, aCurrentTimeStamp, aStartTimeStamp, aEndTimeStamp, percentage))
end





print("Updating the last aggregate...")
aggregator.updateLastAggregate()

print("Updating one day of historical data...")
db.debug.beginTransaction()
local ts, msg = db.getLastElectricityConsumptionMeasurementTimestamp()
if not(ts) then
	print("Cannot get the last measurement timestamp, using 'now': " .. tostring(msg))
	ts = os.time()
end
local startTS = ts - 24 * 60 * 60
local endTS = ts
print("Re-aggregating from " .. os.date("!%Y-%m-%d %H:%M:%S", startTS) .. " to " .. os.date("!%Y-%m-%d %H:%M:%S", endTS))
local timer = perf.newTimer()
aggregator.aggregate(startTS, endTS, progressCallback)
db.debug.commitTransaction()
timer("aggregated")



print("Finished.")
