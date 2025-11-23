-- test-tariffPlan.lua

--[[
Implements a basic test for the tariffPlan module that runs in a single thread for easier debugging.
--]]





local db = require("db")
db.createSchema()
local tariffPlan = require("tariffPlan")
local utils = require("utils")

local day_2025_10_20 = os.time({year = 2025, month = 10, day = 20, hour = 0, minute = 0, second = 0})
local sch1 = tariffPlan.generateSchedule(day_2025_10_20, day_2025_10_20 + tariffPlan.SECONDS_PER_DAY)
print("Tariff schedule for 2025-10-20:")
utils.printTable(sch1)
