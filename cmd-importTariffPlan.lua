-- cmd-importTariffPlan.lua

--[[
Command-line tool to import tariff plan from a specified file
--]]





--- Read the input data:
local arg = {...}
local f = io.stdin
if (arg[1]) then
	f = assert(io.open(arg[1], "r"))
end
local plan = f:read("*all")
if (f ~= io.stdin) then
	f:close()
end

-- Parse the plan data:
local db = require("db")
db.createSchema()
local tariffPlan = require("tariffPlan")
local schedules, dayTypes, exceptionDates = assert(tariffPlan.parseFile(plan))
tariffPlan.replace(schedules, dayTypes, exceptionDates)
