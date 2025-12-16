-- test-remoteImport.lua

--[[
Implements tests for importing remote data, checking the progress along the way.
--]]





--- The remote address to be used for the test:
local remoteAddress = "blackbox:5500"





local utils = require("utils")
local remoteImport = require("Handlers.remoteImport")





remoteImport.remoteAddress = remoteAddress
utils.shouldUseBlockingHttp = true
print("Fetching range...")
local startTs, endTs = remoteImport.fetchRemoteAvailableRange()
print(string.format("Range: %d - %d (%s - %s)", startTs, endTs, utils.timeStampToYmd(startTs), utils.timeStampToYmd(endTs)))
print("Fetching daily stats...")
local dailyStats = remoteImport.fetchRemoteDailyStats(startTs, endTs)
utils.printTable(dailyStats)

for dayTs, _ in pairs(dailyStats) do
	print(string.format("Fetching day %d (%s)...", dayTs, utils.timeStampToYmd(dayTs)))
	local rawRows, msg = remoteImport.fetchRemoteDayRawData(dayTs)
	if not(rawRows) then
		print("Failed: " .. tostring(msg))
	else
		print(string.format("Got %d rows", rawRows.n))
	end
end
print("All done")
