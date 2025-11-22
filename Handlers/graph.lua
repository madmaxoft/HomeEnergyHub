-- Handlers/graph.lua

--[[ Handles the "/graph" HTTP endpoint generating SVG graphs
The graph to be drawn can contain several data series definitions, in the query's "def" parameter
The definition is a semicolon-concatenated list of string, each string being a "Column-AggregationSec-Color" value,
such as "powerA-5-ff0000" (no aggregation, red) or "maxPowerTotal-900-00cc00" (15 minute aggregation, green).
The request can also specify the graph dimensions, background, grid.
The following parameters are accepted:
	- "axislabels": how to label axes, "none" or "values". Defaults to "values"
	- "background": what background to draw, "none", "grid". Defaults to "grid"
	- "def": the data series definitions, such as "powerA-5-cc0000;powerB-5-008800;powerC-5-0000cc"
	- "from": the timestamp of the latest value in the graph, or "now" for current time. Defaults to "now"
	- "height": the graph height. Defaults to 500
	- "interval": the number of seconds covered by the graph
	- "width": the graph width. Defaults to 1500
Data series aggregation can be:
	- 5 (no aggregation, raw data
	- 60 (1 minute)
	- 900 (15 minutes)
	- 86400 (1 day)
--]]





local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local db = require("db")
local svgGraph = require("svgGraph")





--- Dict-table of valid aggregation values, seconds -> true for a valid value of seconds:
local gValidAggregations =
{
	[5] = true,
	[60] = true,
	[15 * 60] = true,
	[24 * 60 * 60] = true,
}




--- Converts the rows loaded from DB into a graphable series
-- Returns the series definition table and the maximum value
-- Assumes that the DB rows have been ordered by their ascending timeStamp
local function convertDbRowsToSeries(aStartTs, aEndTs, aDbRows, aAggr)
	assert(type(aStartTs) == "number")
	assert(type(aEndTs) == "number")
	assert(type(aDbRows) == "table")
	assert(type(aDbRows.n) == "number")
	assert(type(aAggr) == "number")

	-- Convert from array of DB rows into a dict-table of values keyd by the rounded timestamp:
	local values = {}
	local maxV = 0
	for _, row in ipairs(aDbRows) do
		if (row.value) then
			values[row.timeStamp - row.timeStamp % aAggr] = row.value
			if (row.value > maxV) then
				maxV = row.value
			end
		end
	end

	return {
		aggregation = aAggr,
		values = values,
	}, maxV
end





return function (aClient, aPath, aRequestHeaders)
	-- Parse path and query:
	local path, query = httpRequest.parseRequestPath(aPath)
	local fromParam = query.from or "now"
	local interval = tonumber(query.interval)
	if not(interval) then
		return httpResponse.sendError(aClient, 400, "Missing 'interval' parameter")
	end
	local width = query.width or 1500
	local height = query.height or 500
	local def = query.def
	if not(def) then
		return httpResponse.sendError(aClient, 400, "Missing 'def' parameter")
	end
	query.background = query.background or "grid"
	query.axislabels = query.axislabels or "values"

	-- Determine timestamp range:
	local endTs
	if (fromParam == "now") then
		endTs = os.time()
	else
		endTs = tonumber(fromParam)
		if not(endTs) then
			return httpResponse.sendError(aClient, 400, "Invalid 'from' parameter")
		end
	end
	local startTs = endTs - interval

	-- Prepare each series in the "def" parameter:
	local series = {}  -- Array of series to draw
	local n = 0        -- Number of items in series
	local maxV = 0
	for seriesDef in def:gmatch("[^;]+") do
		-- seriesDef is expected to be a string like "A-5-f00"
		local columnName, aggr, color = seriesDef:match("(.+)%-(%d+)%-(.+)")
		aggr = tonumber(aggr)
		color = color or "000000"
		if (not(columnName) or not(aggr)) then
			return httpResponse.sendError(aClient, 400, "Invalid series definition " .. seriesDef)
		end
		if not(gValidAggregations[aggr]) then
			return httpResponse.sendError(aClient, 400, "Invalid aggregation value: " .. aggr)
		end
		local rows, msg = db.getGraphPowerColumnData(startTs, endTs, columnName, aggr)
		if not(rows) then
			return httpResponse.sendError(aClient, 400, "Cannot query from DB: " .. tostring(msg))
		end
		local s, m = convertDbRowsToSeries(startTs, endTs, rows, aggr)
		if (s) then
			n = n + 1
			series[n] = s
			s.color = color
			if (m > maxV) then
				maxV = m
			end
		end
	end
	if (maxV <= 0) then
		maxV = 1
	end

	-- Draw the graph:
	local graph = svgGraph:new(width, height, startTs, endTs)
	graph:setMaxValue(maxV)
	if (query.background == "grid") then
		graph:drawBackgroundGrid()
	end
	if (query.axislabels == "values") then
		graph:drawAxisLabels()
	end
	for _, s in ipairs(series) do
		graph:drawKeyedSeries(s)
	end

	-- Send the resulting SVG data to the client:
	local svgString = graph:finish()
	httpResponse.send(aClient, 200, { ["Content-Type"] = "image/svg+xml" }, svgString)
end
