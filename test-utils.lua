-- test-utils.lua

--[[
Implements tests for the various utils functions
--]]





local utils = require("utils")





local function testNextDayYmd()
	assert(utils.nextDayYmd("2025-11-25") == "2025-11-26")  -- normal date
	assert(utils.nextDayYmd("2025-11-30") == "2025-12-01")  -- month rollover
	assert(utils.nextDayYmd("2025-12-31") == "2026-01-01")  -- year rollover
	assert(utils.nextDayYmd("2025-11-31") == nil)           -- invalid date
	assert(utils.nextDayYmd("2025-02-28") == "2025-03-01")  -- non-leap year
	assert(utils.nextDayYmd("2025-02-29") == nil)           -- invalid date
	assert(utils.nextDayYmd("2024-02-28") == "2024-02-29")  --leap year
	assert(utils.nextDayYmd("2024-02-29") == "2024-03-01")
	assert(utils.nextDayYmd("2100-02-28") == "2100-03-01")  -- non-leap year (divisible by 100)
	assert(utils.nextDayYmd("2000-02-28") == "2000-02-29")  -- leap year (divisible by 400)
end





local function testPrevDayYmd()
	assert(utils.prevDayYmd("2025-11-25") == "2025-11-24")  -- normal date
	assert(utils.prevDayYmd("2025-12-01") == "2025-11-30")  -- month rollover
	assert(utils.prevDayYmd("2026-01-01") == "2025-12-31")  -- year rollover
	assert(utils.prevDayYmd("2025-11-31") == nil)           -- invalid date
	assert(utils.prevDayYmd("2025-03-01") == "2025-02-28")  -- non-leap year
	assert(utils.prevDayYmd("2025-02-29") == nil)           -- invalid date
	assert(utils.prevDayYmd("2024-03-01") == "2024-02-29")  -- leap year
	assert(utils.prevDayYmd("2024-02-29") == "2024-02-28")  -- leap year
	assert(utils.prevDayYmd("2100-03-01") == "2100-02-28")  -- non-leap year (divisible by 100)
	assert(utils.prevDayYmd("2000-03-01") == "2000-02-29")  -- leap year (divisible by 400)
end





testNextDayYmd()
testPrevDayYmd()
