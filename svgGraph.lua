-- svgGraph.lua

--[[ Implements drawing an SVG graph from time series
--]]





local svgGraph = {}
svgGraph.__index = svgGraph





--- Creates a new Graph object
function svgGraph:new(aWidth, aHeight, aStartTs, aEndTs)
	local o = {
		width = aWidth,
		height = aHeight,
		startTs = aStartTs,
		endTs = aEndTs,
		padding = 40,
		maxValue = 10000,   -- default; caller may override later via setMaxValue()
		parts = {
			string.format(
				'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">',
				aWidth, aHeight
			),
			'<rect width="100%" height="100%" fill="white"/>'
		},
		n = 2,
		wasGridDrawn = false,
		wereAxesDrawn = false,
		wereAxisLabelsDrawn = false,
	}
	setmetatable(o, self)
	return o
end





-- Optional: allow adjusting max Y value
function svgGraph:setMaxValue(v)
	self.maxValue = v
end





-- Internal scaling
function svgGraph:scaleX(ts)
	local pad = self.padding
	local span = self.endTs - self.startTs
	if (span <= 0) then
		span = 1
	end
	return pad + ((ts - self.startTs) / span) * (self.width - 2 * pad)
end





--- Internal scaling
function svgGraph:scaleY(val)
	local pad = self.padding
	local maxV = self.maxValue
	if (maxV <= 0) then
		maxV = 1
	end
	return self.height - pad - (val / maxV) * (self.height - 2 * pad)
end





--- Draws axes, if not already drawn
function svgGraph:drawAxes()
	if (self.wereAxesDrawn) then
		return
	end
	self.wereAxesDrawn = true

	local pad = self.padding
	local w, h = self.width, self.height

	self.parts[self.n + 1] = string.format(
		'<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="black"/>',
		pad, h - pad, w - pad, h - pad
	)
	self.parts[self.n + 2] = string.format(
		'<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="black"/>',
		pad, pad, pad, h - pad
	)
	self.n = self.n + 2
end





--- Draws a single time series into the graph
-- A series is an array-table of {timestamp, value}
function svgGraph:drawSeries(aSeries, aStrokeColor)
	assert(type(aSeries) == "table")
	aStrokeColor = aStrokeColor or "#000"
	assert(type(aStrokeColor) == "string")

	self:drawAxes()

	local path, m = {}, 0
	local hasStarted = false
	for _, datapoint in ipairs(aSeries) do
		local ts, val = datapoint[1], datapoint[2]
		if (ts and val) then
			local x = self:scaleX(ts)
			local y = self:scaleY(val)

			if not(hasStarted) then
				m = m + 1
				path[m] = string.format("M %.2f %.2f", x, y)
				hasStarted = true
			else
				m = m + 1
				path[m] = string.format("L %.2f %.2f", x, y)
			end
		else
			hasStarted = false
		end
	end
	self.n = self.n + 1
	self.parts[self.n] = string.format(
		'<path d="%s" fill="none" stroke="%s" stroke-width="1.5"/>',
		table.concat(path, " "), aStrokeColor
	)
end





--- Draws a single keyed time series into the graph
-- A keyed series is a dict-table of {color = ..., aggregation = ..., values = { [timestamp] = value, ...}
function svgGraph:drawKeyedSeries(aKeyedSeries)
	assert(type(aKeyedSeries) == "table")
	assert(type(aKeyedSeries.aggregation) == "number")
	assert(type(aKeyedSeries.values) == "table")
	aKeyedSeries.color = aKeyedSeries.color or "000000"
	assert(type(aKeyedSeries.color) == "string")

	self:drawAxes()

	local path, m = {}, 0
	local hasStarted = false
	local startTs = self.startTs - (self.startTs % aKeyedSeries.aggregation)
	if (startTs < self.startTs) then
		startTs = startTs + aKeyedSeries.aggregation
	end
	local endTs = (self.endTs + aKeyedSeries.aggregation - 1) - ((self.endTs + aKeyedSeries.aggregation - 1) % aKeyedSeries.aggregation)
	for ts = startTs, endTs, aKeyedSeries.aggregation do
		local val = aKeyedSeries.values[ts]
		if (val) then
			local x = self:scaleX(ts)
			local y = self:scaleY(val)
			if not(hasStarted) then
				m = m + 1
				path[m] = string.format("M %.2f %.2f", x, y)
				hasStarted = true
			else
				m = m + 1
				path[m] = string.format("L %.2f %.2f", x, y)
			end
		else
			hasStarted = false
		end
	end
	self.n = self.n + 1
	self.parts[self.n] = string.format(
		'<path d="%s" fill="none" stroke="#%s" stroke-width="1.5"/>',
		table.concat(path, " "), aKeyedSeries.color
	)
end





--- Draws background grid as a true checkerboard based on value and timestamp scales
function svgGraph:drawBackgroundGrid()
	-- Only draw once:
	if (self.wasGridDrawn) then
		return
	end
	self.wasGridDrawn = true

	local pad = self.padding
	local w, h = self.width, self.height

	-- Determine vertical grid step (values):
	local maxV = self.maxValue
	if (maxV <= 0) then
		maxV = 1
	end

	-- Choose value step (~2–10 horizontal bands):
	local rawStep = maxV / 6
	local pow = 10 ^ math.floor(math.log(rawStep) / math.log(10))
	local stepV = pow
	if (rawStep / pow > 5) then
		stepV = pow * 10
	elseif (rawStep / pow > 2) then
		stepV = pow * 5
	end

	-- Determine horizontal grid step (timestamps):
	local span = self.endTs - self.startTs
	local stepT
	if (span <= 20 * 60) then
		stepT = 60          -- 1 minute
	elseif (span <= 2 * 86400) then
		stepT = 3600        -- 1 hour
	else
		stepT = 86400       -- 1 day
	end

	-- Vertical stripes:
	local startTs = math.floor(self.startTs / stepT) * stepT
	local col = 0
	for ts = startTs, self.endTs, stepT do
		local realTs = ts
		if (realTs < self.startTs) then
			realTs = self.startTs
		end
		local xLeft = self:scaleX(realTs)
		local realEndTs = ts + stepT
		if (realEndTs > self.endTs) then
			realEndTs = self.endTs
		end
		local xRight = self:scaleX(realEndTs)
		local wBand = xRight - xLeft
		if (wBand > 0) then
			local fill = (col % 2 == 0) and "#fafafa" or "#ffffff"
			self.n = self.n + 1
			self.parts[self.n] = string.format(
				'<rect x="%.2f" y="%d" width="%.2f" height="%d" fill="%s"/>',
				xLeft, pad, wBand, h - 2 * pad, fill
			)
		end
		col = col + 1
	end

	-- Horizontal value lines:
	local startV = 0
	local row = 0
	for v = startV, maxV, stepV do
		local y = self:scaleY(v)
		self.n = self.n + 1
		self.parts[self.n] = string.format(
			'<line x1="%d" y1="%.2f" x2="%d" y2="%.2f" stroke="#dddddd" stroke-width="1"/>',
			pad, y, w - pad, y
		)
		row = row + 1
	end
end





--- Draws axis labels for time (X) and power (Y)
function svgGraph:drawAxisLabels()
	-- Only draw once:
	if (self.wereAxisLabelsDrawn) then
		return
	end
	self.wereAxisLabelsDrawn = true

	local pad = self.padding
	local w, h = self.width, self.height

	local maxV = self.maxValue
	if (maxV <= 0) then
		maxV = 1
	end

	-- Determine vertical label step:
	local rawStepV = maxV / 5
	local powV = 10 ^ math.floor(math.log(rawStepV) / math.log(10))
	local stepV = powV
	if (rawStepV / powV > 5) then
		stepV = powV * 10
	elseif (rawStepV / powV > 2) then
		stepV = powV * 5
	end

	-- Draw Y-axis labels:
	for v = 0, maxV, stepV do
		local y = self:scaleY(v)
		self.n = self.n + 1
		self.parts[self.n] = string.format(
			'<text x="%d" y="%.2f" font-family="Arial" font-size="10" fill="black" text-anchor="end" alignment-baseline="middle">%d</text>',
			pad - 4, y, v
		)
	end

	-- Determine horizontal label step (time):
	local span = self.endTs - self.startTs
	if (span <= 0) then
		span = 1
	end

	local stepT
	if (span <= 20 * 60) then
		stepT = 60          -- 1 min
	elseif (span <= 3 * 3600) then
		stepT = 300         -- 5 min
	elseif (span <= 2 * 86400) then
		stepT = 3600        -- 1 hour
	elseif (span <= 60 * 86400) then
		stepT = 21600       -- 6 hours
	else
		stepT = 86400       -- 1 day
	end

	local startTs = math.floor(self.startTs / stepT) * stepT
	for ts = startTs, self.endTs, stepT do
		if ((ts >= self.startTs) and (ts <= self.endTs)) then
			local x = self:scaleX(ts)
			local timestr
			if (stepT < 86400) then
				timestr = os.date("%H:%M", ts)
			else
				timestr = os.date("%Y-%m-%d", ts)
			end
			self.n = self.n + 1
			self.parts[self.n] = string.format(
				'<text x="%.2f" y="%d" font-family="Arial" font-size="10" fill="black" text-anchor="middle">%s</text>',
				x, h - pad + 12, timestr
			)
		end
	end
end





--- Finalizes the SVG and returns it as a string
function svgGraph:finish()
	self.n = self.n + 1
	self.parts[self.n] = '</svg>'
	return table.concat(self.parts, "\n")
end

return svgGraph
