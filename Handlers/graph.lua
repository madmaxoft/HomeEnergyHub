-- Handlers/graph.lua

--[[ Handles the /graph endpoint for serving SVG graphs
--]]




local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local db = require("db")
local svgGraph = require("svgGraph")





--- Converts from DB row format to three array-tables of {timestamp, value} items, for each phase
local function convertDbRowsToSeries(aDbRows)
	local seriesA, seriesB, seriesC = {}, {}, {}
	local na, nb, nc = 0, 0, 0
	for _, r in ipairs(aDbRows) do
		if (r.powerA) then
			na = na + 1
			seriesA[na] = { r.timeStamp, r.powerA }
		end
		if (r.powerB) then
			nb = nb + 1
			seriesB[nb] = { r.timeStamp, r.powerB }
		end
		if (r.powerC) then
			nc = nc + 1
			seriesC[nc] = { r.timeStamp, r.powerC }
		end
	end
	seriesA.n = na
	seriesB.n = nb
	seriesC.n = nc
	return seriesA, seriesB, seriesC
end





--- Returns the maximum value across all series in an array-table of series
-- Returns 0 if no row in the series
local function getMaxValueAcrossSeries(aMultipleSeries)
	local maxV = 0
	for _, series in ipairs(aMultipleSeries) do
		for _, row in ipairs(series) do
			local v = row[2]
			if (v > maxV) then
				maxV = v
			end
		end
	end
	return maxV
end





return function (aClient, aPath, aRequestHeaders)
	-- Parse path and query:
	local path, query = httpRequest.parseRequestPath(aPath)
	local interval = tonumber(query.interval)
	local fromParam = query.from or "now"
	if not(interval) then
		return httpResponse.sendError(aClient, 400, "Missing 'interval' parameter")
	end

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

	-- Get the series to draw:
	local rows = db.getGraphPowerData(startTs, endTs)
	local seriesA, seriesB, seriesC = convertDbRowsToSeries(rows)
	local maxV = getMaxValueAcrossSeries({seriesA, seriesB, seriesC})
	if (maxV <= 0) then
		maxV = 1
	end

	-- Create SVG graph:
	local width  = 1500
	local height = 500
	local graph = svgGraph:new(width, height, startTs, endTs)
	graph:setMaxValue(maxV)
	if (query.background ~= "none") then
		graph:drawBackgroundGrid()
	end
	if (query.axislabels ~= "none") then
		graph:drawAxisLabels()
	end
	graph:drawSeries(seriesA, "#cc0000")
	graph:drawSeries(seriesB, "#008800")
	graph:drawSeries(seriesC, "#0000cc")

	-- Send the resulting SVG data to the client:
	local svgString = graph:finish()
	httpResponse.send(aClient, 200, { ["Content-Type"] = "image/svg+xml" }, svgString)
end
