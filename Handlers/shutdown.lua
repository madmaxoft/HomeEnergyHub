-- Handlers/shutdown.lua

--[[
Implements the handler for the /shutdown endpoint, used to shut the server down gracefully
--]]

local copas = require("copas")
local utils = require("utils")
local httpClient = require("httpClient")
local chintSensor = require("chintSensor")
local log = require("logger").log
local bat = require("backgroundAggregationTask")





return function(aRequest, aResponse)
	assert(type(aRequest) == "table")
	assert(aResponse.sendSimpleMessage)

	if (aRequest.isReadOnly) then
		return aResponse:sendTemplate("readOnly", {})
	end

	aResponse:setConnectionClose()
	aResponse:sendSimpleMessage("Shutting down")

	-- Close all sockets currently opened in the server
	copas.debug.start()
	copas.exit()
	httpClient.closeAllConnections()
	chintSensor.stop()
	bat.stop()
	copas.removeserver(copas.mainServerSocket)
	for sock, _ in pairs(copas.mainServerClients or {}) do
		if (sock.close) then
			sock:close()
		end
	end

	log("shutdown", "Shutdown signalized to all subsystems")
end