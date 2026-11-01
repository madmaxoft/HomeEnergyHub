-- cmd-exportTariffPlan.lua

--[[
Command-line tool to export the tariff plan to a specified file.

NOTE: Needs to be run from the main app folder
--]]




local db = require("db")

local arg = {...}
if not(arg[1]) then
	error("No output file specified")
end
local f = assert(io.open(arg[1], "w"))
db.createSchema()
local tariffPlan = require("tariffPlan")
f:write(tariffPlan.export())
f:close()
