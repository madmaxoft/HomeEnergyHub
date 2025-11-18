-- Handlers/home.lua

--[[ Handler for the "/" root URL path.
--]]

local db = require("db")
local httpResponse = require("httpResponse")





return function (aClient, aPath)
	if (aPath ~= "/") then
		httpResponse.sendError(aClient, 404, "Not found")
	end

	local body = require("Templates").home({
		latestMeasurement = db.getLatestElectricityConsumptionMeasurement() or {},
		currentTime = os.time(),
	})
	httpResponse.send(aClient, "200 OK", nil, body)
end
