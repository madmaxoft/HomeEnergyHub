-- test-rawDataExport.lua

--[[
Implements a test for the DB operations used by rawDataExport.
The tests run in a single-threaded environment, easier for debugging.
--]]





local db = require("db")
db.createSchema()





local rangeStart, rangeEnd = db.getElectricityConsumptionDataRange()
print("range: ", rangeStart, rangeEnd)
print(os.date("!%Y-%m-%d", rangeStart), os.date("!%Y-%m-%d", rangeEnd))

local dayStats = db.getElectricityConsumptionDailyStats(rangeStart, rangeEnd)
print("Stats: days = ", dayStats.n)
for _, day in ipairs(dayStats) do
	print(string.format(
		"  timeStamp = %d, ymd = \"%s\", count = %d, sum = %d",
		day.timeStamp, os.date("!%Y-%m-%d", day.timeStamp),
		day.count or 0, day.sum or -1
	))
end
