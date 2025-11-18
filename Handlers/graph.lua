-- Handlers/graph.lua

--[[ Handles the /graph endpoint for serving SVG graphs
--]]




local httpRequest = require("httpRequest")
local httpResponse = require("httpResponse")
local db = require("db")





return function (aClient, aPath, aRequestHeaders)
	-- Parse path and query
	local path, query = httpRequest.parseRequestPath(aPath)

	local aInterval = tonumber(query.interval)
	local fromParam = query.from or "now"

	if (not aInterval) then
		httpResponse.send(aClient, 400, {}, "Missing interval parameter")
		return
	end

	-- Determine end timestamp
	local endTs
	if (fromParam == "now") then
		endTs = os.time()
	else
		endTs = tonumber(fromParam)
		if (not endTs) then
			httpResponse.send(aClient, 400, {}, "Invalid 'from' parameter")
			return
		end
	end

	local startTs = endTs - aInterval

	-- Choose aggregation table
	local aggTable
	if (aInterval <= 15 * 60) then
		aggTable = "ElectricityConsumption" -- raw 5s data
	elseif (aInterval <= 24 * 60 * 60) then
		aggTable = "ElectricityConsumptionAggregate15min"
	else
		aggTable = "ElectricityConsumptionAggregateDay"
	end

	-- Query DB for the interval
	local sql = [[
		SELECT timeStamp, powerA, powerB, powerC
		FROM ]] .. aggTable .. [[
		WHERE timeStamp >= ? AND timeStamp <= ?
		ORDER BY timeStamp ASC
	]]
	local rows = db.getArrayFromQuery(sql, {startTs, endTs}, "graphHandler query")

	-- SVG parameters
	local width, height = 900, 300
	local padding = 40

	local function scaleX(ts)
		return padding + ((ts - startTs) / (endTs - startTs)) * (width - 2*padding)
	end

	local function scaleY(p)
		local maxP = 10000  -- adjust dynamically if needed
		return height - padding - (p / maxP) * (height - 2*padding)
	end

	local colors = {A="#f00", B="#0a0", C="#00f"}

	local tbl, n = {}, 0

	-- Add SVG header
	n = n + 1
	tbl[n] = string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', width, height)
	n = n + 1
	tbl[n] = string.format('<rect width="100%%" height="100%%" fill="white"/>')

	-- Add axes in one block
	local axes = {}
	axes[1] = string.format('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="black"/>', padding, height-padding, width-padding, height-padding)
	axes[2] = string.format('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="black"/>', padding, padding, padding, height-padding)
	n = n + #axes
	for i=1,#axes do
		tbl[n - #axes + i] = axes[i]
	end

	-- Function to draw line for a column with gaps
	local function drawLine(aCol)
		local pathTbl, m = {}, 0
		local started = false
		for i,row in ipairs(rows) do
			local val = row[aCol]
			if (val) then
				local x = scaleX(row.timeStamp)
				local y = scaleY(val)
				if (not started) then
					m = m + 1
					pathTbl[m] = string.format("M %.2f %.2f", x, y)
					started = true
				else
					m = m + 1
					pathTbl[m] = string.format("L %.2f %.2f", x, y)
				end
			else
				started = false
			end
		end
		return table.concat(pathTbl, " ")
	end

	-- Draw lines for each phase
	for _, colName in ipairs({"powerA","powerB","powerC"}) do
		local path = drawLine(colName)
		local color = colors[colName:sub(-1)]
		n = n + 1
		tbl[n] = string.format('<path d="%s" fill="none" stroke="%s" stroke-width="1.5"/>', path, color)
	end

	-- Close SVG
	n = n + 1
	tbl[n] = '</svg>'

	httpResponse.send(aClient, 200, {["Content-Type"]="image/svg+xml"}, table.concat(tbl,"\n"))
end
