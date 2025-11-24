-- Handlers/tariffPlan.lua

--[[
Implements the handler for the /tariffPlan endpoint, used to view and edit the tariff plan
--]]

local db = require("db")
local httpResponse = require("httpResponse")
local tariffPlan = require("tariffPlan")





local function handlePostAddNewDayType(aClient)
	-- Add a new dayType:
	db.addTariffPlanDayType()

	-- Reload the tariff plan from DB:
	tariffPlan.reloadFromDB()

	return httpResponse.sendRedirect(aClient, "/tariffPlan")
end





return {
	get = function(aClient, aPath, aRequestHeaders)
		local body = require("Templates").tariffPlan({
			currentTime = os.time(),
			seasons = tariffPlan.seasons,
			dayTypeSchedules = tariffPlan.dayTypeSchedules,
			exceptionDates = tariffPlan.exceptionDates,
		})
		httpResponse.send(aClient, "200 OK", nil, body)
	end,


	post = function(aClient, aPath, aRequestHeaders)
		if (aPath == "/tariffPlan/addNewDayType") then
			return handlePostAddNewDayType(aClient)
		elseif (aPath == "/tariffPlan/addNewSeason") then
			-- TODO: return handlePostAddNewSeason(aClient)
		end
	end,
}
