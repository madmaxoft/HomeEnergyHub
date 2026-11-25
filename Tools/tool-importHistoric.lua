-- tool-importHistoric.lua

--[[
Imports historical tall-format meter data into the new wide-format ElectricityConsumption table.
Buckets data into 5-second intervals.
Optimized for batch insertion and progress reporting.
Also re-aggregates the affectd data range.

Usage: luajit Tools/importHistoric.lua [<oldDb> <minTimeStamp>]
<oldDb> defaults to Meters.sqlite if not provided
<minTimeStamp> defaults to 0

NOTE: Needs to be run from the main app folder
--]]





local sqlite3 = require("lsqlite3")
local db = require("db")
local aggr = require("aggregator")

local oldDbName = arg[1] or "Meters.sqlite"
local minTimeStamp = tonumber(arg[2]) or 0
local batchSize = 10000   -- number of buckets per DB insert





--- Map of OldDB SensorName -> NewDB column name
local gSensorNameToColumnName = {
	chint_combined_active_power = "powerTotal",
	chint_active_power_A = "powerA",
	chint_active_power_B = "powerB",
	chint_active_power_C = "powerC",
	chint_positive_total_active_energy = "energyTotal",
	chint_positive_active_energy_A = "energyA",
	chint_positive_active_energy_B = "energyB",
	chint_positive_active_energy_C = "energyC",
}





--- Rounds a timestamp down to nearest 5-second bucket
local function roundToBucket(aTimestamp)
	return aTimestamp - (aTimestamp % 5)
end





--- Processes the old DB row stream and inserts buckets in batches
local function importOldDb(aDbName, aMinTimeStamp)
	assert(type(aDbName) == "string")
	assert(type(aMinTimeStamp) == "number")

	local rawDb = sqlite3.open(aDbName)

	local stmt = assert(rawDb:prepare([[
		SELECT Timestamp, SensorName, SensorValue
		FROM MeterData
		ORDER BY Timestamp ASC
		WHERE Timestamp > ?
	]]))
	assert(stmt:bind_values({minTimeStamp}))

	local currentBucketTs = nil
	local currentBucket = nil
	local batch = {}
	local nBatch = 0
	for row in stmt:nrows() do
		local tsBucket = roundToBucket(row.Timestamp)

		if (tsBucket ~= currentBucketTs) then
			-- Save previous bucket into batch:
			if (currentBucket) then
				nBatch = nBatch + 1
				batch[nBatch] = currentBucket
				if (nBatch >= batchSize) then
					batch.n = nBatch
					db.saveMultipleElectricityMeasurements(batch)
					print(string.format("Saved %d buckets ending at timestamp %d (%s)", nBatch, tsBucket, os.date("!%Y-%m-%d", tsBucket)))
					batch = {}
					nBatch = 0
				end
			end

			-- Start new bucket:
			currentBucketTs = tsBucket
			currentBucket = {
				timeStamp = currentBucketTs,
			}
		end

		-- Map sensor to wide column
		local col = gSensorNameToColumnName[row.SensorName]
		if (col) then
			currentBucket[col] = row.SensorValue
		end
	end

	-- Save the final bucket
	if (currentBucket) then
		nBatch = nBatch + 1
		batch[nBatch] = currentBucket
	end

	if (nBatch > 0) then
		batch.n = nBatch
		db.saveMultipleElectricityMeasurements(batch)
		print(string.format("Saved final %d buckets", nBatch))
	end

	stmt:finalize()
	rawDb:close()
end





--- Main routine
local function main()
	print("Backing up the DB...")
	db.backup()
	print("Starting import from " .. oldDbName)
	importOldDb(oldDbName, minTimeStamp)
	print("Import completed. Re-aggregating the data...")
	aggr.aggregate(minTimeStamp, os.time())
	print("Done.")
end





main()
