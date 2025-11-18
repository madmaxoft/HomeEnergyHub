-- Handlers/home.lua

--[[ Handler for the "/" root URL path.
--]]

local db = require("db")




return function (aClient)
	local body = require("Templates").home({
		lastMeasurementTimestamp = db.getLastElectricityConsumptionMeasurementTimestamp()
	})
	require("httpResponse").send(aClient, "200 OK", nil, body)
end
