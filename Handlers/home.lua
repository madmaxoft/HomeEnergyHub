-- Handlers/home.lua

--[[ Handler for the "/" root URL path.
--]]

local db = require("db")





return function (aRequest, aResponse)
	aResponse:sendTemplate("home", {
		latestMeasurement = db.getLatestElectricityConsumptionMeasurement() or {},
		currentTime = os.time(),
	})
end
