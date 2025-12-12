-- cmd-exportTariffPlan.lua

--[[
Command-line tool to export the tariff plan to a specified file.
--]]




local arg = {...}
if not(arg[1]) then
	error("No output file specified")
end
local f = assert(io.open(arg[1], "w"))
local db = require("db")
db.createSchema()
local tariffPlan = require("tariffPlan")
f:write(tariffPlan.export())
f:close()
