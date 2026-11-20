-- backgroundAggregationTask.lua

--[[
Implements a background task that aggregated old data.

Runs a background task that checks the currently set range, aggregates data in that range one day at a time.

Usage:
require("backgroundAggregationTask").setRange(startTS, endTS)
--]]




local copas = require("copas")
local db = require("db")
local aggregator = require("aggregator")
local log = require("logger").log
local utils = require("utils")





--- The API returned from this module
local bat = {}

--- The range that still needs re-aggregating
-- Both start and end timestamps are zero if no aggregation needed
local gCurrentRange =
{
	startTS = 0,
	endTS = 0,

	--- The timestamp to be processed at the next iteration
	currentTS = 0,

	--- The timestamp when the current range processing started.
	-- Used for estimating the time of completion in the UI.
	processingStartedOn = 0,
}

--- The Copas thread representing the background task
local gTaskThread = nil

--- Flag specifying if the background thread should terminate
local gShouldTerminate = false





--- The main loop of the background task
-- Periodically checks the gCurrentRange and if there's any range left, aggregates up to a day from the start of the range.
local function batLoop()
	while not(gShouldTerminate) do
		if ((gCurrentRange.startTS > 0) and (gCurrentRange.endTS > 0)) then
			assert(gCurrentRange.startTS <= gCurrentRange.endTS)
			assert(gCurrentRange.currentTS >= gCurrentRange.startTS)
			assert(gCurrentRange.currentTS <= gCurrentRange.endTS)

			local endTS = gCurrentRange.currentTS + 24 * 60 * 60
			if (endTS > gCurrentRange.endTS) then
				endTS = gCurrentRange.endTS
			end
			db.withinTransaction(function()
				aggregator.aggregate(gCurrentRange.currentTS, endTS)
			end)
			if (endTS == gCurrentRange.endTS) then
				gCurrentRange.startTS = 0
				gCurrentRange.endTS = 0
				gCurrentRange.currentTS = 0
			else
				gCurrentRange.currentTS = endTS
			end
		end
		copas.pause(0.1)
	end
	log("backgroundAggregationTask", "Finished")
end





--- Sets the range for (re-)aggregating
-- The background task picks up this new range in its next loop
function bat.setRange(aStartTimeStamp, aEndTimeStamp)
	assert(gTaskThread ~= nil)

	if (aStartTimeStamp > aEndTimeStamp) then
		aStartTimeStamp, aEndTimeStamp = aEndTimeStamp, aStartTimeStamp
	end
	gCurrentRange.startTS = aStartTimeStamp
	gCurrentRange.endTS = aEndTimeStamp
	gCurrentRange.currentTS = aStartTimeStamp
	gCurrentRange.processingStartedOn = os.time()

	log("backgroundAggregationTask", "New range: %d - %d (%s - %s)",
		aStartTimeStamp, aEndTimeStamp,
		utils.timeStampToYmdHms(aStartTimeStamp), utils.timeStampToYmdHms(aEndTimeStamp)
	)
end





--- Starts the background task
function bat.start()
	assert(gTaskThread == nil)

	gTaskThread = copas.addnamedthread("backgroundAggregation", batLoop)
end





--- Returns the current status of the thread
-- The returned value is a copy of gCurrentRange, with an extra member, "isRunning"
function bat.status()
	return {
		startTS = gCurrentRange.startTS,
		endTS = gCurrentRange.endTS,
		currentTS = gCurrentRange.currentTS,
		processingStartedOn = gCurrentRange.processingStartedOn,
		isRunning = (gCurrentRange.startTS > 0) and (gCurrentRange.endTS > 0),
	}
end





--- Terminates the background thread
function bat.stop()
	assert(gTaskThread ~= nil)

	gShouldTerminate = true
	copas.wakeup(gTaskThread)
end





return bat
