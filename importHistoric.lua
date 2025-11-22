-- importHistoric.lua

--[[ Imports historical tall-format meter data into the new wide-format ElectricityConsumption table.
Buckets data into 5-second intervals.
Optimized for batch insertion and progress reporting.

Usage: lua importHistoric.lua [<oldDb>]
<oldDb> defaults to Meters.sqlite if not provided
--]]





local sqlite3 = require("lsqlite3")
local db = require("db")

local oldDbName = arg[1] or "Meters.sqlite"
local bucketInterval = 5  -- seconds
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
	return aTimestamp - (aTimestamp % bucketInterval)
end





--- Processes the old DB row stream and inserts buckets in batches
local function importOldDb(aDbName)
	local rawDb = sqlite3.open(aDbName)

	local stmt = rawDb:prepare([[
		SELECT Timestamp, SensorName, SensorValue
		FROM MeterData
		ORDER BY Timestamp ASC
	]])
	if not(stmt) then
		error("Failed to prepare statement for old DB")
	end

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
					print(string.format("Saved %d buckets", nBatch))
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
	importOldDb(oldDbName)
	print("Import completed!")
end





main()
