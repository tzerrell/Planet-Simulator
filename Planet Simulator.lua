--------------------------------------------------------------------------------
--Planet Simulator by Bobert13
--Based on: PerfectWorld3.lua map script (c)2010 Rich Marinaccio
--version LL3
--------------------------------------------------------------------------------
--This map script uses simulated plate tectonics to create landforms, and generates
--climate based on a simplified model of geostrophic and monsoon wind patterns.
--Rivers are generated along accurate drainage paths governed by the elevation map
--used to create the landforms.
--
--Version History
--LL3	- Bugfix: Sea levels no longer always generate as "Low" regardless of option chosen
--		- Bugfix: Rivers ending in inland seas no longer sometimes end before reaching the sea
--		- Bugfix: Terra-style start placement available (as "All Civs on Largest Continent")
--		- Adjusted plate generation based on Beyond Earth version of Planet Simulator
--		- Tweaked rainfall constants based on Beyond Earth version
--		- Removed non-existent "Other" option from "Map Preset"
--		- Internal: Marked more opportunities to integrate Beyond Earth version's code (with "TODO" and a description)
--		- Internal: Cleaned up deprecated code
--LL2	- Prevented "inland" seas from generating when one of the boundaries is an
--		  ice cap. This also slightly reduces the rate of continents going into the ice caps
--		- Added additional failsafe elevation generation when very few mountains are generated
--		  along faults. This avoids the low-desert high-tundra maps that form when there is
--		  little elevation variation.
--LL2beta-Changed mountain generation to emphasize inland mountains along convergent
--		  faults. This moves mountains away from the coasts and causes most mountains
--		  to form in long ranges.
--		- Added "Islands" option for generation of different numbers and types of islands
--		- Introduced bug where small maps (mostly smaller than standard) sometimes generate
--		  with large amounts of tundra over the entire map. I suspect it happens when there
--		  are no continental-continental convergent faults.
--LL	- Bugfix: Resource generation now affected by correct option
--		- Bugfix: Fixed rare crash when script couldn't get close to target land percentage
--		- Enabled world age, temperature, rainfall, and sea level options that adjust existing MapConstants
--		- Added coast width controlling how far coasts tend to extend from land
--		(version LL changes by LamilLerran)
--TT	- Prevented forests from spawning on deserts
--		(version TT changes by TowerTipping)
--1		- YAY VERSION 1!!

include("MapGenerator");
include("FeatureGenerator");
include("TerrainGenerator");
-- bit = require("bit")



MapConstants = {}
Time = nil
Time2 = nil
Time3 = nil
function MapConstants:New()
	local mconst = {}
	setmetatable(mconst, self)
	self.__index = self
	
	mconst.MultiPlayer = Game:IsNetworkMultiPlayer()

	-------------------------------------------------------------------------------------------
	--Landmass constants
	-------------------------------------------------------------------------------------------
	--(Moved)mconst.landPercent = 0.31 		--Now in InitializeSeaLevel()
	--(Moved)mconst.hillsPercent = 0.70 		--Now in InitializeWorldAge()
	--(Moved)mconst.mountainsPercent = 0.94 	--Now in InitializeWorldAge()
	mconst.landPercentCheat = 0.01	--What proportion of total tiles more continental plate tiles there are than
									--land tiles (at least in terms of the goal; actually results depend on
									--plate generation and can vary). This value tends to not create lakes or
									--islands other than ones we deliberately added. (Larger numbers may lead to
									--lakes and smaller numbers to islands, but this is inconsistent.)
									--Note that this is changed by InitializeIslands() in some cases.
	--mconst.continentalPercent	--now defined at the end of this function

	--These settings affect Plate Tectonics.
	--none, yet

	--These attenuation factors lower the altitude of the map edges. This is currently used to prevent large continents in the uninhabitable polar regions.
	mconst.northAttenuationFactor = 0.85
	mconst.northAttenuationRange = 0.08 --percent of the map height.
	mconst.southAttenuationFactor = 0.85
	mconst.southAttenuationRange = 0.08 --percent of the map height.

	--East/west attenuation is set to zero, but modded maps may have need for them.
	mconst.eastAttenuationFactor = 0.0
	mconst.eastAttenuationRange = 0.0 --percent of the map width.
	mconst.westAttenuationFactor = 0.0
	mconst.westAttenuationRange = 0.0 --percent of the map width.

	--Hex maps are shorter in the y direction than they are wide per unit by this much. We need to know this to sample the perlin maps properly so they don't look squished.
	local W,H = Map.GetGridSize()
	mconst.YtoXRatio = math.sqrt(W/H)
	-------------------------------------------------------------------------------------------
	--Terrain type constants
	-------------------------------------------------------------------------------------------
	mconst.plateSpeedHeightScalarRange = 0.3 --this constant affects how much plate speed affects continental plate height. Slower plates tend to be higher as they've lost their momentum due to upward redirection. TODO: Implement
	--(Moved)mconst.desertPercent = 0.25		--Now in InitializeRainfall()
	--(Moved)mconst.desertMinTemperature = 0.35 --Now in InitializeTemperature()
	--(Moved)mconst.plainsPercent = 0.50 	--Now in InitializeRainfall()
	--(Moved)mconst.tundraTemperature = 0.31	--Now in InitializeTemperature()
	--(Moved)mconst.snowTemperature = 0.26 	--Now in InitializeTemperature()
	--For below see http://forums.civfanatics.com/showthread.php?t=544360
	--(Elsewhere)mconst.coastExpansionChance = {4,4}	--In InitializeCoasts()
	
	--(Elsewhere)mconst.oceanicVolcanoFrequency = 0.20	--In InitializeIslands()
	--(Elsewhere)mconst.islandExpansionFactor = 1			--In InitializeIslands()
	-------------------------------------------------------------------------------------------
	--Terrain feature constants
	-------------------------------------------------------------------------------------------
	--(Moved)mconst.zeroTreesPercent = 0.70 	--Now in InitializeRainfall()
	--(Moved)mconst.treesMinTemperature = 0.28 --Now in InitializeTemperature()

	--(Moved)mconst.junglePercent = 0.88 	--Now in InitializeRainfall()
	--(Moved)mconst.jungleMinTemperature = 0.66 --Now in InitializeTemperature()

	--(Moved)mconst.riverPercent = 0.18 		--Now in InitializeRainfall()
	--(Moved)mconst.riverRainCheatFactor = 1.6 --Now in InitializeRainfall()
	--(Moved)mconst.minRiverSize = 24		--Now in InitializeRainfall()
	mconst.minOceanSize = 5			--Fill in any lakes smaller than this. It looks bad to have large river systems flowing into a tiny lake.

	--(Deprecated)mconst.marshPercent = 0.92 	--Percent of land below the jungle marsh rainfall threshold.
	--(Moved)mconst.marshElevation = 0.07 	--Now in InitializeRainfall()

	mconst.OasisThreshold = 7 		--Maximum food around a tile for it to be considered for an Oasis -Bobert13

	--(Moved)mconst.atollNorthLatitudeLimit = 47 --Now in InitializeTemperature()
	--(Moved)mconst.atollSouthLatitudeLimit = -47 --Now in InitializeTemperature()
	mconst.atollMinDeepWaterNeighbors = 4 --Minimum nearby deep water tiles for it to be considered for an Atoll.

	--(Moved)mconst.iceNorthLatitudeLimit = 63 --Now in InitializeTemperature()
	--(Moved)mconst.iceSouthLatitudeLimit = -63 --Now in InitializeTemperature()
	-------------------------------------------------------------------------------------------
	--Weather constants
	-------------------------------------------------------------------------------------------
	--Important latitude markers used for generating climate.
	mconst.polarFrontLatitude = 65
	mconst.tropicLatitudes = 23
	mconst.horseLatitudes = 31
	mconst.topLatitude = 70
	mconst.bottomLatitude = -mconst.topLatitude

	--These set the water temperature compression that creates the land/sea seasonal temperature differences that cause monsoon winds.
	mconst.minWaterTemp = 0.10
	mconst.maxWaterTemp = 0.50

	--Strength of geostrophic climate generation versus monsoon climate generation.
	mconst.geostrophicFactor = 3.0
	mconst.geostrophicLateralWindStrength = 0.4

	--Crazy rain tweaking variables. I wouldn't touch these if I were you.
	mconst.minimumRainCost = 0.0001
	mconst.upLiftExponent = 4
	mconst.polarRainBoost = 0.08
	mconst.pressureNorm = 0.90 --[1.0 = no normalization] Helps to prevent exaggerated Jungle/Marsh banding on the equator. -Bobert13

    -------------------------------------------------------------------------------------------
	--Balance constants
	-------------------------------------------------------------------------------------------
    --~
    --##### Natural Wonder tweaks are GnK/BNW ONLY! #####--
    --~
    --~ Natural Wonder Numbers:
    --~ 1 Crater - 2 Fuji - 3 Mesa - 4 Reef - 5 Krakatoa - 6 Gibraltar - 7 Old Faithful
    --~ 8 Fountain of Youth - 9 Potosi - 10 El Dorado - 11 Sri Pada - 12 Mt. Sinai
    --~ 13 Mt. Kailash - 14 Uluru - 15 Lake Victoria - 16 Kilimanjaro - 17 Solomon's Mines
    --~-----------------------------------------------------------------------------------------
    --~ Add NW numbers to the following table to ban them from spawning.
    --~ example: mconst.banNWs = {8, 10, 16} bans FoY, El Dorado, and Kili (the really OP wonders)
    -- mconst.banNWs = {8, 10, 16}
    mconst.banNWs = {}
    -- The number of natural wonders to attempt to spawn for a given world size.
    mconst.NWTarget = {
		[GameInfo.Worlds.WORLDSIZE_DUEL.ID]     = 4,    --Default: 2 I calculated the new numbers with the following:
		[GameInfo.Worlds.WORLDSIZE_TINY.ID]     = 5,    --Default: 3 (sqareroot(width * height))/8
		[GameInfo.Worlds.WORLDSIZE_SMALL.ID]    = 6,    --Default: 4
		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = 8,    --Default: 6
		[GameInfo.Worlds.WORLDSIZE_LARGE.ID]    = 10,   --Default: 7
		[GameInfo.Worlds.WORLDSIZE_HUGE.ID]     = 12}   --Default: 8


	--#######################################################################################--
	--Below are map constants that should not be altered.
	--#######################################################################################--
	--directions
	mconst.C = 0
	mconst.W = 1
	mconst.NW = 2
	mconst.NE = 3
	mconst.E = 4
	mconst.SE = 5
	mconst.SW = 6
	mconst.DIRECTIONS = Set:New({mconst.C, mconst.W, mconst.NW, mconst.NE, mconst.E, mconst.SE, mconst.SW})
	
	--relative directions
	mconst.CENTER = 0
	mconst.LONE = 1
	mconst.SHORE = 2
	mconst.INTERMEDIATE = 3
	mconst.INLAND = 4
	
	--land patterns
	mconst.CONTIGUOUS = 1
	mconst.BALANCED = 2
	mconst.UNBALANCED = 3

	--flow directions
	mconst.NOFLOW = 0
	mconst.WESTFLOW = 1
	mconst.EASTFLOW = 2
	mconst.VERTFLOW = 3

	--wind zones
	mconst.NOZONE = -1
	mconst.NPOLAR = 0
	mconst.NTEMPERATE = 1
	mconst.NEQUATOR = 2
	mconst.SEQUATOR = 3
	mconst.STEMPERATE = 4
	mconst.SPOLAR = 5
	
	--plate types
	mconst.OCEANIC = 0
	mconst.PANGEAL = 1
	mconst.CONTINENTAL = 1
	
	--fault types
	mconst.NOFAULT = 0
	mconst.MINORFAULT = 1
	mconst.DIVERGENTFAULT = 2
	mconst.TRANSFORMFAULT = 3
	mconst.CONVERGENTFAULT = 4
	mconst.FALLBACKFAULT = 5	--Not a true fault, used where a fake fault is needed

	mconst:InitializeSeaLevel()
	mconst.continentalPercent = mconst.landPercent + mconst.landPercentCheat	--Percent of tiles on continental/pangeal plates

	mconst:InitializeUpliftCoefficients()
	mconst:InitializeWorldAge()
	mconst:InitializeTemperature()
	mconst:InitializeRainfall()
	mconst:InitializeCoasts()
	--mconst:NormalizeLatitudeForArea()
	mconst:InitializeLakes()
	mconst:InitializeIslands()
	return mconst
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeUpliftCoefficients()
	--TODO: Add options for these
	self.uplift = {}
	
	self.uplift[1] = {}
	self.uplift[1].center = {}
	self.uplift[1].center[self.CONVERGENTFAULT] = 1.05
	
	self.uplift[2] = {}
	self.uplift[2].center = {}
	self.uplift[2].center[self.CONVERGENTFAULT] = 1.2
	self.uplift[2].lone = {}
	self.uplift[2].lone[self.CONVERGENTFAULT] = 0.9
	
	self.uplift[3] = {}
	self.uplift[3].contiguous = {}
	self.uplift[3].contiguous.center = {}
	self.uplift[3].contiguous.center[self.CONVERGENTFAULT] = 1
	self.uplift[3].contiguous.shore = {}
	self.uplift[3].contiguous.shore[self.CONVERGENTFAULT] = 1
	self.uplift[3].unbalanced = {}
	self.uplift[3].unbalanced.center = {}
	self.uplift[3].unbalanced.center[self.CONVERGENTFAULT] = 1
	self.uplift[3].unbalanced.lone = {}
	self.uplift[3].unbalanced.lone[self.CONVERGENTFAULT] = 1
	self.uplift[3].balanced = {}
	self.uplift[3].balanced.center = {}
	self.uplift[3].balanced.center[self.CONVERGENTFAULT] = 1
	self.uplift[3].balanced.lone = {}
	self.uplift[3].balanced.lone[self.CONVERGENTFAULT] = 1
	
	self.uplift[4] = {}
	self.uplift[4].contiguous = {}
	self.uplift[4].contiguous.center = {}
	self.uplift[4].contiguous.center[self.CONVERGENTFAULT] = 1
	self.uplift[4].contiguous.shore = {}
	self.uplift[4].contiguous.shore[self.CONVERGENTFAULT] = 1.3
	self.uplift[4].contiguous.inland = {}
	self.uplift[4].contiguous.inland[self.CONVERGENTFAULT] = 1.05
	self.uplift[4].unbalanced = {}
	self.uplift[4].unbalanced.center = {}
	self.uplift[4].unbalanced.center[self.CONVERGENTFAULT] = 1
	self.uplift[4].unbalanced.lone = {}
	self.uplift[4].unbalanced.lone[self.CONVERGENTFAULT] = 1
	self.uplift[4].unbalanced.shore = {}
	self.uplift[4].unbalanced.shore[self.CONVERGENTFAULT] = 1
	self.uplift[4].balanced = {}
	self.uplift[4].balanced.center = {}
	self.uplift[4].balanced.center[self.CONVERGENTFAULT] = 1
	self.uplift[4].balanced.lone = {}
	self.uplift[4].balanced.lone[self.CONVERGENTFAULT] = 1
	
	self.uplift[5] = {}
	self.uplift[5].contiguous = {}
	self.uplift[5].contiguous.center = {}
	self.uplift[5].contiguous.center[self.CONVERGENTFAULT] = 1
	self.uplift[5].contiguous.shore = {}
	self.uplift[5].contiguous.shore[self.CONVERGENTFAULT] = 1
	self.uplift[5].contiguous.inland = {}
	self.uplift[5].contiguous.inland[self.CONVERGENTFAULT] = 1.5
	self.uplift[5].unbalanced = {}
	self.uplift[5].unbalanced.center = {}
	self.uplift[5].unbalanced.center[self.CONVERGENTFAULT] = 1
	self.uplift[5].unbalanced.lone = {}
	self.uplift[5].unbalanced.lone[self.CONVERGENTFAULT] = 1
	self.uplift[5].unbalanced.shore = {}
	self.uplift[5].unbalanced.shore[self.CONVERGENTFAULT] = 1
	self.uplift[5].unbalanced.inland = {}
	self.uplift[5].unbalanced.inland[self.CONVERGENTFAULT] = 1.4
	self.uplift[5].balanced = {}
	self.uplift[5].balanced.center = {}
	self.uplift[5].balanced.center[self.CONVERGENTFAULT] = 1
	self.uplift[5].balanced.shore = {}
	self.uplift[5].balanced.shore[self.CONVERGENTFAULT] = 1
	
	self.uplift[6] = {}
	self.uplift[6].center = {}
	self.uplift[6].center[self.CONVERGENTFAULT] = 1.05
	self.uplift[6].shore = {}
	self.uplift[6].shore[self.CONVERGENTFAULT] = 1.05
	self.uplift[6].intermediate = {}
	self.uplift[6].intermediate[self.CONVERGENTFAULT] = 1.47
	self.uplift[6].inland = {}
	self.uplift[6].inland[self.CONVERGENTFAULT] = 1.68
	
	self.uplift[7] = {}
	self.uplift[7].center = {}
	self.uplift[7].center[self.CONVERGENTFAULT] = 1.8
	self.uplift[7].center[self.FALLBACKFAULT] = 4
	self.uplift[7].inland = {}
	self.uplift[7].inland[self.CONVERGENTFAULT] = 1.8
	self.uplift[7].inland[self.FALLBACKFAULT] = 2
end
-------------------------------------------------------------------------------------------
function MapConstants:GetUpliftCoeff(faultType, landCount, pattern, position)
	if landCount == 1 then
		if position ~= self.CENTER then
			print(string.format("Warning: Unexpected position %i with landCount 1", position))
		end
		return self.uplift[1].center[faultType] or 1
	elseif landCount == 2 then
		if position == self.CENTER then
			return self.uplift[2].center[faultType] or 1
		elseif position == self.LONE then
			return self.uplift[2].lone[faultType] or 1
		else
			print(string.format("Warning: Unexpected position %i with landCount 2", position))
		end
	elseif landCount == 3 then
		if pattern == self.CONTIGUOUS then
			if position == self.CENTER then
				return self.uplift[3].contiguous.center[faultType] or 1
			elseif position == self.SHORE then
				return self.uplift[3].contiguous.shore[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 3 and pattern Contiguous",position))
			end
		elseif pattern == self.UNBALANCED then
			if position == self.CENTER then
				return self.uplift[3].unbalanced.center[faultType] or 1
			elseif position == self.LONE then
				return self.uplift[3].unbalanced.lone[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 3 and pattern Unbalanced",position))
			end			
		elseif pattern == self.BALANCED then
			if position == self.CENTER then
				return self.uplift[3].balanced.center[faultType] or 1
			elseif position == self.LONE then
				return self.uplift[3].balanced.lone[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 3 and pattern Balanced",position))
			end			
		else
			print(string.format("Warning: Unexpected pattern %i with landCount 3", pattern))
		end
	elseif landCount == 4 then
		if pattern == self.CONTIGUOUS then
			if position == self.CENTER then
				return self.uplift[4].contiguous.center[faultType] or 1
			elseif position == self.SHORE then
				return self.uplift[4].contiguous.shore[faultType] or 1
			elseif position == self.INLAND then
				return self.uplift[4].contiguous.inland[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 4 and pattern Contiguous",position))
			end
		elseif pattern == self.UNBALANCED then
			if position == self.CENTER then
				return self.uplift[4].unbalanced.center[faultType] or 1
			elseif position == self.LONE then
				return self.uplift[4].unbalanced.lone[faultType] or 1
			elseif position == self.SHORE then
				return self.uplift[4].unbalanced.shore[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 4 and pattern Unbalanced",position))
			end			
		elseif pattern == self.BALANCED then
			if position == self.CENTER then
				return self.uplift[4].balanced.center[faultType] or 1
			elseif position == self.LONE then
				return self.uplift[4].balanced.lone[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 4 and pattern Balanced",position))
			end			
		else
			print(string.format("Warning: Unexpected pattern %i with landCount 4", pattern))
		end
	elseif landCount == 5 then
		if pattern == self.CONTIGUOUS then
			if position == self.CENTER then
				return self.uplift[5].contiguous.center[faultType] or 1
			elseif position == self.SHORE then
				return self.uplift[5].contiguous.shore[faultType] or 1
			elseif position == self.INLAND then
				return self.uplift[5].contiguous.inland[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 5 and pattern Contiguous",position))
			end
		elseif pattern == self.UNBALANCED then
			if position == self.CENTER then
				return self.uplift[5].unbalanced.center[faultType] or 1
			elseif position == self.LONE then
				return self.uplift[5].unbalanced.lone[faultType] or 1
			elseif position == self.SHORE then
				return self.uplift[5].unbalanced.shore[faultType] or 1
			elseif position == self.INLAND then
				return self.uplift[5].unbalanced.inland[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 5 and pattern Unbalanced",position))
			end			
		elseif pattern == self.BALANCED then
			if position == self.CENTER then
				return self.uplift[5].balanced.center[faultType] or 1
			elseif position == self.SHORE then
				return self.uplift[5].balanced.shore[faultType] or 1
			else
				print(string.format("Warning: Unexpected position %i with landCount 5 and pattern Balanced",position))
			end			
		else
			print(string.format("Warning: Unexpected pattern %i with landCount 5", pattern))
		end
	elseif landCount == 6 then
		if position == self.CENTER then
			return self.uplift[6].center[faultType] or 1
		elseif position == self.SHORE then
			return self.uplift[6].shore[faultType] or 1
		elseif position == self.INTERMEDIATE then
			return self.uplift[6].intermediate[faultType] or 1
		elseif position == self.INLAND then
			return self.uplift[6].inland[faultType] or 1
		else
			print(string.format("Warning: Unexpected position %i with landCount 6", position))
		end
	elseif landCount == 7 then
		if position == self.CENTER then
			return self.uplift[7].center[faultType] or 1
		elseif position == self.INLAND then
			return self.uplift[7].inland[faultType] or 1
		else
			print(string.format("Warning: Unexpected position %i with landCount 7", position))
		end
	else
		print(string.format("Warning: Unexpected landCount of %i", landCount))
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeWorldAge()
	local age = Map.GetCustomOption(1)
	if age == 4 then
		age = 1 + Map.Rand(3, "Random World Age Option - Planet Simulator");
	end
	if age == 1 then		--Young
		print("Setting young world constants - Planet Simulator")
		self.hillsPercent = 0.65	
		self.mountainsPercent = 0.90
	elseif age == 3 then	--Old
		print("Setting old world constants - Planet Simulator")
		self.hillsPercent = 0.74 		
		self.mountainsPercent = 0.97 		
	else									--Standard
		print("Setting middle aged world constants - Planet Simulator")
		self.hillsPercent = 0.70 		--Percent of dry land that is below the hill elevation deviance threshold.		
		self.mountainsPercent = 0.94	--Percent of dry land that is below the mountain elevation deviance threshold. 	
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeTemperature()
	local temp = Map.GetCustomOption(2)
	if temp == 4 then
		temp = 1 + Map.Rand(3, "Random World Temperature Option - Planet Simulator");
	end
	if temp == 1 then						--Cold
		print("Setting cold world constants - Planet Simulator")
		self.desertMinTemperature = 0.40
		self.tundraTemperature = 0.35
		self.snowTemperature = 0.29
		
		self.treesMinTemperature = 0.30
		self.jungleMinTemperature = 0.75

		self.atollNorthLatitudeLimit = 42
		self.atollSouthLatitudeLimit = -42
		self.iceNorthLatitudeLimit = 60
		self.iceSouthLatitudeLimit = -60
	elseif temp == 3 then					--Warm
		print("Setting warm world constants - Planet Simulator")
		self.desertMinTemperature = 0.32
		self.tundraTemperature = 0.26
		self.snowTemperature = 0.20
		
		self.treesMinTemperature = 0.21
		self.jungleMinTemperature = 0.60

		self.atollNorthLatitudeLimit = 51
		self.atollSouthLatitudeLimit = -51
		self.iceNorthLatitudeLimit = 65
		self.iceSouthLatitudeLimit = -65
	else									--Standard
		print("Setting temperate world constants - Planet Simulator")
		self.desertMinTemperature = 0.35	--Coldest absolute temperature allowed to be desert, plains if colder.
		self.tundraTemperature = 0.31		--Absolute temperature below which is tundra.
		self.snowTemperature = 0.26 		--Absolute temperature below which is snow.
		
		self.treesMinTemperature = 0.27		--Coldest absolute temperature where trees appear.
		self.jungleMinTemperature = 0.66	--Coldest absolute temperature allowed to be jungle, forest if colder.

		self.atollNorthLatitudeLimit = 47	--Northern Atoll latitude limit.
		self.atollSouthLatitudeLimit = -47	--Southern Atoll latitude limit.
		self.iceNorthLatitudeLimit = 63		--Northern Ice latitude limit.
		self.iceSouthLatitudeLimit = -63	--Southern Ice latitude limit.
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeRainfall()
	local rain = Map.GetCustomOption(3)
	if rain == 4 then
		rain = 1 + Map.Rand(3, "Random World Rainfall Option - Planet Simulator");
	end
	if rain == 1 then					--Arid
		print("Setting arid world constants - Planet Simulator")
		self.desertPercent = 0.33
		self.plainsPercent = 0.55
		self.zeroTreesPercent = 0.78
		self.junglePercent = 0.94
		
		self.riverPercent = 0.14
		self.riverRainCheatFactor = 1.2
		self.minRiverSize = 32
		self.marshElevation = 0.04
	elseif rain == 3 then				--Wet
		print("Setting wet world constants - Planet Simulator")
		self.desertPercent = 0.20
		self.plainsPercent = 0.45
		self.zeroTreesPercent = 0.62
		self.junglePercent = 0.80
		
		self.riverPercent = 0.25
		self.riverRainCheatFactor = 1.6
		self.minRiverSize = 16
		self.marshElevation = 0.10
	else								--Standard
		print("Setting normal rainfall constants - Planet Simulator")
		self.desertPercent = 0.25		--Percent of land that is below the desert rainfall threshold.
		self.plainsPercent = 0.50 		--Percent of land that is below the plains rainfall threshold.
		self.zeroTreesPercent = 0.70 	--Percent of land that is below the rainfall threshold where no trees can appear.
		self.junglePercent = 0.88 		--Percent of land below the jungle rainfall threshold.
		
		self.riverPercent = 0.18 		--percent of river junctions that are large enough to become rivers.
		self.riverRainCheatFactor = 1.6 --This value is multiplied by each river step. Values greater than one favor watershed size. Values less than one favor actual rain amount.
		self.minRiverSize = 24			--Helps to prevent a lot of really short rivers. Recommended values are 15 to 40. -Bobert13
		self.marshElevation = 0.07 		--Percent of land below the lowlands marsh threshold.
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeSeaLevel()
	local sea = Map.GetCustomOption(4)
	if sea == 4 then
		sea = 1 + Map.Rand(3, "Random Sea Level Option - Planet Simulator");
	end
	if sea == 1 then			--Low
		print("Setting low sea level constants - Planet Simulator")
		self.landPercent = 0.37 
	elseif sea == 3 then		--High
		print("Setting high sea level constants - Planet Simulator")
		self.landPercent = 0.25		
	else						--Standard
		print("Setting medium sea level constants - Planet Simulator")
		self.landPercent = 0.31 --Percent of land tiles on the map.
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeCoasts()
	-- Superfluously Wide coasts can generate coast tiles more than 3 away from land,
	-- where the resources will be useless. However, this setting makes it quite likely
	-- that all continents will be connected by coast.
	-- Land-Adjacent Only coasts means that every coast tile will be adjacent to land,
	-- which means there will be fewer resources available in the sea, but also increases
	-- the chance of separation between continents (and gives the highest chance for more
	-- than two ocean-separated continental regions).
	-- Random does not include the extreme cases of Superfluously Wide or Land-Adjacent
	-- Only coasts.
	local width = Map.GetCustomOption(8)
	if width == 8 then
		width = 2 + Map.Rand(5, "Random Coastal Width Option - Planet Simulator")
	end
	if width == 7 then		--Superfluously Wide
		print("Setting superfluously wide coast constants - Planet Simulator")
		self.coastExpansionChance = {1,2,3,4,6,8}
	elseif width == 6 then	--Very Wide
		print("Setting very wide coast constants - Planet Simulator")
		self.coastExpansionChance = {1,2}
	elseif width == 5 then	--Wide
		print("Setting wide coast constants - Planet Simulator")
		self.coastExpansionChance = {2,3}
	elseif width == 3 then	--Narrow
		print("Setting narrow coast constants - Planet Simulator")
		self.coastExpansionChance = {6,8}
	elseif width == 2 then	--Very Narrow
		print("Setting very narrow coast constants - Planet Simulator")
		self.coastExpansionChance = {10}
	elseif width == 1 then	--Land-Adjacent Only
		print("Setting land-adjacent only coast constants - Planet Simulator")
		self.coastExpansionChance = {}
	else					--Standard
		print("Setting standard width coast constants - Planet Simulator")
		self.coastExpansionChance = {4,4}	--Odds of extending coast beyond one tile. Smaller is more likely. -LamilLerran
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeLakes()
	self.lakeFactor = 1
	--TODO: Make this actually do something useful
	--[[local lakes = Map.GetCustomOption(9)
	if lakes == 4 then
		lakes = 1 + Map.Rand(3, "Random Lakes Option - Planet Simulator");
	end
	if lakes == 1 then		--Uncommon
		print("Setting uncommon lakes constants - Planet Simulator")
		self.lakeFactor = 0.4
	elseif lakes == 3 then	--Frequent
		print("Setting frequent lakes constants - Planet Simulator")
		self.lakeFactor = 2
	else					--Standard
		print("Setting standard lakes constants - Planet Simulator")
		self.lakeFactor = 1	--adjusts target number of lakes in AddLakes(); larger means more
	end]]
end
-------------------------------------------------------------------------------------------
function MapConstants:InitializeIslands()
	--TODO: could use some fine tuning, especially for island expansion -LamilLerran
	local isles = Map.GetCustomOption(9)
	if isles == 6 then
		isles = 1 + Map.Rand(5, "Random Oceanic Islands Option - Planet Simulator");
	end
	if isles == 1 then		--Minimal
		print("Setting minimal islands constants - Planet Simulator")
		self.hotspotFrequency = 0
		self.oceanicVolcanoFrequency = 0.02
		self.islandExpansionFactor = 0
	elseif isles == 2 then	--Scattered and Small
		print("Setting scattered and small islands constants - Planet Simulator")
		self.hotspotFrequency = 0.2
		self.oceanicVolcanoFrequency = 0.02
		self.islandExpansionFactor = 0
	elseif isles == 3 then	--Large and Infrequent
		print("Setting large and infrequent islands constants - Planet Simulator")
		self.hotspotFrequency = 0
		self.oceanicVolcanoFrequency = 0.04
		self.islandExpansionFactor = .7
	elseif isles == 5 then	--Frequent and Varied
		print("Setting frequent and varied islands constants - Planet Simulator")
		self.hotspotFrequency = 0.05
		self.oceanicVolcanoFrequency = 0.1
		self.islandExpansionFactor = .4
		self.landPercentCheat = self.landPercentCheat - 0.02
	else					--Arcs of Small Islands
		print("Setting arcs of small islands constants - Planet Simulator")
		self.hotspotFrequency = 0			--What proportion of tiles are hotspots
		self.oceanicVolcanoFrequency = 0.20	--What proportion of tiles on an oceanic faultline or hotspot get an elevation boost?
		self.islandExpansionFactor = 0			--This tiles adjacent to a "volcano" (as selected above) also get an elevation
											--boost equal to this factor times the elevation boost of the main "volcano"
											--When 0, tiles adjacent to a "volcano" are unaffected by it.
	end
end
-------------------------------------------------------------------------------------------
function MapConstants:GetOppositeDir(dir)
	if dir == self.C then
		print("Warning: Finding direction opposite of Center")
	end
	return ((dir + 2) % 6) + 1
end
-------------------------------------------------------------------------------------------
function MapConstants:GetClockwiseDir(dir)
	if dir == self.C then
		print("Warning: Finding direction clockwise of Center")
	end
	return ((dir) % 6) + 1
end
-------------------------------------------------------------------------------------------
function MapConstants:GetCounterclockwiseDir(dir)
	if dir == self.C then
		print("Warning: Finding direction counterclockwise of Center")
	end
	return ((dir - 2) % 6) + 1
end
-------------------------------------------------------------------------------------------
--Returns a value along a bell curve from a 0 - 1 range
function MapConstants:GetBellCurve(value)
	return math.sin(value * math.pi * 2 - math.pi * 0.5) * 0.5 + 0.5
end
-------------------------------------------------------------------------------
--functions that Civ needs
-------------------------------------------------------------------------------
--function GetCoreMapOptions()
	--[[ All options have a default SortPriority of 0. Lower values will be shown above
	higher values. Negative integers are valid. So the Core Map Options, which should
	always be at the top of the list, are getting negative values from -99 to -95. Note
	that any set of options with identical SortPriority will be sorted alphabetically. ]]--
	--local resources = {
		--Name = "TXT_KEY_MAP_OPTION_RESOURCES",
		--Values = {
			--"TXT_KEY_MAP_OPTION_SPARSE",
			--"TXT_KEY_MAP_OPTION_STANDARD",
			--"TXT_KEY_MAP_OPTION_ABUNDANT",
			--"TXT_KEY_MAP_OPTION_LEGENDARY_START",
			--"TXT_KEY_MAP_OPTION_STRATEGIC_BALANCE",
			--"TXT_KEY_MAP_OPTION_RANDOM",
		--},
		--DefaultValue = 2,
		--SortPriority = 99,
	--};
	--return resources
--end
-------------------------------------------------------------------------------
function GetMapScriptInfo()
	local world_age, temperature, rainfall, sea_level, resources = GetCoreMapOptions()
	return {
		Name = "Planet Simulator",
		Description = "Tectonic Landmasses meet Geostrophic Weather",
		IsAdvancedMap = 0,
		SupportsMultiplayer = true,
		IconIndex = 1,
		SortIndex = 1,
		CustomOptions =
        {
			world_age,
			temperature,
			rainfall,
			sea_level,
			resources,
			{
				Name = "Map Preset",
				Values =
				{
					"Continents",
					"Pangaea"
				},
				DefaultValue = 1,
				SortPriority = 2,
            },
            {
                Name = "Start Placement",
                Values = {
                    "Start Anywhere",
                    "All Civs on Largest Continent"
                },
                DefaultValue = 1,
                SortPriority = 1,
            },
			-- Following options by LamilLerran
			{
				Name = "Coastal Waters",
				Values = 
				{
					"Land-Adjacent Only",
					"Very Narrow",
					"Narrow",
					"Standard",
					"Wide",
					"Very Wide",
					"Superfluously Wide",
					"Random"
				},
				DefaultValue = 4,
				SortPriority = 3,
			},
			{
				Name = "Islands",
				Values =
				{
					"Minimal",
					"Scattered and Small",
					"Large and Infrequent",
					"Arcs of Small Islands",
					"Frequent and Varied",
					"Random"
				},
				DefaultValue = 2,
				SortPriority = 4,
			},
			--[[
			{
				Name = "Lakes",
				Values =
				{
					"Uncommon",
					"Standard",
					"Frequent",
					"Random"
				},
				DefaultValue = 2,
				SortPriority = 5,
			},]]
        },
	};
end
-------------------------------------------------------------------------------------------
function GetMapInitData(worldSize)
	local worldsizes = {
		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {42, 26},
		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {52, 32},
		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {64, 40},
		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {84, 52},
		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {104, 64},
		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {128, 80}
		}
	if Map.GetCustomOption(7) == 2 then
		-- Enlarge terra-style maps to create expansion room on the new world
		worldsizes = {
		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = {52, 32},
		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = {64, 40},
		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = {84, 52},
		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = {104, 64},
		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = {122, 76},
		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = {144, 90},
		}
	end
	local grid_size = worldsizes[worldSize];
	--
	local world = GameInfo.Worlds[worldSize];
	if(world ~= nil) then
	return {
		Width = grid_size[1],
		Height = grid_size[2],
		WrapX = true,
	};
    end
end
-------------------------------------------------------------------------------------------
function Round(n)
	if n > 0 then
		if n - math.floor(n) >= 0.5 then
			return math.ceil(n)
		else
			return math.floor(n)
		end
	else
		if math.abs(n - math.ceil(n)) >= 0.5 then
			return math.floor(n)
		else
			return math.ceil(n)
		end
	end
end
-------------------------------------------------------------------------------------------
function Push(a,item)
	table.insert(a,item)
end
-------------------------------------------------------------------------------------------
function Pop(a)
	return table.remove(a)
end
------------------------------------------------------------------------
--inheritance mechanism from http://www.gamedev.net/community/forums/topic.asp?topic_id=561909
------------------------------------------------------------------------
function inheritsFrom( baseClass )

    local new_class = {}
    local class_mt = { __index = new_class }

    function new_class:create()
        local newinst = {}
        setmetatable( newinst, class_mt )
        return newinst
    end

    if nil ~= baseClass then
        setmetatable( new_class, { __index = baseClass } )
    end

    -- Implementation of additional OO properties starts here --

    -- Return the class object of the instance
    function new_class:class()
        return new_class;
    end

	-- Return the super class object of the instance, optional base class of the given class (must be part of hiearchy)
    function new_class:baseClass(class)
		return new_class:_B(class);
    end

    -- Return the super class object of the instance, optional base class of the given class (must be part of hiearchy)
    function new_class:_B(class)
		if (class==nil) or (new_class==class) then
			return baseClass;
		elseif(baseClass~=nil) then
			return baseClass:_B(class);
		end
		return nil;
    end

	-- Return true if the caller is an instance of theClass
    function new_class:_ISA( theClass )
        local b_isa = false

        local cur_class = new_class

        while ( nil ~= cur_class ) and ( false == b_isa ) do
            if cur_class == theClass then
                b_isa = true
            else
                cur_class = cur_class:baseClass()
            end
        end

        return b_isa
    end

    return new_class
end
-------------------------------------------------------------------------------------------
-- Random functions will use lua rands for stand alone script running
-- and Map.rand for in game.
-------------------------------------------------------------------------------------------
function PWRand()
	if not mc.MultiPlayer then
		return math.random()
	else
		return ((Map.Rand(65535,"") * 65536) + Map.Rand(65535,""))/4294967295 --32 bit floating point precision random for multiplayer.
	end
end
-------------------------------------------------------------------------------------------
function PWRandSeed(fixedseed)
	if not mc.MultiPlayer then
		local seed

		if fixedseed == nil then

			seed = (Map.Rand(32767,"") * 65536) + Map.Rand(65535,"")
		else
			seed = fixedseed
		end
		math.randomseed(seed) --This function caps at 2,147,483,647, if you set it any higher, or try to trick it with multiple RNGs that can end up with a value above this, it will break randomization.

		local W,H = Map.GetGridSize()
		print("Random seed for this "..W.."x"..H.." map is "..seed.." - Planet Simulator")
		PWRand() --Trash the first random to avoid issues on non-Windows systems.
	else
		print("Multiplayer game detected, using Map.Rand instead of a seeded lua random. - Planet Simulator")
	end
end
-------------------------------------------------------------------------------------------
--range is inclusive, low and high are possible results
function PWRandInt(low, high)
	if not mc.MultiPlayer then
		return math.random(low, high)
	else
		return Map.Rand(high-low,"")+low -- the maximum difference between high and low is 65,535 as Map.Rand is limited to returning a 16 bit integer.
	end
end
-------------------------------------------------------------------------------------------
-- Set class
-- Implements a set (unsorted collection without duplicates)
-------------------------------------------------------------------------------------------
Set = inheritsFrom(nil)

function Set.length(set)
	local length = 0
	for k, v in pairs(set) do
		length = length + 1
	end
	return length
end

function Set:New(elementsList)
	local new_inst = {}
	setmetatable(new_inst, {__index = Set});	--setup metatable
	
	for _, element in pairs(elementsList) do
		new_inst[element] = true
	end
	return new_inst
end

function Set.add(set,item)
	set[item] = true
end

function Set.delete(set,item)
	set[item] = nil
end

function Set.contains(set,item)
	return set[item] ~= nil
end
-------------------------------------------------------------------------------------------
-- FloatMap class
-- This is for storing 2D map data. The 'data' field is a zero based, one
-- dimensional array. To access map data by x and y coordinates, use the
-- GetIndex method to obtain the 1D index, which will handle any needs for
-- wrapping in the x and y directions.
-------------------------------------------------------------------------------------------
FloatMap = inheritsFrom(nil)

function FloatMap:New(width, height, wrapX, wrapY, initValue)
	local new_inst = {}
	setmetatable(new_inst, {__index = FloatMap});	--setup metatable

	new_inst.width = width
	new_inst.height = height
	new_inst.wrapX = wrapX
	new_inst.wrapY = wrapY
	new_inst.length = width*height

	--These fields are used to access only a subset of the map
	--with the GetRectIndex function. This is useful for
	--making Perlin noise wrap without generating separate
	--noise fields for each octave
	new_inst.rectX = 0
	new_inst.rectY = 0
	new_inst.rectWidth = width
	new_inst.rectHeight = height

	new_inst.data = {}
	if initValue == nil then	--default to initializing every tile to 0.0 -LL
		for i = 0,width*height - 1,1 do
			new_inst.data[i] = 0.0
		end
	else
		for i = 0,width*height - 1,1 do
			new_inst.data[i] = initValue
		end
	end
		

	return new_inst
end
-------------------------------------------------------------------------------------------
function FloatMap:GetNeighbor(x,y,dir,validate)
	--Note: by default validate is nil (i.e. false); in this case we will return the off-map
	--location where the tile would be in non-wrapping cases. When we validate, we return -1
	--for at least one coordinate of any off-map tile. -LL
	
	--Warning: Does not currently allow for Y wrapping -LL
	
	--Returns the x coordinate of the neighbor tile, then the y coordinate of the neighbor
	--tile, then whether this returned tile is a valid map location. Note that if you do
	--not pass validate = true, the third return value may be wrong!
	
	--Starting off the map is never valid
	if validate then
		if x < 0 or x >= self.width or y < 0 or y >= self.height then
			return -1, -1, false
		end
	end

	if (dir == nil) then
		error("Direction is nil in FloatMap:GetNeighbor")
	end
	
	local xx
	local yy
	local odd = y % 2
	if dir == mc.C then
		return x,y, x >= 0 and y >= 0
	elseif dir == mc.W then
		if x == 0 and self.wrapX then
			xx = self.width-1
			yy = y
		else
			xx = x - 1
			yy = y
		end
		return xx,yy, xx >= 0 and yy >= 0
	elseif dir == mc.NW then
		if x == 0 and odd == 0 and self.wrapX then
			xx = self.width-1
			yy = y + 1
		else
			xx = x - 1 + odd
			yy = y + 1
		end
		if validate and yy == self.height then
			yy = -1
		end
		return xx,yy, xx >= 0 and yy >= 0
	elseif dir == mc.NE then
		if x == self.width-1 and odd == 1 and self.wrapX then
			xx = 0
			yy = y+1
		else
			xx = x + odd
			yy = y + 1
			if validate and xx == self.width then
				xx = -1
			end
		end
		if validate and yy == self.height then
			yy = -1
		end
		return xx,yy, xx >= 0 and yy >= 0
	elseif dir == mc.E then
		if x == self.width-1 and self.wrapX then
			xx = 0
			yy = y
		else
			xx = x + 1
			yy = y
			if validate and xx == self.width then
				xx = -1
			end
		end
		return xx,yy, xx >= 0 and yy >= 0
	elseif dir == mc.SE then
		if x == self.width-1 and odd == 1 and self.wrapX then
			xx = 0
			yy = y - 1
		else
			xx = x + odd
			yy = y - 1
			if validate and xx == self.width then
				xx = -1
			end
		end
		return xx,yy, xx >= 0 and yy >= 0
	elseif dir == mc.SW then
		if x == 0 and odd == 0 and self.wrapX then
			xx = self.width - 1
			yy = y - 1
		else
			xx = x - 1 + odd
			yy = y - 1
		end
		return xx,yy, xx >= 0 and yy >= 0
	else
		print("Bad direction in FloatMap:GetNeighbor - Planet Simulator")
		error("Bad direction in FloatMap:GetNeighbor")
	end
	
	error("Invalid exit from FloatMap:GetNeighbor")
	
	return -1,-1, false
end
-------------------------------------------------------------------------------------------
function FloatMap:GetIndex(x,y)
	local xx
	if self.wrapX then
		xx = x % self.width
	elseif x < 0 or x > self.width - 1 then
		return -1
	else
		xx = x
	end

	if self.wrapY then
		yy = y % self.height
	elseif y < 0 or y > self.height - 1 then
		return -1
	else
		yy = y
	end

	return yy * self.width + xx
end
-------------------------------------------------------------------------------------------
function FloatMap:GetXYFromIndex(i)
	local x = i % self.width
	local y = (i - x)/self.width
	return x,y
end
-------------------------------------------------------------------------------------------
--quadrants are labeled
--A B
--D C
function FloatMap:GetQuadrant(x,y)
	if x < self.width/2 then
		if y < self.height/2 then
			return "A"
		else
			return "D"
		end
	else
		if y < self.height/2 then
			return "B"
		else
			return "C"
		end
	end
end
-------------------------------------------------------------------------------------------
--Gets an index for x and y based on the current
--rect settings. x and y are local to the defined rect.
--Wrapping is assumed in both directions
function FloatMap:GetRectIndex(x,y)
	local xx = x % self.rectWidth
	local yy = y % self.rectHeight

	xx = self.rectX + xx
	yy = self.rectY + yy

	return self:GetIndex(xx,yy)
end
-------------------------------------------------------------------------------------------
function FloatMap:Normalize(low,high)
	--Normalize to range 0,1 if no range is specified in parameters
	low = low or 0
	high = high or 1
	
	--find highest and lowest values
	local maxAlt = -1000.0
	local minAlt = 1000.0
	for i = 0,self.length - 1,1 do
		local alt = self.data[i]
		if alt > maxAlt then
			maxAlt = alt
		elseif alt < minAlt then
			minAlt = alt
		end
	end
	--subtract minAlt from all values so that
	--all values are zero and above
	for i = 0, self.length - 1, 1 do
		self.data[i] = self.data[i] - minAlt
	end

	--subract minAlt also from maxAlt
	maxAlt = maxAlt - minAlt

	--determine and apply scaler to whole map
	local scaler
	if maxAlt == 0.0 then
		scaler = 0.0
	else
		scaler = 1.0/maxAlt
	end

	for i = 0,self.length - 1,1 do
		self.data[i] = self.data[i] * scaler
	end

end
-------------------------------------------------------------------------------------------
function FloatMap:GenerateNoise()
	for i = 0,self.length - 1,1 do
		self.data[i] = PWRand()
	end

end
-------------------------------------------------------------------------------------------
function FloatMap:GenerateBinaryNoise()
	for i = 0,self.length - 1,1 do
		if PWRand() > 0.5 then
			self.data[i] = 1
		else
			self.data[i] = 0
		end
	end

end
-------------------------------------------------------------------------------------------
function FloatMap:FindThresholdFromPercent(percent, greaterThan, excludeZeros)
	local mapList = {}
	local percentage = percent * 100
	local const = 0.0

	if not excludeZeros then
		const = 0.000000000000000001
	end

	if greaterThan then
		percentage = 100-percentage
	end

	if percentage >= 100 then
		return 1.01 --whole map
	elseif percentage <= 0 then
		return -0.01 --none of the map
	end

	for i=0,self.length-1,1 do
		if not (self.data[i] == 0.0 and excludeZeros) then
			table.insert(mapList,self.data[i])
		end
	end

	table.sort(mapList, function (a,b) return a < b end)
	local threshIndex = math.floor((#mapList * percentage)/100)

	return mapList[threshIndex-1]+const
end
-------------------------------------------------------------------------------------------
function FloatMap:GetLatitudeForY(y)
	local range = mc.topLatitude - mc.bottomLatitude
	local lat = nil
	if y < self.height/2 then
		lat = (y+1) / self.height * range + (mc.bottomLatitude - mc.topLatitude / self.height)
	else
		lat = y / self.height * range + (mc.bottomLatitude + mc.topLatitude / self.height)
	end
	return lat
end
-------------------------------------------------------------------------------------------
function FloatMap:GetYForLatitude(lat)
	local range = mc.topLatitude - mc.bottomLatitude
	local y = nil
	if lat < 0 then
		y = math.floor(((lat - (mc.bottomLatitude - mc.topLatitude / self.height)) / range * self.height))
	else
		y = math.ceil(((lat - (mc.bottomLatitude + mc.topLatitude / self.height)) / range * self.height) - 1)
	end
	return y
end
-------------------------------------------------------------------------------------------
function FloatMap:GetZone(y)
	local lat = self:GetLatitudeForY(y)
	if y < 0 or y >= self.height then
		return mc.NOZONE
	end
	if lat > mc.polarFrontLatitude then
		return mc.NPOLAR
	elseif lat >= mc.horseLatitudes then
		return mc.NTEMPERATE
	elseif lat >= 0.0 then
		return mc.NEQUATOR
	elseif lat > -mc.horseLatitudes then
		return mc.SEQUATOR
	elseif lat >= -mc.polarFrontLatitude then
		return mc.STEMPERATE
	else
		return mc.SPOLAR
	end
end
-------------------------------------------------------------------------------------------
function FloatMap:GetYFromZone(zone, bTop)
	if bTop then
		for y=self.height - 1,0,-1 do
			if zone == self:GetZone(y) then
				return y
			end
		end
	else
		for y=0,self.height - 1,1 do
			if zone == self:GetZone(y) then
				return y
			end
		end
	end
	return -1
end
-------------------------------------------------------------------------------------------
function FloatMap:GetGeostrophicWindDirections(zone)

	if zone == mc.NPOLAR then
		return mc.SW,mc.W
	elseif zone == mc.NTEMPERATE then
		return mc.NE,mc.E
	elseif zone == mc.NEQUATOR then
		return mc.SW,mc.W
	elseif zone == mc.SEQUATOR then
		return mc.NW,mc.W
	elseif zone == mc.STEMPERATE then
		return mc.SE, mc.E
	else
		return mc.NW,mc.W
	end
	return -1,-1
end
-------------------------------------------------------------------------------------------
function FloatMap:GetGeostrophicPressure(lat)
	local latRange = nil
	local latPercent = nil
	local pressure = nil
	if lat > mc.polarFrontLatitude then
		latRange = 90.0 - mc.polarFrontLatitude
		latPercent = (lat - mc.polarFrontLatitude)/latRange
		pressure = 1.0 - latPercent
	elseif lat >= mc.horseLatitudes then
		latRange = mc.polarFrontLatitude - mc.horseLatitudes
		latPercent = (lat - mc.horseLatitudes)/latRange
		pressure = latPercent
	elseif lat >= 0.0 then
		latRange = mc.horseLatitudes - 0.0
		latPercent = (lat - 0.0)/latRange
		pressure = 1.0 - latPercent
	elseif lat > -mc.horseLatitudes then
		latRange = 0.0 + mc.horseLatitudes
		latPercent = (lat + mc.horseLatitudes)/latRange
		pressure = latPercent
	elseif lat >= -mc.polarFrontLatitude then
		latRange = -mc.horseLatitudes + mc.polarFrontLatitude
		latPercent = (lat + mc.polarFrontLatitude)/latRange
		pressure = 1.0 - latPercent
	else
		latRange = -mc.polarFrontLatitude + 90.0
		latPercent = (lat + 90)/latRange
		pressure = latPercent
	end
	pressure = pressure + 1
	if pressure > 1.5 then
		pressure = pressure * mc.pressureNorm
	else
		pressure = pressure / mc.pressureNorm
	end
	pressure = pressure - 1
	--print(pressure)
	return pressure
end
-------------------------------------------------------------------------------------------
function FloatMap:ApplyFunction(func)
	for i = 0,self.length - 1,1 do
		self.data[i] = func(self.data[i])
	end
end
-------------------------------------------------------------------------------------------
function GetCircle(i,radius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local tab = {}
	local topY = radius
	local bottomY = radius
	local currentY = nil
	local len = 1+radius

	--constrain the top of our circle to be on the map
	if y+radius > H-1 then
		for r=0,radius-1,1 do
			if y+r == H-1 then
				topY = r
				break
			end
		end
	end
	--constrain the bottom of our circle to be on the map
	if y-radius < 0 then
		for r=0,radius,1 do
			if y-r == 0 then
				bottomY = r
				break
			end
		end
	end

	--adjust starting length, apply the top and bottom limits, and correct odd for the starting point
	len = len+(radius-bottomY)
	currentY = y - bottomY
	topY = y + topY
	odd = (odd+bottomY)%2
	--set the starting point, the if statement checks for xWrap
	if x-(radius-bottomY)-math.floor((bottomY+odd)/2) < 0 then
		i = i-(W*bottomY)+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		x = x+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
	else
		i = i-(W*bottomY)-(radius-bottomY)-math.floor((bottomY+odd)/2)
		x = x-(radius-bottomY)-math.floor((bottomY+odd)/2)
	end

	--cycle through the plot indexes and add them to a table
	while currentY <= topY do
		--insert the start value, scan left to right adding each index in the line to our table
		table.insert(tab,i)

		local wrapped = false
		for n=1,len-1,1 do
			if x ~= (W-1) then
				i = i + 1
				x = x + 1
			else
				i = i-(W-1)
				x = 0
				wrapped = true
			end
			table.insert(tab,i)
		end

		if currentY < y then
			--move i NW and increment the length to scan
			if not wrapped then
				i = i+W-len+odd
				x = x-len+odd
			else
				i = i+W+(W-len+odd)
				x = x+(W-len+odd)
			end
			len = len+1
		else
			--move i NE and decrement the length to scan
			if not wrapped then
				i = i+W-len+1+odd
				x = x-len+1+odd
			else
				i = i+W+(W-len+1+odd)
				x = x+(W-len+1+odd)
			end
			len = len-1
		end

		currentY = currentY+1
		if odd == 0 then
			odd = 1
		else
			odd = 0
		end
	end
	return tab
end
-------------------------------------------------------------------------------------------
function GetSpiral(i,maxRadius,minRadius)
	--Returns a list of all the tiles at least minRadius from tile i and no more than
	--maxRadius from tile i. For each such tile that would be located off the map, include
	--a -1 in the list instead. The list is ordered from small radius to large radius. If
	--minRadius is omitted, it will default to 0. (description by LamilLerran)
	--Starts each loop due west, then goes around clockwise.

	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local tab ={}
	local first = true


	if minRadius == nil or minRadius == 0 then
		table.insert(tab,i)
		minRadius = 1
	end

	for r = minRadius, maxRadius, 1 do
		if first == true then
			--start r to the west on the first spiral
			if x-r > -1 then
				i = i-r
				x = x-r
			else
				i = i+(W-r)
				x = x+(W-r)
			end
			first = false
		else
			--go west 1 tile before the next spiral
			if x ~= 0 then
				i = i-1
				x = x-1
			else
				i = i+(W-1)
				x = W-1
			end
		end
		--Go r times to the NE
		for z=1,r,1 do
			if x ~= (W-1) or odd == 0 then
				i = i+W+odd
				x = x+odd
			else
				i = i + 1
				x = 0
			end

			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
		--Go r times to the E
		for z=1,r,1 do
			if x ~= (W-1) then
				i = i+1
				x = x+1
			else
				i = i-(W-1)
				x = 0
			end

			--store the index value or -1 if the plot isn't on the map
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
		end
		--Go r times to the SE
		for z=1,r,1 do
			if x ~= (W-1) or odd == 0 then
				i = i-W+odd
				x = x+odd
			else
				i = i-(W+(W-1))
				x = 0
			end

			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
		--Go r times to the SW
		for z=1,r,1 do
			if x ~= 0 or odd == 1 then
				i = i-W-1+odd
				x = x-1+odd
			else
				i = i-(W+1)
				x = (W-1)
			end

			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
		--Go r times to the W
		for z = 1,r,1 do
			if x ~= 0 then
				i = i-1
				x=x-1
			else
				i = i+(W-1)
				x = (W-1)
			end

			--store the index value or -1 if the plot isn't on the map
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
		end
		--Go r times to the NW!!!!!
		for z = 1,r,1 do
			if x ~= 0 or odd == 1 then
				i = i+W-1+odd
				x = x-1+odd
			else
				i = i+W+(W-1)
				x = W-1
			end

			--store the index value or -1 if the plot isn't on the map; flip odd
			if i > -1 and i < WH then table.insert(tab,i) else table.insert(tab,-1) end
			if odd == 0 then odd = 1 else odd = 0 end
		end
	end

	return tab
end
-------------------------------------------------------------------------------------------
function FloatMap:GetAverageInHex(i,radius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local topY = radius
	local bottomY = radius
	local currentY = nil
	local len = 1+radius
	local avg = 0
	local count = 0

	--constrain the top of our circle to be on the map
	if y+radius > H-1 then
		for r=0,radius-1,1 do
			if y+r == H-1 then
				topY = r
				break
			end
		end
	end
	--constrain the bottom of our circle to be on the map
	if y-radius < 0 then
		for r=0,radius,1 do
			if y-r == 0 then
				bottomY = r
				break
			end
		end
	end

	--adjust starting length, apply the top and bottom limits, and correct odd for the starting point
	len = len+(radius-bottomY)
	currentY = y - bottomY
	topY = y + topY
	odd = (odd+bottomY)%2
	--set the starting point, the if statement checks for xWrap
	if x-(radius-bottomY)-math.floor((bottomY+odd)/2) < 0 then
		i = i-(W*bottomY)+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		x = x+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		-- print(string.format("i for (%d,%d) WOULD have been in outer space. x is (%d,%d) i is (%d)",xx,y,x,y-bottomY,i))
	else
		i = i-(W*bottomY)-(radius-bottomY)-math.floor((bottomY+odd)/2)
		x = x-(radius-bottomY)-math.floor((bottomY+odd)/2)
	end

	--cycle through the plot indexes and add them to a table
	while currentY <= topY do
		--insert the start value, scan left to right adding each index in the line to our table

		avg = avg+self.data[i]
		local wrapped = false
		for n=1,len-1,1 do
			if x ~= (W-1) then
				i = i + 1
				x = x + 1
			else
				i = i-(W-1)
				x = 0
				wrapped = true
			end
			avg = avg+self.data[i]
			count = count+1
		end

		if currentY < y then
			--move i NW and increment the length to scan
			if not wrapped then
				i = i+W-len+odd
				x = x-len+odd
			else
				i = i+W+(W-len+odd)
				x = x+(W-len+odd)
			end
			len = len+1
		else
			--move i NE and decrement the length to scan
			if not wrapped then
				i = i+W-len+1+odd
				x = x-len+1+odd
			else
				i = i+W+(W-len+1+odd)
				x = x+(W-len+1+odd)
			end
			len = len-1
		end

		currentY = currentY+1
		if odd == 0 then
			odd = 1
		else
			odd = 0
		end
	end

	avg = avg/count
	return avg
end
-------------------------------------------------------------------------------------------
function FloatMap:GetStdDevInHex(i,radius)
	local W,H = Map.GetGridSize()
	local WH = W*H
	local x = i%W
	local y = (i-x)/W
	local odd = y%2
	local topY = radius
	local bottomY = radius
	local currentY = nil
	local len = 1+radius
	local avg = self:GetAverageInHex(i,radius)
	local deviation = 0
	local count = 0

	--constrain the top of our circle to be on the map
	if y+radius > H-1 then
		for r=0,radius-1,1 do
			if y+r == H-1 then
				topY = r
				break
			end
		end
	end
	--constrain the bottom of our circle to be on the map
	if y-radius < 0 then
		for r=0,radius,1 do
			if y-r == 0 then
				bottomY = r
				break
			end
		end
	end

	--adjust starting length, apply the top and bottom limits, and correct odd for the starting point
	len = len+(radius-bottomY)
	currentY = y - bottomY
	topY = y + topY
	odd = (odd+bottomY)%2
	--set the starting point, the if statement checks for xWrap
	if x-(radius-bottomY)-math.floor((bottomY+odd)/2) < 0 then
		i = i-(W*bottomY)+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
		x = x+(W-(radius-bottomY))-math.floor((bottomY+odd)/2)
	else
		i = i-(W*bottomY)-(radius-bottomY)-math.floor((bottomY+odd)/2)
		x = x-(radius-bottomY)-math.floor((bottomY+odd)/2)
	end

	--cycle through the plot indexes and add them to a table
	while currentY <= topY do
		--insert the start value, scan left to right adding each index in the line to our table

		local sqr = self.data[i] - avg
		deviation = deviation + (sqr * sqr)
		local wrapped = false
		for n=1,len-1,1 do
			if x ~= (W-1) then
				i = i + 1
				x = x + 1
			else
				i = i-(W-1)
				x = 0
				wrapped = true
			end

			sqr = self.data[i] - avg
			deviation = deviation + (sqr * sqr)
			count = count+1
		end

		if currentY < y then
			--move i NW and increment the length to scan
			if not wrapped then
				i = i+W-len+odd
				x = x-len+odd
			else
				i = i+W+(W-len+odd)
				x = x+(W-len+odd)
			end
			len = len+1
		else
			--move i NE and decrement the length to scan
			if not wrapped then
				i = i+W-len+1+odd
				x = x-len+1+odd
			else
				i = i+W+(W-len+1+odd)
				x = x+(W-len+1+odd)
			end
			len = len-1
		end

		currentY = currentY+1
		if odd == 0 then
			odd = 1
		else
			odd = 0
		end
	end

	deviation = math.sqrt(deviation/count)
	return deviation
end
-------------------------------------------------------------------------------------------
function FloatMap:Smooth(radius)
	local dataCopy = {}

	if radius > 8 then
		radius = 8
	end

	for i=0,self.length-1,1 do
			dataCopy[i] = self:GetAverageInHex(i,radius)
	end

	self.data = dataCopy
end
-------------------------------------------------------------------------------------------
function FloatMap:Deviate(radius)
	local dataCopy = {}

	if radius > 7 then
		radius = 7
	end
	for i=0,self.length-1,1 do
		dataCopy[i] = self:GetStdDevInHex(i,radius)
	end

	self.data = dataCopy
end
-------------------------------------------------------------------------------------------
function FloatMap:IsOnMap(x,y)
	local i = self:GetIndex(x,y)
	if i == -1 then
		return false
	end
	return true
end
-------------------------------------------------------------------------------------------
function FloatMap:Save(name)
	print("saving " .. name .. "...")
	local str = self.width .. "," .. self.height
	for i = 0,self.length - 1,1 do
		str = str .. "," .. self.data[i]
	end
	local file = io.open(name,"w+")
	file:write(str)
	file:close()
	print("bitmap saved as " .. name .. ".")
end
-------------------------------------------------------------------------------------------
function FloatMap:Save2(name)
	local file = io.open(name,"w+")
	local first = true
	local str = ""
	for y = self.height, 0, -1 do
		if first then
			str = "xy,"
		else
			str = string.format("%d,",y)
		end
		for x = 0, self.width-1 do
			local i = y*self.width+(x%self.width)
			if first then
				if x < self.width-1 then
					str = str..string.format("%d,",x)
				else
					str = str..string.format("%d\n",x)
				end
			elseif x < self.width-1 then
				str = str..string.format("%d,",self.ID[i])
			else
				str = str..string.format("%d\n",self.ID[i])
			end
		end
		first = false
		file:write(str)
	end
	file:close()
	print("bitmap saved as "..name..".")
end
-------------------------------------------------------------------------------------------
function FloatMap:Save3(name)
	local file = io.open(name,"w+")
	local first = true
	local str = ""
	for y = self.height, 0, -1 do
		if first then
			str = "xy,"
		else
			str = string.format("%d,",y)
		end
		for x = 0, self.width-1 do
			local i = y*self.width+(x%self.width)
			if first then
				if x < self.width-1 then
					str = str..string.format("%d,",x)
				else
					str = str..string.format("%d\n",x)
				end
			elseif x < self.width-1 then
				str = str..string.format("%d,",self.fault[i])
			else
				str = str..string.format("%d\n",self.fault[i])
			end
		end
		first = false
		file:write(str)
	end
	file:close()
	print("bitmap saved as "..name..".")
end
-------------------------------------------------------------------------------------------
function FloatMap:Save4(name,precision)
	local file = io.open(name,"w+")
	local first = true
	local str = ""
	local decimalPlaces = precision or 1
	for y = self.height, 0, -1 do
		if first then
			str = "xy,"
		else
			str = string.format("%d,",y)
		end
		for x = 0, self.width-1 do
			local i = y*self.width+(x%self.width)
			if first then
				if x < self.width-1 then
					str = str..string.format("%d,",x)
				else
					str = str..string.format("%d\n",x)
				end
			elseif x < self.width-1 then
				str = str..string.format("%."..decimalPlaces.."f,",self.data[i])
			else
				str = str..string.format("%."..decimalPlaces.."f\n",self.data[i])
			end
		end
		first = false
		file:write(str)
	end
	file:close()
	print("bitmap saved as "..name..".")
end
-------------------------------------------------------------------------------------------
--ElevationMap class
-------------------------------------------------------------------------------------------
ElevationMap = inheritsFrom(FloatMap)

function ElevationMap:New(width, height, wrapX, wrapY)
	local new_inst = FloatMap:New(width,height,wrapX,wrapY)
	setmetatable(new_inst, {__index = ElevationMap});	--setup metatable
	return new_inst
end
-------------------------------------------------------------------------------------------
function ElevationMap:IsBelowSeaLevel(x,y)
	local i = self:GetIndex(x,y)
	if self.data[i] < self.seaLevelThreshold then
		return true
	else
		return false
	end
end
-------------------------------------------------------------------------------------------
--AreaMap class
-------------------------------------------------------------------------------------------
PWAreaMap = inheritsFrom(FloatMap)

function PWAreaMap:New(width,height,wrapX,wrapY)
	local new_inst = FloatMap:New(width,height,wrapX,wrapY)
	setmetatable(new_inst, {__index = PWAreaMap});	--setup metatable

	new_inst.areaList = {}
	new_inst.segStack = {}
	return new_inst
end
-------------------------------------------------------------------------------------------
function PWAreaMap:DefineAreas(matchFunction)
	--zero map data
	for i = 0,self.width*self.height - 1,1 do
		self.data[i] = 0.0
	end

	self.areaList = {}
	local currentAreaID = 0
	local i = 0
	for y = 0, self.height - 1,1 do
		for x = 0, self.width - 1,1 do
			if self.data[i] == 0 then
				currentAreaID = currentAreaID + 1
				local area = PWArea:New(currentAreaID,x,y,matchFunction(x,y))
				--print(string.format("Filling area %d, matchFunction(x = %d,y = %d) = %s",area.id,x,y,tostring(matchFunction(x,y)))
				self:FillArea(x,y,area,matchFunction)
				table.insert(self.areaList, area)
			end
			i=i+1
		end
	end
end
-------------------------------------------------------------------------------------------
function PWAreaMap:FillArea(x,y,area,matchFunction)
	self.segStack = {}
	local seg = LineSeg:New(y,x,x,1)
	Push(self.segStack,seg)
	seg = LineSeg:New(y + 1,x,x,-1)
	Push(self.segStack,seg)
	while #self.segStack > 0 do
		seg = Pop(self.segStack)
		self:ScanAndFillLine(seg,area,matchFunction)
	end
end
-------------------------------------------------------------------------------------------
function PWAreaMap:ScanAndFillLine(seg,area,matchFunction)

	--str = string.format("Processing line y = %d, xLeft = %d, xRight = %d, dy = %d -------",seg.y,seg.xLeft,seg.xRight,seg.dy)
	--print(str)
	if self:ValidateY(seg.y + seg.dy) == -1 then
		return
	end

	local odd = (seg.y + seg.dy) % 2
	local notOdd = seg.y % 2
	--str = string.format("odd = %d, notOdd = %d",odd,notOdd)
	--print(str)

	local lineFound = 0
	local xStop = nil
	if self.wrapX then
		xStop = 0 - (self.width * 30)
	else
		xStop = -1
	end
	local leftExtreme = nil
	for leftExt = seg.xLeft - odd,xStop + 1,-1 do
		leftExtreme = leftExt --need this saved
		--str = string.format("leftExtreme = %d",leftExtreme)
		--print(str)
		local x = self:ValidateX(leftExtreme)
		local y = self:ValidateY(seg.y + seg.dy)
		local i = self:GetIndex(x,y)
		--str = string.format("x = %d, y = %d, area.trueMatch = %s, matchFunction(x,y) = %s",x,y,tostring(area.trueMatch),tostring(matchFunction(x,y)))
		--print(str)
		if self.data[i] == 0 and area.trueMatch == matchFunction(x,y) then
			self.data[i] = area.id
			area.size = area.size + 1
			--print("adding to area")
			lineFound = 1
		else
			--if no line was found, then leftExtreme is fine, but if
			--a line was found going left, then we need to increment
            --xLeftExtreme to represent the inclusive end of the line
			if lineFound == 1 then
				leftExtreme = leftExtreme + 1
				--print("line found, adding 1 to leftExtreme")
			end
			break
		end
	end
	--str = string.format("leftExtreme = %d",leftExtreme)
	--print(str)
	local rightExtreme = nil
	--now scan right to find extreme right, place each found segment on stack
	if self.wrapX then
		xStop = self.width * 20
	else
		xStop = self.width
	end
	for rightExt = seg.xLeft + lineFound - odd,xStop - 1,1 do
		rightExtreme = rightExt --need this saved
		--str = string.format("rightExtreme = %d",rightExtreme)
		--print(str)
		local x = self:ValidateX(rightExtreme)
		local y = self:ValidateY(seg.y + seg.dy)
		local i = self:GetIndex(x,y)
		--str = string.format("x = %d, y = %d, area.trueMatch = %s, matchFunction(x,y) = %s",x,y,tostring(area.trueMatch),tostring(matchFunction(x,y)))
		--print(str)
		if self.data[i] == 0 and area.trueMatch == matchFunction(x,y) then
			self.data[i] = area.id
			area.size = area.size + 1
			--print("adding to area")
			if lineFound == 0 then
				lineFound = 1 --starting new line
				leftExtreme = rightExtreme
			end
		elseif lineFound == 1 then --found the right end of a line segment
			--print("found right end of line")
			lineFound = 0
			--put same direction on stack
			local newSeg = LineSeg:New(y,leftExtreme,rightExtreme - 1,seg.dy)
			Push(self.segStack,newSeg)
			--str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",y,leftExtreme,rightExtreme - 1,seg.dy)
			--print(str)
			--determine if we must put reverse direction on stack
			if leftExtreme < seg.xLeft - odd or rightExtreme >= seg.xRight + notOdd then
				--out of shadow so put reverse direction on stack
				newSeg = LineSeg:New(y,leftExtreme,rightExtreme - 1,-seg.dy)
				Push(self.segStack,newSeg)
				--str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",y,leftExtreme,rightExtreme - 1,-seg.dy)
				--print(str)
			end
			if(rightExtreme >= seg.xRight + notOdd) then
				break
			end
		elseif lineFound == 0 and rightExtreme >= seg.xRight + notOdd then
			break --past the end of the parent line and no line found
		end
		--continue finding segments
	end
	if lineFound == 1 then --still needing a line to be put on stack
		print("still need line segments")
		lineFound = 0
		--put same direction on stack
		local newSeg = LineSeg:New(seg.y + seg.dy,leftExtreme,rightExtreme - 1,seg.dy)
		Push(self.segStack,newSeg)
		str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",seg.y + seg.dy,leftExtreme,rightExtreme - 1,seg.dy)
		print(str)
		--determine if we must put reverse direction on stack
		if leftExtreme < seg.xLeft - odd or rightExtreme >= seg.xRight + notOdd then
			--out of shadow so put reverse direction on stack
			newSeg = LineSeg:New(seg.y + seg.dy,leftExtreme,rightExtreme - 1,-seg.dy)
			Push(self.segStack,newSeg)
			str = string.format("  pushing y = %d, xLeft = %d, xRight = %d, dy = %d",seg.y + seg.dy,leftExtreme,rightExtreme - 1,-seg.dy)
			print(str)
		end
	end
end
-------------------------------------------------------------------------------------------
function PWAreaMap:GetAreaByID(id)
	for i = 1,#self.areaList,1 do
		if self.areaList[i].id == id then
			return self.areaList[i]
		end
	end
	error("Can't find area id in AreaMap.areaList")
end
-------------------------------------------------------------------------------------------
function PWAreaMap:ValidateY(y)
	local yy = nil
	if self.wrapY then
		yy = y % self.height
	elseif y < 0 or y >= self.height then
		return -1
	else
		yy = y
	end
	return yy
end
-------------------------------------------------------------------------------------------
function PWAreaMap:ValidateX(x)
	local xx = nil
	if self.wrapX then
		xx = x % self.width
	elseif x < 0 or x >= self.width then
		return -1
	else
		xx = x
	end
	return xx
end
-------------------------------------------------------------------------------------------
function PWAreaMap:PrintAreaList()
	for i=1,#self.areaList,1 do
		local id = self.areaList[i].id
		local seedx = self.areaList[i].seedx
		local seedy = self.areaList[i].seedy
		local size = self.areaList[i].size
		local trueMatch = self.areaList[i].trueMatch
		local str = string.format("area id = %d, trueMatch = %s, size = %d, seedx = %d, seedy = %d",id,tostring(trueMatch),size,seedx,seedy)
		print(str)
	end
end
-------------------------------------------------------------------------------------------
--Area class
-------------------------------------------------------------------------------------------
PWArea = inheritsFrom(nil)

function PWArea:New(id,seedx,seedy,trueMatch)
	local new_inst = {}
	setmetatable(new_inst, {__index = PWArea});	--setup metatable

	new_inst.id = id
	new_inst.seedx = seedx
	new_inst.seedy = seedy
	new_inst.trueMatch = trueMatch
	new_inst.size = 0

	return new_inst
end
-------------------------------------------------------------------------------------------
--LineSeg class
-------------------------------------------------------------------------------------------
LineSeg = inheritsFrom(nil)

function LineSeg:New(y,xLeft,xRight,dy)
	local new_inst = {}
	setmetatable(new_inst, {__index = LineSeg});	--setup metatable

	new_inst.y = y
	new_inst.xLeft = xLeft
	new_inst.xRight = xRight
	new_inst.dy = dy

	return new_inst
end
-------------------------------------------------------------------------------------------
--RiverMap class
-------------------------------------------------------------------------------------------
RiverMap = inheritsFrom(nil)

function RiverMap:New()
	local new_inst = {}
	setmetatable(new_inst, {__index = RiverMap});

	new_inst.riverData = {}
	local i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			new_inst.riverData[i] = RiverHex:New(x,y)
			i=i+1
		end
	end

	return new_inst
end
-------------------------------------------------------------------------------------------
function RiverMap:GetJunction(x,y,isNorth)
	local i = elevationMap:GetIndex(x,y)
	if isNorth then
		return self.riverData[i].northJunction
	else
		return self.riverData[i].southJunction
	end
end
-------------------------------------------------------------------------------------------
function RiverMap:GetJunctionNeighbor(direction,junction)
	local xx = nil
	local yy = nil
	local ii = nil
	local neighbor = nil
	local odd = junction.y % 2
	if direction == mc.NOFLOW then
		error("can't get junction neighbor in direction NOFLOW")
	elseif direction == mc.WESTFLOW then
		xx = junction.x + odd - 1
		if junction.isNorth then
			yy = junction.y + 1
		else
			yy = junction.y - 1
		end
		ii = elevationMap:GetIndex(xx,yy)
		if ii ~= -1 then
			neighbor = self:GetJunction(xx,yy,not junction.isNorth)
			return neighbor
		end
	elseif direction == mc.EASTFLOW then
		xx = junction.x + odd
		if junction.isNorth then
			yy = junction.y + 1
		else
			yy = junction.y - 1
		end
		ii = elevationMap:GetIndex(xx,yy)
		if ii ~= -1 then
			neighbor = self:GetJunction(xx,yy,not junction.isNorth)
			return neighbor
		end
	elseif direction == mc.VERTFLOW then
		xx = junction.x
		if junction.isNorth then
			yy = junction.y + 2
		else
			yy = junction.y - 2
		end
		ii = elevationMap:GetIndex(xx,yy)
		if ii ~= -1 then
			neighbor = self:GetJunction(xx,yy,not junction.isNorth)
			return neighbor
		end
	end

	return nil --neighbor off map
end
-------------------------------------------------------------------------------------------
--Get the west or east hex neighboring this junction
function RiverMap:GetRiverHexNeighbor(junction,westNeighbor)
	local xx = nil
	local yy = nil
	local ii = nil
	local odd = junction.y % 2
	if junction.isNorth then
		yy = junction.y + 1
	else
		yy = junction.y - 1
	end
	if westNeighbor then
		xx = junction.x + odd - 1
	else
		xx = junction.x + odd
	end

	ii = elevationMap:GetIndex(xx,yy)
	if ii ~= -1 then
		return self.riverData[ii]
	end

	return nil
end
-------------------------------------------------------------------------------------------
function RiverMap:SetJunctionAltitudes()
	local i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			local vertAltitude = elevationMap.data[i]
			local westAltitude = nil
			local eastAltitude = nil
			local vertNeighbor = self.riverData[i]
			local westNeighbor = nil
			local eastNeighbor = nil
			local xx = nil
			local yy = nil
			local ii = nil

			--first do north
			westNeighbor = self:GetRiverHexNeighbor(vertNeighbor.northJunction,true)
			eastNeighbor = self:GetRiverHexNeighbor(vertNeighbor.northJunction,false)

			if westNeighbor ~= nil then
				ii = elevationMap:GetIndex(westNeighbor.x,westNeighbor.y)
			else
				ii = -1
			end

			if ii ~= -1 then
				westAltitude = elevationMap.data[ii]
			else
				westAltitude = vertAltitude
			end

			if eastNeighbor ~= nil then
				ii = elevationMap:GetIndex(eastNeighbor.x, eastNeighbor.y)
			else
				ii = -1
			end

			if ii ~= -1 then
				eastAltitude = elevationMap.data[ii]
			else
				eastAltitude = vertAltitude
			end

			vertNeighbor.northJunction.altitude = math.min(math.min(vertAltitude,westAltitude),eastAltitude)

			--then south
			westNeighbor = self:GetRiverHexNeighbor(vertNeighbor.southJunction,true)
			eastNeighbor = self:GetRiverHexNeighbor(vertNeighbor.southJunction,false)

			if westNeighbor ~= nil then
				ii = elevationMap:GetIndex(westNeighbor.x,westNeighbor.y)
			else
				ii = -1
			end

			if ii ~= -1 then
				westAltitude = elevationMap.data[ii]
			else
				westAltitude = vertAltitude
			end

			if eastNeighbor ~= nil then
				ii = elevationMap:GetIndex(eastNeighbor.x, eastNeighbor.y)
			else
				ii = -1
			end

			if ii ~= -1 then
				eastAltitude = elevationMap.data[ii]
			else
				eastAltitude = vertAltitude
			end

			vertNeighbor.southJunction.altitude = math.min(math.min(vertAltitude,westAltitude),eastAltitude)
			i=i+1
		end
	end
end
-------------------------------------------------------------------------------------------
function RiverMap:isLake(junction)

	--first exclude the map edges that don't have neighbors
	if junction.y == 0 and junction.isNorth == false then
		return false
	elseif junction.y == elevationMap.height - 1 and junction.isSouth == true then	--pretty sure this is right (changed from junction.isNorth) -L
		return false
	end

	--exclude altitudes below sea level
	if junction.altitude < elevationMap.seaLevelThreshold then
		return false
	end

	--print(string.format("junction = (%d,%d) N = %s, alt = %f",junction.x,junction.y,tostring(junction.isNorth),junction.altitude))

	local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
	local vertAltitude = nil
	if vertNeighbor == nil then
		vertAltitude = junction.altitude
		print("Warning: vertNeighbor == nil in RiverMap:isLake")
	else
		vertAltitude = vertNeighbor.altitude
		--print(string.format("--vertNeighbor = (%d,%d) N = %s, alt = %f",vertNeighbor.x,vertNeighbor.y,tostring(vertNeighbor.isNorth),vertNeighbor.altitude))
	end

	local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
	local westAltitude = nil
	if westNeighbor == nil then
		westAltitude = junction.altitude
		print("Warning: westNeighbor == nil in RiverMap:isLake")
	else
		westAltitude = westNeighbor.altitude
		--print(string.format("--westNeighbor = (%d,%d) N = %s, alt = %f",westNeighbor.x,westNeighbor.y,tostring(westNeighbor.isNorth),westNeighbor.altitude))
	end

	local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
	local eastAltitude = nil
	if eastNeighbor == nil then
		eastAltitude = junction.altitude
		print("Warning: eastNeighbor == nil in RiverMap:isLake")
	else
		eastAltitude = eastNeighbor.altitude
		--print(string.format("--eastNeighbor = (%d,%d) N = %s, alt = %f",eastNeighbor.x,eastNeighbor.y,tostring(eastNeighbor.isNorth),eastNeighbor.altitude))
	end

	local lowest = math.min(vertAltitude,math.min(westAltitude,math.min(eastAltitude,junction.altitude)))

	if lowest == junction.altitude then
		--print("--is lake")
		return true
	end
	--print("--is not lake")
	return false
end
-------------------------------------------------------------------------------------------
--get the average altitude of the two lowest neighbors that are higher than
--the junction altitude.
function RiverMap:GetNeighborAverage(junction)
	local count = 0
	local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
	local vertAltitude = nil
	if vertNeighbor == nil then
		vertAltitude = 0
	else
		vertAltitude = vertNeighbor.altitude
		count = count +1
	end

	local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
	local westAltitude = nil
	if westNeighbor == nil then
		westAltitude = 0
	else
		westAltitude = westNeighbor.altitude
		count = count +1
	end

	local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
	local eastAltitude = nil
	if eastNeighbor == nil then
		eastAltitude = 0
	else
		eastAltitude = eastNeighbor.altitude
		count = count +1
	end

	local lowestNeighbor = eastAltitude
	if westAltitude < lowestNeighbor then lowestNeighbor = westAltitude end
	if vertAltitude ~= 0 and vertAltitude < lowestNeighbor then lowestNeighbor = vertAltitude end

	--local avg = (vertAltitude + westAltitude + eastAltitude)/count

	return lowestNeighbor+0.0000001
end
-------------------------------------------------------------------------------------------
--this function alters the drainage pattern
function RiverMap:SiltifyLakes()
	local Time3 = os.clock()
	local lakeList = {}
	local onQueueMapNorth = {}
	local onQueueMapSouth = {}

	for i=0,elevationMap.length-1,1 do
		if self:isLake(self.riverData[i].northJunction) then
			table.insert(lakeList,self.riverData[i].northJunction)
			onQueueMapNorth[i] = true
		else
			onQueueMapNorth[i] = false
		end
		if self:isLake(self.riverData[i].southJunction) then
			table.insert(lakeList,self.riverData[i].southJunction)
			onQueueMapSouth[i] = true
		else
			onQueueMapSouth[i] = false
		end
	end


	local iterations = 0
	--print(string.format("Initial lake count = %d",#lakeList))
	while #lakeList > 0 do
		iterations = iterations + 1
		if iterations > 100000000 then
			--debugOn = true
			print("###ERROR### - Endless loop in lake siltification.")
			break
		end

		local junction = table.remove(lakeList)
		local i = elevationMap:GetIndex(junction.x,junction.y)
		if junction.isNorth then
			onQueueMapNorth[i] = false
		else
			onQueueMapSouth[i] = false
		end

		-- local avg = self:GetNeighborAverage(junction)
		-- if avg < junction.altitude + 0.0001 then --using == in fp comparison is precarious and unpredictable due to sp vs. dp floats, rounding, and all that nonsense. =P
			-- while self:isLake(junction) do
				-- junction.altitude = junction.altitude + 0.0001
			-- end
		-- else
			-- junction.altitude = avg
		-- end
		
		if not self:isLake(junction) then
			print("Debug: Fake Lake")
		else
			junction.altitude = junction.altitude + self:GetNeighborAverage(junction)
		end

		-- if self:isLake(junction) then
			-- print("Oh bother")
		-- end

		for dir = mc.WESTFLOW,mc.VERTFLOW,1 do
			local neighbor = self:GetJunctionNeighbor(dir,junction)
			if neighbor ~= nil and self:isLake(neighbor) then
				local ii = elevationMap:GetIndex(neighbor.x,neighbor.y)
				if neighbor.isNorth == true and onQueueMapNorth[ii] == false then
					table.insert(lakeList,neighbor)
					onQueueMapNorth[ii] = true
				elseif neighbor.isNorth == false and onQueueMapSouth[ii] == false then
					table.insert(lakeList,neighbor)
					onQueueMapSouth[ii] = true
				end
			end
		end
	end
	print(string.format("Siltified Lakes in %.4f seconds over %d iterations. - Planet Simulator",os.clock()-Time3,iterations))

--[[Commented out this section because it's debug code that forces a crash. -Bobert13
	local belowSeaLevelCount = 0
	local riverTest = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	local lakesFound = false
	for i=0, elevationMap.length-1,1 do
		local northAltitude = self.riverData[i].northJunction.altitude
		local southAltitude = self.riverData[i].southJunction.altitude
		if northAltitude < elevationMap.seaLevelThreshold then
			belowSeaLevelCount = belowSeaLevelCount + 1
		end
		if southAltitude < elevationMap.seaLevelThreshold then
			belowSeaLevelCount = belowSeaLevelCount + 1
		end
		riverTest.data[i] = (northAltitude + southAltitude)/2.0

		if self:isLake(self.riverData[i].northJunction) then
			local junction = self.riverData[i].northJunction
			print(string.format("lake found at (%d, %d) isNorth = %s, altitude = %.12f!",junction.x,junction.y,tostring(junction.isNorth),junction.altitude))
			local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
			if vertNeighbor ~= nil then
				print(string.format("vert neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",vertNeighbor.x,vertNeighbor.y,tostring(vertNeighbor.isNorth),vertNeighbor.altitude))
			end
			local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
			if westNeighbor ~= nil then
				print(string.format("west neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",westNeighbor.x,westNeighbor.y,tostring(westNeighbor.isNorth),westNeighbor.altitude))
			end
			local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
			if eastNeighbor ~= nil then
				print(string.format("east neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",eastNeighbor.x,eastNeighbor.y,tostring(eastNeighbor.isNorth),eastNeighbor.altitude))
			end
			riverTest.data[i] = 1.0
			lakesFound = true
		end
		if self:isLake(self.riverData[i].southJunction) then
			local junction = self.riverData[i].southJunction
			print(string.format("lake found at (%d, %d) isNorth = %s, altitude = %.12f!",junction.x,junction.y,tostring(junction.isNorth),junction.altitude))
			local vertNeighbor = self:GetJunctionNeighbor(mc.VERTFLOW,junction)
			if vertNeighbor ~= nil then
				print(string.format("vert neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",vertNeighbor.x,vertNeighbor.y,tostring(vertNeighbor.isNorth),vertNeighbor.altitude))
			end
			local westNeighbor = self:GetJunctionNeighbor(mc.WESTFLOW,junction)
			if westNeighbor ~= nil then
				print(string.format("west neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",westNeighbor.x,westNeighbor.y,tostring(westNeighbor.isNorth),westNeighbor.altitude))
			end
			local eastNeighbor = self:GetJunctionNeighbor(mc.EASTFLOW,junction)
			if eastNeighbor ~= nil then
				print(string.format("east neighbor at(%d, %d) isNorth = %s, altitude = %.12f!",eastNeighbor.x,eastNeighbor.y,tostring(eastNeighbor.isNorth),eastNeighbor.altitude))
			end
			riverTest.data[i] = 1.0
			lakesFound = true
		end
	end

	if lakesFound then
		print("###ERROR### - Failed to siltify lakes. check logs")
		--elevationMap:Save4("elevationMap(SiltifyLakes).csv")
	end
]]-- -Bobert13
--	riverTest:Normalize()
--	riverTest:Save("riverTest.csv")
end
-------------------------------------------------------------------------------------------
function RiverMap:SetFlowDestinations()
	junctionList = {}
	local i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			table.insert(junctionList,self.riverData[i].northJunction)
			table.insert(junctionList,self.riverData[i].southJunction)
			i=i+1
		end
	end

	table.sort(junctionList,function (a,b) return a.altitude > b.altitude end)

	for n=1,#junctionList do
		local junction = junctionList[n]
		local validList = self:GetValidFlows(junction)
		if #validList > 0 then
			local choice = PWRandInt(1,#validList)
			junction.flow = validList[choice]
		else
			junction.flow = mc.NOFLOW
		end
	end
end
-------------------------------------------------------------------------------------------
function RiverMap:GetValidFlows(junction)
	local validList = {}
	for dir = mc.WESTFLOW,mc.VERTFLOW,1 do
		neighbor = self:GetJunctionNeighbor(dir,junction)
		if neighbor ~= nil and neighbor.altitude < junction.altitude then
			table.insert(validList,dir)
		end
	end
	return validList
end
-------------------------------------------------------------------------------------------
function RiverMap:IsTouchingOcean(junction)

	if elevationMap:IsBelowSeaLevel(junction.x,junction.y) then
		return true
	end
	local westNeighbor = self:GetRiverHexNeighbor(junction,true)
	local eastNeighbor = self:GetRiverHexNeighbor(junction,false)

	if westNeighbor == nil or elevationMap:IsBelowSeaLevel(westNeighbor.x,westNeighbor.y) then
		return true
	end
	if eastNeighbor == nil or elevationMap:IsBelowSeaLevel(eastNeighbor.x,eastNeighbor.y) then
		return true
	end
	return false
end
-------------------------------------------------------------------------------------------
function RiverMap:SetRiverSizes(rainfallMap)
	local junctionList = {} --only include junctions not touching ocean in this list
	local i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			if not self:IsTouchingOcean(self.riverData[i].northJunction) then
				table.insert(junctionList,self.riverData[i].northJunction)
			end
			if not self:IsTouchingOcean(self.riverData[i].southJunction) then
				table.insert(junctionList,self.riverData[i].southJunction)
			end
			i=i+1
		end
	end

	table.sort(junctionList,function (a,b) return a.altitude > b.altitude end)

	for n=1,#junctionList do
		local junction = junctionList[n]
		local nextJunction = junction
		local i = elevationMap:GetIndex(junction.x,junction.y)
		while true do
			nextJunction.size = (nextJunction.size + rainfallMap.data[i]) * mc.riverRainCheatFactor
			if nextJunction.flow == mc.NOFLOW or self:IsTouchingOcean(nextJunction) then
				nextJunction.size = 0.0
				break
			end
			--TODO: The BE script has some extra river code in this vicinity
			nextJunction = self:GetJunctionNeighbor(nextJunction.flow,nextJunction)
		end
	end

	--now sort by river size to find river threshold
	table.sort(junctionList,function (a,b) return a.size > b.size end)
	local riverIndex = math.floor(mc.riverPercent * #junctionList)
	self.riverThreshold = junctionList[riverIndex].size
		if self.riverThreshold < mc.minRiverSize then
			self.riverThreshold = mc.minRiverSize
		end
	--print(string.format("river threshold = %f",self.riverThreshold))

end
-------------------------------------------------------------------------------------------
--This function returns the flow directions needed by civ
function RiverMap:GetFlowDirections(x,y)
	--TODO: If I merge the BE river changes, perhaps will need to add logic to each case below -- see BE script
	--print(string.format("Get flow dirs for %d,%d",x,y))
	local i = elevationMap:GetIndex(x,y)

	local WOfRiver = FlowDirectionTypes.NO_FLOWDIRECTION
	local xx,yy = elevationMap:GetNeighbor(x,y,mc.NE)
	local ii = elevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].southJunction.flow == mc.VERTFLOW and self.riverData[ii].southJunction.size > self.riverThreshold then
		--print(string.format("--NE(%d,%d) south flow=%d, size=%f",xx,yy,self.riverData[ii].southJunction.flow,self.riverData[ii].southJunction.size))
		WOfRiver = FlowDirectionTypes.FLOWDIRECTION_SOUTH
	end
	xx,yy = elevationMap:GetNeighbor(x,y,mc.SE)
	ii = elevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].northJunction.flow == mc.VERTFLOW and self.riverData[ii].northJunction.size > self.riverThreshold then
		--print(string.format("--SE(%d,%d) north flow=%d, size=%f",xx,yy,self.riverData[ii].northJunction.flow,self.riverData[ii].northJunction.size))
		WOfRiver = FlowDirectionTypes.FLOWDIRECTION_NORTH
	end

	local NWOfRiver = FlowDirectionTypes.NO_FLOWDIRECTION
	xx,yy = elevationMap:GetNeighbor(x,y,mc.SE)
	ii = elevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].northJunction.flow == mc.WESTFLOW and self.riverData[ii].northJunction.size > self.riverThreshold then
		NWOfRiver = FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST
	end
	if self.riverData[i].southJunction.flow == mc.EASTFLOW and self.riverData[i].southJunction.size > self.riverThreshold then
		NWOfRiver = FlowDirectionTypes.FLOWDIRECTION_NORTHEAST
	end

	local NEOfRiver = FlowDirectionTypes.NO_FLOWDIRECTION
	xx,yy = elevationMap:GetNeighbor(x,y,mc.SW)
	ii = elevationMap:GetIndex(xx,yy)
	if ii ~= -1 and self.riverData[ii].northJunction.flow == mc.EASTFLOW and self.riverData[ii].northJunction.size > self.riverThreshold then
		NEOfRiver = FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST
	end
	if self.riverData[i].southJunction.flow == mc.WESTFLOW and self.riverData[i].southJunction.size > self.riverThreshold then
		NEOfRiver = FlowDirectionTypes.FLOWDIRECTION_NORTHWEST
	end

	return WOfRiver,NWOfRiver,NEOfRiver
end
-------------------------------------------------------------------------------------------
--RiverHex class
-------------------------------------------------------------------------------------------
RiverHex = inheritsFrom(nil)

function RiverHex:New(x,y)
	local new_inst = {}
	setmetatable(new_inst, {__index = RiverHex});

	new_inst.x = x
	new_inst.y = y
	new_inst.northJunction = RiverJunction:New(x,y,true)
	new_inst.southJunction = RiverJunction:New(x,y,false)

	return new_inst
end
-------------------------------------------------------------------------------------------
--RiverJunction class
-------------------------------------------------------------------------------------------
RiverJunction = inheritsFrom(nil)

function RiverJunction:New(x,y,isNorth)
	local new_inst = {}
	setmetatable(new_inst, {__index = RiverJunction});

	new_inst.x = x
	new_inst.y = y
	new_inst.isNorth = isNorth
	new_inst.altitude = 0.0
	new_inst.flow = mc.NOFLOW
	new_inst.size = 0.0

	return new_inst
end
-------------------------------------------------------------------------------------------
--PlateMap Class
-------------------------------------------------------------------------------------------

PlateMap = inheritsFrom(FloatMap)

function PlateMap:New(width,height,wrapX,wrapY)
	local new_inst = FloatMap:New(width,height,wrapX,wrapY)
	setmetatable(new_inst, {__index = PlateMap});

	new_inst.index = {}
	new_inst.centers = {}
	new_inst.info = {}
	new_inst.ID = {}
	new_inst.size = {}
	new_inst.speed = {}
	new_inst.fault = {}
	new_inst.type = {}
	new_inst.neighbors = {}
	new_inst.ToDo = {}

	return new_inst
end
-------------------------------------------------------------------------------------------
function GeneratePlates(W,H,xWrap,yWrap,Plates)
	--This function determines which tiles belong to which plates. It also keeps track of plate sizes, and identifiers.
	local WH = W*H
	local avgSize = WH/Plates
	local minSize = math.ceil(avgSize/4)
	local maxSize = math.floor(avgSize * 2.5)
	local Size = PWRandInt(minSize,maxSize)
	PlateMap = PlateMap:New(W,H,xWrap,yWrap)


	if (Plates <= 10) then --Warn if extremely few plates
		print(string.format("Warning: GeneratePlates not intended to work with only %i plates.", Plates))
	end

	-- initialize polar plate settings (the two polar plates are handled separately -LL).
	local PolarWidth
	do
		local latRange = mc.topLatitude - mc.bottomLatitude
		local icefreeLatRange = mc.iceNorthLatitudeLimit - mc.iceSouthLatitudeLimit
		--This produces a width giving at least 2/3 of the ice-possible rows on the plates
		PolarWidth = math.ceil((1/3)*((latRange - icefreeLatRange)/latRange))
	end
	
	--PlateMap.centers = {}
	for k = 1, Plates do	--Determine plate centers -LL
		if k == 1 or k == 2 then	--north and south pole plates treated separately
			--This sets these twice which is unnecessary but doesn't hurt anything
			PlateMap.centers[1] = 0
			PlateMap.centers[2] = WH - 1
		else	--place other centers at random (not in first or last row)
			local XY = PWRandInt(W,WH - W - 1)
			PlateMap.centers[k] = XY
		end
	end

	--Sets up a blank table with an index for every tile on the map. -Bobert13
	--PlateMap.ID = {}
	for i = 0, WH-1 do
		PlateMap.ID[i] = 0
	end
	for PlateID = 1, Plates, 1 do
		--Mark the plate center.
		local i = PlateMap.centers[PlateID]
		PlateMap.ID[i] = PlateID
		table.insert(PlateMap.index,PlateID)
		PlateMap.info[PlateID] = {}
		table.insert(PlateMap.info[PlateID],i)
		PlateMap.neighbors[PlateID] = {}
		table.insert(PlateMap.neighbors[PlateID],PlateID)
	end
	--First construct polar plates ...
	for i = 0, W - 1 do
		PlateMap.ID[i] = 1
		PlateMap.ID[WH - W + i] = 2
		table.insert(PlateMap.info[1],i)
		table.insert(PlateMap.info[2],WH - W + i)
	end
	table.insert(PlateMap.size, W)
	table.insert(PlateMap.size, W)

	--... then nonpolar plates
	for PlateID =3, Plates, 1 do
		--Iterates a spiral around the center tile checking tiles to add them.
		local i = PlateMap.centers[PlateID]
		local currentSize = 1
		local r = math.ceil((math.sqrt(Size/math.pi))/2)
		local x = i%W
		local y = (i-x)/W
		local tiles = GetCircle(i,r)
		for n=1, #tiles do
			local ii = tiles[n]
			local xx = ii%W
			local yy = (ii-xx)/W
			if currentSize < Size then
				--Make sure the candidate tile doesn't belong to another plate.
				if PlateMap.ID[ii] == 0 then
					--Make sure the candidate tile is adjacent to a tile owned by this plate.
					local tiles2 = GetCircle(ii,1)
					for k=1,#tiles2 do
						local iii = tiles2[k]
						if PlateMap.ID[iii] == PlateID then
							--If all other conditions are met, 2/3 times the candidate tile is added to the plate.
							local roll = PWRandInt(1,300)
							--local ySkew = (W/H)*1.2-(math.abs(y-yy)/(H/3))
							local ySkew = mc.YtoXRatio
							if roll*ySkew > 100 then
								PlateMap.ID[ii] = PlateID
								table.insert(PlateMap.info[PlateID],ii)
								currentSize = currentSize+1
								break
							end
							break
						end
					end
				end
			else
				break
			end
		end
		table.insert(PlateMap.size,currentSize)
	end

	local zeros = {}
	for i = 0 , #PlateMap.ID do
		if PlateMap.ID[i] == 0 then
			table.insert(zeros,i)
		else
			--local x = i%W
			--local y = (i-x)/W
			local tiles = GetSpiral(i,1,1)
			local neighborCount = 0
			for n = 1, #tiles,1 do
				local k = tiles[n]
				if PlateMap.ID[i] == PlateMap.ID[k] then
					neighborCount = neighborCount + 1
				end
			end
			if neighborCount == 0 then
                --print(string.format("Killing plate %d because it's one tile.", PlateMap.ID[i]))
				PlateMap.size[PlateMap.ID[i]] = PlateMap.size[PlateMap.ID[i]]-1
				PlateMap.ID[i] = 0
				table.insert(zeros,i)
			end
		end
	end

	--print("Growing Plates. - Planet Simulator")
	ShuffleList2(zeros)
	local f = 0
	while #zeros > 0 do
		f=f+1
		local z = 1
		for q = 1, #zeros do
			local i = zeros[z]
			--local x = i%W
			--local y = (i-x)/W
			local tiles = GetSpiral(i,1,1)
			ShuffleList2(tiles)
			for n = 1, #tiles do
				local k = tiles[n]
				if k ~= -1 and PlateMap.ID[k] ~= 0 then
					PlateMap.ID[i] = PlateMap.ID[k]
					table.insert(PlateMap.info[PlateMap.ID[i]],i)
					table.remove(zeros,z)
					PlateMap.size[PlateMap.ID[i]] = PlateMap.size[PlateMap.ID[i]] + 1
					z=z-1
					break
				end
			end
			z=z+1
		end
	end
	--print("Finished Growing Plates in "..f.." iterations. -Planet Simulator")

	local i = 1
	for n = 1, #PlateMap.index do
		if PlateMap.size[i] <= 1 then
			--print(string.format("Striking plate %d from the record. - Planet Simulator", n))
			table.remove(PlateMap.size,i)
			for k=#PlateMap.info[i],1,-1 do
				table.remove(PlateMap.info[i],k)
			end
			table.remove(PlateMap.info,i)
			for k=#PlateMap.neighbors[i],1,-1 do
				table.remove(PlateMap.neighbors[i],k)
			end
			table.remove(PlateMap.neighbors,i)
			table.remove(PlateMap.index,i)
			table.remove(PlateMap.centers,i)
			i=i-1
		end
		i=i+1
	end

	--Debug
	--PlateMap:Save2("PlateMap.ID.csv")
end
-------------------------------------------------------------------------------------------
function GenerateFaults()
	--TODO: Merge Bobert13's refactor -- although this is pretty close to what PlateMap:GenerateNeighborData() in BE script does, not much to change that I see yet ...
	--This ubiquitously named function determines plate motions, neighbors, faults, and fault types.
	local W = PlateMap.width
	local H = PlateMap.height
	local WH = W*H
	for i = 1, #PlateMap.index do	--generate a random velocity for each plate -LamilLerran
		local xMo = PWRandInt(2,10)	--current plate motion in x direction -LamilLerran
		local rollx = PWRandInt(0,1)
			if rollx == 0 then	--50/50 chance to move in -x rather than +x direction -LamilLerran
				xMo = xMo * -1
			end
		local yMo = PWRandInt(2,10)	--current plate motion in y direction -LamilLerran
		local rolly = PWRandInt(0,1)
			if rolly == 0 then	--50/50 chance to move in -y rather than +y direction -LamilLerran
				yMo = yMo * -1
			end
		PlateMap.speed[i] = xMo * 100 + yMo	--encode velocity as single integer by multiplying x-motion by 100 -LamilLerran
	end

	local faults = {}
	for i = 0, #PlateMap.ID, 1 do --While this looks like an off-by-one error, testing suggests it's correct -LamilLerran
		local index = GetPlateByID(PlateMap.ID[i])
		
		--local x = i%W
		--local y = (i-x)/W
		local tiles = GetCircle(i,1)
		for n = 1, #tiles, 1 do
			local k = tiles[n]
			if PlateMap.ID[i] ~= PlateMap.ID[k] then
				table.insert(faults,i)
				PlateMap.fault[i] = mc.MINORFAULT	--When a tile is adjacent to a tile from a different plate,
													--there is at least a minor fault there -LL
				local add = true
				for m = 1, #PlateMap.neighbors[index], 1 do
					if PlateMap.neighbors[index][m] == PlateMap.ID[k] then
						add = false
					end
				end
				if add then
					table.insert(PlateMap.neighbors[index], PlateMap.ID[k])
				end
			else
				PlateMap.fault[i] = mc.NOFAULT	--Tiles in the interior of a plate have no fault -LL
			end
		end
	end
	
	for k = 1, #faults do
		local i = faults[k]	--k is a fault index; i is a tile index -LL
		local x = i%W
		local y = (i-x)/W
		local ID1 = PlateMap.ID[i]
		local index1 = GetPlateByID(ID1)	--index1 is the index of the plate containing tile i -LL
		local Sx1 = Round(PlateMap.speed[index1]/100)	--Decode velocity into x component ...
		local Sy1 = PlateMap.speed[index1] - (Sx1*100)	--... and y component -LamilLerran
		local tiles = GetSpiral(i,1)
		for n = 2, #tiles, 1 do	--start at 2 since we don't want to consider the central tile -LamilLerran
			local dir
			if 		n == 2 then dir = mc.W
			elseif	n == 3 then dir = mc.NW
			elseif	n == 4 then dir = mc.NE
			elseif	n == 5 then dir = mc.E
			elseif	n == 6 then dir = mc.SE
			elseif	n == 7 then dir = mc.SW
			else
				print("Warning: Unexpected output size from GetSpiral. - Planet Creator")
			end
			local ii = tiles[n]
			if ii ~= -1 then
				local xx = ii%W
				local yy = (ii-xx)/W
				local ID2 = PlateMap.ID[ii]
				local index2 = GetPlateByID(ID2)	--index2 is the index of the plate containing tile ii -LL
				if index2 == nil then
					print("index2 is nil; ID2 at ("..xx..","..yy..") is:"..ID2)	--Debug warning -LL
				end
				local Sx2 = Round(PlateMap.speed[index2]/100)	--Decode velocity into x component ...
				local Sy2 = PlateMap.speed[index2] - (Sx2*100)	--... and y component -LamilLerran
				if ID1 ~= ID2 then
					local Sx = Sx1 - Sx2
					local Sy = Sy1 - Sy2
					local S = math.sqrt(Sx^2+Sy^2)	--The relative speed of the two plates -LamilLerran
					if S > 5 then	--When the relative speed of the plates is slow (<= 5), then their
									--fault remains classified as a minor fault (type 1) -LL
						local Nx = Sx/S		--Normalized x component of relative velocity -LamilLerran
						local Ny = Sy/S
						local Dx = xx - x	--x component of relative position of the two tiles -LL
						local Dy = yy - y
						local DS = math.sqrt(Dx^2+Dy^2)	--distance between the two tiles -LL
						local DNx = Dx/DS	--Normalized x component of relative position -LL
						local DNy = Dy/DS
						local P = Nx*DNx+Ny*DNy	--Dot Product of <Nx,Ny> with <DNx,DNy>. This ranges
												--from -1 to 1; it will be -1 if the tiles are moving
												--directly apart, 1 if they are moving directly toward
												--each other, and 0 if all motion is perpendicular to
												--their relative positions. -LL
						if P < -0.5 then	--Plates moving in opposite direction of their relative positions are convergent -LL
							PlateMap.fault[i] = mc.CONVERGENTFAULT
						elseif P > 0.5 then	--Plates moving in same direction as their relative positions are divergent -LL
							PlateMap.fault[i] = mc.DIVERGENTFAULT
						else				--Others move sideways so are transform -LL
							PlateMap.fault[i] = mc.TRANSFORMFAULT
						end
					end
				end
			end
		end
	end
	
	--Debug
	--PlateMap:Save3("PlateMap.fault.csv")
end
-------------------------------------------------------------------------------------------
function DetermineRiftZone(W,H,k,centerRift,modifier)
	local RiftPer = 0
    local RiftAmt = 0
    local typeScalar = 0

    if Map.GetCustomOption(6) == 1 then
        typeScalar = 20
    elseif Map.GetCustomOption(6) == 2 then
        typeScalar = 12
    else
        typeScalar = 20
    end

    for n = 1, PlateMap.size[k] do
		local i = PlateMap.info[k][n]
		local x = i%W
		local y = (i-x)/W
        if x+1 >= W - W/typeScalar then
            RiftAmt = RiftAmt + (1 * modifier)
        elseif x+1 <= W/typeScalar then
            RiftAmt = RiftAmt + (1 * modifier)
        elseif x+1 >= centerRift - (W/typeScalar) and x+1 <= centerRift + (W/typeScalar) then
            RiftAmt = RiftAmt + (1 * modifier)
        elseif y+1 >= H - H/12 then
            RiftAmt = RiftAmt + (0.75 * modifier)
        elseif y+1 <= H/12 then
            RiftAmt = RiftAmt + (0.75 * modifier)
        end
	end
    RiftPer = RiftAmt/PlateMap.size[k]

	--print(string.format("Rift Percent of Plate %d is %.4f", k, RiftPer))
	if RiftPer >= 0.33 then
		return 0
	else
		return 1
	end
end
-------------------------------------------------------------------------------------------
function MakeList(k)
	for n=2, #PlateMap.neighbors[k], 1 do
		local add = true
		local index = GetPlateByID(PlateMap.neighbors[k][n])
		--print("index from "..PlateMap.neighbors[k][n].." the neighbor of "..PlateMap.neighbors[k][1])
		if PlateMap.type[index] == 1 then
			for nn=1, #PlateMap.ToDo, 1 do
				if PlateMap.neighbors[k][n] == PlateMap.ToDo[nn] then
					--print("did not add "..PlateMap.neighbors[k][n].." the neighbor of "..PlateMap.neighbors[k][1].." because it's already on the list")
					add = false
				end
			end
			if add then
				--print("adding "..PlateMap.neighbors[k][n].." to ToDo because, it''s the neighbor of "..PlateMap.neighbors[k][1])
				table.insert(PlateMap.ToDo, PlateMap.neighbors[k][n])
				MakeList(index)
			end
		end
	end
end
-------------------------------------------------------------------------------------------
function Blockade(k,ID,W,H)
	--This function determines whether flipping the plate at k will prevent naval circumnavigation.
	local N = false
	local S = false
	local block = false
	local big = 0
	if #PlateMap.ToDo > 0 then
		PlateMap.ToDo = {}
	end
	table.insert(PlateMap.ToDo, ID)
	MakeList(k)

	for n=1, #PlateMap.ToDo, 1 do
		big = big + PlateMap.size[GetPlateByID(PlateMap.ToDo[n])]
	end

	if big > (W*H)/6 and Map.GetCustomOption(6) == 1 then
		-- print("too big")
		return true
	else
		for n = 1, #PlateMap.ToDo, 1 do
			for nn = 1, PlateMap.size[GetPlateByID(PlateMap.ToDo[n])] do
				local i = PlateMap.info[GetPlateByID(PlateMap.ToDo[n])][nn]
				local x = i%W
				local y = (i-x)/W
				if not N then
					if y+1 >= H-(H/10) then
						N = true
						--print(PlateMap.neighbors[k][1], "North")
					end
				end
				if not S then
					if y+1 <= (H/10) then
						S = true
						--print(PlateMap.neighbors[k][1], "South")
					end
				end
				if S and N then
					--print(PlateMap.neighbors[k][1], "blocked")
					return true
				end
			end
		end
		return false
	end
end
-------------------------------------------------------------------------------------------
contPercent = 0
contSize = 0
contCount = 0
sinkPlate = 0

function CreateContinentalShelf(W,H)
	--This function determines whether a plate is Oceanic or Continental.
	local WH = W*H
	local Plates = {}
	local riftMod = PWRandInt(math.floor(W/32), math.ceil(W/10))
	local riftPosNeg = PWRandInt(0,1)
	local centerRift = W/2
	if riftPosNeg == 0 then
		centerRift = centerRift + riftMod
	else
		centerRift = centerRift - riftMod
	end
	--print("centerRift is "..centerRift)

	for i = 1, #PlateMap.index do
        if PlateMap.size[i] > 0 then
            Plates[i] = PlateMap.index[i]
        end
	end
	ShuffleList2(Plates)

    -- Flip viable plates to be continental
    for i = 1, #Plates do
        local index = GetPlateByID(Plates[i])
        local Zone = DetermineRiftZone(W,H,index,centerRift,1.0)
        if contPercent >= mc.continentalPercent then
            PlateMap.type[index] = mc.OCEANIC
        elseif Zone == 0 then
            PlateMap.type[index] = mc.OCEANIC
        elseif H > 32 and Blockade(index,Plates[i],W,H) then
            PlateMap.type[index] = mc.OCEANIC
		elseif i == 1 or i == 2 then	--polar plates always oceanic
			PlateMap.type[index] = mc.OCEANIC
        else
            PlateMap.type[index] = mc.CONTINENTAL
            contSize = contSize + PlateMap.size[index]
            contCount = contCount+1
            lastPlate = Plates[i]
            --print(string.format("Flipped plate %d.", Plates[i]))
        end
        contPercent = contSize/WH
    end

    -- Repeat the previous with a lowered RiftZone threshold if contPercent is significantly lower than our target
    if contPercent / mc.continentalPercent < 0.95 then
        --print(string.format("Twice!"))
        for i = 1, #Plates do
            local index = GetPlateByID(Plates[i])
            local Zone = DetermineRiftZone(W,H,index,centerRift,0.6)
            if PlateMap.type[index] == 0 then
                if contPercent >= mc.continentalPercent then
                    PlateMap.type[index] = mc.OCEANIC
                elseif Zone == 0 then
                    PlateMap.type[index] = mc.OCEANIC
                    --print(string.format("Rift Zone at plate %d", Plates[i]))
                elseif H > 32 and Blockade(index,Plates[i],W,H) then
                    PlateMap.type[index] = mc.OCEANIC
                    --print(string.format("Blockade at plate %d", Plates[i]))
				elseif i == 1 or i == 2 then	--polar plates always oceanic
					PlateMap.type[index] = mc.OCEANIC
                else
                    PlateMap.type[index] = mc.CONTINENTAL
                    contSize = contSize + PlateMap.size[index]
                    contCount = contCount+1
                    --print(string.format("Flipped plate %d.", Plates[i]))
                end
                contPercent = contSize/WH
            end
        end
    end

    -- highestZone = 0
    -- if contPercent / mc.continentalPercent > 1.03 then
        -- for i = 1, #Plates do
            -- local index = GetPlateByID(Plates[i])
            -- if PlateMap.type[index] == 1 then
                -- local Zone = DetermineRiftAmount(W,H,index,centerRift,1.0)
                -- if Zone > highestZone then
                    -- highestZone = Zone
                    -- sinkPlate = Plates[i]
                -- end
            -- end
        -- end
        -- print(string.format("sinkPlate is %d, it's size is %d", sinkPlate, PlateMap.size[GetPlateByID(sinkPlate)]))
    -- end

    if contPercent / mc.continentalPercent > 1.05 then
		local foundSink = false	-- True if a plate to sink has been found -LamilLerran
        local nearest = contPercent - mc.continentalPercent
        for i = 1, #Plates do
            local index = GetPlateByID(Plates[i])
            if PlateMap.type[index] == 1 then
                local target = contPercent - mc.continentalPercent
                local size = PlateMap.size[index]/WH
                if math.abs(size - target) < nearest then
                    nearest = math.abs(size - target)
                    sinkPlate = Plates[i]
					foundSink = true
                end
            end
        end
		if foundSink then
			local index = GetPlateByID(sinkPlate)
			--print(string.format("index is %d, sinkPlate is %d, #Plates is %d", (index and index or -1), (sinkPlate and sinkPlate or -1),#Plates))
			PlateMap.type[index] = mc.OCEANIC
			contSize = contSize - PlateMap.size[index]
			contPercent = contSize/WH
			contCount = contCount - 1
			--print(string.format("sinkPlate is %d, it's size is %d", sinkPlate, PlateMap.size[GetPlateByID(sinkPlate)]))
		else
			print("Skipped sinking plate because every option moved land percentage away from target. - Planet Simulator")
		end
    end

	print(string.format("%d plates flipped to make %.2f%% of the map continental shelf. - Planet Simulator", contCount, contPercent * 100))
end
-------------------------------------------------------------------------------------------
function CreatePangealShelf(W,H)
	--This function determines whether a plate is Oceanic or Continental.
	local WH = W*H
	local Plates = {}
	local centerRift = math.floor(W/10)

	for i = 1, #PlateMap.index do
        if PlateMap.size[i] > 0 then
            Plates[i] = PlateMap.index[i]
        end
	end
	ShuffleList2(Plates)

    -- Flip viable plates to be continental
    local first = true
    for i = 1, #Plates do
        local index = GetPlateByID(Plates[i])
        local Zone = DetermineRiftZone(W,H,index,centerRift,1.0)
        if contPercent >= mc.continentalPercent then
            PlateMap.type[index] = mc.OCEANIC
        elseif Zone == 0 then
            PlateMap.type[index] = mc.OCEANIC
        elseif H > 32 and Blockade(index,Plates[i],W,H) then
            PlateMap.type[index] = mc.OCEANIC
		elseif i == 1 or i == 2 then	--polar plates always oceanic
			PlateMap.type[index] = mc.OCEANIC
        else
            local landNeighbor = false
            for k = 1, #PlateMap.neighbors[index] do
                if PlateMap.type[GetPlateByID(PlateMap.neighbors[index][k])] == mc.PANGEAL or first then
                    landNeighbor = true
                    first = false
                    break
                end
            end
            if landNeighbor then
                PlateMap.type[index] = mc.CONTINENTAL
                contSize = contSize + PlateMap.size[index]
                contCount = contCount+1
                lastPlate = Plates[i]
                --print(string.format("Flipped plate %d.", Plates[i]))
            else
                PlateMap.type[index] = mc.OCEANIC
            end
        end
        contPercent = contSize/WH
    end

    -- Repeat the previous with a lowered RiftZone threshold if contPercent is significantly lower than our target
    local loopCount = 1
    while contPercent / mc.landPercent < 0.95 and loopCount < 10 do
        --print(string.format("Twice!"))
        for i = 1, #Plates do
            local index = GetPlateByID(Plates[i])
            local Zone = DetermineRiftZone(W,H,index,centerRift,(1-(loopCount/20)))
            if PlateMap.type[index] == mc.OCEANIC then
                if contPercent >= mc.continentalPercent then
                    PlateMap.type[index] = mc.OCEANIC
                elseif Zone == 0 then
                    PlateMap.type[index] = mc.OCEANIC
                    --print(string.format("Rift Zone at plate %d", Plates[i]))
                elseif H > 32 and Blockade(index,Plates[i],W,H) then
                    PlateMap.type[index] = mc.OCEANIC
                    --print(string.format("Blockade at plate %d", Plates[i]))
				elseif i == 1 or i == 2 then	--polar plates always oceanic
					PlateMap.type[index] = mc.OCEANIC
                else
                    local landNeighbor = false
                    for k = 1, #PlateMap.neighbors[index] do
                        if PlateMap.type[GetPlateByID(PlateMap.neighbors[index][k])] == mc.PANGEAL then
                            landNeighbor = true
                        end
                    end
                    if landNeighbor then
                        PlateMap.type[index] = mc.PANGEAL
                        contSize = contSize + PlateMap.size[index]
                        contCount = contCount+1
                        lastPlate = Plates[i]
                        --print(string.format("Flipped plate %d.", Plates[i]))
                    else
                        --print(string.format("No landNeighbor found for plate %d", Plates[i]))
                        PlateMap.type[index] = mc.OCEANIC
                    end
                end
                contPercent = contSize/WH
            end
        end
        loopCount = loopCount + 1
    end

    if contPercent / mc.continentalPercent > 1.05 then
        local nearest = (contPercent - mc.continentalPercent) * 0.9
        for i = 1, #Plates do
            local index = GetPlateByID(Plates[i])
            if PlateMap.type[index] == mc.PANGEAL then
                local landNeighborCount = 0
                for k = 1, #PlateMap.neighbors[index] do
                    if PlateMap.type[GetPlateByID(PlateMap.neighbors[index][k])] == mc.PANGEAL then
                        landNeighborCount = landNeighborCount + 1
                    end
                end
                local target = contPercent - mc.continentalPercent
                local size = PlateMap.size[index]/WH
                if math.abs(size - target) < nearest and landNeighborCount < 4 then
                    nearest = math.abs(size - target)
                    sinkPlate = Plates[i]
                end
            end
        end
        if not (sinkPlate == 0) then
            local index = GetPlateByID(sinkPlate)
            PlateMap.type[index] = mc.OCEANIC
            contSize = contSize - PlateMap.size[index]
            contPercent = contSize/WH
            contCount = contCount - 1
            print(string.format("sinkPlate is %d, it's size is %d", sinkPlate, PlateMap.size[GetPlateByID(sinkPlate)]))
        else
            print("Warning -- Could not find an applicable sinkPlate")
        end
    end

	print(string.format("%d plates flipped, in %d iterations, to make %.2f%% of the map pangeal shelf. - Planet Simulator", contCount, loopCount, contPercent * 100))
end
--TODO: Add plate fusing as per BE script?
-------------------------------------------------------------------------------------------
function AdjacentContinentalTiles(x,y)
	--Returns a set containing all directions from the tile at (x,y) for which the
	--neighbor tile in that direction is continental (or pangeal).
	--Note that this includes the direction mc.C if the tile at (x,y) is continental/pangeal
	local returnSet = Set:New({})
	local xx, yy, valid, ii, plateType
	
	for dir,_ in pairs(mc.DIRECTIONS) do
		xx, yy, valid = PlateMap:GetNeighbor(x,y,dir,true)
		if valid then
			ii = PlateMap:GetIndex(xx,yy)
			plateType = PlateMap.type[GetPlateByID(PlateMap.ID[ii])]
			if plateType == mc.CONTINENTAL or plateType == mc.PANGEAL then
				returnSet:add(dir)
			end
		end
	end
	
	return returnSet
end


function DetermineLandPattern(landDirs)
	--[[ Given a set of directions from a central tile in which the pointed-at tile is
	land, this function determines the pattern the land tiles form, and what position
	in that pattern each land tile is in. (This function identifies patterns up to
	symmetry, so two different sets of directions will return the same pattern if they
	can be rotated or reflected to be the same, although the table of positions will differ.)
	
	Returns first the pattern (one of mc.BALANCED, mc.UNBALANCED, mc.CONTIGUOUS, or -1 (the
	last if there is only one pattern for the number of land tiles in landDirs)) and second
	a table whose indices are the directions in landDirs and whose values are the position
	that tile is in in the pattern (one of mc.CENTER, mc.LONE, mc.SHORE, mc.INTERMEDIATE,
	or mc.INLAND; see below for details).
	
	NOTE: THIS FUNCTION ASSUMES THE CENTRAL TILE IS LAND. It *probably* works even if the
	center tile is water (although it will give a warning and will have the position table
	include posTable[mc.C] = mc.CENTER even though mc.C isn't in landDirs in this case),
	but it hasn't been tested.
	Since the central tile is assumed to be land, there are 13 possible patterns:
	1 land: (1 of 1 type)
	 W W
	W L W	- Includes land position center
	 W W
	2 land: (6 of 1 type)
	 W W	
	W L L	- Includes land positions center, lone
	 W W
	3 land: (6, 6, and 3 of 3 types)
	 W W	Pattern CONTIGUOUS
	W L L	- Includes land positions center, shore
	 W L
	 W W	Pattern UNBALANCED
	W L L	- Includes land positions center, lone
	 L W
	 W W	Pattern BALANCED
	L L L	- Includes land positions center, lone
	 W W
	4 land: (6, 12, and 2 of 3 types)
	 W W	Pattern CONTIGUOUS
	W L L	- Includes land positions center, shore, inland
	 L L
	 W W	Pattern UNBALANCED
	L L L	- Includes land positions center, lone, shore
	 W L
	 L W	Pattern BALANCED
	W L L	- Includes land positions center, lone
	 L W
	5 land:
	 W L	Pattern CONTIGUOUS
	W L L	- Includes land positions center, shore, inland
	 L L
	 W L	Pattern UNBALANCED
	L L L	- Includes land positions center, lone, shore, inland
	 W L
	 L W	Pattern BALANCED
	L L L	- Includes land positions center, shore
	 W L
	6 land:
	 L L
	W L L	- Includes land positions center, shore, intermediate, inland
	 L L
	7 land:
	 L L
	L L L	- Includes land positions center, inland
	 L L
	]]
	landCount = landDirs:length()
	local pattern = -1	--if we never need to set this, no function should expect it; so send -1 as default warning
	local posTable = {}
	if not landDirs:contains(mc.C) then
		print("Warning: DetermineLandPattern called centered on oceanic tile")
		landCount = landCount + 1	--Everything assumes center tile is land, so pretend it is
	end
	posTable[mc.C] = mc.CENTER
	if landCount == 1 then
		--Do Nothing
	elseif landCount == 2 then
		for dir,_ in pairs(landDirs) do
			if dir ~= mc.C then
				posTable[dir] = mc.LONE
			end
		end
	elseif landCount == 3 then
		for dir,_ in pairs(landDirs) do
			if dir == mc.C then 
				--Do Nothing
			elseif landDirs:contains(mc:GetClockwiseDir(dir)) then
				pattern = mc.CONTIGUOUS
				posTable[dir] = mc.SHORE
				posTable[mc:GetClockwiseDir(dir)] = mc.SHORE
				break
			elseif landDirs:contains(mc:GetClockwiseDir(mc:GetClockwiseDir(dir))) then
				pattern = mc.UNBALANCED
				posTable[dir] = mc.LONE
				posTable[mc:GetClockwiseDir(mc:GetClockwiseDir(dir))] = mc.LONE
				break
			elseif landDirs:contains(mc:GetOppositeDir(dir)) then
				pattern = mc.BALANCED
				posTable[dir] = mc.LONE
				posTable[mc:GetOppositeDir(dir)] = mc.LONE
				break
			end
		end
	elseif landCount == 4 then
		for dir,_ in pairs(landDirs) do
			if dir == mc.C then 
				--Do Nothing
			else
				if landDirs:contains(mc:GetOppositeDir(dir)) then
					pattern = mc.UNBALANCED
					local oppDir = mc:GetOppositeDir(dir)
					local thirdDir
					for innerDir,_ in pairs(landDirs) do
						if innerDir ~= mc.C and innerDir ~= dir and innerDir ~= oppDir then
							thirdDir = innerDir
							break
						end
					end
					posTable[thirdDir] = mc.SHORE
					if mc:GetClockwiseDir(thirdDir) == dir or mc:GetCounterclockwiseDir(thirdDir) == dir then
						posTable[dir] = mc.SHORE
						posTable[oppDir] = mc.LONE
					elseif mc:GetClockwiseDir(thirdDir) == oppDir or mc:GetCounterclockwiseDir(thirdDir) == oppDir then
						posTable[oppDir] = mc.SHORE
						posTable[dir] = mc.LONE
					else
						print("Warning: unexpected land positions in DetermineLandPattern (unbalanced 4 land)")
					end
					break
				elseif landDirs:contains(mc:GetClockwiseDir(mc:GetClockwiseDir(dir))) then
					if landDirs:contains(mc:GetClockwiseDir(dir)) then
						pattern = mc.CONTIGUOUS
						posTable[dir] = mc.SHORE
						posTable[mc:GetClockwiseDir(dir)] = mc.INLAND
						posTable[mc:GetClockwiseDir(mc:GetClockwiseDir(dir))] = mc.SHORE
						break
					elseif landDirs:contains(mc:GetCounterclockwiseDir(mc:GetCounterclockwiseDir(dir))) then
						pattern = mc.BALANCED
						posTable[dir] = mc.LONE
						posTable[mc:GetClockwiseDir(mc:GetClockwiseDir(dir))] = mc.LONE
						posTable[mc:GetCounterclockwiseDir(mc:GetCounterclockwiseDir(dir))] = mc.LONE
						break
					end
				end
			end
		end
	elseif landCount == 5 then
		local waterDirs = Set:New({})
		--Every direction that isn't continental/pangeal plate is oceanic plate
		--(Or off the map, which we count as oceanic)
		for dir,_ in pairs(mc.DIRECTIONS) do
			if not landDirs:contains(dir) then
				waterDirs:add(dir)
			end
		end
	
		for dir,_ in pairs(waterDirs) do
			if waterDirs:contains(mc:GetClockwiseDir(dir)) then
				pattern = mc.CONTIGUOUS
				posTable[mc:GetClockwiseDir(mc:GetClockwiseDir(dir))] = mc.SHORE
				posTable[mc:GetOppositeDir(dir)] = mc.INLAND
				posTable[mc:GetCounterclockwiseDir(mc:GetCounterclockwiseDir(dir))] = mc.INLAND
				posTable[mc:GetCounterclockwiseDir(dir)] = mc.SHORE
				break
			elseif waterDirs:contains(mc:GetClockwiseDir(mc:GetClockwiseDir(dir))) then
				pattern = mc.UNBALANCED
				posTable[mc:GetClockwiseDir(dir)] = mc.LONE
				posTable[mc:GetOppositeDir(dir)] = mc.SHORE
				posTable[mc:GetCounterclockwiseDir(mc:GetCounterclockwiseDir(dir))] = mc.INLAND
				posTable[mc:GetCounterclockwiseDir(dir)] = mc.SHORE
				break
			elseif waterDirs:contains(mc:GetOppositeDir(dir)) then
				pattern = mc.BALANCED
				for dir2,_ in pairs(landDirs) do
					if dir2 ~= mc.C then
						posTable[dir2] = mc.SHORE
					end
				end
				break
			end
		end
	elseif landCount == 6 then
		local waterDir = nil
		for dir,_ in pairs(mc.DIRECTIONS) do
			if not landDirs:contains(dir) then
				waterDir = dir
			end
		end
		if not waterDir then 
			print("Warning: Unexpected number of directions in DetermineLandPattern")
			print(string.format("#landDirs == %x", #landDirs))
			print("landDirs are:")
			for dir,_ in pairs(landDirs) do
				print(string.format("%x",dir))
			end
		end
	
		posTable[mc:GetOppositeDir(waterDir)] = mc.INLAND
		posTable[mc:GetClockwiseDir(mc:GetClockwiseDir(waterDir))] = mc.INTERMEDIATE
		posTable[mc:GetCounterclockwiseDir(mc:GetCounterclockwiseDir(waterDir))] = mc.INTERMEDIATE
		posTable[mc:GetClockwiseDir(waterDir)] = mc.SHORE
		posTable[mc:GetCounterclockwiseDir(waterDir)] = mc.SHORE
	elseif landCount == 7 then
		for dir,_ in pairs(mc.DIRECTIONS) do
			if dir ~= mc.C then
				posTable[dir] = mc.INLAND
			end
		end
	else
		print(string.format("Warning: Unexpected number of land tiles (%i) in DetermineLandPattern",landCount))
	end

	return pattern, posTable
end

function UpliftAtFault(x,y,faultType)
	--Elevates tiles along faults to a degree based on the local continental/oceanic
	--plate patterns, as determined by DetermineLandPatterns. Returns the sum of the
	--percent increases in elevation made as a rough measure of how much uplifting
	--was done

	--Note: Assumes everything in landDirs is a valid tile (i.e. lies on the map)
	local landDirs = AdjacentContinentalTiles(x,y)
	local netUplift = 0
	if not landDirs:contains(mc.C) then
		print("Warning: UpliftAtFault called on oceanic tile")
	end
	local pattern, positionLookupTable = DetermineLandPattern(landDirs)
	for dir, _ in pairs(landDirs) do
		if positionLookupTable[dir] == nil then	--Warn that dir is missing
			print(string.format("Warning: Direction %i not found in positionLookupTable in UpliftAtFault", dir))
		end
		local xx, yy = PlateMap:GetNeighbor(x,y,dir)
		local index = PlateMap:GetIndex(xx,yy)
		local coeff = mc:GetUpliftCoeff(faultType, landDirs:length(), pattern, positionLookupTable[dir])
		PlateMap.data[index] = PlateMap.data[index] * coeff
		netUplift = netUplift + (coeff - 1)
	end
	return netUplift
end

--An old method of uplifting mountains that seemed promising but which I never
--got to work at all reasonably. --LL
--[[function LiftAtContinentalConvergence(x,y)
	--Note: Assumes everything in landDirs is a valid tile (i.e. lies on the map)
	--print("Debug 1")
	local landDirs = AdjacentContinentalTiles(x,y)
	--print("Debug 2")
	if not landDirs:contains(mc.C) then
		print("Warning: LiftAtContinentalConvergence called on oceanic tile")
	end
	if landDirs:length() == 1 then
		print("Warning: Unexpected single-tile continent detected by LiftAtContinentalConvergence")
		PlateMap.data[PlateMap:GetIndex(x,y)] = PlateMap.data[PlateMap:GetIndex(x,y)] * 1.05
	elseif landDirs:length() == 2 then
		PlateMap.data[PlateMap:GetIndex(x,y)] = PlateMap.data[PlateMap:GetIndex(x,y)] * 1.2
		for dir, _ in pairs(landDirs) do
			local xx, yy, index
			xx, yy = PlateMap:GetNeighbor(x,y,dir)	
			index = PlateMap:GetIndex(xx,yy)
			PlateMap.data[index] = PlateMap.data[index] * 0.9
		end
	elseif landDirs:length() == 3 then
		--Do Nothing TODO: Change?
	elseif landDirs:length() == 4 then
		landDirs:delete(mc.C)
		--for dir, _ in ipairs(landDirs) do --This is wrong, but is what it used to be
		for dir, _ in pairs(landDirs) do
			-- Only add elevation if all three land tiles are contiguous
			if landDirs:contains(mc:GetClockwiseDir(dir)) and landDirs:contains(mc:GetCounterclockwiseDir(dir)) then
				local xx = {}
				local yy = {}
				xx[1], yy[1] = PlateMap:GetNeighbor(x,y,dir)
				xx[2], yy[2] = PlateMap:GetNeighbor(x,y,mc:GetClockwiseDir(dir))
				xx[3], yy[3] = PlateMap:GetNeighbor(x,y,mc:GetCounterclockwiseDir(dir))
				for i = 1, 3 do
					local scalar = 1.05
					if i == 1 then scalar = 1.3 end	--Raise the central land tile a moderate amount and the edge lands a tiny amount
					local index = PlateMap:GetIndex(xx[i],yy[i])
					PlateMap.data[index] = PlateMap.data[index] * scalar
				end
			end
		end
	elseif landDirs:length() == 5 then
		local waterDirs = Set:New({})
		--Every direction that isn't continental/pangeal plate is oceanic plate
		--(Or off the map, which we count as oceanic)
		for dir,_ in pairs(mc.DIRECTIONS) do
			if not landDirs:contains(dir) then
				waterDirs:add(dir)
			end
		end
		
		--Check the locations of the two water tiles
		for dir,_ in pairs(waterDirs) do
			if waterDirs:contains(mc:GetClockwiseDir(dir)) then
				--They are adjacent; elevate the two inland land tiles
				inlandDirCW = mc:GetCounterclockwiseDir(mc:GetCounterclockwiseDir(dir))
				inlandDirCCW = mc:GetCounterclockwiseDir(inlandDirCW)
				local xx, yy = PlateMap:GetNeighbor(x,y,inlandDirCW)
				local index = PlateMap:GetIndex(xx,yy)
				PlateMap.data[index] = PlateMap.data[index] * 1.5
				xx, yy = PlateMap:GetNeighbor(x,y,inlandDirCCW)
				index = PlateMap:GetIndex(xx,yy)
				PlateMap.data[index] = PlateMap.data[index] * 1.5
				return
			elseif waterDirs:contains(mc:GetClockwiseDir(mc:GetClockwiseDir(dir))) then
				--They are separated by a single land tile; elevate the one inland land tile
				local lonelandDir = mc:GetClockwiseDir(dir)
				local xx, yy = PlateMap:GetNeighbor(x,y,mc:GetOppositeDir(lonelandDir))
				local index = PlateMap:GetIndex(xx,yy)
				PlateMap.data[index] = PlateMap.data[index] * 1.4
				return
			elseif waterDirs:contains(mc:GetClockwiseDir(mc:GetClockwiseDir(mc:GetClockwiseDir(dir)))) then
				--They are opposite; Do Nothing
				return
			end
		end
		print("Warning: Unexpected case in LiftAtContinentalConvergence with #landDirs == 5")
		print("landDirs are:")
		for dir,_ in pairs(landDirs) do
			print(string.format("%x",dir))
		end
	elseif landDirs:length() == 6 then
		local waterDir = nil
		--The direction that isn't continental/pangeal plate is oceanic plate
		--(Or off the map, which we count as oceanic)
		for dir,_ in pairs(mc.DIRECTIONS) do
			if not landDirs:contains(dir) then
				waterDir = dir
			end
		end
		if not waterDir then 
			print("Warning: Unexpected number of directions")
			print(string.format("#landDirs == %x", #landDirs))
			print("landDirs are:")
			for dir,_ in pairs(landDirs) do
				print(string.format("%x",dir))
			end
		end
		landmostDir = mc:GetOppositeDir(waterDir)
		inlandDirCW = mc:GetClockwiseDir(landmostDir)
		inlandDirCCW = mc:GetCounterclockwiseDir(landmostDir)
		
		--Raise the inland land
		local xx, yy = PlateMap:GetNeighbor(x,y,landmostDir)
		local landmostIndex = PlateMap:GetIndex(xx,yy)
		xx, yy = PlateMap:GetNeighbor(x,y,inlandDirCW)
		local CWIndex = PlateMap:GetIndex(xx,yy)
		xx, yy = PlateMap:GetNeighbor(x,y,inlandDirCCW)
		local CCWIndex = PlateMap:GetIndex(xx,yy)
		PlateMap.data[landmostIndex] = PlateMap.data[landmostIndex] * 1.6
		PlateMap.data[CWIndex] = PlateMap.data[CWIndex] * 1.4
		PlateMap.data[CCWIndex] = PlateMap.data[CCWIndex] * 1.4
		
		--Also raise all land a tiny amount
		for dir,_ in pairs(landDirs) do
			xx, yy = PlateMap:GetNeighbor(x,y,dir)
			local index = PlateMap:GetIndex(xx,yy)
			PlateMap.data[index] = PlateMap.data[index] * 1.05
		end
	elseif landDirs:length() == 7 then
		--Everything is land, so elevate all of it!
		for dir, _ in pairs(landDirs) do
			xx, yy = PlateMap:GetNeighbor(x,y,dir)
			local index = PlateMap:GetIndex(xx,yy)
			PlateMap.data[index] = PlateMap.data[index] * 1.8
		end
	else
		print("Warning: Unexpected oceans in LiftAtContinentalConvergence")
		print(string.format("landDirs:length() == %x",landDirs:length()))
	end
end]]
--TODO: BE script uses ContiguateFaults function to move mountains away from faults I believe
-------------------------------------------------------------------------------------------
function GenerateElevations(W,H,xWrap,yWrap)
	--This function takes all of the data we've generated up to this point and translates it into a crude elevation map.
	local WH = W*H
	local scalar = 4

	local inputNoise = FloatMap:New(W,H,xWrap,yWrap)
	inputNoise:GenerateNoise()
	inputNoise:Normalize()
	local inputNoise2 = FloatMap:New(W,H,xWrap,yWrap)
	inputNoise2:GenerateNoise()
	inputNoise2:Normalize()

	PlateMap:GenerateNoise()
	PlateMap:Normalize()

    -- local landFactor = mc.continentalPercent/contPercent
    local landFactor = contPercent/mc.continentalPercent
	local minUplift = 140
	local currentUplifted = 0
	for i = 0, WH-1, 1 do
		if GetPlateType(i) == mc.PANGEAL or GetPlateType(i) == mc.CONTINENTAL then
			if PlateMap.fault[i] == mc.CONVERGENTFAULT then
				--PlateMap.data[i] = PlateMap.data[i] * 3 * (landFactor)^scalar
				PlateMap.data[i] = PlateMap.data[i] * .3 * (landFactor)^scalar
				--LiftAtContinentalConvergence(PlateMap:GetXYFromIndex(i))
				local x,y = PlateMap:GetXYFromIndex(i)
				currentUplifted = currentUplifted + 	--Note the odd line break; I think it makes the purpose here clearer (and you can comment this one line out if abandoning keeping track of uplift coefficient amount)
				UpliftAtFault(x,y,mc.CONVERGENTFAULT)
			elseif PlateMap.fault[i] == mc.TRANSFORMFAULT then
				PlateMap.data[i] = PlateMap.data[i] * 0.25 * (landFactor)^scalar
			else	--Divergent, Minor, or No Fault -LL
				PlateMap.data[i] = PlateMap.data[i] * 0.2 * (landFactor)^scalar
			end

            -- if PlateMap.ID[i] == sinkPlate and landFactor > 1.03 then
                -- PlateMap.data[i] = PlateMap.data[i]/(landFactor^((100 * landFactor) - 100))
                -- -- PlateMap.data[i] = PlateMap.data[i] / ((PlateMap.size[GetPlateByID(sinkPlate)]/WH) / (contPercent - mc.continentalPercent))
            -- elseif PlateMap.ID[i] == sinkPlate and landFactor < 0.97 then
                -- -- PlateMap.data[i] = PlateMap.data[i]*(landFactor^(100 - (100 * landFactor)))
                -- PlateMap.data[i] = PlateMap.data[i] * ((landFactor - 1.0) / (PlateMap.size[GetPlateByID(sinkPlate)]/WH))
            -- end
		else							--This is an oceanic plate -LamilLerran
			local hotspotRand = PWRand()
			if (PlateMap.fault[i] == mc.CONVERGENTFAULT or hotspotRand < mc.hotspotFrequency) then
				--Populate faults and hotspots with volcanos, which may create islands
				local islandRand = PWRand()
				if islandRand <= mc.oceanicVolcanoFrequency then
					local old = PlateMap.data[i]
					PlateMap.data[i] = PlateMap.data[i] * (0.05+(PWRandInt(1,2500)/10000)) * (1/landFactor)^scalar
					if (mc.islandExpansionFactor ~= 0) then
						--The adjustment size is what we got for the central tile being a "volcano" minus
						--what we would have gotten if it weren't a volcano
						local adjustment = PlateMap.data[i] - old * 0.0002
						if adjustment > 0 then
							local adjacentTiles = GetSpiral(i,1,1)
							for n = 1, #adjacentTiles, 1 do
								local j = adjacentTiles[n]
								if j ~= -1 then	--i.e. skip if j is not on the map
									PlateMap.data[j] = PlateMap.data[j] + mc.islandExpansionFactor * adjustment
								end
							end
							local twoOutTiles = GetSpiral(i,2,2)
							for n = 1, #twoOutTiles, 1 do
								local j = twoOutTiles[n]
								if j ~= -1 then	--i.e. skip if j is not on the map
									PlateMap.data[j] = PlateMap.data[j] + mc.islandExpansionFactor * mc.islandExpansionFactor * adjustment
								end
							end
							local threeOutTiles = GetSpiral(i,3,3)
							for n = 1, #threeOutTiles, 1 do
								local j = threeOutTiles[n]
								if j ~= -1 then	--i.e. skip if j is not on the map
									PlateMap.data[j] = PlateMap.data[j] + mc.islandExpansionFactor * mc.islandExpansionFactor * mc.islandExpansionFactor * adjustment
								end
							end
						end
					end
				else
					PlateMap.data[i] = PlateMap.data[i] * 0.0002
				end
			elseif PlateMap.fault[i] == mc.TRANSFORMFAULT then
				PlateMap.data[i] = PlateMap.data[i] * 0.00005
			else	--Divergent, Minor, or No Fault -LL
				PlateMap.data[i] = PlateMap.data[i] * 0.00005
			end
		end
	end

	--If there are too few mountains it can cause deserts to fail to generate and tundra to spread
	--way too far. This generates additional mountains if not enough uplift occured.
	if currentUplifted < minUplift then
		print(string.format("Sum of uplift coefficient values in excess of 1 insufficient at %.2f; adding failsafe mountains - Planet Simulator", currentUplifted))
	else
		print(string.format("Total uplift of %.2f is sufficient, no failsafe mountains needed - Planet Simulator", currentUplifted))
	end
	while currentUplifted < minUplift do
		i = PWRandInt(0, WH - 1)
		if GetPlateType(i) == mc.PANGEAL or GetPlateType(i) == mc.CONTINENTAL then
			--PlateMap.data[i] = PlateMap.data[i] * 6
			--currentUplifted = currentUplifted + 3 --These mountains are not as well placed as standard mountains, so count for less
		
			local x,y = PlateMap:GetXYFromIndex(i)
			for dir,_ in pairs(mc.DIRECTIONS) do
				local xx,yy,valid
				xx,yy,valid = PlateMap:GetNeighbor(x,y,dir,true)
				if valid and (dir == mc.C or PWRandInt(1,3) == 1) then
					newUpliftAmount = UpliftAtFault(x,y,mc.FALLBACKFAULT)
					currentUplifted = currentUplifted + newUpliftAmount/3	--These mountains are not as well placed as standard mountains, so count for less
				end
			end
		end
	end

	PlateMap:Normalize()

	for i = 0, WH-1, 1 do
		local x = i%W
		local y = (i-x)/W
		local val = PlateMap.data[i]
		PlateMap.data[i] = (math.sin(val*math.pi*2-math.pi*0.5)*0.5+0.5)
		PlateMap.data[i] = PlateMap.data[i] * GetAttenuationFactor(PlateMap,x,y)
	end
	PlateMap:Normalize()

	--Debug
	--PlateMap:Save4("PlateMap.data.csv",5)
end
-------------------------------------------------------------------------------------------
function GetPlateByID(ID)
	for i = 1, #PlateMap.index do
		if PlateMap.index[i] == ID then
			if PlateMap.size[i] == 0 then
				print("Warning - Returning a dead plate")
			end
			return i
		end
	end

	print("Error - Attempted to get plate index for an invalid ID")
end
-------------------------------------------------------------------------------------------
function GetPlateType(k)
	local ID = PlateMap.ID[k]
	local index = GetPlateByID(ID)
	return PlateMap.type[index]
end
-------------------------------------------------------------------------------------------
function SimulateTectonics(W,H,xWrap,yWrap)
	local Plates = 10+math.ceil(H*0.625)

	GeneratePlates(W,H,xWrap,yWrap,Plates)

	GenerateFaults()

    if Map.GetCustomOption(6) == 1 then
        --print("Generating Continents style map")
        CreateContinentalShelf(W,H)
    else
        --print("Generating Pangea style map.")
        CreatePangealShelf(W,H)
    end

	GenerateElevations(W,H,xWrap,yWrap)

	return PlateMap
end

-------------------------------------------------------------------------------------------
--Global functions
-------------------------------------------------------------------------------------------
function ShuffleList(list)
	local len = #list
	for i=0,len - 1,1 do
		local k = PWRandInt(0,len-1)
		list[i], list[k] = list[k], list[i]
	end
end
-------------------------------------------------------------------------------------------
function ShuffleList2(list)
	local len = #list
	for i=1,len ,1 do
		local k = PWRandInt(1,len)
		list[i], list[k] = list[k], list[i]
	end
end
-------------------------------------------------------------------------------------------
function waterMatch(x,y)
	if elevationMap:IsBelowSeaLevel(x,y) then
		return true
	end
	return false
end
-------------------------------------------------------------------------------------------
function GetAttenuationFactor(map,x,y)
	local southY = map.height * mc.southAttenuationRange
	local southRange = map.height * mc.southAttenuationRange
	local yAttenuation = 1.0
	if y < southY then
		yAttenuation = mc.southAttenuationFactor + (y/southRange) * (1.0 - mc.southAttenuationFactor)
	end

	local northY = map.height - (map.height * mc.northAttenuationRange)
	local northRange = map.height * mc.northAttenuationRange
	if y > northY then
		yAttenuation = mc.northAttenuationFactor + ((map.height - y)/northRange) * (1.0 - mc.northAttenuationFactor)
	end

	local eastY = map.width - (map.width * mc.eastAttenuationRange)
	local eastRange = map.width * mc.eastAttenuationRange
	local xAttenuation = 1.0
	if x > eastY then
		xAttenuation = mc.eastAttenuationFactor + ((map.width - x)/eastRange) * (1.0 - mc.eastAttenuationFactor)
	end

	local westY = map.width * mc.westAttenuationRange
	local westRange = map.width * mc.westAttenuationRange
	if x < westY then
		xAttenuation = mc.westAttenuationFactor + (x/westRange) * (1.0 - mc.westAttenuationFactor)
	end

	return yAttenuation * xAttenuation
end
-------------------------------------------------------------------------------------------
function GenerateElevationMap(width,height,xWrap,yWrap)
	--local twistMinFreq = 128/width * mc.twistMinFreq --0.02/128
	--local twistMaxFreq = 128/width * mc.twistMaxFreq --0.12/128
	--local twistVar = 128/width * mc.twistVar --0.042/128
	--local mountainFreq = 128/width * mc.mountainFreq --0.05/128
	--local twistMap = GenerateTwistedPerlinMap(width,height,xWrap,yWrap,twistMinFreq,twistMaxFreq,twistVar)
	--local mountainMap = GenerateMountainMap(width,height,xWrap,yWrap,mountainFreq)
	local elevationMap = ElevationMap:New(width,height,xWrap,yWrap)

	PlateMap = SimulateTectonics(width,height,xWrap,yWrap)

	local i = 0
	for y = 0,height - 1,1 do
		for x = 0,width - 1,1 do
			local tVal = PlateMap.data[i]
			tVal = (math.sin(tVal*math.pi-math.pi*0.5)*0.5+0.5)^0.25 --this formula adds a curve flattening the extremes
			elevationMap.data[i] = tVal
			i=i+1
		end
	end

	elevationMap:Normalize()

	--attentuation should not break normalization
	i = 0
	for y = 0,height - 1,1 do
		for x = 0,width - 1,1 do
			local attenuationFactor = GetAttenuationFactor(elevationMap,x,y)
			if y == 0 then
				elevationMap.data[i] = 0.0
			elseif y == height-1 then
				elevationMap.data[i] = 0.0
			else
				elevationMap.data[i] = elevationMap.data[i] * attenuationFactor
			end
			i=i+1
		end
	end

	elevationMap.seaLevelThreshold = elevationMap:FindThresholdFromPercent(mc.landPercent,true,false)

	--Debug
	--elevationMap:Save4("elevationMap.data.csv",5)

	return elevationMap
end
-------------------------------------------------------------------------------------------
function FillInLakes()
	local areaMap = PWAreaMap:New(elevationMap.width,elevationMap.height,elevationMap.wrapX,elevationMap.wrapY)
	areaMap:DefineAreas(waterMatch)
	for i=1,#areaMap.areaList,1 do
		local area = areaMap.areaList[i]
		if area.trueMatch and area.size < mc.minOceanSize then
			for n = 0,areaMap.length,1 do
				if areaMap.data[n] == area.id then
					elevationMap.data[n] = elevationMap.seaLevelThreshold
				end
			end
		end
	end
end
-------------------------------------------------------------------------------------------
function GenerateTempMaps(elevationMap)

	local aboveSeaLevelMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	local i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			if elevationMap:IsBelowSeaLevel(x,y) then
				aboveSeaLevelMap.data[i] = 0.0
			else
				aboveSeaLevelMap.data[i] = elevationMap.data[i] - elevationMap.seaLevelThreshold
			end
			i=i+1
		end
	end
	aboveSeaLevelMap:Normalize()
	--aboveSeaLevelMap:Save("aboveSeaLevelMap.csv")

	local summerMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	local zenith = mc.tropicLatitudes
	local topTempLat = mc.topLatitude + zenith
	local bottomTempLat = mc.bottomLatitude
	local latRange = topTempLat - bottomTempLat
	i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			local lat = summerMap:GetLatitudeForY(y)
			--print("y=" .. y ..",lat=" .. lat)
			local latPercent = (lat - bottomTempLat)/latRange
			--print("latPercent=" .. latPercent)
			local temp = (math.sin(latPercent * math.pi * 2 - math.pi * 0.5) * 0.5 + 0.5)
			if elevationMap:IsBelowSeaLevel(x,y) then
				temp = temp * mc.maxWaterTemp + mc.minWaterTemp
			end
			summerMap.data[i] = temp
			i=i+1
		end
	end

	local winterMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	zenith = -mc.tropicLatitudes
	topTempLat = mc.topLatitude
	bottomTempLat = mc.bottomLatitude + zenith
	latRange = topTempLat - bottomTempLat
	i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			local lat = winterMap:GetLatitudeForY(y)
			local latPercent = (lat - bottomTempLat)/latRange
			local temp = math.sin(latPercent * math.pi * 2 - math.pi * 0.5) * 0.5 + 0.5
			if elevationMap:IsBelowSeaLevel(x,y) then
				temp = temp * mc.maxWaterTemp + mc.minWaterTemp
			end
			winterMap.data[i] = temp
			i=i+1
		end
	end

	--Time3 = os.clock()
	summerMap:Smooth(math.floor(elevationMap.width/8))
	summerMap:Normalize()

	winterMap:Smooth(math.floor(elevationMap.width/8))
	winterMap:Normalize()
	--print(string.format("Smoothed weather maps in %.4f seconds. - Planet Simulator", os.clock() - Time3))

	local temperatureMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			temperatureMap.data[i] = (winterMap.data[i] + summerMap.data[i]) * (1.0 - aboveSeaLevelMap.data[i])
			i=i+1
		end
	end
	temperatureMap:Normalize()

	return summerMap,winterMap,temperatureMap
end
-------------------------------------------------------------------------------------------
function ConvertInlandOceansToSeas(elevationMap)
	local W,H = Map.GetGridSize()
	for n=1, #PlateMap.index, 1 do
		if PlateMap.type[n] == 0 then
			local inlandSea = true
			for nn=2, #PlateMap.neighbors[n], 1 do
				if PlateMap.type[GetPlateByID(PlateMap.neighbors[n][nn])] == 0 then
					inlandSea = false
					break
				end
			end
			if inlandSea then
				print("Inland sea, covering "..PlateMap.size[n].." tiles, detected at plate: "..PlateMap.index[n].." - Planet Simulator")
				for k=1, PlateMap.size[n], 1 do
					local i = PlateMap.info[n][k]
					local x = (i%W)
					local y = (i-x)/W
					x=x-shift_x
					if x < 0 then
						x = x+W
					end
					--print(string.format("plot is: (%d,%d). index is: %d. Xshift is: %d",x,y,i,shift_x))
					local plot = Map.GetPlot(x,y)
					local plotElevIndex = elevationMap:GetIndex(x,y)
					if plot:GetPlotType() == PlotTypes.PLOT_OCEAN then
						local lat = elevationMap:GetLatitudeForY(y)
						if lat < mc.iceNorthLatitudeLimit and lat > mc.iceSouthLatitudeLimit then
							local roll = PWRandInt(0,100)
							if roll > 15 then
								plot:SetTerrainType(GameDefines.SHALLOW_WATER_TERRAIN,false,false)
							elseif roll > 9 then
								plot:SetPlotType(PlotTypes.PLOT_HILLS,false,true)
								elevationMap.data[plotElevIndex] = elevationMap.seaLevelThreshold + 0.05 + 0.05 * PWRand()
							else
								plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
								elevationMap.data[plotElevIndex] = elevationMap.seaLevelThreshold + 0.005 + 0.005 * PWRand()
							end
						else
							plot:SetTerrainType(GameDefines.SHALLOW_WATER_TERRAIN,false,false)
						end
					end
				end
			end
		end
	end
end
-------------------------------------------------------------------------------------------
function GenerateRainfallMap(elevationMap)
	local summerMap,winterMap,temperatureMap = GenerateTempMaps(elevationMap)
	--summerMap:Save("summerMap.csv")
	--winterMap:Save("winterMap.csv")
	--temperatureMap:Save("temperatureMap.csv")

	local geoMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	local i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			local lat = elevationMap:GetLatitudeForY(y)
			local pressure = elevationMap:GetGeostrophicPressure(lat)
			geoMap.data[i] = pressure
			--print(string.format("pressure for (%d,%d) is %.8f",x,y,pressure))
			i=i+1
		end
	end
	geoMap:Normalize()
	--geoMap:Save("geoMap.csv")

	i = 0
	local sortedSummerMap = {}
	local sortedWinterMap = {}
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			sortedSummerMap[i + 1] = {x,y,summerMap.data[i]}
			sortedWinterMap[i + 1] = {x,y,winterMap.data[i]}
			i=i+1
		end
	end
	table.sort(sortedSummerMap, function (a,b) return a[3] < b[3] end)
	table.sort(sortedWinterMap, function (a,b) return a[3] < b[3] end)

	local sortedGeoMap = {}
	local xStart = 0
	local xStop = 0
	local yStart = 0
	local yStop = 0
	local incX = 0
	local incY = 0
	local geoIndex = 1
	local str = ""
	for zone=0,5,1 do
		local topY = elevationMap:GetYFromZone(zone,true)
		local bottomY = elevationMap:GetYFromZone(zone,false)
		if not (topY == -1 and bottomY == -1) then
			if topY == -1 then
				topY = elevationMap.height - 1
			end
			if bottomY == -1 then
				bottomY = 0
			end
			--print(string.format("topY = %d, bottomY = %d",topY,bottomY))
			local dir1,dir2 = elevationMap:GetGeostrophicWindDirections(zone)
			--print(string.format("zone = %d, dir1 = %d",zone,dir1))
			if (dir1 == mc.SW) or (dir1 == mc.SE) then
				yStart = topY
				yStop = bottomY --- 1
				incY = -1
			else
				yStart = bottomY
				yStop = topY --+ 1
				incY = 1
			end
			if dir2 == mc.W then
				xStart = elevationMap.width - 1
				xStop = 0---1
				incX = -1
			else
				xStart = 0
				xStop = elevationMap.width
				incX = 1
			end
			--print(string.format("yStart = %d, yStop = %d, incY = %d",yStart,yStop,incY))
			--print(string.format("xStart = %d, xStop = %d, incX = %d",xStart,xStop,incX)

			for y = yStart,yStop ,incY do
				--print(string.format("y = %d",y))
				--each line should start on water to avoid vast areas without rain
				local xxStart = xStart
				local xxStop = xStop
				for xx = xStart,xStop - incX, incX do
					local i = elevationMap:GetIndex(xx,y)
					if elevationMap:IsBelowSeaLevel(xx,y) then
						xxStart = xx
						xxStop = xx + elevationMap.width * incX
						break
					end
				end
				for x = xxStart,xxStop - incX,incX do
					local i = elevationMap:GetIndex(x,y)
					sortedGeoMap[geoIndex] = {x,y,geoMap.data[i]}
					geoIndex = geoIndex + 1
				end
			end
		end
	end
	--table.sort(sortedGeoMap, function (a,b) return a[3] < b[3] end)
	--print(#sortedGeoMap)
	--print(#geoMap.data)

	local rainfallSummerMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	local moistureMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	for i = 1,#sortedSummerMap,1 do
		local x = sortedSummerMap[i][1]
		local y = sortedSummerMap[i][2]
		local pressure = sortedSummerMap[i][3]
		DistributeRain(x,y,elevationMap,temperatureMap,summerMap,rainfallSummerMap,moistureMap,false)
	end

	local rainfallWinterMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	local moistureMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	for i = 1,#sortedWinterMap,1 do
		local x = sortedWinterMap[i][1]
		local y = sortedWinterMap[i][2]
		local pressure = sortedWinterMap[i][3]
		DistributeRain(x,y,elevationMap,temperatureMap,winterMap,rainfallWinterMap,moistureMap,false)
	end

	local rainfallGeostrophicMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	moistureMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	--print("----------------------------------------------------------------------------------------")
	--print("--GEOSTROPHIC---------------------------------------------------------------------------")
	--print("----------------------------------------------------------------------------------------")
	for i = 1,#sortedGeoMap,1 do
		local x = sortedGeoMap[i][1]
		local y = sortedGeoMap[i][2]
		DistributeRain(x,y,elevationMap,temperatureMap,geoMap,rainfallGeostrophicMap,moistureMap,true)
	end

	--zero below sea level for proper percent threshold finding
	i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			if elevationMap:IsBelowSeaLevel(x,y) then
				rainfallSummerMap.data[i] = 0.0
				rainfallWinterMap.data[i] = 0.0
				rainfallGeostrophicMap.data[i] = 0.0
			end
			i=i+1
		end
	end

	rainfallSummerMap:Normalize()
	--rainfallSummerMap:Save("rainFallSummerMap.csv")
	rainfallWinterMap:Normalize()
	--rainfallWinterMap:Save("rainFallWinterMap.csv")
	rainfallGeostrophicMap:Normalize()
	--rainfallGeostrophicMap:Save("rainfallGeostrophicMap.csv")

	local rainfallMap = FloatMap:New(elevationMap.width,elevationMap.height,elevationMap.xWrap,elevationMap.yWrap)
	i = 0
	for y = 0,elevationMap.height - 1,1 do
		for x = 0,elevationMap.width - 1,1 do
			rainfallMap.data[i] = rainfallSummerMap.data[i] + rainfallWinterMap.data[i] + (rainfallGeostrophicMap.data[i] * mc.geostrophicFactor)
			i=i+1
		end
	end
	rainfallMap:Normalize()
	--TODO: BE script also looks at polar circle temperatures to determine what forest temp should be. I'll probably skip? but could help getting at target forest tile #

	return rainfallMap, temperatureMap
end
-------------------------------------------------------------------------------------------
function DistributeRain(x,y,elevationMap,temperatureMap,pressureMap,rainfallMap,moistureMap,boolGeostrophic)

	local i = elevationMap:GetIndex(x,y)
	local upLiftSource = math.max(math.pow(pressureMap.data[i],mc.upLiftExponent),1.0 - temperatureMap.data[i])
	--local str = string.format("geo=%s,x=%d, y=%d, srcPressure uplift = %f, upliftSource = %f",tostring(boolGeostrophic),x,y,math.pow(pressureMap.data[i],mc.upLiftExponent),upLiftSource)
	--print(str)
	if elevationMap:IsBelowSeaLevel(x,y) then
		moistureMap.data[i] = math.max(moistureMap.data[i], temperatureMap.data[i])
		--print("water tile = true")
	end
	--print(string.format("moistureMap.data[i] = %f",moistureMap.data[i]))

	--make list of neighbors
	local nList = {}
	if boolGeostrophic then
		local zone = elevationMap:GetZone(y)
		local dir1,dir2 = elevationMap:GetGeostrophicWindDirections(zone)
		local x1,y1 = elevationMap:GetNeighbor(x,y,dir1)
		local ii = elevationMap:GetIndex(x1,y1)
		--neighbor must be on map and in same wind zone
		if ii >= 0 and (elevationMap:GetZone(y1) == elevationMap:GetZone(y)) then
			table.insert(nList,{x1,y1})
		end
		local x2,y2 = elevationMap:GetNeighbor(x,y,dir2)
		ii = elevationMap:GetIndex(x2,y2)
		if ii >= 0 then
			table.insert(nList,{x2,y2})
		end
	else
		for dir = 1,6,1 do
			local xx,yy = elevationMap:GetNeighbor(x,y,dir)
			local ii = elevationMap:GetIndex(xx,yy)
			if ii >= 0 and pressureMap.data[i] <= pressureMap.data[ii] then
				table.insert(nList,{xx,yy})
			end
		end
	end
	if #nList == 0 or boolGeostrophic and #nList == 1 then
		local cost = moistureMap.data[i]
		rainfallMap.data[i] = cost
		return
	end
	local moisturePerNeighbor = moistureMap.data[i]/#nList
	--drop rain and pass moisture to neighbors
	for n = 1,#nList,1 do
		local xx = nList[n][1]
		local yy = nList[n][2]
		local ii = elevationMap:GetIndex(xx,yy)
		local upLiftDest = math.max(math.pow(pressureMap.data[ii],mc.upLiftExponent),1.0 - temperatureMap.data[ii])
		local cost = GetRainCost(upLiftSource,upLiftDest)
		local bonus = 0.0
		if (elevationMap:GetZone(y) == mc.NPOLAR or elevationMap:GetZone(y) == mc.SPOLAR) then
			bonus = mc.polarRainBoost
		end
		if boolGeostrophic and #nList == 2 then
			if n == 1 then
				moisturePerNeighbor = (1.0 - mc.geostrophicLateralWindStrength) * moistureMap.data[i]
			else
				moisturePerNeighbor = mc.geostrophicLateralWindStrength * moistureMap.data[i]
			end
		end
		--print(string.format("---xx=%d, yy=%d, destPressure uplift = %f, upLiftDest = %f, cost = %f, moisturePerNeighbor = %f, bonus = %f",xx,yy,math.pow(pressureMap.data[ii],mc.upLiftExponent),upLiftDest,cost,moisturePerNeighbor,bonus))
		rainfallMap.data[i] = rainfallMap.data[i] + cost * moisturePerNeighbor + bonus
		--pass to neighbor.
		--print(string.format("---moistureMap.data[ii] = %f",moistureMap.data[ii]))
		moistureMap.data[ii] = moistureMap.data[ii] + moisturePerNeighbor - (cost * moisturePerNeighbor)
		--print(string.format("---dropping %f rain",cost * moisturePerNeighbor + bonus))
		--print(string.format("---passing on %f moisture",moisturePerNeighbor - (cost * moisturePerNeighbor)))
	end

end
-------------------------------------------------------------------------------------------
function GetRainCost(upLiftSource,upLiftDest)
	local cost = mc.minimumRainCost
	cost = math.max(mc.minimumRainCost, cost + upLiftDest - upLiftSource)
	if cost < 0.0 then
		cost = 0.0
	end
	return cost
end
-------------------------------------------------------------------------------------------
function GetDifferenceAroundHex(i)
	--local W,H = Map.GetGridSize();
	local avg = elevationMap:GetAverageInHex(i,1)
 	--local i = elevationMap:GetIndex(x,y)
	return elevationMap.data[i] - avg
end
-------------------------------------------------------------------------------------------
--Global lookup tables used to track land, and terrain type. Used throughout terrain placement, Cleanup, and feature placement. -Bobert13
desertTab = {}
snowTab = {}
tundraTab = {}
plainsTab = {}
grassTab = {}
landTab = {}
-------------------------------------------------------------------------------------------
function PlacePossibleOasis()
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"]
	local terrainPlains	= GameInfoTypes["TERRAIN_PLAINS"]
	local terrainTundra	= GameInfoTypes["TERRAIN_TUNDRA"]
	local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"]
	local featureFloodPlains = FeatureTypes.FEATURE_FLOOD_PLAINS
	local featureOasis = FeatureTypes.FEATURE_OASIS
	local plotMountain = PlotTypes.PLOT_MOUNTAIN
	local oasisTotal = 0
	local W,H = Map.GetGridSize()
	local WH = W*H
	ShuffleList2(desertTab)
	for k=1,#desertTab do
		local i = desertTab[k]
		local plot = Map.GetPlotByIndex(i) --Sets the candidate plot.
		local tiles = GetSpiral(i,3) --Creates a table of all coordinates within 3 tiles of the candidate plot.
		local desertCount = 0
		local canPlace = true
		for n=1,7 do --Analyzes the first 7 entries in the table. These will all be adjacent to the candidate plot or thep candidate itself.
			local ii = tiles[n]
			if ii ~= -1 then
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetFeatureType() == featureFloodPlains then
					canPlace = false
					break
				elseif nPlot:IsWater() then
					canPlace = false
					break
				elseif nPlot:GetTerrainType() == terrainDesert then
					if nPlot:GetPlotType() ~= plotMountain then
						desertCount = desertCount + 1
					end
				end
			end
		end
		if desertCount < 4 then
			canPlace = false
		end
		if canPlace then
			local foodCount = 0
			for n=1,19 do --Analyzes the first 19 entries in the table. These will all be the candidate plot itself or within two tiles of it.
				local ii = tiles[n]
				if ii ~= -1 then
					local nPlot = Map.GetPlotByIndex(ii)
					if nPlot:GetPlotType() ~= PlotTypes.PLOT_HILLS then
						if nPlot:GetTerrainType() == terrainGrass or nPlot:IsRiver() then
							foodCount = foodCount + 2
						elseif nPlot:GetTerrainType() == terrainPlains or nPlot:GetTerrainType() == terrainTundra or nPlot:IsWater() then
							foodCount = foodCount + 1
						elseif nPlot:GetFeatureType() == featureOasis then
							foodCount = foodCount + mc.OasisThreshold --Prevents Oases from spawning within two tiles of eachother -Bobert13
						end
					elseif nPlot:IsRiver() then --Hills on a river. -Bobert13
						foodCount = foodCount + 1
					end
				end
			end
			if foodCount < mc.OasisThreshold then
				local oasisCount = 0
				local doplace = true
				for n=20,#tiles do --Analyzes the LAST 18 entries in the table. These will all be in the third ring of tiles around the candidate plot.
					local ii = tiles[n]
					if ii ~= -1 then
						local nPlot = Map.GetPlotByIndex(ii)
						if nPlot:GetFeatureType() == featureOasis then
							oasisCount = oasisCount+1
						end
					end
				end
				if oasisCount == 1 then
					local roll = PWRandInt(0,1)
					if roll == 1 then
						doplace = false
					end
				elseif oasisCount > 1 then
					doplace = false
				end
				if doplace then
					--local x = i%W
					--local y = (i-x)/W
					--print(string.format("---Placing Oasis at (%d,%d)",x,y))
					plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
					plot:SetFeatureType(featureOasis,-1)
					oasisTotal = oasisTotal +1
				end
			end
		end
	end
	--print(string.format("---Placed %d Oases.",oasisTotal))
end
-------------------------------------------------------------------------------------------
function PlacePossibleIce(i,W)
	local featureIce = FeatureTypes.FEATURE_ICE
	local plot = Map.GetPlotByIndex(i)
	local x = i%W
	local y = (i-x)/W
	if plot:IsWater() then
		local temp = temperatureMap.data[i]
		local latitude = temperatureMap:GetLatitudeForY(y)
		local randvalNorth = PWRand() * (mc.iceNorthLatitudeLimit - mc.topLatitude) + mc.topLatitude - 3
		local randvalSouth = PWRand() * (mc.bottomLatitude - mc.iceSouthLatitudeLimit) + mc.iceSouthLatitudeLimit + 3
		--print(string.format("lat = %f, randvalNorth = %f, randvalSouth = %f",latitude,randvalNorth,randvalSouth))
		if latitude > randvalNorth  or latitude < randvalSouth then
			local tiles = GetCircle(i,1)
			local count = 0
			for n=1,#tiles do
				local ii = tiles[n]
				--local xx = ii % W
				--local yy = (ii-xx)/W
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetFeatureType() ~= -1 and nPlot:GetFeatureType() ~= FeatureTypes.FEATURE_ICE then
					local tiles2 = GetSpiral(ii,1)
					for nn = 2, #tiles2 do
						local iii = tiles2[nn]
						local pPlot = Map.GetPlotByIndex(iii)
						if iii == -1 or pPlot:GetFeatureType() == FeatureTypes.FEATURE_ICE or not pPlot:IsWater() then
							count = count + 1
						end
					end
				end
			end
			if count < 5 then
				plot:SetFeatureType(featureIce,-1)
			end
		end
	end
end
-------------------------------------------------------------------------------------------
function PlacePossibleAtoll(i)
	local shallowWater = GameDefines.SHALLOW_WATER_TERRAIN
	local deepWater = GameDefines.DEEP_WATER_TERRAIN
	local featureAtoll = GameInfo.Features.FEATURE_ATOLL.ID
	local W,H = Map.GetGridSize();
	local plot = Map.GetPlotByIndex(i)
	local x = i%W
	local y = (i-x)/W
	if plot:GetTerrainType() == shallowWater then
		local temp = temperatureMap.data[i]
		local latitude = temperatureMap:GetLatitudeForY(y)
		if latitude < mc.atollNorthLatitudeLimit and latitude > mc.atollSouthLatitudeLimit then
			local tiles = GetCircle(i,1)
			local deepCount = 0
			for n=1,#tiles do
				local ii = tiles[n]
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetTerrainType() == deepWater then
					deepCount = deepCount + 1
				end
			end
			if deepCount >= mc.atollMinDeepWaterNeighbors then
				local roll1 = PWRandInt(1,5)
				if roll1 < 3 then
					plot:SetFeatureType(featureAtoll,-1)
				end
			end
		end
	end
end
-------------------------------------------------------------------------------------------
--ShiftMap Class
-------------------------------------------------------------------------------------------
shift_x = 0
function ShiftMaps()
	--local stripRadius = self.stripRadius;
	local shift_y = 0

	shift_x = DetermineXShift()

	ShiftMapsBy(shift_x, shift_y)
end
-------------------------------------------------------------------------------------------
function ShiftMapsBy(xshift, yshift)
	local W, H = Map.GetGridSize();
	if(xshift > 0 or yshift > 0) then
		local Shift = {}
		local iDestI = 0
		for iDestY = 0, H-1 do
			for iDestX = 0, W-1 do
				local iSourceX = (iDestX + xshift) % W;
				--local iSourceY = (iDestY + yshift) % H; -- If using yshift, enable this and comment out the faster line below. - Bobert13
				local iSourceY = iDestY
				local iSourceI = W * iSourceY + iSourceX
				Shift[iDestI] = elevationMap.data[iSourceI]
				--print(string.format("Shift:%d,	%f	|	eMap:%d,	%f",iDestI,Shift[iDestI],iSourceI,elevationMap.data[iSourceI]))
				iDestI = iDestI+1
			end
		end
		elevationMap.data = Shift --It's faster to do one large table operation here than it is to do thousands of small operations to set up a copy of the input table at the beginning. -Bobert13
		return elevationMap
	end
end
-------------------------------------------------------------------------------------------
function DetermineXShift()
	--[[ This function will align the most water-heavy vertical portion of the map with the
	vertical map edge. This is a form of centering the landmasses, but it emphasizes the
	edge not the middle. If there are columns completely empty of land, these will tend to
	be chosen as the new map edge, but it is possible for a narrow column between two large
	continents to be passed over in favor of the thinnest section of a continent, because
	the operation looks at a group of columns not just a single column, then picks the
	center of the most water heavy group of columns to be the new vertical map edge. ]]--

	-- First loop through the map columns and record land plots in each column.
	local W, H = Map.GetGridSize();
	local land_totals = {};
	for x = 0, W - 1 do
		local current_column = 0;
		for y = 0, H - 1 do
			if not elevationMap:IsBelowSeaLevel(x,y) then
				current_column = current_column + 1;
			end
		end
		table.insert(land_totals, current_column);
	end

	-- Now evaluate column groups, each record applying to the center column of the group.
	local column_groups = {};
	-- Determine the group size in relation to map width.
	local group_radius = 3;
	-- Measure the groups.
	for column_index = 1, W do
		local current_group_total = 0;
		--for current_column = column_index - group_radius, column_index + group_radius do
		--Changed how group_radius works to get groups of four. -Bobert13
		for current_column = column_index, column_index + group_radius do
			local current_index = current_column % W;
			if current_index == 0 then -- Modulo of the last column will be zero; this repairs the issue.
				current_index = W;
			end
			current_group_total = current_group_total + land_totals[current_index];
		end
		table.insert(column_groups, current_group_total);
	end

	-- Identify the group with the least amount of land in it.
	local best_value = H * (group_radius + 1); -- Set initial value to max possible.
	local best_group = 1; -- Set initial best group as current map edge.
	for column_index, group_land_plots in ipairs(column_groups) do
		if group_land_plots < best_value then
			best_value = group_land_plots;
			best_group = column_index;
		end
	end

	-- Determine X Shift
	local x_shift = best_group + 2;
	if x_shift == W then
		x_shift = 0
	elseif x_shift == W+1 then
		x_shift = 1
	end
	return x_shift;
end
------------------------------------------------------------------------------
--DiffMap Class
------------------------------------------------------------------------------
--Seperated this from GeneratePlotTypes() to use it in other functions. -Bobert13

DiffMap = inheritsFrom(FloatMap)

function GenerateDiffMap(width,height,xWrap,yWrap)
	DiffMap = FloatMap:New(width,height,xWrap,yWrap)
	local i = 0
	for y = 0, height - 1,1 do
		for x = 0,width - 1,1 do
			if elevationMap:IsBelowSeaLevel(x,y) then
				DiffMap.data[i] = 0.0
			else
				DiffMap.data[i] = GetDifferenceAroundHex(i)
			end
			i=i+1
		end
	end

	DiffMap:Normalize()
	i = 0
	for y = 0, height - 1,1 do
		for x = 0,width - 1,1 do
			if elevationMap:IsBelowSeaLevel(x,y) then
				DiffMap.data[i] = 0.0
			else
				DiffMap.data[i] = DiffMap.data[i] + elevationMap.data[i] * 1.1
			end
			i=i+1
		end
	end

	DiffMap:Normalize()
	return DiffMap
end
-------------------------------------------------------------------------------------------
function GenerateCoasts(args)
	print("Setting coasts and oceans - Planet Simulator");
	local args = args or {};
	local bExpandCoasts = args.bExpandCoasts or true;
	local expansion_diceroll_table = args.expansion_diceroll_table or {4, 4};

	local shallowWater = GameDefines.SHALLOW_WATER_TERRAIN;
	local deepWater = GameDefines.DEEP_WATER_TERRAIN;

	for i, plot in Plots() do
		if(plot:IsWater()) then
			if(plot:IsAdjacentToLand()) then
				plot:SetTerrainType(shallowWater, false, false);
			else
				plot:SetTerrainType(deepWater, false, false);
			end
		end
	end

	if bExpandCoasts == false then
		return
	end

	-- print("Expanding coasts (MapGenerator.Lua)");
	for loop, iExpansionDiceroll in ipairs(expansion_diceroll_table) do
        local shallowWaterPlots = {};
		for i, plot in Plots() do
			if(plot:GetTerrainType() == deepWater) then
				-- Chance for each eligible plot to become an expansion is 1 / iExpansionDiceroll.
				-- Default is two passes at 1/4 chance per eligible plot on each pass.
				if(plot:IsAdjacentToShallowWater() and PWRandInt(0, iExpansionDiceroll) == 0) then
					table.insert(shallowWaterPlots, plot);
                    -- plot:SetTerrainType(shallowWater, false, false);
				end
			end
		end
        for i, plot in ipairs(shallowWaterPlots) do
            plot:SetTerrainType(shallowWater, false, false);
        end
	end
end
-------------------------------------------------------------------------------------------
function GeneratePlotTypes()
	Time = os.clock()

	print("Creating initial map data - Planet Simulator")
	local W,H = Map.GetGridSize()
	--first do all the preliminary calculations in this function
	--print(string.format("Map size: width=%d, height=%d - Planet Simulator",W,H))
	mc = MapConstants:New()
	-- PWRandSeed(373137609)
    PWRandSeed()

	elevationMap = GenerateElevationMap(W,H,true,false)
	FillInLakes()
	ShiftMaps()
	DiffMap = GenerateDiffMap(W,H,true,false)
	
	--Debug
	--elevationMap:Save4("elevationMap-afterShiftMaps.data.csv",5)

	--now gen plot types
	print("Generating plot types - Planet Simulator")
	--find exact thresholds
	local hillsThreshold = DiffMap:FindThresholdFromPercent(mc.hillsPercent,false,true)
	local mountainsThreshold = DiffMap:FindThresholdFromPercent(mc.mountainsPercent,false,true)
	local mountainTab = {}
	local i = 0
	for y = 0, H - 1,1 do
		for x = 0,W - 1,1 do
			local plot = Map.GetPlot(x,y);
			if elevationMap:IsBelowSeaLevel(x,y) then
				plot:SetPlotType(PlotTypes.PLOT_OCEAN, false, false)
			elseif DiffMap.data[i] < hillsThreshold then
				plot:SetPlotType(PlotTypes.PLOT_LAND,false,false)
				table.insert(landTab,i)
			--This code makes the game only ever plot flat land if it's within two tiles of
			--the seam. This prevents issues with tiles that don't look like what they are.
			elseif x == 0 or x == 1 or x == W - 1 or x == W -2 then
				plot:SetPlotType(PlotTypes.PLOT_LAND,false,false)
				table.insert(landTab,i)
			-- Bobert13
			elseif DiffMap.data[i] < mountainsThreshold then
				plot:SetPlotType(PlotTypes.PLOT_HILLS,false,false)
				table.insert(landTab,i)
			else
				plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN,false,false)
				table.insert(mountainTab,i)
			end
			i=i+1
		end
	end

	-- Gets rid of most single tile mountains in the oceans. -- Bobert13
	for k = 1,#mountainTab,1 do
		local i = mountainTab[k]
		local plot = Map.GetPlotByIndex(i)
		local tiles = GetSpiral(i,1,1)
		local landCount = 0
		for n=1,#tiles do
			local ii = tiles[n]
			if ii ~= -1 then
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetPlotType() == PlotTypes.PLOT_HILLS then
					landCount = landCount + 1
				elseif nPlot:GetPlotType() == PlotTypes.PLOT_LAND then
					landCount = landCount + 1
				end
			end
		end
		if landCount == 0 then
			local roll1 = PWRandInt(1,4)
			if roll1 == 1 then
				plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
			else
				plot:SetPlotType(PlotTypes.PLOT_HILLS,false,true)
			end
		end
	end

	GenerateCoasts({expansion_diceroll_table = mc.coastExpansionChance});
	
	--removes "ocean" tiles from inland seas
	--this only affects inland seas made of a single oceanic plate. I like rare inland oceans, so I'm leaving it -LL
	ConvertInlandOceansToSeas(elevationMap)
	
	rainfallMap, temperatureMap = GenerateRainfallMap(elevationMap)
	riverMap = RiverMap:New(elevationMap)
	riverMap:SetJunctionAltitudes()
	riverMap:SiltifyLakes()
	riverMap:SetFlowDestinations()
	riverMap:SetRiverSizes(rainfallMap)
	--Debug -- doesn't work
	--riverMap:Save4("riverMap.data.csv",5)
end
------------------------------------------------------------------------------
function GenerateTerrain()
	print("Generating terrain - Planet Simulator")
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
	local terrainPlains	= GameInfoTypes["TERRAIN_PLAINS"];
	local terrainSnow	= GameInfoTypes["TERRAIN_SNOW"];
	local terrainTundra	= GameInfoTypes["TERRAIN_TUNDRA"];
	local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"];
	local W, H = Map.GetGridSize();
	--first find minimum rain above sea level for a soft desert transition
	local minRain = 100.0
	for k = 1,#landTab do
		local i = landTab[k]
		if rainfallMap.data[i] < minRain then
			minRain = rainfallMap.data[i]
		end
	end

	--find exact thresholds
	local desertThreshold = rainfallMap:FindThresholdFromPercent(mc.desertPercent,false,true)
	local plainsThreshold = rainfallMap:FindThresholdFromPercent(mc.plainsPercent,false,true)

	ShuffleList2(landTab)
	for k=1,#landTab do
		local i = landTab[k]
		local plot = Map.GetPlotByIndex(i)
		if rainfallMap.data[i] < desertThreshold then
			if temperatureMap.data[i] < mc.snowTemperature then
				plot:SetTerrainType(terrainSnow,false,false)
				table.insert(snowTab,i)
			elseif temperatureMap.data[i] < mc.tundraTemperature then
				plot:SetTerrainType(terrainTundra,false,false)
				table.insert(tundraTab,i)
			elseif temperatureMap.data[i] < mc.desertMinTemperature then
				plot:SetTerrainType(terrainPlains,false,false)
				table.insert(plainsTab,i)
			else
				plot:SetTerrainType(terrainDesert,false,false)
				table.insert(desertTab,i)
			end
		elseif rainfallMap.data[i] < plainsThreshold then
			if temperatureMap.data[i] < mc.snowTemperature then
				plot:SetTerrainType(terrainSnow,false,false)
				table.insert(snowTab,i)
			elseif temperatureMap.data[i] < mc.tundraTemperature then
				plot:SetTerrainType(terrainTundra,false,false)
				table.insert(tundraTab,i)
			else
				if rainfallMap.data[i] < (PWRand() * (plainsThreshold - desertThreshold) + plainsThreshold - desertThreshold)/2.0 + desertThreshold then
					plot:SetTerrainType(terrainPlains,false,false)
					table.insert(plainsTab,i)
				else
					plot:SetTerrainType(terrainGrass,false,false)
					table.insert(grassTab,i)
				end
			end
		else
			if temperatureMap.data[i] < mc.snowTemperature then
				plot:SetTerrainType(terrainSnow,false,false)
				table.insert(snowTab,i)
			elseif temperatureMap.data[i] < mc.tundraTemperature then
				plot:SetTerrainType(terrainTundra,false,false)
				table.insert(tundraTab,i)
			else
				plot:SetTerrainType(terrainGrass,false,false)
				table.insert(grassTab,i)
			end
		end
	end
end
------------------------------------------------------------------------------
function AddLakes()
	print("Adding Lakes - Planet Simulator")
	local Desert	= GameInfoTypes["TERRAIN_DESERT"]
	local Plains	= GameInfoTypes["TERRAIN_PLAINS"]
	local Snow		= GameInfoTypes["TERRAIN_SNOW"]
	local Tundra	= GameInfoTypes["TERRAIN_TUNDRA"]
	local Grass		= GameInfoTypes["TERRAIN_GRASS"]
	local W, H 		= Map.GetGridSize()
	local flowN		= FlowDirectionTypes.FLOWDIRECTION_NORTH
	local flowNE	= FlowDirectionTypes.FLOWDIRECTION_NORTHEAST
	local flowSE	= FlowDirectionTypes.FLOWDIRECTION_SOUTHEAST
	local flowS		= FlowDirectionTypes.FLOWDIRECTION_SOUTH
	local flowSW	= FlowDirectionTypes.FLOWDIRECTION_SOUTHWEST
	local flowNW	= FlowDirectionTypes.FLOWDIRECTION_NORTHWEST
	local flowNone	= FlowDirectionTypes.NO_FLOWDIRECTION
	local WOfRiver, NWOfRiver, NEOfRiver = nil
	local numLakes	= 0
	local LakeUntil	= H * mc.lakeFactor/8

	local iters = 0
	while numLakes < LakeUntil do
		local k = 1
		for n = 1,#landTab do
			local i = landTab[k]
			local x = i%W
			local y = (i-x)/W
			local plot = Map.GetPlotByIndex(i)
			if not plot:IsCoastalLand() then
				if not plot:IsRiver() then
					local placeLake = true
					local terrain = plot:GetTerrainType()
					local tiles = GetCircle(i,1)
					for k=1,#tiles,1 do
						local zplot = Map.GetPlotByIndex(tiles[k])
						if zplot:GetTerrainType() == Desert then
							placeLake = false
							break
						end
					end
					local r = PWRandInt(1 , 512)
					if placeLake and r == 1 then
						--print(string.format("adding lake at (%d,%d)",x,y))
						if terrain == Grass then
							for z=1,#grassTab,1 do if i == grassTab[z] then table.remove(grassTab, z) end end
						elseif terrain == Plains then
							for z=1,#plainsTab,1 do if i == plainsTab[z] then table.remove(plainsTab, z) end end
						elseif terrain == Tundra then
							for z=1,#tundraTab,1 do if i == tundraTab[z] then table.remove(tundraTab, z) end end
						elseif terrain == Snow then
							for z=1,#snowTab,1 do if i == snowTab[z] then table.remove(snowTab, z) end end
						else
							print("Error - could not find index in any terrain table during AddLakes(). landTab must be getting fucked up...")
						end
						plot:SetArea(-1)
						plot:SetPlotType(PlotTypes.PLOT_OCEAN, true, true)
						numLakes = numLakes + 1
						table.remove(landTab, k)
						k=k-1
					end
				-- else
					-- local r = PWRandInt(1 , 128)
					-- if r == 1 then
						-- --print(string.format("adding lake at (%d,%d)",x,y))
						-- terrain = plot:GetTerrainType()
						-- if terrain == Desert then
							-- for z=1,#desertTab,1 do if i == desertTab[z] then table.remove(desertTab, z) end end
						-- elseif terrain == Grass then
							-- for z=1,#grassTab,1 do if i == grassTab[z] then table.remove(grassTab, z) end end
						-- elseif terrain == Plains then
							-- for z=1,#plainsTab,1 do if i == plainsTab[z] then table.remove(plainsTab, z) end end
						-- elseif terrain == Tundra then
							-- for z=1,#tundraTab,1 do if i == tundraTab[z] then table.remove(tundraTab, z) end end
						-- elseif terrain == Snow then
							-- for z=1,#snowTab,1 do if i == snowTab[z] then table.remove(snowTab, z) end end
						-- else
							-- print("Error - could not find index in any terrain table during AddLakes(). landTab must be getting fucked up...")
						-- end
						-- --plot:SetArea(-1)
						-- plot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, true)
						-- numLakes = numLakes + 1
						-- table.remove(landTab, k)
						-- k=k-1
						-- for dir = mc.W, mc.SW, 1 do
							-- local xx,yy = elevationMap:GetNeighbor(x,y,dir)
							-- local pplot = Map.GetPlot(xx,yy)
							-- if pplot then
								-- WOfRiver, NWOfRiver, NEOfRiver = riverMap:GetFlowDirections(xx,yy)
								-- if dir == mc.W then
									-- pplot:SetWOfRiver(false,flowNone)
									-- if NWOfRiver and pplot:GetRiverSEFlowDirection() == flowSW then
										-- print(string.format("Adding spokes to river at (%d,%d)",xx,yy))
										-- pplot:SetWOfRiver(true,flowS)
										-- plot:SetNEOfRiver(true,flowNW)
									-- end
								-- elseif dir == mc.NW then
									-- pplot:SetNWOfRiver(false,flowNone)
									-- if NEOfRiver and pplot:GetRiverSWFlowDirection() == flowNW then
										-- print(string.format("Adding spokes to river at (%d,%d)",xx,yy))
										-- pplot:SetNWOfRiver(true,flowSW)
										-- local xxx,yyy = elevationMap:GetNeighbor(xx,yy,mc.SW)
										-- local nplot = Map.GetPlot(xxx,yyy)
										-- if nplot then
											-- nplot:SetWOfRiver(true,flowN)
										-- end
									-- end
									-- if WOfRiver and pplot:GetRiverEFlowDirection() == flowN then
										-- print(string.format("Adding spokes to river at (%d,%d)",xx,yy))
										-- pplot:SetNWOfRiver(true,flowNE)
										-- local xxx,yyy = elevationMap:GetNeighbor(xx,yy,mc.E)
										-- local nplot = Map.GetPlot(xxx,yyy)
										-- if nplot then
											-- nplot:SetNEOfRiver(true,flowNW)
										-- end
									-- end
								-- elseif dir == mc.NE then
									-- local nplot = Map.GetPlot(elevationMap:GetNeighbor(xx,yy,mc.W))
									-- if nplot and nplot:GetRiverEFlowDirection() ~= flowN then
										-- pplot:SetNEOfRiver(false,flowNone)
									-- end
									-- if NWOfRiver and pplot:GetRiverSEFlowDirection() == flowNE then
										-- print(string.format("Adding spokes to river at (%d,%d)",xx,yy))
										-- pplot:SetNEOfRiver(true,flowSE)
										-- plot:SetWOfRiver(true,flowN)
									-- end
								-- elseif dir == mc.E then
									-- if NEOfRiver and pplot:GetRiverSWFlowDirection() == flowSE then
										-- print(string.format("Adding spokes to river at (%d,%d)",xx,yy))
										-- plot:SetWOfRiver(true,flowS)
										-- plot:SetNWOfRiver(true,flowNE)
									-- end
								-- elseif dir == mc.SW then
									-- if WOfRiver and pplot:GetRiverEFlowDirection() == flowS then
										-- print(string.format("Adding spokes to river at (%d,%d)",xx,yy))
										-- plot:SetNWOfRiver(true,flowSW)
										-- plot:SetNEOfRiver(true,flowSE)
									-- end
								-- end
							-- end
						-- end
					-- end
				end
			end
			k=k+1
		end
		iters = iters+1
		if iters > 499 then
			print(string.format("Could not meet lake quota after %d iterations. - Planet Simulator",iters))
			break
		end
	end

	if numLakes > 0 then
		print(string.format("Added %d lakes. - Planet Simulator",numLakes))
		Map.CalculateAreas();
	end
end
------------------------------------------------------------------------------
function Cleanup()
	--now we fix things up so that the border of tundra and ice regions are hills
	--this looks a bit more believable. Also keep desert away from tundra and ice
	--by turning it into plains

	--Moved this entire section because some of the calls require features and rivers
	--to be placed in order for them to work properly.
	--Got rid of the Hills bit because I like flat Snow/Tundra. Also added
	--a few terrain matching sections - Bobert13
	local W, H = Map.GetGridSize();
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
	local terrainPlains	= GameInfoTypes["TERRAIN_PLAINS"];
	local terrainSnow	= GameInfoTypes["TERRAIN_SNOW"];
	local terrainTundra	= GameInfoTypes["TERRAIN_TUNDRA"];
	local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"];
	local featureIce = FeatureTypes.FEATURE_ICE
	local featureOasis = FeatureTypes.FEATURE_OASIS
	local featureMarsh = FeatureTypes.FEATURE_MARSH
	local featureFloodPlains = FeatureTypes.FEATURE_FLOOD_PLAINS
	local featureForest = FeatureTypes.FEATURE_FOREST
	local nofeature = FeatureTypes.NO_FEATURE
	-- Gets rid of stray Snow tiles and replaces them with Tundra; also softens rivers in snow -Bobert13
	local k = 1
	for n=1,#snowTab do
		local i = snowTab[k]
		local x = i%W
		local y = (i-x)/W
		local plot = Map.GetPlotByIndex(i)
		if plot:IsRiver() then
			plot:SetTerrainType(terrainTundra, true, true)
			table.insert(tundraTab,i)
			table.remove(snowTab,k)
			k=k-1
		else
			local tiles = GetCircle(i,1)
			local snowCount = 0
			local grassCount = 0
			for n=1,#tiles do
				local ii = tiles[n]
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetTerrainType() == terrainGrass then
					grassCount = grassCount + 1
				elseif nPlot:GetTerrainType() == terrainSnow then
					snowCount = snowCount + 1
				end
			end
			if snowCount == 1 or grassCount == 2 or (elevationMap:GetLatitudeForY(y) < (mc.iceNorthLatitudeLimit - H/5) and elevationMap:GetLatitudeForY(y) > (mc.iceSouthLatitudeLimit + H/5)) then
				plot:SetTerrainType(terrainTundra,true,true)
				table.insert(tundraTab,i)
				table.remove(snowTab,k)
				k=k-1
			elseif grassCount >= 3 then
				plot:SetTerrainType(terrainPlains,true,true)
				table.insert(plainsTab,i)
				table.remove(snowTab,k)
				k=k-1
			end
		end
		k=k+1
	end
    -- Replaces stray Grass tiles -Bobert13
	k=1
	for n=1,#grassTab do
		local i = grassTab[k]
		local plot = Map.GetPlotByIndex(i)
		local tiles = GetCircle(i,1)
		local snowCount = 0
		local desertCount = 0
		local grassCount = 0
		for n=1,#tiles do
			local ii = tiles[n]
			local nPlot = Map.GetPlotByIndex(ii)
			if nPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
				if nPlot:GetTerrainType() == terrainGrass then
					grassCount = grassCount + 1
				elseif nPlot:GetTerrainType() == terrainDesert then
					desertCount = desertCount + 1
				elseif nPlot:GetTerrainType() == terrainSnow or nPlot:GetTerrainType() == terrainTundra  then
					snowCount = snowCount + 1
				end
			end
		end
		if desertCount >= 3 then
			plot:SetTerrainType(terrainDesert,true,true)
			table.insert(desertTab,i)
			table.remove(grassTab,k)
			if plot:GetFeatureType() ~= nofeature then
				plot:SetFeatureType(nofeature,-1)
			end
			k=k-1
		elseif snowCount >= 3 then
			plot:SetTerrainType(terrainPlains,true,true)
			table.insert(plainsTab,i)
			table.remove(grassTab,k)
			k=k-1
		elseif grassCount == 0 then
			if desertCount >= 2 then
				plot:SetTerrainType(terrainDesert,true,true)
				table.insert(desertTab,i)
				table.remove(grassTab,k)
				if plot:GetFeatureType() ~= nofeature then
					plot:SetFeatureType(nofeature,-1)
				end
				k=k-1
			elseif snowCount >= 2 then
				plot:SetTerrainType(terrainPlains,true,true)
				table.insert(plainsTab,i)
				table.remove(grassTab,k)
				k=k-1
			end
		end
		k=k+1
	end
	--Gets rid of strips of plains in the middle of deserts. -Bobert 13
	k = 1
	for n=1,#plainsTab do
		local i = plainsTab[k]
		local plot = Map.GetPlotByIndex(i)
		local tiles = GetCircle(i,1)
		local desertCount = 0
		local grassCount = 0
		for n=1,#tiles do
			local ii = tiles[n]
			local nPlot = Map.GetPlotByIndex(ii)
			if nPlot:GetTerrainType() == terrainGrass then
				grassCount = grassCount + 1
			elseif nPlot:GetTerrainType() == terrainDesert then
				desertCount = desertCount + 1
			end
		end
        if i == 365 then
            local x = i%W
            local y = (i-x)/W
            print(string.format("desertCount for plot (%d, %d) is %d", y, x, desertCount))
        end
		if desertCount >= 3 and grassCount == 0 then
			plot:SetTerrainType(terrainDesert,true,true)
			table.insert(desertTab,i)
			table.remove(plainsTab,k)
			if plot:GetFeatureType() ~= nofeature then
				plot:SetFeatureType(nofeature,-1)
			end
			k=k-1
		end
		k=k+1
	end
	--Replaces stray Desert tiles with Plains or Grasslands. -Bobert13
	k=1
	for n=1,#desertTab do
		local i = desertTab[k]
		local plot = Map.GetPlotByIndex(i)
		local tiles = GetCircle(i,1)
		local snowCount = 0
		local desertCount = 0
		local grassCount = 0
		for n=1,#tiles do
			local ii = tiles[n]
			local nPlot = Map.GetPlotByIndex(ii)
			if nPlot:GetTerrainType() == terrainGrass then
				grassCount = grassCount + 1
			elseif nPlot:GetTerrainType() == terrainDesert then
				desertCount = desertCount + 1
			elseif nPlot:GetTerrainType() == terrainSnow or nPlot:GetTerrainType() == terrainTundra  then
				snowCount = snowCount + 1
			end
		end
		if snowCount ~= 0 then
			plot:SetTerrainType(terrainPlains,true,true)
			table.insert(plainsTab,i)
			table.remove(desertTab,k)
			k=k-1
		elseif desertCount < 2 then
			if grassCount >= 4 then
				plot:SetTerrainType(terrainGrass,true,true)
				table.insert(grassTab,i)
				table.remove(desertTab,k)
				k=k-1
			elseif grassCount == 2 or grassCount == 3 or desertCount == 0 then
				plot:SetTerrainType(terrainPlains,true,true)
				table.insert(plainsTab,i)
				table.remove(desertTab,k)
				k=k-1
			end
		end
		k=k+1
	end
	--Places marshes at river Deltas and in wet lowlands.
	local marshThreshold = elevationMap:FindThresholdFromPercent(mc.marshElevation,false,true)
	for k = 1, #landTab do
		local i = landTab[k]
		local plot = Map.GetPlotByIndex(i)
		if not plot:IsMountain() then
			if temperatureMap.data[i] > mc.treesMinTemperature then
				if plot:IsCoastalLand() then
					if plot:IsRiver() then
						if plot:GetTerrainType() ~= terrainDesert then
							local roll = PWRandInt(1,3)
							if roll == 1 then
								plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
								plot:SetTerrainType(terrainGrass, true, true)
								plot:SetFeatureType(featureMarsh,-1)
							end
						end
					end
				end
				if DiffMap.data[i] < marshThreshold then
					local tiles = GetCircle(i,1)
					local marsh = true
					for n=1,#tiles do
						local ii = tiles[n]
						local nPlot = Map.GetPlotByIndex(ii)
						if nPlot:GetTerrainType() == terrainDesert then
							if nPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN then
								marsh = false
							end
						end
					end
					if marsh then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
						plot:SetTerrainType(terrainGrass, true, true)
						plot:SetFeatureType(featureMarsh,-1)
					end
				end
			end
			if plot:CanHaveFeature(featureFloodPlains) then
				plot:SetFeatureType(featureFloodPlains,-1)
			end
		end
	end
    -- fills in gaps in Forests
    for k = 1, #landTab do
        local i = landTab[k]
		local plot = Map.GetPlotByIndex(i)
		if not plot:IsMountain() then
            if plot:GetFeatureType() == nofeature then
                if temperatureMap.data[i] > mc.treesMinTemperature then
                    local tiles = GetCircle(i,1)
					local forestCount = 0
					for n=1,#tiles do
						local ii = tiles[n]
						local nPlot = Map.GetPlotByIndex(ii)
						if nPlot:GetFeatureType() == featureForest then
                            forestCount = forestCount + 1
						end
					end
					if forestCount > 3 and PWRandInt(1,2) < 2 then
						plot:SetFeatureType(featureForest,-1)
					end
                end
            end
        end
    end
end
------------------------------------------------------------------------------
function AddFeatures()
	print("Adding Features - Planet Simulator");

	local terrainPlains	= GameInfoTypes["TERRAIN_PLAINS"]
	local featureFloodPlains = FeatureTypes.FEATURE_FLOOD_PLAINS
	local featureIce = FeatureTypes.FEATURE_ICE
	local featureJungle = FeatureTypes.FEATURE_JUNGLE
	local featureForest = FeatureTypes.FEATURE_FOREST
	local featureOasis = FeatureTypes.FEATURE_OASIS
	local featureMarsh = FeatureTypes.FEATURE_MARSH
	local terrainSnow	= GameInfoTypes["TERRAIN_SNOW"];
	-- Edit by TowerTipping
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
	-- /TowerTipping
	local W, H = Map.GetGridSize()
	local WH = W*H

	local zeroTreesThreshold = rainfallMap:FindThresholdFromPercent(mc.zeroTreesPercent,false,true)
	local jungleThreshold = rainfallMap:FindThresholdFromPercent(mc.junglePercent,false,true)
	for k = 1,#landTab do
		local i = landTab[k]
		local plot = Map.GetPlotByIndex(i)
        local x = i%W
        local y = (i-x)/W
		-- if rainfallMap.data[i] < jungleThreshold then
			-- if not plot:IsMountain() then
				-- local treeRange = jungleThreshold - zeroTreesThreshold
				-- if rainfallMap.data[i] > PWRand() * treeRange + zeroTreesThreshold then
					-- if temperatureMap.data[i] > mc.treesMinTemperature then
						-- plot:SetFeatureType(featureForest,-1)
					-- end
				-- end
			-- end
		if rainfallMap.data[i] < jungleThreshold then
			if not plot:IsMountain() then
                -- local treeRange = jungleThreshold - zeroTreesThreshold
                local treeModifier = (math.abs(mc.topLatitude/rainfallMap:GetLatitudeForY(y))/mc.topLatitude)^1/2
                -- if rainfallMap.data[i] > PWRand() * treeRange + zeroTreesThreshold then
                if rainfallMap.data[i] > zeroTreesThreshold  + (treeModifier - 0.025) then
                    if temperatureMap.data[i] > mc.treesMinTemperature then
                        local tiles = GetCircle(i, 1)
                        local forest = true
                        for n = 1, #tiles do
                            local ii = tiles[n]
                            local nPlot = Map.GetPlotByIndex(ii)
							-- Edit by TowerTipping
                            -- if nPlot:GetTerrainType() == terrainSnow then
								-- forest = false
								-- break
							-- end
							local terrainType = nPlot:GetTerrainType()
							if terrainType == terrainSnow then
                                forest = false
                                break
							elseif terrainType == terrainDesert then
								forest = false
								break
                            end
							-- /TowerTipping
                        end
                        if forest == true then
                            plot:SetFeatureType(featureForest,-1)
                        end
                    end
                end
			end
		else
			if not plot:IsMountain() then
				if temperatureMap.data[i] < mc.jungleMinTemperature and temperatureMap.data[i] > mc.treesMinTemperature then
					plot:SetFeatureType(featureForest,-1)
				elseif temperatureMap.data[i] >= mc.jungleMinTemperature then
					-- Edit by TowerTipping
					-- local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
					-- /TowerTipping
					local tiles = GetCircle(i,1)
					local desertCount = 0
					for n=1,#tiles do
						local ii = tiles[n]
						local nPlot = Map.GetPlotByIndex(ii)
						if nPlot:GetTerrainType() == terrainDesert then
							desertCount = desertCount + 1
						end
					end
					if desertCount < 4 then
						local roll = PWRandInt(1,100)
						if roll > 4 then
							plot:SetFeatureType(featureJungle,-1)
							plot:SetTerrainType(terrainPlains,false,true)
						else
							plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
							plot:SetFeatureType(featureMarsh,-1)
						end
					end
				end
			end
		end
	end
	for i=0,WH-1,1 do
		local plot = Map.GetPlotByIndex(i)
		if plot:IsWater() then
			PlacePossibleAtoll(i)
			PlacePossibleIce(i,W)
		end
	end
	Cleanup()
	Map.RecalculateAreas()
	PlacePossibleOasis()
end
-------------------------------------------------------------------------------------------
function AddRivers()
	print("Adding Rivers. - Planet Simulator")
	local gridWidth, gridHeight = Map.GetGridSize();
	for y = 0, gridHeight - 1,1 do
		for x = 0,gridWidth - 1,1 do
			local plot = Map.GetPlot(x,y)

			local WOfRiver, NWOfRiver, NEOfRiver = riverMap:GetFlowDirections(x,y)

			if WOfRiver == FlowDirectionTypes.NO_FLOWDIRECTION then
				plot:SetWOfRiver(false,WOfRiver)
			else
				local xx,yy = elevationMap:GetNeighbor(x,y,mc.E)
				local nPlot = Map.GetPlot(xx,yy)
				if plot:IsMountain() and nPlot:IsMountain() then
					plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
				end
				plot:SetWOfRiver(true,WOfRiver)
				--print(string.format("(%d,%d)WOfRiver = true dir=%d",x,y,WOfRiver))
			end

			if NWOfRiver == FlowDirectionTypes.NO_FLOWDIRECTION then
				plot:SetNWOfRiver(false,NWOfRiver)
			else
				local xx,yy = elevationMap:GetNeighbor(x,y,mc.SE)
				local nPlot = Map.GetPlot(xx,yy)
				if plot:IsMountain() and nPlot:IsMountain() then
					plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
				end
				plot:SetNWOfRiver(true,NWOfRiver)
				--print(string.format("(%d,%d)NWOfRiver = true dir=%d",x,y,NWOfRiver))
			end

			if NEOfRiver == FlowDirectionTypes.NO_FLOWDIRECTION then
				plot:SetNEOfRiver(false,NEOfRiver)
			else
				local xx,yy = elevationMap:GetNeighbor(x,y,mc.SW)
				local nPlot = Map.GetPlot(xx,yy)
				if plot:IsMountain() and nPlot:IsMountain() then
					plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
				end
				plot:SetNEOfRiver(true,NEOfRiver)
				--print(string.format("(%d,%d)NEOfRiver = true dir=%d",x,y,NEOfRiver))
			end
		end
	end
end
-------------------------------------------------------------------------------------------
function StartPlotSystem()
	-- Get Resources setting input by user.
	local res = Map.GetCustomOption(5)
	if res == 6 then
		res = 1 + Map.Rand(3, "Random Resources Option - Lua");
	end

	local starts = Map.GetCustomOption(7)
	local divMethod = nil
	if starts == 1 then
		divMethod = 2
	else
		divMethod = 1
	end

	print("Creating start plot database.");
	local start_plot_database = AssignStartingPlots.Create()

	print("Dividing the map in to Regions.");
	-- Regional Division Method 2: Continental or 1:Terra
	local args = {
		method = divMethod,
		resources = res,
		};
	start_plot_database:GenerateRegions(args)

	print("Choosing start locations for civilizations.");
	start_plot_database:ChooseLocations()

	print("Normalizing start locations and assigning them to Players.");
	start_plot_database:BalanceAndAssign()

	print("Placing Natural Wonders.");
    if YieldTypes.YIELD_FAITH then
        --print("Expansion detected; using modified NW placement.")
        PlaceNaturalWonders = PlaceNaturalWondersMOD
    -- else
        --print("No expansion detected; using vanilla NW placement.")
    end
    start_plot_database:PlaceNaturalWonders()

	print("Placing Resources and City States.");
	start_plot_database:PlaceResourcesAndCityStates()
	
	print("Finished StartPlotSystem()")
end
-------------------------------------------------------------------------------------------
function oceanMatch(x,y)
	local plot = Map.GetPlot(x,y)
	if plot:GetPlotType() == PlotTypes.PLOT_OCEAN then
		return true
	end
	return false
end
-------------------------------------------------------------------------------------------
-- function jungleMatch(x,y)
	-- local terrainGrass	= GameInfoTypes["TERRAIN_GRASS"];
	-- local plot = Map.GetPlot(x,y)
	-- if plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
		-- return true
	-- --include any mountains on the border as part of the desert.
	-- elseif (plot:GetFeatureType() == FeatureTypes.FEATURE_MARSH or plot:GetFeatureType() == FeatureTypes.FEATURE_FOREST) and plot:GetTerrainType() == terrainGrass then
		-- local nList = elevationMap:GetRadiusAroundHex(x,y,1,W)
		-- for n=1,#nList do
			-- local ii = nList[n]
			-- if 11 ~= -1 then
				-- local nPlot = Map.GetPlotByIndex(ii)
				-- if nPlot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
					-- return true
				-- end
			-- end
		-- end
	-- end
	-- return false
-- end
-------------------------------------------------------------------------------------------
function desertMatch(i)
	local W,H = Map.GetGridSize();
	local terrainDesert	= GameInfoTypes["TERRAIN_DESERT"];
	local plot = Map.GetPlotByIndex(i)
	if plot:GetTerrainType() == terrainDesert then
		return true
	--include any mountains on the border as part of the desert.
	elseif plot:GetPlotType() == PlotTypes.PLOT_MOUNTAIN then
		local nList = GetCircle(i,1)
		for n=1,#nList do
			local ii = nList[n]
			if 11 ~= -1 then
				local nPlot = Map.GetPlotByIndex(ii)
				if nPlot:GetPlotType() ~= PlotTypes.PLOT_MOUNTAIN and nPlot:GetTerrainType() == terrainDesert then
					return true
				end
			end
		end
	end
	return false
end
-------------------------------------------------------------------------------------------
function DetermineContinents()
	print("Determining continents for art purposes - Planet Simulator")
	-- Each plot has a continent art type. Mixing and matching these could look
	-- extremely bad, but there is nothing technical to prevent it. The worst
	-- that will happen is that it can't find a blend and draws red checkerboards.

	-- Command for setting the art type for a plot is: <plot object>:SetContinentArtType(<art_set_number>)

	-- CONTINENTAL ART SETS
	-- 0) Ocean
	-- 1) America
	-- 2) Asia
	-- 3) Africa
	-- 4) Europe

	-- Here is an example that sets all land in the world to use the European art set.

--~ 	for i, plot in Plots() do
--~ 		if plot:IsWater() then
--~ 			plot:SetContinentArtType(0)
--~ 		else
--~ 			plot:SetContinentArtType(4)
--~ 		end
--~ 	end

	-- local continentMap = PWAreaMap:New(elevationMap.width,elevationMap.height,elevationMap.wrapX,elevationMap.wrapY)
	-- continentMap:DefineAreas(oceanMatch)
	-- table.sort(continentMap.areaList,function (a,b) return a.size > b.size end)

	-- --check for jungle
	-- for y=0,elevationMap.height - 1,1 do
		-- for x=0,elevationMap.width - 1,1 do
			-- local i = elevationMap:GetIndex(x,y)
			-- local area = continentMap:GetAreaByID(continentMap.data[i])
			-- area.hasJungle = false
		-- end
	-- end
	-- for y=0,elevationMap.height - 1,1 do
		-- for x=0,elevationMap.width - 1,1 do
			-- local plot = Map.GetPlot(x,y)
			-- if plot:GetFeatureType() == FeatureTypes.FEATURE_JUNGLE then
				-- local i = elevationMap:GetIndex(x,y)
				-- local area = continentMap:GetAreaByID(continentMap.data[i])
				-- area.hasJungle = true
			-- end
		-- end
	-- end
	-- local firstArtStyle = PWRandInt(1,3)
	-- print(string.format("firstArtStyle = %d",firstArtStyle))
	-- for n=1,#continentMap.areaList do
		-- --print(string.format("area[%d] size = %d",n,desertMap.areaList[n].size))
		-- --if not continentMap.areaList[n].trueMatch and not continentMap.areaList[n].hasJungle then
		-- if not continentMap.areaList[n].trueMatch then
			-- continentMap.areaList[n].artStyle = (firstArtStyle % 4) + 1
			-- --print(string.format("area[%d] size = %d, artStyle = %d",n,continentMap.areaList[n].size,continentMap.areaList[n].artStyle))
			-- firstArtStyle = firstArtStyle + 1
		-- end
	-- end
	-- for y=0,elevationMap.height - 1,1 do
		-- for x=0,elevationMap.width - 1,1 do
			-- local plot = Map.GetPlot(x,y)
			-- local i = elevationMap:GetIndex(x,y)
			-- local area = continentMap:GetAreaByID(continentMap.data[i])
			-- local artStyle = area.artStyle
			-- if plot:IsWater() then
				-- plot:SetContinentArtType(0)
			-- -- elseif jungleMatch(x,y) then
				-- -- plot:SetContinentArtType(4)
			-- else
				-- plot:SetContinentArtType(artStyle)
			-- end
		-- end
	-- end
	-- -- Africa has the best looking deserts, so for the biggest
	-- -- desert use Africa. America has a nice dirty looking desert also, so
	-- -- that should be the second biggest desert.
	-- local desertMap = PWAreaMap:New(elevationMap.width,elevationMap.height,elevationMap.wrapX,elevationMap.wrapY)
	-- desertMap:DefineAreas(desertMatch)
	-- table.sort(desertMap.areaList,function (a,b) return a.size > b.size end)
	-- local largestDesertID = nil
	-- local secondLargestDesertID = nil
	-- for n=1,#desertMap.areaList do
		-- --print(string.format("area[%d] size = %d",n,desertMap.areaList[n].size))
		-- if desertMap.areaList[n].trueMatch then
			-- if largestDesertID == nil then
				-- largestDesertID = desertMap.areaList[n].id
			-- else
				-- secondLargestDesertID = desertMap.areaList[n].id
				-- break
			-- end
		-- end
	-- end
	-- for y=0,elevationMap.height - 1,1 do
		-- for x=0,elevationMap.width - 1,1 do
			-- local plot = Map.GetPlot(x,y)
			-- local i = elevationMap:GetIndex(x,y)
			-- if desertMap.data[i] == largestDesertID then
				-- plot:SetContinentArtType(3)
			-- elseif desertMap.data[i] == secondLargestDesertID then
				-- plot:SetContinentArtType(1)
			-- end
		-- end
	-- end
	Map.DefaultContinentStamper();
	-- continentMap:Save4("continentMap.csv")
	print(string.format("Generated map in %.3f seconds.", os.clock() - Time))
end

------------------------------------------------------------------------------

--~ mc = MapConstants:New()
--~ PWRandSeed()

--~ elevationMap = GenerateElevationMap(100,70,true,false)
--~ FillInLakes()
--~ elevationMap:Save("elevationMap.csv")

--~ rainfallMap, temperatureMap = GenerateRainfallMap(elevationMap)
--~ temperatureMap:Save("temperatureMap.csv")
--~ rainfallMap:Save("rainfallMap.csv")

--~ riverMap = RiverMap:New(elevationMap)
--~ riverMap:SetJunctionAltitudes()
--~ riverMap:SiltifyLakes()
--~ riverMap:SetFlowDestinations()
--~ riverMap:SetRiverSizes(rainfallMap)

function AssignStartingPlots:CanBeThisNaturalWonderType(x, y, wn, rn)
    -- Forces certain wonders to always fail this check.
    for i = 1, #mc.banNWs do
        if wn == mc.banNWs[i] then
            return
        end
    end

	-- Checks a candidate plot for eligibility to host the supplied wonder type.
	-- "rn" = the row number for this wonder type within the xml Placement data table.
	local plot = Map.GetPlot(x, y);
	-- Use Custom Eligibility method if indicated.
	if self.EligibilityMethodNumber[wn] ~= -1 then
		local method_number = self.EligibilityMethodNumber[wn];
		if NWCustomEligibility(x, y, method_number) == true then
			local iW, iH = Map.GetGridSize();
			local plotIndex = y * iW + x + 1;
			table.insert(self.eligibility_lists[wn], plotIndex);
		end
		return
	end
	-- Run root checks.
	if self.bWorldHasOceans == true then -- Check to see if this wonder requires or avoids the biggest landmass.
		if self.RequireBiggestLandmass[wn] == true then
			local iAreaID = plot:GetArea();
			if iAreaID ~= self.iBiggestLandmassID then
				return
			end
		elseif self.AvoidBiggestLandmass[wn] == true then
			local iAreaID = plot:GetArea();
			if iAreaID == self.iBiggestLandmassID then
				return
			end
		end
	end
	if self.RequireFreshWater[wn] == true then
		if plot:IsFreshWater() == false then
			return
		end
	elseif self.AvoidFreshWater[wn] == true then
		if plot:IsRiver() or plot:IsLake() or plot:IsFreshWater() then
			return
		end
	end
	-- Land or Sea
	if self.LandBased[wn] == true then
		if plot:IsWater() == true then
			return
		end
		local iW, iH = Map.GetGridSize();
		local plotIndex = y * iW + x + 1;
		if self.RequireLandAdjacentToOcean[wn] == true then
			if self.plotDataIsCoastal[plotIndex] == false then
				return
			end
		elseif self.AvoidLandAdjacentToOcean[wn] == true then
			if self.plotDataIsCoastal[plotIndex] == true then
				return
			end
		end
		if self.RequireLandOnePlotInland[wn] == true then
			if self.plotDataIsNextToCoast[plotIndex] == false then
				return
			end
		elseif self.AvoidLandOnePlotInland[wn] == true then
			if self.plotDataIsNextToCoast[plotIndex] == true then
				return
			end
		end
		if self.RequireLandTwoOrMorePlotsInland[wn] == true then
			if self.plotDataIsCoastal[plotIndex] == true then
				return
			elseif self.plotDataIsNextToCoast[plotIndex] == true then
				return
			end
		elseif self.AvoidLandTwoOrMorePlotsInland[wn] == true then
			if self.plotDataIsCoastal[plotIndex] == false and self.plotDataIsNextToCoast[plotIndex] == false then
				return
			end
		end
	end
	-- Core Tile
	if self.CoreTileCanBeAnyPlotType[wn] == false then
		local plotType = plot:GetPlotType()
		if plotType == PlotTypes.PLOT_LAND and self.CoreTileCanBeFlatland[wn] == true then
			-- Continue
		elseif plotType == PlotTypes.PLOT_HILLS and self.CoreTileCanBeHills[wn] == true then
			-- Continue
		elseif plotType == PlotTypes.PLOT_MOUNTAIN and self.CoreTileCanBeMountain[wn] == true then
			-- Continue
		elseif plotType == PlotTypes.PLOT_OCEAN and self.CoreTileCanBeOcean[wn] == true then
			-- Continue
		else -- Plot type does not match an eligible type, reject this plot.
			return
		end
	end
	if self.CoreTileCanBeAnyTerrainType[wn] == false then
		local terrainType = plot:GetTerrainType()
		if terrainType == TerrainTypes.TERRAIN_GRASS and self.CoreTileCanBeGrass[wn] == true then
			-- Continue
		elseif terrainType == TerrainTypes.TERRAIN_PLAINS and self.CoreTileCanBePlains[wn] == true then
			-- Continue
		elseif terrainType == TerrainTypes.TERRAIN_DESERT and self.CoreTileCanBeDesert[wn] == true then
			-- Continue
		elseif terrainType == TerrainTypes.TERRAIN_TUNDRA and self.CoreTileCanBeTundra[wn] == true then
			-- Continue
		elseif terrainType == TerrainTypes.TERRAIN_SNOW and self.CoreTileCanBeSnow[wn] == true then
			-- Continue
		elseif terrainType == TerrainTypes.TERRAIN_COAST and self.CoreTileCanBeShallowWater[wn] == true then
			-- Continue
		elseif terrainType == TerrainTypes.TERRAIN_OCEAN and self.CoreTileCanBeDeepWater[wn] == true then
			-- Continue
		else -- Terrain type does not match an eligible type, reject this plot.
			return
		end
	end
	if self.CoreTileCanBeAnyFeatureType[wn] == false then
		local featureType = plot:GetFeatureType()
		if featureType == FeatureTypes.NO_FEATURE and self.CoreTileCanBeNoFeature[wn] == true then
			-- Continue
		elseif featureType == FeatureTypes.FEATURE_FOREST and self.CoreTileCanBeForest[wn] == true then
			-- Continue
		elseif featureType == FeatureTypes.FEATURE_JUNGLE and self.CoreTileCanBeJungle[wn] == true then
			-- Continue
		elseif featureType == FeatureTypes.FEATURE_OASIS and self.CoreTileCanBeOasis[wn] == true then
			-- Continue
		elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS and self.CoreTileCanBeFloodPlains[wn] == true then
			-- Continue
		elseif featureType == FeatureTypes.FEATURE_MARSH and self.CoreTileCanBeMarsh[wn] == true then
			-- Continue
		elseif featureType == FeatureTypes.FEATURE_ICE and self.CoreTileCanBeIce[wn] == true then
			-- Continue
		elseif featureType == self.feature_atoll and self.CoreTileCanBeAtoll[wn] == true then
			-- Continue
		else -- Feature type does not match an eligible type, reject this plot.
			return
		end
	end
	-- Adjacent Tiles: Plot Types
	if self.AdjacentTilesCareAboutPlotTypes[wn] == true then
		local iNumAnyLand, iNumFlatland, iNumHills, iNumMountain, iNumHillsPlusMountains, iNumOcean = 0, 0, 0, 0, 0, 0;
		for loop, direction in ipairs(self.direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			local plotType = adjPlot:GetPlotType();
			if plotType == PlotTypes.PLOT_OCEAN then
				iNumOcean = iNumOcean + 1;
			else
				iNumAnyLand = iNumAnyLand + 1;
				if plotType == PlotTypes.PLOT_LAND then
					iNumFlatland = iNumFlatland + 1;
				else
					iNumHillsPlusMountains = iNumHillsPlusMountains + 1;
					if plotType == PlotTypes.PLOT_HILLS then
						iNumHills = iNumHills + 1;
					else
						iNumMountain = iNumMountain + 1;
					end
				end
			end
		end
		if iNumAnyLand > 0 and self.AdjacentTilesAvoidAnyland[wn] == true then
			return
		end
		-- Require
		if self.AdjacentTilesRequireFlatland[wn] == true then
			if iNumFlatland < self.RequiredNumberOfAdjacentFlatland[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireHills[wn] == true then
			if iNumHills < self.RequiredNumberOfAdjacentHills[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireMountain[wn] == true then
			if iNumMountain < self.RequiredNumberOfAdjacentMountain[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireHillsPlusMountains[wn] == true then
			if iNumHillsPlusMountains < self.RequiredNumberOfAdjacentHillsPlusMountains[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireOcean[wn] == true then
			if iNumOcean < self.RequiredNumberOfAdjacentOcean[wn] then
				return
			end
		end
		-- Avoid
		if self.AdjacentTilesAvoidFlatland[wn] == true then
			if iNumFlatland > self.MaximumAllowedAdjacentFlatland[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidHills[wn] == true then
			if iNumHills > self.MaximumAllowedAdjacentHills[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidMountain[wn] == true then
			if iNumMountain > self.MaximumAllowedAdjacentMountain[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidHillsPlusMountains[wn] == true then
			if iNumHillsPlusMountains > self.MaximumAllowedAdjacentHillsPlusMountains[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidOcean[wn] == true then
			if iNumOcean > self.MaximumAllowedAdjacentOcean[wn] then
				return
			end
		end
	end
	-- Adjacent Tiles: Terrain Types
	if self.AdjacentTilesCareAboutTerrainTypes[wn] == true then
		local iNumGrass, iNumPlains, iNumDesert, iNumTundra, iNumSnow, iNumShallowWater, iNumDeepWater = 0, 0, 0, 0, 0, 0, 0;
		for loop, direction in ipairs(self.direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			local terrainType = adjPlot:GetTerrainType();
			if terrainType == TerrainTypes.TERRAIN_GRASS then
				iNumGrass = iNumGrass + 1;
			elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
				iNumPlains = iNumPlains + 1;
			elseif terrainType == TerrainTypes.TERRAIN_DESERT then
				iNumDesert = iNumDesert + 1;
			elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
				iNumTundra = iNumTundra + 1;
			elseif terrainType == TerrainTypes.TERRAIN_SNOW then
				iNumSnow = iNumSnow + 1;
			elseif terrainType == TerrainTypes.TERRAIN_COAST then
				iNumShallowWater = iNumShallowWater + 1;
			elseif terrainType == TerrainTypes.TERRAIN_OCEAN then
				iNumDeepWater = iNumDeepWater + 1;
			end
		end
		-- Require
		if self.AdjacentTilesRequireGrass[wn] == true then
			if iNumGrass < self.RequiredNumberOfAdjacentGrass[wn] then
				return
			end
		end
		if self.AdjacentTilesRequirePlains[wn] == true then
			if iNumPlains < self.RequiredNumberOfAdjacentPlains[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireDesert[wn] == true then
			if iNumDesert < self.RequiredNumberOfAdjacentDesert[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireTundra[wn] == true then
			if iNumTundra < self.RequiredNumberOfAdjacentTundra[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireSnow[wn] == true then
			if iNumSnow < self.RequiredNumberOfAdjacentSnow[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireShallowWater[wn] == true then
			if iNumShallowWater < self.RequiredNumberOfAdjacentShallowWater[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireGrass[wn] == true then
			if iNumDeepWater < self.RequiredNumberOfAdjacentDeepWater[wn] then
				return
			end
		end
		-- Avoid
		if self.AdjacentTilesAvoidGrass[wn] == true then
			if iNumGrass > self.MaximumAllowedAdjacentGrass[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidPlains[wn] == true then
			if iNumPlains > self.MaximumAllowedAdjacentPlains[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidDesert[wn] == true then
			if iNumDesert > self.MaximumAllowedAdjacentDesert[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidTundra[wn] == true then
			if iNumTundra > self.MaximumAllowedAdjacentTundra[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidSnow[wn] == true then
			if iNumSnow > self.MaximumAllowedAdjacentSnow[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidShallowWater[wn] == true then
			if iNumShallowWater > self.MaximumAllowedAdjacentShallowWater[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidDeepWater[wn] == true then
			if iNumDeepWater > self.MaximumAllowedAdjacentDeepWater[wn] then
				return
			end
		end
	end
	-- Adjacent Tiles: Feature Types
	if self.AdjacentTilesCareAboutFeatureTypes[wn] == true then
		local iNumNoFeature, iNumForest, iNumJungle, iNumOasis, iNumFloodPlains, iNumMarsh, iNumIce, iNumAtoll = 0, 0, 0, 0, 0, 0, 0, 0;
		for loop, direction in ipairs(self.direction_types) do
			local adjPlot = Map.PlotDirection(x, y, direction)
			local featureType = adjPlot:GetFeatureType();
			if featureType == FeatureTypes.NO_FEATURE then
				iNumNoFeature = iNumNoFeature + 1;
			elseif featureType == FeatureTypes.FEATURE_FOREST then
				iNumForest = iNumForest + 1;
			elseif featureType == FeatureTypes.FEATURE_JUNGLE then
				iNumJungle = iNumJungle + 1;
			elseif featureType == FeatureTypes.FEATURE_OASIS then
				iNumOasis = iNumOasis + 1;
			elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
				iNumFloodPlains = iNumFloodPlains + 1;
			elseif featureType == FeatureTypes.FEATURE_MARSH then
				iNumMarsh = iNumMarsh + 1;
			elseif featureType == FeatureTypes.FEATURE_ICE then
				iNumIce = iNumIce + 1;
			elseif featureType == self.feature_atoll then
				iNumAtoll = iNumAtoll + 1;
			end
		end
		-- Require
		if self.AdjacentTilesRequireNoFeature[wn] == true then
			if iNumNoFeature < self.RequiredNumberOfAdjacentNoFeature[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireForest[wn] == true then
			if iNumForest < self.RequiredNumberOfAdjacentForest[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireJungle[wn] == true then
			if iNumJungle < self.RequiredNumberOfAdjacentJungle[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireOasis[wn] == true then
			if iNumOasis < self.RequiredNumberOfAdjacentOasis[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireFloodPlains[wn] == true then
			if iNumFloodPlains < self.RequiredNumberOfAdjacentFloodPlains[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireMarsh[wn] == true then
			if iNumMarsh < self.RequiredNumberOfAdjacentMarsh[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireIce[wn] == true then
			if iNumIce < self.RequiredNumberOfAdjacentIce[wn] then
				return
			end
		end
		if self.AdjacentTilesRequireAtoll[wn] == true then
			if iNumAtoll < self.RequiredNumberOfAdjacentAtoll[wn] then
				return
			end
		end
		-- Avoid
		if self.AdjacentTilesAvoidNoFeature[wn] == true then
			if iNumNoFeature > self.MaximumAllowedAdjacentNoFeature[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidForest[wn] == true then
			if iNumForest > self.MaximumAllowedAdjacentForest[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidJungle[wn] == true then
			if iNumJungle > self.MaximumAllowedAdjacentJungle[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidOasis[wn] == true then
			if iNumOasis > self.MaximumAllowedAdjacentOasis[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidFloodPlains[wn] == true then
			if iNumFloodPlains > self.MaximumAllowedAdjacentFloodPlains[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidMarsh[wn] == true then
			if iNumMarsh > self.MaximumAllowedAdjacentMarsh[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidIce[wn] == true then
			if iNumIce > self.MaximumAllowedAdjacentIce[wn] then
				return
			end
		end
		if self.AdjacentTilesAvoidAtoll[wn] == true then
			if iNumAtoll > self.MaximumAllowedAdjacentAtoll[wn] then
				return
			end
		end
	end

	-- This plot has survived all tests and is eligible to host this wonder type.
	local iW, iH = Map.GetGridSize();
	local plotIndex = y * iW + x + 1;
	table.insert(self.eligibility_lists[wn], plotIndex);
end
-------------------------------------------------------------------------------------------
function AssignStartingPlots:AttemptToPlaceNaturalWonderMOD(wonder_number, row_number)
	-- Attempts to place a specific natural wonder. The "wonder_number" is a Lua index while "row_number" is an XML index.
	local iW, iH = Map.GetGridSize();
	local feature_type_to_place;
	for thisFeature in GameInfo.Features() do
		if thisFeature.Type == self.wonder_list[wonder_number] then
			feature_type_to_place = thisFeature.ID;
			break
		end
	end
	local temp_table = self.eligibility_lists[wonder_number];
	local candidate_plot_list = GetShuffledCopyOfTable(temp_table)
	for loop, plotIndex in ipairs(candidate_plot_list) do
		if self.naturalWondersData[plotIndex] == 0 then -- No collision with civ start or other NW, so place wonder here!
			local x = (plotIndex - 1) % iW;
			local y = (plotIndex - x - 1) / iW;
			local plot = Map.GetPlot(x, y);
			-- If called for, force the local terrain to conform to what the wonder needs.
			local method_number = GameInfo.Natural_Wonder_Placement[row_number].TileChangesMethodNumber;
			if method_number ~= -1 then
				-- Custom method for tile changes needed by this wonder.
				NWCustomPlacement(x, y, row_number, method_number)
			else
				-- Check the XML data for any standard type tile changes, execute any that are indicated.
				if GameInfo.Natural_Wonder_Placement[row_number].ChangeCoreTileToMountain == true then
					if not plot:IsMountain() then
						plot:SetPlotType(PlotTypes.PLOT_MOUNTAIN, false, false);
					end
				elseif GameInfo.Natural_Wonder_Placement[row_number].ChangeCoreTileToFlatland == true then
					if plot:GetPlotType() ~= PlotTypes.PLOT_LAND then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, false);
					end
				end
				if GameInfo.Natural_Wonder_Placement[row_number].ChangeCoreTileTerrainToGrass == true then
					if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_GRASS then
						plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false);
					end
				elseif GameInfo.Natural_Wonder_Placement[row_number].ChangeCoreTileTerrainToPlains == true then
					if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_PLAINS then
						plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, false);
					end
				end
				if GameInfo.Natural_Wonder_Placement[row_number].SetAdjacentTilesToShallowWater == true then
					for loop, direction in ipairs(self.direction_types) do
						local adjPlot = Map.PlotDirection(x, y, direction)
						if adjPlot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST then
							adjPlot:SetTerrainType(TerrainTypes.TERRAIN_COAST, false, false)
						end
					end
				end
			end
			-- Now place this wonder and record the placement.
			plot:SetFeatureType(feature_type_to_place)
			table.insert(self.placed_natural_wonder, wonder_number);
            if wonder_number == 1 then
                Game.SetPlotExtraYield(x,y,YieldTypes.YIELD_CULTURE, 3)
            elseif wonder_number == 3 then
                Game.SetPlotExtraYield(x,y,YieldTypes.YIELD_FAITH, 3)
            elseif wonder_number == 6 then
                Game.SetPlotExtraYield(x,y,YieldTypes.YIELD_CULTURE, 3)
            end
			self:PlaceResourceImpact(x, y, 6, math.floor(iH / 5))	-- Natural Wonders layer
			self:PlaceResourceImpact(x, y, 1, 1)					-- Strategic layer
			self:PlaceResourceImpact(x, y, 2, 1)					-- Luxury layer
			self:PlaceResourceImpact(x, y, 3, 1)					-- Bonus layer
			self:PlaceResourceImpact(x, y, 5, 1)					-- City State layer
			self:PlaceResourceImpact(x, y, Round(iH / 11), 1)		-- Marble layer
			local plotIndex = y * iW + x + 1;
			self.playerCollisionData[plotIndex] = true;				-- Record exact plot of wonder in the collision list.
			--
			--print("- Placed ".. self.wonder_list[wonder_number].. " in Plot", x, y);
			--
			return true
		end
	end
	-- If reached here, this wonder was unable to be placed because all candidates are too close to an already-placed NW.
	return false
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceNaturalWondersMOD()
	print("DEBUG 1 for PlaceNaturalWondersMOD")	--TODO: Delete
	local NW_eligibility_order = self:GenerateNaturalWondersCandidatePlotLists()
	local iNumNWCandidates = table.maxn(NW_eligibility_order);
	if iNumNWCandidates == 0 then
		print("No Natural Wonders placed, no eligible sites found for any of them.");
		return
	end

	--[[ Debug printout
	print("-"); print("--- Readout of NW Assignment Priority ---");
	for print_loop, order in ipairs(NW_eligibility_order) do
		print("NW Assignment Priority#", print_loop, "goes to NW#", order);
	end
	print("-"); print("-"); ]]--

	-- Determine how many NWs to attempt to place. Target is regulated per map size.
	-- The final number cannot exceed the number the map has locations to support.
	local target_number = mc.NWTarget[Map.GetWorldSize()];
	local iNumNWtoPlace = math.min(target_number, iNumNWCandidates);
	local selected_NWs, fallback_NWs = {}, {};
	for loop, NW in ipairs(NW_eligibility_order) do
		if loop <= iNumNWtoPlace then
			table.insert(selected_NWs, NW);
		else
			table.insert(fallback_NWs, NW);
		end
	end

	--[[
	print("-");
	for loop, NW in ipairs(selected_NWs) do
		print("Natural Wonder #", NW, "has been selected for placement.");
	end
	print("-");
	for loop, NW in ipairs(fallback_NWs) do
		print("Natural Wonder #", NW, "has been selected as fallback.");
	end
	print("-");
	--
	print("--- Placing Natural Wonders! ---");
	]]--

	-- Place the NWs
	local iNumPlaced = 0;
	for loop, nw_number in ipairs(selected_NWs) do
		local nw_type = self.wonder_list[nw_number];
		-- Obtain the correct Row number from the xml Placement table.
		local row_number;
		for row in GameInfo.Natural_Wonder_Placement() do
			if row.NaturalWonderType == nw_type then
				row_number = row.ID;
			end
		end
		-- Place the wonder, using the correct row data from XML.
		local bSuccess = self:AttemptToPlaceNaturalWonderMOD(nw_number, row_number)
		if bSuccess then
			iNumPlaced = iNumPlaced + 1;
		end
	end
	if iNumPlaced < iNumNWtoPlace then
		for loop, nw_number in ipairs(fallback_NWs) do
			if iNumPlaced >= iNumNWtoPlace then
				break
			end
			local nw_type = self.wonder_list[nw_number];
			-- Obtain the correct Row number from the xml Placement table.
			local row_number;
			for row in GameInfo.Natural_Wonder_Placement() do
				if row.NaturalWonderType == nw_type then
					row_number = row.ID;
				end
			end
			-- Place the wonder, using the correct row data from XML.
			local bSuccess = self:AttemptToPlaceNaturalWonderMOD(nw_number, row_number)
			if bSuccess then
				iNumPlaced = iNumPlaced + 1;
			end
		end
	end

	--
	if iNumPlaced >= iNumNWtoPlace then
		print("-- Placed all Natural Wonders --"); print("-"); print("-");
	else
		print("-- Not all Natural Wonders targeted got placed --"); print("-"); print("-");
	end
	--

end
-------------------------------------------------------------------------------------------
function AssignStartingPlots:__CustomInit()
	-- This function included to provide a quick and easy override for changing 
	-- any initial settings. Add your customized version to the map script.
	--TODO: This function is empty in base CiV -- this is the setup for the Communitas ASP functions
	--[[
	if not debugPrint then
		print = function() end
	end
	--]]
	self.islandAreaBuffed = {}
	--Reassignment (TODO)
	self.MeasureStartPlacementFertilityOfPlot = AssignStartingPlots.MeasureStartPlacementFertilityOfPlotCOMM
	self.GenerateRegions = AssignStartingPlots.GenerateRegionsCOMM
	self.ExaminePlotForNaturalWondersEligibility = AssignStartingPlots.ExaminePlotForNaturalWondersEligibilityCOMM
	self.PlaceNaturalWonders = AssignStartingPlots.PlaceNaturalWondersCOMM
	self.CanPlaceCityStateAt = AssignStartingPlots.CanPlaceCityStateAtCOMM
	self.PlaceCityStateInRegion = AssignStartingPlots.PlaceCityStateInRegionCOMM
	self.BuffIslands = AssignStartingPlots.BuffIslandsCOMM
	self.AdjustTiles = AssignStartingPlots.AdjustTilesCOMM
	self.BuffDeserts = AssignStartingPlots.BuffDeserts
	self.ProcessResourceList = AssignStartingPlots.ProcessResourceListCOMM
	self.PlaceSpecificNumberOfResources = AssignStartingPlots.PlaceSpecificNumberOfResources
	self.GetMajorStrategicResourceQuantityValues = AssignStartingPlots.GetMajorStrategicResourceQuantityValuesCOMM
	self.GetSmallStrategicResourceQuantityValues = AssignStartingPlots.GetSmallStrategicResourceQuantityValuesCOMM
	self.PlaceOilInTheSea = AssignStartingPlots.PlaceOilInTheSeaCOMM
	self.PlaceStrategicAndBonusResources = AssignStartingPlots.PlaceStrategicAndBonusResourcesCOMM
	self.PlaceFish = AssignStartingPlots.PlaceFishCOMM
	self.PlacePossibleFish = AssignStartingPlots.PlacePossibleFish
	self.PlaceBonusResources = AssignStartingPlots.PlaceBonusResourcesCOMM
	self.PlaceResourcesAndCityStates = AssignStartingPlots.PlaceResourcesAndCityStatesCOMM
	self.NormalizeStartLocation = AssignStartingPlots.NormalizeStartLocationCOMM
	self.BalanceAndAssign = AssignStartingPlots.BalanceAndAssignCOMM
end	
------------------------------------------------------------------------------
function AssignStartingPlots:MeasureStartPlacementFertilityOfPlotCOMM(x, y, checkForCoastalLand)
	--TODO: The base CiV version of this is rather more elaborate; and Plot_GetFertility doesn't exist in base CiV, so check there
	return Plot_GetFertility(Map.GetPlot(x, y))
end
function Plot_GetFertility(plot, yieldID, ignoreStrategics)
	--TODO: This is rather different from the base civ version ... I kind of like this (Communitas) version.
	local basicYields = {	--TODO: Move to constants?
		YieldTypes.YIELD_FOOD,
		YieldTypes.YIELD_PRODUCTION,
		YieldTypes.YIELD_GOLD,
		YieldTypes.YIELD_SCIENCE,
		YieldTypes.YIELD_CULTURE,
		YieldTypes.YIELD_FAITH
	}
	
	if plot:IsImpassable() or plot:GetTerrainType() == TerrainTypes.TERRAIN_OCEAN then
		return 0
	end
	
	local value = 0
	local featureID = plot:GetFeatureType()
	local terrainID = plot:GetTerrainType()
	local resID = plot:GetResourceType()
	
	if yieldID then
		value = value + plot:CalculateYield(yieldID, true)
	else
		for _, yieldID in pairs(basicYields) do
			value = value + plot:CalculateYield(yieldID, true)
		end
	end
	
	if plot:IsFreshWater() then
		value = value + 0.25
	end
	
	if plot:IsLake() then
		-- can't improve lakes
		value = value - 1
	end
	
	if featureID == FeatureTypes.FEATURE_FOREST and terrainID ~= TerrainTypes.TERRAIN_TUNDRA then
		value = value + 0.5
	end
	
	if resID == -1 then
		if featureID == -1 and terrainID == TerrainTypes.TERRAIN_COAST then
			-- can't do much with these tiles in BNW
			value = value - 0.75
		end
	else
		local resInfo = GameInfo.Resources[resID]
		value = value + 4 * resInfo.Happiness
		if resInfo.ResourceClassType == "RESOURCECLASS_RUSH" and not ignoreStrategics then
			value = value + math.ceil(5 * math.sqrt(plot:GetNumResource()))
		elseif resInfo.ResourceClassType == "RESOURCECLASS_BONUS" then
			value = value + 2
		end
	end
	--]]
	return value
end
------------------------------------------------------------------------------
function AssignStartingPlots:GenerateRegionsCOMM(args)
	--print("Map Generation - Dividing the map in to Regions");	--TODO: Communitas commented this out
	-- This function stores its data in the instance (self) data table.
	--
	-- The "Three Methods" of regional division:
	-- 1. Biggest Landmass: All civs start on the biggest landmass.
	-- 2. Continental: Civs are assigned to continents. Any continents with more than one civ are divided.
	-- 3. Rectangular: Civs start within a given rectangle that spans the whole map, without regard to landmass sizes.
	--                 This method is primarily applied to Archipelago and other maps with lots of tiny islands.
	-- 4. Rectangular: Civs start within a given rectangle defined by arguments passed in on the function call.
	--                 Arguments required for this method: iWestX, iSouthY, iWidth, iHeight
	local args = args or {};
	local iW, iH = Map.GetGridSize();
	self.method = args.method or self.method; -- Continental method is default.
	self.resource_setting = args.resources or 2; -- Each map script has to pass in parameter for Resource setting chosen by user.

	-- Determine number of civilizations and city states present in this game.
	self.iNumCivs, self.iNumCityStates, self.player_ID_list, self.bTeamGame, self.teams_with_major_civs, self.number_civs_per_team = GetPlayerAndTeamInfo()
	self.iNumCityStatesUnassigned = self.iNumCityStates;
	--print("-"); print("Civs:", self.iNumCivs); print("City States:", self.iNumCityStates);--TODO: Communitas commented this out

	if self.method == 1 then -- Biggest Landmass
		-- Identify the biggest landmass.
		local biggest_area = Map.FindBiggestArea(False);
		local iAreaID = biggest_area:GetID();
		-- We'll need all eight data fields returned in the results table from the boundary finder:
		local landmass_data = ObtainLandmassBoundaries(iAreaID);
		local iWestX = landmass_data[1];
		local iSouthY = landmass_data[2];
		local iEastX = landmass_data[3];
		local iNorthY = landmass_data[4];
		local iWidth = landmass_data[5];
		local iHeight = landmass_data[6];
		local wrapsX = landmass_data[7];
		local wrapsY = landmass_data[8];
		
		-- Obtain "Start Placement Fertility" of the landmass. (This measurement is customized for start placement).
		-- This call returns a table recording fertility of all plots within a rectangle that contains the landmass,
		-- with a zero value for any plots not part of the landmass -- plus a fertility sum and plot count.
		local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityOfLandmass(iAreaID, 
		                                         iWestX, iEastX, iSouthY, iNorthY, wrapsX, wrapsY);
		-- Now divide this landmass in to regions, one per civ.
		-- The regional divider requires three arguments:
		-- 1. Number of divisions. (For "Biggest Landmass" this means number of civs in the game).
		-- 2. Fertility table. (This was obtained from the last call.)
		-- 3. Rectangle table. This table includes seven data fields:
		-- westX, southY, width, height, AreaID, fertilityCount, plotCount
		-- This is why we got the fertCount and plotCount from the fertility function.
		--
		-- Assemble the Rectangle data table:
		local rect_table = {iWestX, iSouthY, iWidth, iHeight, iAreaID, fertCount, plotCount};
		-- The data from this call is processed in to self.regionData during the process.
		self:DivideIntoRegions(self.iNumCivs, fert_table, rect_table)
		-- The regions have been defined.
	
	elseif self.method == 3 or self.method == 4 then -- Rectangular
		-- Obtain the boundaries of the rectangle to be processed.
		-- If no coords were passed via the args table, default to processing the entire map.
		-- Note that it matters if method 3 or 4 is designated, because the difference affects
		-- how city states are placed, whether they look for any uninhabited lands outside the rectangle.
		self.inhabited_WestX = args.iWestX or 0;
		self.inhabited_SouthY = args.iSouthY or 0;
		self.inhabited_Width = args.iWidth or iW;
		self.inhabited_Height = args.iHeight or iH;
		
		-- Obtain "Start Placement Fertility" inside the rectangle.
		-- Data returned is: fertility table, sum of all fertility, plot count.
		local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityInRectangle(self.inhabited_WestX, 
		                                         self.inhabited_SouthY, self.inhabited_Width, self.inhabited_Height)
		-- Assemble the Rectangle data table:
		local rect_table = {self.inhabited_WestX, self.inhabited_SouthY, self.inhabited_Width, 
		                    self.inhabited_Height, -1, fertCount, plotCount}; -- AreaID -1 means ignore area IDs.
		-- Divide the rectangle.
		self:DivideIntoRegions(self.iNumCivs, fert_table, rect_table)
		-- The regions have been defined.
	
	else -- Continental.
		--[[ Loop through all plots on the map, measuring fertility of each land 
		     plot, identifying its AreaID, building a list of landmass AreaIDs, and
		     tallying the Start Placement Fertility for each landmass. ]]--

		-- region_data: [WestX, EastX, SouthY, NorthY, 
		-- numLandPlotsinRegion, numCoastalPlotsinRegion,
		-- numOceanPlotsinRegion, iRegionNetYield, 
		-- iNumLandAreas, iNumPlotsinRegion]
		local best_areas = {};
		local globalFertilityOfLands = {};

		-- Obtain info on all landmasses for comparision purposes.
		local iGlobalFertilityOfLands = 0;
		local iNumLandPlots = 0;
		local iNumLandAreas = 0;
		local land_area_IDs = {};
		local land_area_plots = {};
		local land_area_fert = {};
		-- Cycle through all plots in the world, checking their Start Placement Fertility and AreaID.
		for x = 0, iW - 1 do
			for y = 0, iH - 1 do
				local i = y * iW + x + 1;
				local plot = Map.GetPlot(x, y);
				if not plot:IsWater() then -- Land plot, process it.
					iNumLandPlots = iNumLandPlots + 1;
					local iArea = plot:GetArea();
					local plotFertility = self:MeasureStartPlacementFertilityOfPlot(x, y, true); -- Check for coastal land is enabled.
					iGlobalFertilityOfLands = iGlobalFertilityOfLands + plotFertility;
					--
					if TestMembership(land_area_IDs, iArea) == false then -- This plot is the first detected in its AreaID.
						iNumLandAreas = iNumLandAreas + 1;
						table.insert(land_area_IDs, iArea);
						land_area_plots[iArea] = 1;
						land_area_fert[iArea] = plotFertility;
					else -- This AreaID already known.
						land_area_plots[iArea] = land_area_plots[iArea] + 1;
						land_area_fert[iArea] = land_area_fert[iArea] + plotFertility;
					end
				end
			end
		end
		
		--[[ Debug printout
		print("* * * * * * * * * *");
		for area_loop, AreaID in ipairs(land_area_IDs) do
			print("Area ID " .. AreaID .. " is land.");
		end
		--	--TODO: This second print section is not commented out in base CiV
		print("* * * * * * * * * *");
		for AreaID, fert in pairs(land_area_fert) do
			print("Area ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *");
		--]]
		
		-- Sort areas, achieving a list of AreaIDs with best areas first.
		--
		-- Fertility data in land_area_fert is stored with areaID index keys.
		-- Need to generate a version of this table with indices of 1 to n, where n is number of land areas.
		local interim_table = {};
		for loop_index, data_entry in pairs(land_area_fert) do
			table.insert(interim_table, data_entry);
		end
		
		--[[for AreaID, fert in ipairs(interim_table) do
			print("Interim Table ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *"); ]]--
		
		-- Sort the fertility values stored in the interim table. Sort order in Lua is lowest to highest.
		table.sort(interim_table);

		--[[	--TODO: This print section not commented out in base CiV
		for AreaID, fert in ipairs(interim_table) do
			print("Interim Table ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *");
		--]]

		-- If less players than landmasses, we will ignore the extra landmasses.
		local iNumRelevantLandAreas = math.min(iNumLandAreas, self.iNumCivs);
		-- Now re-match the AreaID numbers with their corresponding fertility values
		-- by comparing the original fertility table with the sorted interim table.
		-- During this comparison, best_areas will be constructed from sorted AreaIDs, richest stored first.
		local best_areas = {};
		-- Currently, the best yields are at the end of the interim table. We need to step backward from there.
		local end_of_interim_table = table.maxn(interim_table);
		-- We may not need all entries in the table. Process only iNumRelevantLandAreas worth of table entries.
		local fertility_value_list = {};
		local fertility_value_tie = false;
		for tableConstructionLoop = end_of_interim_table, (end_of_interim_table - iNumRelevantLandAreas + 1), -1 do
			if TestMembership(fertility_value_list, interim_table[tableConstructionLoop]) == true then
				fertility_value_tie = true;
				print("*** WARNING: Fertility Value Tie exists! ***");
			else
				table.insert(fertility_value_list, interim_table[tableConstructionLoop]);
			end
		end

		if fertility_value_tie == false then -- No ties, so no need of special handling for ties.
			for areaTestLoop = end_of_interim_table, (end_of_interim_table - iNumRelevantLandAreas + 1), -1 do
				for loop_index, AreaID in ipairs(land_area_IDs) do
					if interim_table[areaTestLoop] == land_area_fert[land_area_IDs[loop_index]] then
						table.insert(best_areas, AreaID);
						break
					end
				end
			end
		else -- Ties exist! Special handling required to protect against a shortfall in the number of defined regions.
			local iNumUniqueFertValues = table.maxn(fertility_value_list);
			for fertLoop = 1, iNumUniqueFertValues do
				for AreaID, fert in pairs(land_area_fert) do
					if fert == fertility_value_list[fertLoop] then
						-- Add ties only if there is room!
						local best_areas_length = table.maxn(best_areas);
						if best_areas_length < iNumRelevantLandAreas then
							table.insert(best_areas, AreaID);
						else
							break
						end
					end
				end
			end
		end
				
		--[[ Debug printout	--TODO: Print section not commented out in base CiV
		print("-"); print("--- Continental Division, Initial Readout ---"); print("-");
		print("- Global Fertility:", iGlobalFertilityOfLands);
		print("- Total Land Plots:", iNumLandPlots);
		print("- Total Areas:", iNumLandAreas);
		print("- Relevant Areas:", iNumRelevantLandAreas); print("-");
		--]]

		--[[ Debug printout	--TODO: This print section not commented out in base CiV
		print("* * * * * * * * * *");
		for area_loop, AreaID in ipairs(best_areas) do
			print("Area ID " .. AreaID .. " has fertility of " .. land_area_fert[AreaID]);
		end
		print("* * * * * * * * * *");
		--]]

		-- Assign continents to receive start plots. Record number of civs assigned to each landmass.
		local inhabitedAreaIDs = {};
		local numberOfCivsPerArea = table.fill(0, iNumRelevantLandAreas); -- Indexed in synch with best_areas. Use same index to match values from each table.
		for civToAssign = 1, self.iNumCivs do
			local bestRemainingArea;
			local bestRemainingFertility = 0;
			local bestAreaTableIndex;
			-- Loop through areas, find the one with the best remaining fertility (civs added 
			-- to a landmass reduces its fertility rating for subsequent civs).
			--
			--print("- - Searching landmasses in order to place Civ #", civToAssign); print("-");	--TODO: Not commented out in base CiV
			for area_loop, AreaID in ipairs(best_areas) do
				local thisLandmassCurrentFertility = land_area_fert[AreaID] / (1 + numberOfCivsPerArea[area_loop]);
				if thisLandmassCurrentFertility > bestRemainingFertility then
					bestRemainingArea = AreaID;
					bestRemainingFertility = thisLandmassCurrentFertility;
					bestAreaTableIndex = area_loop;
					--
					--print("- Found new candidate landmass with Area ID#:", bestRemainingArea, " with fertility of ", bestRemainingFertility);	--TODO: Not commented out in base CiV
				end
			end
			-- Record results for this pass. (A landmass has been assigned to receive one more start point than it previously had).
			numberOfCivsPerArea[bestAreaTableIndex] = numberOfCivsPerArea[bestAreaTableIndex] + 1;
			if TestMembership(inhabitedAreaIDs, bestRemainingArea) == false then
				table.insert(inhabitedAreaIDs, bestRemainingArea);
			end
			--print("Civ #", civToAssign, "has been assigned to Area#", bestRemainingArea); print("-");	--TODO: Not commented out in base Civ
		end
		--print("-"); print("--- End of Initial Readout ---"); print("-");	--TODO: Not commented out in base CiV
		
		--[[print("*** Number of Civs per Landmass - Table Readout ***");	--TODO: this print section not commented out in base CiV
		PrintContentsOfTable(numberOfCivsPerArea)
		print("--- End of Civs per Landmass readout ***"); print("-"); print("-");
		--]]
		-- Loop through the list of inhabited landmasses, dividing each landmass in to regions.
		-- Note that it is OK to divide a continent with one civ on it: this will assign the whole
		-- of the landmass to a single region, and is the easiest method of recording such a region.
		local iNumInhabitedLandmasses = table.maxn(inhabitedAreaIDs);
		for loop, currentLandmassID in ipairs(inhabitedAreaIDs) do
			-- Obtain the boundaries of and data for this landmass.
			local landmass_data = ObtainLandmassBoundaries(currentLandmassID);
			local iWestX = landmass_data[1];
			local iSouthY = landmass_data[2];
			local iEastX = landmass_data[3];
			local iNorthY = landmass_data[4];
			local iWidth = landmass_data[5];
			local iHeight = landmass_data[6];
			local wrapsX = landmass_data[7];
			local wrapsY = landmass_data[8];
			-- Obtain "Start Placement Fertility" of the current landmass. (Necessary to do this
			-- again because the fert_table can't be built prior to finding boundaries, and we had
			-- to ID the proper landmasses via fertility to be able to figure out their boundaries.
			local fert_table, fertCount, plotCount = self:MeasureStartPlacementFertilityOfLandmass(currentLandmassID, 
		  	                                         iWestX, iEastX, iSouthY, iNorthY, wrapsX, wrapsY);
			-- Assemble the rectangle data for this landmass.
			local rect_table = {iWestX, iSouthY, iWidth, iHeight, currentLandmassID, fertCount, plotCount};
			-- Divide this landmass in to number of regions equal to civs assigned here.
			iNumCivsOnThisLandmass = numberOfCivsPerArea[loop];
			if iNumCivsOnThisLandmass > 0 and iNumCivsOnThisLandmass <= 22 then -- valid number of civs.
			
				--[[ Debug printout for regional division inputs.	--TODO: This print section not commented out in base CiV
				print("-"); print("- Region #: ", loop);
				print("- Civs on this landmass: ", iNumCivsOnThisLandmass);
				print("- Area ID#: ", currentLandmassID);
				print("- Fertility: ", fertCount);
				print("- Plot Count: ", plotCount); print("-");
				--]]
			
				self:DivideIntoRegions(iNumCivsOnThisLandmass, fert_table, rect_table)
			else
				print("Invalid number of civs assigned to a landmass: ", iNumCivsOnThisLandmass);
			end
		end
		--
		-- The regions have been defined.
	end
	
	-- Entry point for easier overrides.
	self:CustomOverride()
	
	--[[ Printout is for debugging only. Deactivate otherwise.	--TODO: This print block not commented out in base CiV
	local tempRegionData = self.regionData;
	for i, data in ipairs(tempRegionData) do
		print("-");
		print("Data for Start Region #", i);
		print("WestX:  ", data[1]);
		print("SouthY: ", data[2]);
		print("Width:  ", data[3]);
		print("Height: ", data[4]);
		print("AreaID: ", data[5]);
		print("Fertility:", data[6]);
		print("Plots:  ", data[7]);
		print("Fert/Plot:", data[8]);
		print("-");
	end
	--]]
end
------------------------------------------------------------------------------
function AssignStartingPlots:ExaminePlotForNaturalWondersEligibilityCOMM(x, y)
	-- This function checks only for eligibility requirements applicable to all 
	-- Natural Wonders. If a candidate plot passes all such checks, we will move
	-- on to checking it against specific needs for each particular wonderID.
	--
	-- Update, May 2011: Control over wonderID placement is being migrated to XML. Some checks here moved to there.
	local iW, iH = Map.GetGridSize();
	local plotIndex = iW * y + x + 1;
	
	-- Check for collision with player starts
	if self.naturalWondersData[plotIndex] > 0 then
		return false
	end
	
	--TODO: The next chunk is novel to Communitas
	-- Check the location is a decent city site, otherwise the wonderID is pointless
	local plot = Map.GetPlot(x, y);
	if Plot_GetFertilityInRange(plot, 3) < 12 then
		return false
	end
	return true
end
function Plot_GetFertilityInRange(plot, range, yieldID)
	--TODO: This function is novel to Communitas
	local value = 0
	for nearPlot, distance in Plot_GetPlotsInCircle(plot, range, yieldID) do
		value = value + Plot_GetFertility(nearPlot, yieldID) / math.max(1, distance)
	end
	return value
end
function Plot_GetPlotsInCircle(plot, minR, maxR)
	--TODO: This is an imported Communitas utility function
	local function Constrain(lower, mid, upper)
		return math.max(lower, math.min(mid, upper))
	end
	
	if not plot then
		print("plot:GetPlotsInCircle plot=nil")
		return
	end
	if not maxR then
		maxR = minR
		minR = 1
	end
	
	local mapW, mapH	= Map.GetGridSize()
	local isWrapX		= Map:IsWrapX()
	local isWrapY		= Map:IsWrapY()
	local centerX		= plot:GetX()
	local centerY		= plot:GetY()
	
	leftX	= isWrapX and ((centerX-maxR) % mapW) or Constrain(0, centerX-maxR, mapW-1)
	rightX	= isWrapX and ((centerX+maxR) % mapW) or Constrain(0, centerX+maxR, mapW-1)
	bottomY	= isWrapY and ((centerY-maxR) % mapH) or Constrain(0, centerY-maxR, mapH-1)
	topY	= isWrapY and ((centerY+maxR) % mapH) or Constrain(0, centerY+maxR, mapH-1)
	
	local nearX	= leftX
	local nearY	= bottomY
	local stepX	= 0
	local stepY	= 0
	local rectW	= rightX-leftX 
	local rectH	= topY-bottomY
	
	if rectW < 0 then
		rectW = rectW + mapW
	end
	
	if rectH < 0 then
		rectH = rectH + mapH
	end
	
	local nextPlot = Map.GetPlot(nearX, nearY)
	
	return function ()
		while (stepY < 1 + rectH) and nextPlot do
			while (stepX < 1 + rectW) and nextPlot do
				local plot		= nextPlot
				local distance	= Map.PlotDistance(nearX, nearY, centerX, centerY)
				
				nearX		= (nearX + 1) % mapW
				stepX		= stepX + 1
				nextPlot	= Map.GetPlot(nearX, nearY)
				
				if minR <= distance and distance <= maxR then
					return plot, distance
				end
			end
			nearX		= leftX
			nearY		= (nearY + 1) % mapH
			stepX		= 0
			stepY		= stepY + 1
			nextPlot	= Map.GetPlot(nearX, nearY)
		end
	end
end

------------------------------------------------------------------------------
function AssignStartingPlots:PlaceNaturalWondersCOMM()
	--TODO: For some reason this function is slow
	print("DEBUG 1 for PlaceNaturalWondersCOMM")
	local NW_eligibility_order = self:GenerateNaturalWondersCandidatePlotLists()
	local iNumNWCandidates = table.maxn(NW_eligibility_order);
	if iNumNWCandidates == 0 then
		print("No Natural Wonders placed, no eligible sites found for any of them.");
		return
	end
	
	--[[ Debug printout	--TODO: This print block was somewhat rewritten and commented out by Communitas
	print("-"); print("--- Readout of wonderID Assignment Priority ---");
	for loop, wonderID in ipairs(NW_eligibility_order) do
		print("wonderID Assignment Priority#", loop, "goes to wonderID ", self.wonder_list[wonderID]);
	end
	print("-"); print("-"); --]]
	
	-- Determine how many NWs to attempt to place. Target is regulated per map size.
	-- The final number cannot exceed the number the map has locations to support.
	local worldsizes = {
		[GameInfo.Worlds.WORLDSIZE_DUEL.ID] = 2,
		[GameInfo.Worlds.WORLDSIZE_TINY.ID] = 3,
		[GameInfo.Worlds.WORLDSIZE_SMALL.ID] = 4,
		[GameInfo.Worlds.WORLDSIZE_STANDARD.ID] = 5,
		[GameInfo.Worlds.WORLDSIZE_LARGE.ID] = 6,
		[GameInfo.Worlds.WORLDSIZE_HUGE.ID] = 7
		}
	local target_number = worldsizes[Map.GetWorldSize()];	--TODO: Reverted to Civ default from mg.numNaturalWonders
	local iNumNWtoPlace = math.min(target_number, iNumNWCandidates);
	local selected_NWs, fallback_NWs = {}, {};
	for loop, wonderID in ipairs(NW_eligibility_order) do
		if loop <= iNumNWtoPlace then
			table.insert(selected_NWs, wonderID);
		else
			table.insert(fallback_NWs, wonderID);
		end
	end
	
	--[[	--TODO: Communitas slightly adjusted and commented out this print block
	print("-");
	for loop, wonderID in ipairs(selected_NWs) do
		print("Natural Wonder ", self.wonder_list[wonderID], "has been selected for placement.");
	end
	print("-");
	for loop, wonderID in ipairs(fallback_NWs) do
		print("Natural Wonder ", self.wonder_list[wonderID], "has been selected as fallback.");
	end
	print("-");
	--
	print("--- Placing Natural Wonders! ---");
	--]]
	
	-- Place the NWs
	local iNumPlaced = 0;
	for loop, nw_number in ipairs(selected_NWs) do
		local nw_type = self.wonder_list[nw_number];
		-- Obtain the correct Row number from the xml Placement table.
		local row_number;
		for row in GameInfo.Natural_Wonder_Placement() do
			if row.NaturalWonderType == nw_type then
				row_number = row.ID;
			end
		end
		-- Place the wonder, using the correct row data from XML.
		local bSuccess = self:AttemptToPlaceNaturalWonder(nw_number, row_number)
		if bSuccess then
			iNumPlaced = iNumPlaced + 1;
		end
	end
	if iNumPlaced < iNumNWtoPlace then
		for loop, nw_number in ipairs(fallback_NWs) do
			if iNumPlaced >= iNumNWtoPlace then
				break
			end
			local nw_type = self.wonder_list[nw_number];
			-- Obtain the correct Row number from the xml Placement table.
			local row_number;
			for row in GameInfo.Natural_Wonder_Placement() do
				if row.NaturalWonderType == nw_type then
					row_number = row.ID;
				end
			end
			-- Place the wonder, using the correct row data from XML.
			local bSuccess = self:AttemptToPlaceNaturalWonder(nw_number, row_number)
			if bSuccess then
				iNumPlaced = iNumPlaced + 1;
			end
		end
	end
	
	print("Placed " .. iNumPlaced .. " Natural Wonders")
	--
	if iNumPlaced >= iNumNWtoPlace then
		print("-- Placed all Natural Wonders --"); print("-"); print("-");
	else
		print("-- Not all Natural Wonders targeted got placed --"); print("-"); print("-");
	end
	--
		
end
------------------------------------------------------------------------------
function AssignStartingPlots:CanPlaceCityStateAtCOMM(x, y, area_ID, force_it, ignore_collisions)
	--TODO: Function in same spirit as base CiV, but many details changed.
	--TODO: Essentially, removed functionality preventing snow sites, but also
	--added functionality preventing placement near natural wonders or on particularly fertile sites
	local iW, iH = Map.GetGridSize();
	local plot = Map.GetPlot(x, y)
	local area = plot:GetArea()
	if area ~= area_ID and area_ID ~= -1 then
		return false
	end
	
	if plot:IsWater() or plot:IsMountain() then
		return false
	end
	
	-- Avoid natural wonders
	for nearPlot in Plot_GetPlotsInCircle(plot, 1, 4) do
		local featureInfo = GameInfo.Features[nearPlot:GetFeatureType()]
		if featureInfo and featureInfo.NaturalWonder then
			log:Debug("CanPlaceCityStateAt: avoided natural wonder %s", featureInfo.Type)
			return false
		end
	end
	
	-- Reserve the best city sites for major civs
	local fertility = Plot_GetFertilityInRange(plot, 2)
	if fertility > 28 then
		log:Trace("CanPlaceCityStateAt: avoided fertility %s", fertility)
		return false
	end
	
	local plotIndex = y * iW + x + 1;
	if self.cityStateData[plotIndex] > 0 and force_it == false then
		return false
	end
	local plotIndex = y * iW + x + 1;
	if self.playerCollisionData[plotIndex] == true and ignore_collisions == false then
		--print("-"); print("City State candidate plot rejected: collided with already-placed civ or City State at", x, y);
		return false
	end
	return true
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceCityStateInRegionCOMM(city_state_number, region_number)
	--print("Place City State in Region called for City State", city_state_number, "Region", region_number);
	local iW, iH = Map.GetGridSize();
	local placed_city_state = false;
	local reached_middle = false;
	local region_data_table = self.regionData[region_number];
	local iWestX = region_data_table[1];
	local iSouthY = region_data_table[2];
	local iWidth = region_data_table[3];
	local iHeight = region_data_table[4];
	local iAreaID = region_data_table[5];
	
	local eligible_coastal, eligible_inland = {}, {};
	
	-- Main loop, first pass, unforced
	local x, y;
	local curWX = iWestX;
	local curSY = iSouthY;
	local curWid = iWidth;
	local curHei = iHeight;
	while placed_city_state == false and reached_middle == false do
		-- Send the remaining unprocessed portion of the region to be processed.
		local nextWX, nextSY, nextWid, nextHei;
		eligible_coastal, eligible_inland, nextWX, nextSY, nextWid, nextHei, 
		  reached_middle = self:ObtainNextSectionInRegion(curWX, curSY, curWid, curHei, iAreaID, false, false) -- Don't force it. Yet.
		curWX, curSY, curWid, curHei = nextWX, nextSY, nextWid, nextHei;
		-- Attempt to place city state using the two plot lists received from the last call.
		x, y, placed_city_state = self:PlaceCityState(eligible_coastal, eligible_inland, false, false) -- Don't need to re-check collisions.
	end

	--TODO: Communitas removed commented out code on fallback citystate placement
	if placed_city_state == true then
		-- Record and enact the placement.
		self.cityStatePlots[city_state_number] = {x, y, region_number};
		self.city_state_validity_table[city_state_number] = true; -- This is the line that marks a city state as valid to be processed by the rest of the system.
		local city_state_ID = city_state_number + GameDefines.MAX_MAJOR_CIVS - 1;
		local cityState = Players[city_state_ID];
		local cs_start_plot = Map.GetPlot(x, y)
		cityState:SetStartingPlot(cs_start_plot)
		self:GenerateLuxuryPlotListsAtCitySite(x, y, 1, true) -- Removes Feature Ice from coasts near to the city state's new location
		self:PlaceResourceImpact(x, y, 5, 4) -- City State layer
		self:PlaceResourceImpact(x, y, 2, 3) -- Luxury layer
		self:PlaceResourceImpact(x, y, 3, 3) -- Bonus layer
		self:PlaceResourceImpact(x, y, 4, 3) -- Fish layer
		self:PlaceResourceImpact(x, y, 7, 3) -- Marble layer
		--TODO: For non-militaristic states Communitas blocks strategics out to radius 3 (base CiV only blocks strategics at start point regardless of city state type)
		if cityState:GetMinorCivTrait() == MinorCivTraitTypes.MINOR_CIV_TRAIT_MILITARISTIC then
			self:PlaceResourceImpact(x, y, 1, 0) -- Strategic layer, at start point only.
		else
			self:PlaceResourceImpact(x, y, 1, 3) -- Strategic layer
		end
		local impactPlotIndex = y * iW + x + 1;
		self.playerCollisionData[impactPlotIndex] = true;
		--print("-"); print("City State", city_state_number, "has been started at Plot", x, y, "in Region#", region_number);
	else
		--print("-"); print("WARNING: Crowding issues for City State #", city_state_number, " - Could not find valid site in Region#", region_number);
		self.iNumCityStatesDiscarded = self.iNumCityStatesDiscarded + 1;
	end
end
--..**----------------------------------------------------------------------------
function AssignStartingPlots:BuffIslandsCOMM()
	--TODO: This entire function is novel to Communitas (and won't be called without overriding PlaceResourcesAndCityStates)
	print("Buffing Tiny Islands")
	local biggestAreaSize = Map.FindBiggestArea(false):GetNumTiles()
	if biggestAreaSize < 20 then
		-- Skip on archipalego maps
		return
	end
	local resWeights = {
		[self.stone_ID]		= 4,
		[self.coal_ID]		= 4,
		[self.oil_ID]		= 1,
		[self.aluminum_ID]	= 1,
		[self.uranium_ID]	= 2
	}
	for plotID, plot in Plots(Shuffle) do
		local plotType		= plot:GetPlotType()
		local terrainType	= plot:GetTerrainType()
		local area			= plot:Area()
		local areaSize		= area:GetNumTiles()
		if ((plotType == PlotTypes.PLOT_HILLS or plotType == PlotTypes.PLOT_LAND )
				and plot:GetResourceType() == -1
				and 1 <= areaSize and areaSize <= 0.1 * biggestAreaSize
				and not self.islandAreaBuffed[area:GetID()]
				)then
			local resID  = GetRandomWeighted(resWeights)
			local resNum = 1
			if resID ~= self.stone_ID then
				resNum = resNum + Map.Rand(2, "BuffIslands Random Resource Quantity - Lua")
				if resID ~= self.uranium_ID then
					resNum = resNum + 1
				end
			end
			if resNum > 0 then
				self.islandAreaBuffed[area:GetID()] = true
				if 75 >= Map.Rand(100, "BuffIslands Chance - Lua") then
					if resID == self.coal_ID and plotType == PlotTypes.PLOT_LAND then
						if terrainType == TerrainTypes.TERRAIN_TUNDRA then
							plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1)
						elseif terrainType == TerrainTypes.TERRAIN_GRASS or terrainType == TerrainTypes.TERRAIN_PLAINS then
							plot:SetFeatureType(FeatureTypes.FEATURE_JUNGLE, -1)
						end
					end
					plot:SetResourceType(resID, resNum)
					self.amounts_of_resources_placed[resID + 1] = self.amounts_of_resources_placed[resID + 1] + resNum
				end
			end
		end
	end
end
function GetRandomWeighted(list, size)
	--TODO: Communitas Utility Function
	-- GetRandomWeighted(list, size) returns a key from a list of (key, weight) pairs
	size = size or 100
	local chanceIDs = GetWeightedTable(list, size)

	if chanceIDs == -1 then
		return -1
	end
	local randomID = 1 + Map.Rand(size, "GetRandomWeighted")
	if not chanceIDs[randomID] then
		print("GetRandomWeighted: invalid random index selected = %s", randomID)
		chanceIDs[randomID] = -1
	end
	return chanceIDs[randomID]
end
function GetWeightedTable(list, size)
	--TODO: Communitas Utility Function
	-- GetWeightedTable(list, size) returns a table with key blocks sized proportionately to a weighted list
	local totalWeight	= 0
	local chanceIDs		= {}
	local position		= 1
	
	for key, weight in pairs(list) do
		totalWeight = totalWeight + weight
	end
	
	if totalWeight == 0 then
		for key, weight in pairs(list) do
			list[key] = 1
			totalWeight = totalWeight + 1
		end
		if totalWeight == 0 then
			print("GetWeightedTable: empty list")
			--print(debug.traceback())
			return -1
		end
	end
	
	for key, weight in pairs(list) do
		local positionNext = position + size * weight / totalWeight
		for i = math.floor(position), math.floor(positionNext) do
			chanceIDs[i] = key
		end
		position = positionNext
	end	
	return chanceIDs
end

------------------------------------------------------------------------------
function AssignStartingPlots:AdjustTilesCOMM()
	--	TODO: This is a rename of FixSugarJungle with some additional adjustments (which are individually annotated below)
	-- Sugar could not be made to look good in both jungle and open/marsh at the same time.
	-- Jon and I decided the best workaround would be to turn any Sugar/Jungle in to Marsh.
	local iW, iH = Map.GetGridSize()
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local plot = Map.GetPlot(x, y)
			local resID = plot:GetResourceType()
			local featureType = plot:GetFeatureType();
			if resID == self.sugar_ID then
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					local plotID = plot:GetPlotType()
					if plotID ~= PlotTypes.PLOT_LAND then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
					end
					plot:SetFeatureType(FeatureTypes.FEATURE_MARSH, -1)
					plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, true)
					--
					--print("-"); print("Fixed a Sugar/Jungle at plot", x, y);
				end
			elseif resID == self.deer_ID then	--TODO: This clause is added b/c this script could otherwise place non-forest deer
				if featureType == FeatureTypes.NO_FEATURE then
					local plotID = plot:GetPlotType()
					if plotID ~= PlotTypes.PLOT_LAND then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
					end
					plot:SetFeatureType(FeatureTypes.FEATURE_FOREST, -1)
					plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, true)
					--
					--print("-"); print("Added forest to deer at plot", x, y);
				end
			end
			--[[if plot:GetTerrainType() == TerrainTypes.TERRAIN_SNOW then	--TODO: This clause added to make rivers turn adjacent snow into tundra
				if Plot_IsRiver(plot) then
					plot:SetTerrainType(TerrainTypes.TERRAIN_TUNDRA,false,true)
				end
			end--]]--TODO: Uncomment block?
			
			if plot:IsHills() and featureType == FeatureTypes.FEATURE_JUNGLE then	--TODO: This appears to make jungle-hills be on grassland and have forced less food? I guess? I'm confused why you'd do this.
				plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, true)
				Game.SetPlotExtraYield( x, y, YieldTypes.YIELD_FOOD, -1)
			end
			
			--BuffDeserts(plot)					
		end
	end
end
------------------------------------------------------------------------------
function BuffDeserts(plot)
	--TODO: This function is novel to Communitas, but is commented out and never called even there.
	if Cep then
		return
	end
	if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_DESERT or plot:IsHills() or plot:GetFeatureType() ~= -1 then
		return
	end
	
	local resInfo = GameInfo.Resources[plot:GetResourceType()]
	if plot:IsFreshWater() then
		Game.SetPlotExtraYield( x, y, YieldTypes.YIELD_FOOD, 1)
	elseif resInfo then
		if resInfo.Type == "RESOURCE_STONE" then
			Game.SetPlotExtraYield( x, y, YieldTypes.YIELD_PRODUCTION, 2)
		elseif resInfo.ResourceClassType == "RESOURCECLASS_BONUS" then
			Game.SetPlotExtraYield( x, y, YieldTypes.YIELD_FOOD, 1)
		elseif resInfo.Happiness > 0 then
			Game.SetPlotExtraYield( x, y, YieldTypes.YIELD_GOLD, 1)
		elseif not resInfo.TechReveal then
			Game.SetPlotExtraYield( x, y, YieldTypes.YIELD_PRODUCTION, 1)
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:ProcessResourceListCOMM(frequency, impact_table_number, plot_list, resources_to_place)
	-- Added a random factor to strategic resources - Thalassicus

	-- This function needs to receive two numbers and two tables.
	-- Length of the plotlist is divided by frequency to get the number of 
	-- resources to place. .. The first table is a list of plot indices.
	-- The second table contains subtables, one per resource type, detailing the
	-- resource ID number, quantity, weighting, and impact radius of each applicable
	-- resource. If radius min and max are different, the radius length is variable
	-- and a die roll will determine a value >= min and <= max.
	--
	-- The system may be easiest to manage if the weightings add up to 100, so they
	-- can be handled as percentages, but this is not required.
	--
	-- Impact #s - 1 strategic - 2 luxury - 3 bonus
	-- Res data  - 1 ID - 2 quantity - 3 weight - 4 radius min - 5 radius max
	--
	-- The plot list will be processed sequentially, so randomize it in advance.
	-- The default lists are terrain-oriented and are randomized during __Init
	if plot_list == nil then
		--print("Plot list was nil! -ProcessResourceList");
		return
	end
	local iW, iH = Map.GetGridSize();
	local iNumTotalPlots = table.maxn(plot_list);
	local iNumResourcesToPlace = math.ceil(iNumTotalPlots / frequency);
	local iNumResourcesTypes = table.maxn(resources_to_place);
	local res_ID, res_quantity, res_weight, res_min, res_max, res_range, res_threshold = {}, {}, {}, {}, {}, {}, {};
	local totalWeight, accumulatedWeight = 0, 0;
	for index, resource_data in ipairs(resources_to_place) do
		res_ID[index] = resource_data[1];
		res_quantity[index] = resource_data[2];
		res_weight[index] = resource_data[3];
		totalWeight = totalWeight + resource_data[3];
		res_min[index] = resource_data[4];
		res_max[index] = resource_data[5];
		if res_max[index] > res_min[index] then
			res_range[index] = res_max[index] - res_min[index] + 1;
		else
			res_range[index] = -1;
		end
	end
	for index = 1, iNumResourcesTypes do
		-- We'll roll a die and check each resource in turn to see if it is 
		-- the one to get placed in that particular case. The weightings are 
		-- used to decide how much percentage of the total each represents.
		-- This chunk sets the threshold for each resource in turn.
		local threshold = (res_weight[index] + accumulatedWeight) * 10000 / totalWeight;
		table.insert(res_threshold, threshold);
		accumulatedWeight = accumulatedWeight + res_weight[index];
	end
	-- Main loop
	local current_index = 1;
	local avoid_ripples = true;
	for place_resource = 1, iNumResourcesToPlace do
		local placed_this_res = false;
		local use_this_res_index = 1;
		local diceroll = Map.Rand(10000, "Choose resource type - Distribute Resources - Lua");
		for index, threshold in ipairs(res_threshold) do
			if diceroll < threshold then -- Choose this resource type.
				use_this_res_index = index;
				break
			end
		end
		if avoid_ripples == true then -- Still on first pass through plot_list, seek first eligible 0 value on impact matrix.
			for index_to_check = current_index, iNumTotalPlots do
				if index_to_check == iNumTotalPlots then -- Completed first pass of plot_list, now change to seeking lowest value instead of zero value.
					avoid_ripples = false;
				end
				if placed_this_res == true then
					break
				else
					current_index = current_index + 1;
				end
				local plotIndex = plot_list[index_to_check];
				if impact_table_number == 1 then
					if self.strategicData[plotIndex] == 0 then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType() == -1 then -- Placing this strategic resource in this plot. TODO: Base Civ passes -1 to GetResourceType; reason for change unclear
							local res_addition = 0;
							if res_range[use_this_res_index] ~= -1 then
								res_addition = Map.Rand(res_range[use_this_res_index], "Resource Radius - Place Resource LUA");
							end
							local randValue = Map.Rand(self.resource_setting + 1, "Place Strategic Resource - Lua")
							local quantity = res_quantity[use_this_res_index] + randValue	--TODO: Note previous line and this added slight randomization to resource amount
							--print(string.format("ProcessResourceList table 1, Resource: %20s, Quantity: %s + %s - 1", GameInfo.Resources[res_ID[use_this_res_index]].Type, res_quantity[use_this_res_index], randValue));
							res_plot:SetResourceType(res_ID[use_this_res_index], quantity);
							if (Game.GetResourceUsageType(res_ID[use_this_res_index]) == ResourceUsageTypes.RESOURCEUSAGE_LUXURY) then
								self.totalLuxPlacedSoFar = self.totalLuxPlacedSoFar + 1;
							end
							self:PlaceResourceImpact(x, y, impact_table_number, res_min[use_this_res_index] + res_addition);
							placed_this_res = true;
							self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] = self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] + res_quantity[use_this_res_index];
						end
					end
				elseif impact_table_number == 2 then
					if self.luxuryData[plotIndex] == 0 then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType() == -1 then -- Placing this luxury resource in this plot. --TODO: Base Civ passes -1 to GetResourceType
							local res_addition = 0;
							if res_range[use_this_res_index] ~= -1 then
								res_addition = Map.Rand(res_range[use_this_res_index], "Resource Radius - Place Resource LUA");
							end
							--print("ProcessResourceList table 2, Resource: " .. res_ID[use_this_res_index] .. ", Quantity: " .. res_quantity[use_this_res_index]);
							res_plot:SetResourceType(res_ID[use_this_res_index], res_quantity[use_this_res_index]);
							self:PlaceResourceImpact(x, y, impact_table_number, res_min[use_this_res_index] + res_addition);
							placed_this_res = true;
							self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] = self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] + 1;
						end
					end
				elseif impact_table_number == 3 then
					if self.bonusData[plotIndex] == 0 then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType() == -1 then -- Placing this bonus resource in this plot. --TODO: Base Civ passes -1 to GetResourceType
							local res_addition = 0;
							if res_range[use_this_res_index] ~= -1 then
								res_addition = Map.Rand(res_range[use_this_res_index], "Resource Radius - Place Resource LUA");
							end
							--print("ProcessResourceList table 3, Resource: " .. res_ID[use_this_res_index] .. ", Quantity: " .. res_quantity[use_this_res_index]);
							res_plot:SetResourceType(res_ID[use_this_res_index], res_quantity[use_this_res_index]);
							self:PlaceResourceImpact(x, y, impact_table_number, res_min[use_this_res_index] + res_addition);
							placed_this_res = true;
							self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] = self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] + 1;
							if res_ID[use_this_res_index] == self.stone_ID then	--TODO: Note that this if statement is entirely new
								self.islandAreaBuffed[res_plot:GetArea()] = true
							end
						end
					end
				end
			end
		end
		if avoid_ripples == false then -- Completed first pass through plot_list, so use backup method.
			local lowest_impact = 98;
			local best_plot;
			for loop, plotIndex in ipairs(plot_list) do
				if impact_table_number == 1 then
					if lowest_impact > self.strategicData[plotIndex] then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType() == -1 then --TODO: Base Civ passes -1 to GetResourceType
							lowest_impact = self.strategicData[plotIndex];
							best_plot = plotIndex;
						end
					end
				elseif impact_table_number == 2 then
					if lowest_impact > self.luxuryData[plotIndex] then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType() == -1 then --TODO: Line very slightly modded; reason unclear
							lowest_impact = self.luxuryData[plotIndex];
							best_plot = plotIndex;
						end
					end
				elseif impact_table_number == 3 then
					if lowest_impact > self.bonusData[plotIndex] then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType() == -1 then --TODO: Line very slightly modded; reason unclear
							lowest_impact = self.bonusData[plotIndex];
							best_plot = plotIndex;
						end
					end
				end
			end
			if best_plot ~= nil then
				local x = (best_plot - 1) % iW;
				local y = (best_plot - x - 1) / iW;
				local res_plot = Map.GetPlot(x, y)
				local res_addition = 0;
				if res_range[use_this_res_index] ~= -1 then
					res_addition = Map.Rand(res_range[use_this_res_index], "Resource Radius - Place Resource LUA");
				end
				--print("ProcessResourceList backup, Resource: " .. res_ID[use_this_res_index] .. ", Quantity: " .. res_quantity[use_this_res_index]);
				res_plot:SetResourceType(res_ID[use_this_res_index], res_quantity[use_this_res_index]);
				self:PlaceResourceImpact(x, y, impact_table_number, res_min[use_this_res_index] + res_addition);
				self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] = self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] + res_quantity[use_this_res_index];
			end
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceSpecificNumberOfResourcesCOMM(resource_ID, quantity, amount,
	                         ratio, impact_table_number, min_radius, max_radius, plot_list)
	-- This function needs to receive seven numbers and one table.
	--
	-- Resource_ID is the type of resource to place.
	-- Quantity is the in-game quantity of the resource, or 0 if unquantified resource type.
	-- Amount is the number of plots intended to receive an assignment of this resource.
	--
	-- Ratio should be > 0 and <= 1 and is what determines when secondary and tertiary lists 
	-- come in to play. The actual ratio is (AmountOfResource / PlotsInList). For instance, 
	-- if we are assigning Sugar resources to Marsh, then if we are to assign eight Sugar 
	-- resources, but there are only four Marsh plots in the list, a ratio of 1 would assign
	-- a Sugar to every single marsh plot, and then have to return an unplaced value of 4; 
	-- but a ratio of 0.5 would assign only two Sugars to the four marsh plots, and return a 
	-- value of 6. Any ratio less than or equal to 0.25 would assign one Sugar and return
	-- seven, as the ratio results will be rounded up not down, to the nearest integer.
	--
	-- Impact tables: -1 = ignore, 1 = strategic, 2 = luxury, 3 = bonus, 4 = fish
	-- Radius is amount of impact to place on this table when placing a resource.
	--
	-- nil tables are not acceptable but empty tables are fine
	--
	-- The plot lists will be processed sequentially, so randomize them in advance.
	-- 
	
	--print("-"); print("PlaceSpecificResource called. ResID:", resource_ID, "Quantity:", quantity, "Amount:", amount, "Ratio:", ratio);
	
	if plot_list == nil then
		--print("Plot list was nil! -PlaceSpecificNumberOfResources");
		return
	end
	local bCheckImpact = false;
	local impact_table = {};
	if impact_table_number == 1 then
		bCheckImpact = true;
		impact_table = self.strategicData;
	elseif impact_table_number == 2 then
		bCheckImpact = true;
		impact_table = self.luxuryData;
	elseif impact_table_number == 3 then
		bCheckImpact = true;
		impact_table = self.bonusData;
	elseif impact_table_number == 4 then
		bCheckImpact = true;
		impact_table = self.fishData;
	elseif impact_table_number ~= -1 then --TODO: This elseif clause added in Communitas
		bCheckImpact = true;
		impact_table = self.impactData[impact_table_number];
	end
	local iW, iH = Map.GetGridSize();
	local iNumLeftToPlace = amount;
	local iNumPlots = table.maxn(plot_list);
	local iNumResources = math.min(amount, math.ceil(ratio * iNumPlots));
	-- Main loop
	for place_resource = 1, iNumResources do
		for loop, plotIndex in ipairs(plot_list) do
			if not bCheckImpact or impact_table[plotIndex] == 0 then	--TODO: base civ uses  bCheckImpact == false  instead; reason for change unclear
				local x = (plotIndex - 1) % iW;
				local y = (plotIndex - x - 1) / iW;
				local res_plot = Map.GetPlot(x, y)
				if res_plot:GetResourceType(-1) == -1 then -- Placing this resource in this plot.
					res_plot:SetResourceType(resource_ID, quantity);
					self.amounts_of_resources_placed[resource_ID + 1] = self.amounts_of_resources_placed[resource_ID + 1] + quantity;
					--print("-"); print("Placed Resource#", resource_ID, "at Plot", x, y);
					self.totalLuxPlacedSoFar = self.totalLuxPlacedSoFar + 1;
					iNumLeftToPlace = iNumLeftToPlace - 1;
					if bCheckImpact == true then
						local res_addition = 0;
						if max_radius > min_radius then
							res_addition = Map.Rand(1 + (max_radius - min_radius), "Resource Radius - Place Resource LUA");
						end
						local rad = min_radius + res_addition;
						self:PlaceResourceImpact(x, y, impact_table_number, rad)
					end
					break
				end
			end
		end
	end
	return iNumLeftToPlace
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetMajorStrategicResourceQuantityValuesCOMM()
	-- This function determines quantity per tile for each strategic resource's major deposit size.
	-- Note: scripts that cannot place Oil in the sea need to increase amounts on land to compensate.
	-- Also receives a random factor from 0 to self.resource_setting
	
	--TODO: These values are severely reduced relative to base Civ; for the most part they equal the Small values
	
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 2, 2, 2, 2, 3;
	-- Check the resource setting.
	if self.resource_setting == 1 then -- Sparse
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 1, 2, 2, 2, 2, 2;
	elseif self.resource_setting == 3 then -- Abundant
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 3, 3, 3, 3, 4;
	end
	return uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetSmallStrategicResourceQuantityValuesCOMM()
	-- TODO: Some very minor tweaks in the values relative to base civ.  (oil and coal down in standard; uranium down in abundant)
	-- This function determines quantity per tile for each strategic resource's small deposit size.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 2, 2, 2, 2, 3;
	-- Check the resource setting.
	if self.resource_setting == 1 then -- Sparse
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 1, 1, 2, 1, 2, 2;
	elseif self.resource_setting == 3 then -- Abundant
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 3, 3, 3, 3, 3;
	end
	return uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceOilInTheSeaCOMM()
	-- Places sources of Oil in Coastal waters, equal to half what's on the 
	-- land. If the map has too little ocean, then whatever will fit.
	--
	-- WARNING: This operation will render the Strategic Resource Impact Table useless for
	-- further operations, so should always be called last, even after minor placements.
	local sea_oil_amt = 2 --TODO: This is reduced from base Civ; additionally base Civ further increases this on Abundant resources, but this makes no change
	local iNumLandOilUnits = self.amounts_of_resources_placed[self.oil_ID + 1];
	local iNumToPlace = math.floor((iNumLandOilUnits / 2) / sea_oil_amt);

	--print("Adding Oil resources to the Sea.");
	self:PlaceSpecificNumberOfResources(self.oil_ID, sea_oil_amt, iNumToPlace, 0.2, 1, 4, 7, self.coast_list)
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceStrategicAndBonusResourcesCOMM()
	print("PlaceStrategicAndBonusResources")
	-- KEY: {Resource ID, Quantity (0 = unquantified), weighting, minimum radius, maximum radius}
	-- KEY: (frequency (1 per n plots in the list), impact list number, plot list, resource data)
	--
	-- The radius creates a zone around the plot that other resources of that
	-- type will avoid if possible. See ProcessResourceList for impact numbers.
	--
	-- Order of placement matters, so changing the order may affect a later dependency.
	
	-- Adjust amounts, if applicable, based on Resource Setting.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = self:GetMajorStrategicResourceQuantityValues()
	local resources_to_place = {}	--TODO: Note that this is new --not significant though, just saves redeclaring it a bunch below

	-- Adjust appearance rate per Resource Setting chosen by user.
	local resMultiplier = 1;	--TODO: Note that the variable name has changed but this is otherwise the same
	if self.resource_setting == 1 then -- Sparse, so increase the number of tiles per bonus.
		resMultiplier = 1.5;
	elseif self.resource_setting == 3 then -- Abundant, so reduce the number of tiles per bonus.
		resMultiplier = 0.66666667;
	end
	
	print("self.resource_setting = " .. self.resource_setting)
	
	-- Place Strategic resources. --TODO: This is where the re-worked distribution of strategic resources (relative to unmodded Civ) is done
	do
	print("Map Generation - Placing Strategics");
	
	resources_to_place = {
	{self.iron_ID, iron_amt, 10, 0, 2}, --26
	{self.coal_ID, coal_amt, 80, 1, 3}, -- 39
	{self.aluminum_ID, alum_amt, 10, 2, 3} }; -- 35
	self:ProcessResourceList(15, 1, self.hills_list, resources_to_place)
	-- 22

	resources_to_place = {
	{self.coal_ID, coal_amt, 50, 1, 2}, -- 30
	{self.uranium_ID, uran_amt, 50, 1, 2} }; --70
	self:ProcessResourceList(20, 1, self.jungle_flat_list, resources_to_place)
	-- 33
	
	resources_to_place = {
	{self.coal_ID, coal_amt, 80, 1, 2}, --70
	{self.uranium_ID, uran_amt, 20, 1, 1},  --30
	{self.iron_ID, iron_amt, 100, 0, 2} };
	self:ProcessResourceList(30, 1, self.forest_flat_list, resources_to_place)
	-- 39	
	
	resources_to_place = {
	{self.oil_ID, oil_amt, 65, 1, 1},
	{self.uranium_ID, uran_amt, 35, 0, 1} };
	self:ProcessResourceList(30, 1, self.jungle_flat_list, resources_to_place)
	-- 9
	
	resources_to_place = {
	{self.oil_ID, oil_amt, 45, 1, 2},
	{self.aluminum_ID, alum_amt, 45, 1, 2},
	{self.iron_ID, iron_amt, 10, 1, 2} };
	self:ProcessResourceList(16, 1, self.tundra_flat_no_feature, resources_to_place)
	-- 16
	
	resources_to_place = {
	{self.oil_ID, oil_amt, 20, 1, 1},
	{self.aluminum_ID, alum_amt, 20, 2, 3},
	{self.uranium_ID, alum_amt, 20, 2, 3},
	{self.coal_ID, alum_amt, 20, 2, 3},
	{self.iron_ID, iron_amt, 20, 2, 3} };
	self:ProcessResourceList(5, 1, self.snow_flat_list, resources_to_place)
	-- 17
	
	resources_to_place = {
	{self.oil_ID, oil_amt, 80, 0, 1},
	{self.iron_ID, iron_amt, 20, 1, 1} };
	self:ProcessResourceList(10, 1, self.desert_flat_no_feature, resources_to_place)
	-- 13

	resources_to_place = {
	{self.iron_ID, iron_amt, 100, 0, 2} };
	self:ProcessResourceList(10, 1, self.hills_jungle_list, resources_to_place)
	-- 99
	
--	resources_to_place = {
--	{self.iron_ID, iron_amt, 100, 0, 2} };
--	self:ProcessResourceList(5, 1, self.marsh_list, resources_to_place)
	-- 99

	resources_to_place = {
	{self.horse_ID, horse_amt, 100, 2, 5} };
	self:ProcessResourceList(33, 1, self.grass_flat_no_feature, resources_to_place)
	-- 33
	
	resources_to_place = {
	{self.horse_ID, horse_amt, 100, 1, 4} };
	self:ProcessResourceList(33, 1, self.plains_flat_no_feature, resources_to_place)
	-- 33
	
	resources_to_place = {
	{self.horse_ID, horse_amt, 100, 1, 4} };
	self:ProcessResourceList(10, 1, self.flood_plains_list, resources_to_place)
	end
	-- 33

	self:AddModernMinorStrategicsToCityStates() -- Added spring 2011
	
	self:PlaceSmallQuantitiesOfStrategics(23 * resMultiplier, self.land_list);
	
	self:PlaceOilInTheSea();

	
	-- Check for low or missing Strategic resources
	do
	if self.amounts_of_resources_placed[self.iron_ID + 1] < 8 then
		--print("Map has very low iron, adding another.");
		local resources_to_place = { {self.iron_ID, iron_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.hills_list, resources_to_place) -- 99999 means one per that many tiles: a single instance.
	end
	if self.amounts_of_resources_placed[self.iron_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low iron, adding another.");
		local resources_to_place = { {self.iron_ID, iron_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.horse_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low horse, adding another.");
		local resources_to_place = { {self.horse_ID, horse_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.plains_flat_no_feature, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.horse_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low horse, adding another.");
		local resources_to_place = { {self.horse_ID, horse_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.dry_grass_flat_no_feature, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.coal_ID + 1] < 8 then
		--print("Map has very low coal, adding another.");
		local resources_to_place = { {self.coal_ID, coal_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.hills_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.coal_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low coal, adding another.");
		local resources_to_place = { {self.coal_ID, coal_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.oil_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low oil, adding another.");
		local resources_to_place = { {self.oil_ID, oil_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.aluminum_ID + 1] < 4 * self.iNumCivs then
		--print("Map has very low aluminum, adding another.");
		local resources_to_place = { {self.aluminum_ID, alum_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.hills_list, resources_to_place)
	end
	if self.amounts_of_resources_placed[self.uranium_ID + 1] < 2 * self.iNumCivs then
		--print("Map has very low uranium, adding another.");
		local resources_to_place = { {self.uranium_ID, uran_amt, 100, 0, 0} };
		self:ProcessResourceList(99999, 1, self.land_list, resources_to_place)
	end
	end
	
	self:PlaceBonusResources() --TODO: Note PlaceBonusResources is new; the associated code in original ASP.lua is written out here.
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceFishCOMM()
	--TODO: This function significantly rewritten by Communitas
	print("AssignStartingPlots:PlaceFish()")
	for plotID, plot in Plots(Shuffle) do
		PlacePossibleFish(plot)
	end
end
function PlacePossibleFish(plot)
	if plot:GetTerrainType() ~= TerrainTypes.TERRAIN_COAST or plot:IsLake() or plot:GetFeatureType() ~= FeatureTypes.NO_FEATURE or plot:GetResourceType() ~= -1 then
		return
	end
	local x, y			= plot:GetX(), plot:GetY()
	local landDistance	= 999
	local sumFertility	= 0
	local nearFish		= 0
	local odds			= 0
	local fishID		= GameInfo.Resources.RESOURCE_FISH.ID
	local fishMod		= 0
	
	for nearPlot, distance in Plot_GetPlotsInCircle(plot, 1, 3) do
		distance = math.max(1, distance)
		if not nearPlot:IsWater() and distance < landDistance then
			landDistance = distance
		end
		sumFertility = sumFertility + Plot_GetFertility(nearPlot, false, true)
		if nearPlot:GetResourceType() == fishID then
			odds = odds - 100 / distance
		end
	end
	if landDistance >= 3 then
		return
	end
	
	local fishTargetFertility		= 40	-- fish appear to create this average city fertility TODO: Constant taken from Communitas
	fishMod = odds
	odds = odds + 100 * (1 - sumFertility/(fishTargetFertility * 2))
	odds = odds / landDistance
	
	if odds >= Map.Rand(100, "PlacePossibleFish - Lua") then
		plot:SetResourceType(fishID, 1)
		--print(string.format( "PlacePossibleFish fertility=%-3s odds=%-3s fishMod=%-3s", Round(sumFertility), Round(odds), Round(fishMod) ))
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceBonusResourcesCOMM()
	local resMultiplier = 1;
	if self.resource_setting == 1 then -- Sparse, so increase the number of tiles per bonus.
		resMultiplier = 1.5;
	elseif self.resource_setting == 3 then -- Abundant, so reduce the number of tiles per bonus.
		resMultiplier = 0.66666667;
	end
	
	-- Place Bonus Resources
	print("Map Generation - Placing Bonuses");
	self:PlaceFish(10 * resMultiplier, self.coast_list);	--TODO: Note that Communitas' PlaceFish is a fundamentally different algorithm from base Civ's. But they're called the same way, so can leave this as-is and include custom PlaceFish or not
	self:PlaceSexyBonusAtCivStarts()
	self:AddExtraBonusesToHillsRegions()
	local resources_to_place = {}
	
	--TODO: Some changes made below relative to base Civ code
	resources_to_place = {
	{self.deer_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(6 * resMultiplier, 3, self.extra_deer_list, resources_to_place)
	-- 8

	resources_to_place = {
	{self.deer_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(8 * resMultiplier, 3, self.tundra_flat_no_feature, resources_to_place)
	-- 12
	
	resources_to_place = {
	{self.wheat_ID, 1, 100, 0, 2} };
	self:ProcessResourceList(10 * resMultiplier, 3, self.desert_wheat_list, resources_to_place)
	-- 10

	resources_to_place = {
	{self.wheat_ID, 1, 100, 2, 3} };
	self:ProcessResourceList(10 * resMultiplier, 3, self.plains_flat_no_feature, resources_to_place)
	-- 27
	
	resources_to_place = {
	{self.banana_ID, 1, 100, 0, 3} };
	self:ProcessResourceList(14 * resMultiplier, 3, self.banana_list, resources_to_place)
	-- 14
	
	resources_to_place = {
	{self.cow_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(18 * resMultiplier, 3, self.grass_flat_no_feature, resources_to_place)
	-- 18
	
-- CBP
	resources_to_place = {
	{self.bison_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(15 * resMultiplier, 3, self.plains_flat_no_feature, resources_to_place)
-- END

	resources_to_place = {
	{self.sheep_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(8 * resMultiplier, 3, self.hills_open_list, resources_to_place)
	-- 13

	resources_to_place = {
	{self.stone_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(10 * resMultiplier, 3, self.grass_flat_no_feature, resources_to_place)
	-- 20
	
	resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(15 * resMultiplier, 3, self.tundra_flat_no_feature, resources_to_place)
	-- 15
	
	resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(5 * resMultiplier, 3, self.desert_flat_no_feature, resources_to_place)
	-- 19
	
	resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(50 * resMultiplier, 3, self.marsh_list, resources_to_place)
	-- 99
	
	resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(8 * resMultiplier, 3, self.snow_flat_list, resources_to_place)
	-- 99
	
	resources_to_place = {
	{self.deer_ID, 1, 100, 3, 4} };
	self:ProcessResourceList(25 * resMultiplier, 3, self.forest_flat_that_are_not_tundra, resources_to_place)
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceResourcesAndCityStatesCOMM()
	-- This function controls nearly all resource placement. Only resources
	-- placed during Normalization operations are handled elsewhere.
	--
	-- Luxury resources are placed in relationship to Regions, adapting to the
	-- details of the given map instance, including number of civs and city 
	-- states present. At Jon's direction, Luxuries have been implemented to
	-- be diplomatic widgets for trading, in addition to sources of Happiness.
	--
	-- Strategic and Bonus resources are terrain-adjusted. They will customize
	-- to each map instance. Each terrain type has been measured and has certain 
	-- resource types assigned to it. You can customize resource placement to 
	-- any degree desired by controlling generation of plot groups to feed in
	-- to the process. The default plot groups are terrain-based, but any
	-- criteria you desire could be used to determine plot group membership.
	-- 
	-- If any default methods fail to meet a specific need, don't hesitate to 
	-- replace them with custom methods. I have labored to make this new 
	-- system as accessible and powerful as any ever before offered.

	print("Map Generation - Assigning Luxury Resource Distribution");
	self:AssignLuxuryRoles()

	print("Map Generation - Placing City States");
	self:PlaceCityStates()

	-- Generate global plot lists for resource distribution.
	self:GenerateGlobalResourcePlotLists()
	
	print("Map Generation - Placing Luxuries");
	self:PlaceLuxuries()
	
	--TODO: This was added
	--print("Map Generation - Placing Stone on Islands");
	self:BuffIslands()

	-- Place Strategic and Bonus resources.
	--[[	--TODO: The commented out bit is novel, but the active piece matches base CiV
	if GameInfo.Cep then
		self:PlaceStrategicAndBonusResourcesCEP()
	else
		self:PlaceStrategicAndBonusResources()
	end
	--]]
	self:PlaceStrategicAndBonusResources()
	
	--print("Map Generation - Normalize City State Locations");	--TODO: Communitas commented this out
	self:NormalizeCityStateLocations()
	
	-- Fix Sugar graphics	--TODO: This is just a rename
	self:AdjustTiles()
	
	--TODO: This section is novel to Communitas
	local largestLand = Map.FindBiggestArea(false)
	if Map.GetCustomOption(6) == 2 then
		-- Biggest continent placement
		if largestLand:GetNumTiles() < 0.25 * Map.GetLandPlots() then
			print("AI Map Strategy - Offshore expansion with navy bias")
			-- Tell the AI that we should treat this as a offshore expansion map with naval bias
			Map.ChangeAIMapHint(4+1)
		else
			print("AI Map Strategy - Offshore expansion")
			-- Tell the AI that we should treat this as a offshore expansion map
			Map.ChangeAIMapHint(4)
		end
	elseif largestLand:GetNumTiles() < 0.25 * Map.GetLandPlots() then
		print("AI Map Strategy - Navy bias")
		-- Tell the AI that we should treat this as a map with naval bias
		Map.ChangeAIMapHint(1)
	else
		print("AI Map Strategy - Normal")
	end
	
	-- Necessary to implement placement of Natural Wonders, and possibly other plot-type changes.
	-- This operation must be saved for last, as it invalidates all regional data by resetting Area IDs.
	Map.RecalculateAreas();

	-- Activate for debug only
	self:PrintFinalResourceTotalsToLog()
	--
end
------------------------------------------------------------------------------
function AssignStartingPlots:NormalizeStartLocationCOMM(region_number)
	--TODO: This is included in Communitas.lua, but I don't know why as it is identical to base CiV as confirmed by a diff
	--[[ This function measures the value of land in two rings around a given start
	     location, primarily for the purpose of determining how much support the site
	     requires in the form of Bonus Resources. Numerous assumptions are built in 
	     to this operation that would need to be adjusted for any modifications to 
	     terrain or resources types and yields, or to game rules about rivers and 
	     other map elements. Nothing is hardcoded in a way that puts it out of the 
	     reach of modders, but any mods including changes to map elements may have a
	     significant workload involved with rebalancing the start finder and the 
	     resource distribution to fit them properly to a mod's custom needs. I have
	     labored to document every function and method in detail to make it as easy
	     as possible to modify this system.  -- Bob Thomas - April 15, 2010  ]]--
	-- 
	local iW, iH = Map.GetGridSize();
	local start_point_data = self.startingPlots[region_number];
	local x = start_point_data[1];
	local y = start_point_data[2];
	local plot = Map.GetPlot(x, y);
	local plotIndex = y * iW + x + 1;
	local isEvenY = true;
	if y / 2 > math.floor(y / 2) then
		isEvenY = false;
	end
	local wrapX = Map:IsWrapX();
	local wrapY = Map:IsWrapY();
	local innerFourFood, innerThreeFood, innerTwoFood, innerHills, innerForest, innerOneHammer, innerOcean = 0, 0, 0, 0, 0, 0, 0;
	local outerFourFood, outerThreeFood, outerTwoFood, outerHills, outerForest, outerOneHammer, outerOcean = 0, 0, 0, 0, 0, 0, 0;
	local innerCanHaveBonus, outerCanHaveBonus, innerBadTiles, outerBadTiles = 0, 0, 0, 0;
	local iNumFoodBonusNeeded = 0;
	local iNumNativeTwoFoodFirstRing, iNumNativeTwoFoodSecondRing = 0, 0; -- Cities must begin the game with at least three native 2F tiles, one in first ring.
	local search_table = {};
	
	-- Remove any feature Ice from the first ring.
	self:GenerateLuxuryPlotListsAtCitySite(x, y, 1, true)
	
	-- Set up Conditions checks.
	local alongOcean = false;
	local nextToLake = false;
	local isRiver = false;
	local nearRiver = false;
	local nearMountain = false;
	local forestCount, jungleCount = 0, 0;

	-- Check start plot to see if it's adjacent to saltwater.
	if self.plotDataIsCoastal[plotIndex] == true then
		alongOcean = true;
	end
	
	-- Check start plot to see if it's on a river.
	if plot:IsRiver() then
		isRiver = true;
	end

	-- Data Chart for early game tile potentials
	--
	-- 4F:	Flood Plains, Grass on fresh water (includes forest and marsh).
	-- 3F:	Dry Grass, Plains on fresh water (includes forest and jungle), Tundra on fresh water (includes forest), Oasis
	-- 2F:  Dry Plains, Lake, all remaining Jungles.
	--
	-- 1H:	Plains, Jungle on Plains

	-- Adding evaluation of grassland and plains for balance boost of bonus Cows for heavy grass starts. -1/26/2011 BT
	local iNumGrass, iNumPlains = 0, 0;

	-- Evaluate First Ring
	if isEvenY then
		search_table = self.firstRingYIsEven;
	else
		search_table = self.firstRingYIsOdd;
	end

	for loop, plot_adjustments in ipairs(search_table) do
		local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
		--
		if searchX < 0 or searchX >= iW or searchY < 0 or searchY >= iH then
			-- This plot does not exist. It's off the map edge.
			innerBadTiles = innerBadTiles + 1;
		else
			local searchPlot = Map.GetPlot(searchX, searchY)
			local plotType = searchPlot:GetPlotType()
			local terrainType = searchPlot:GetTerrainType()
			local featureType = searchPlot:GetFeatureType()
			--
			if plotType == PlotTypes.PLOT_MOUNTAIN then
				local nearMountain = true;
				innerBadTiles = innerBadTiles + 1;
			elseif plotType == PlotTypes.PLOT_OCEAN then
				if searchPlot:IsLake() then
					nextToLake = true;
					if featureType == FeatureTypes.FEATURE_ICE then
						innerBadTiles = innerBadTiles + 1;
					else
						innerTwoFood = innerTwoFood + 1;
						iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
					end
				else
					if featureType == FeatureTypes.FEATURE_ICE then
						innerBadTiles = innerBadTiles + 1;
					else
						innerOcean = innerOcean + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
					end
				end
			else -- Habitable plot.
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					jungleCount = jungleCount + 1;
					iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
				elseif featureType == FeatureTypes.FEATURE_FOREST then
					forestCount = forestCount + 1;
				end
				if searchPlot:IsRiver() then
					nearRiver = true;
				end
				if plotType == PlotTypes.PLOT_HILLS then
					innerHills = innerHills + 1;
					if featureType == FeatureTypes.FEATURE_JUNGLE then
						innerTwoFood = innerTwoFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
					elseif featureType == FeatureTypes.FEATURE_FOREST then
						innerCanHaveBonus = innerCanHaveBonus + 1;
					elseif terrainType == TerrainTypes.TERRAIN_GRASS then
						iNumGrass = iNumGrass + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						iNumPlains = iNumPlains + 1;
					end
				elseif featureType == FeatureTypes.FEATURE_OASIS then
					innerThreeFood = innerThreeFood + 1;
					iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
				elseif searchPlot:IsFreshWater() then
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						innerFourFood = innerFourFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							innerCanHaveBonus = innerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
						end
					elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
						innerFourFood = innerFourFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						innerThreeFood = innerThreeFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						else
							innerOneHammer = innerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						innerThreeFood = innerThreeFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						innerBadTiles = innerBadTiles + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						innerBadTiles = innerBadTiles + 1;
					end
				else -- Dry Flatlands
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						innerThreeFood = innerThreeFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							innerCanHaveBonus = innerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodFirstRing = iNumNativeTwoFoodFirstRing + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						innerTwoFood = innerTwoFood + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						else
							innerOneHammer = innerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						innerCanHaveBonus = innerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							innerForest = innerForest + 1;
						else
							innerBadTiles = innerBadTiles + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						innerBadTiles = innerBadTiles + 1;
						innerCanHaveBonus = innerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						innerBadTiles = innerBadTiles + 1;
					end
				end
			end
		end
	end
				
	-- Evaluate Second Ring
	if isEvenY then
		search_table = self.secondRingYIsEven;
	else
		search_table = self.secondRingYIsOdd;
	end

	for loop, plot_adjustments in ipairs(search_table) do
		local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
		local plot = Map.GetPlot(x, y);
		--
		--
		if searchX < 0 or searchX >= iW or searchY < 0 or searchY >= iH then
			-- This plot does not exist. It's off the map edge.
			outerBadTiles = outerBadTiles + 1;
		else
			local searchPlot = Map.GetPlot(searchX, searchY)
			local plotType = searchPlot:GetPlotType()
			local terrainType = searchPlot:GetTerrainType()
			local featureType = searchPlot:GetFeatureType()
			--
			if plotType == PlotTypes.PLOT_MOUNTAIN then
				local nearMountain = true;
				outerBadTiles = outerBadTiles + 1;
			elseif plotType == PlotTypes.PLOT_OCEAN then
				if searchPlot:IsLake() then
					if featureType == FeatureTypes.FEATURE_ICE then
						outerBadTiles = outerBadTiles + 1;
					else
						outerTwoFood = outerTwoFood + 1;
						iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
					end
				else
					if featureType == FeatureTypes.FEATURE_ICE then
						outerBadTiles = outerBadTiles + 1;
					elseif terrainType == TerrainTypes.TERRAIN_COAST then
						outerCanHaveBonus = outerCanHaveBonus + 1;
						outerOcean = outerOcean + 1;
					end
				end
			else -- Habitable plot.
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					jungleCount = jungleCount + 1;
					iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
				elseif featureType == FeatureTypes.FEATURE_FOREST then
					forestCount = forestCount + 1;
				end
				if searchPlot:IsRiver() then
					nearRiver = true;
				end
				if plotType == PlotTypes.PLOT_HILLS then
					outerHills = outerHills + 1;
					if featureType == FeatureTypes.FEATURE_JUNGLE then
						outerTwoFood = outerTwoFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
					elseif featureType == FeatureTypes.FEATURE_FOREST then
						outerCanHaveBonus = outerCanHaveBonus + 1;
					elseif terrainType == TerrainTypes.TERRAIN_GRASS then
						iNumGrass = iNumGrass + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						iNumPlains = iNumPlains + 1;
					end
				elseif featureType == FeatureTypes.FEATURE_OASIS then
					innerThreeFood = innerThreeFood + 1;
					iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
				elseif searchPlot:IsFreshWater() then
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						outerFourFood = outerFourFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							outerCanHaveBonus = outerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
						end
					elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
						outerFourFood = outerFourFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						outerThreeFood = outerThreeFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						else
							outerOneHammer = outerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						outerThreeFood = outerThreeFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						outerBadTiles = outerBadTiles + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						outerBadTiles = outerBadTiles + 1;
					end
				else -- Dry Flatlands
					if terrainType == TerrainTypes.TERRAIN_GRASS then
						outerThreeFood = outerThreeFood + 1;
						iNumGrass = iNumGrass + 1;
						if featureType ~= FeatureTypes.FEATURE_MARSH then
							outerCanHaveBonus = outerCanHaveBonus + 1;
						end
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						end
						if featureType == FeatureTypes.NO_FEATURE then
							iNumNativeTwoFoodSecondRing = iNumNativeTwoFoodSecondRing + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
						outerTwoFood = outerTwoFood + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1;
						iNumPlains = iNumPlains + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						else
							outerOneHammer = outerOneHammer + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
						outerCanHaveBonus = outerCanHaveBonus + 1;
						if featureType == FeatureTypes.FEATURE_FOREST then
							outerForest = outerForest + 1;
						else
							outerBadTiles = outerBadTiles + 1;
						end
					elseif terrainType == TerrainTypes.TERRAIN_DESERT then
						outerBadTiles = outerBadTiles + 1;
						outerCanHaveBonus = outerCanHaveBonus + 1; -- Can have Oasis.
					else -- Snow
						outerBadTiles = outerBadTiles + 1;
					end
				end
			end
		end
	end
	
	-- Adjust the hammer situation, if needed.
	local innerHammerScore = (4 * innerHills) + (2 * innerForest) + innerOneHammer;
	local outerHammerScore = (2 * outerHills) + outerForest + outerOneHammer;
	local earlyHammerScore = (2 * innerForest) + outerForest + innerOneHammer + outerOneHammer;
	-- If drastic shortage, attempt to add a hill to first ring.
	if (outerHammerScore < 8 and innerHammerScore < 2) or innerHammerScore == 0 then -- Change a first ring plot to Hills.
		if isEvenY then
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsEven);
		else
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsOdd);
		end
		for attempt = 1, 6 do
			local plot_adjustments = randomized_first_ring_adjustments[attempt];
			local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
			-- Attempt to place a Hill at the currently chosen plot.
			local placedHill = self:AttemptToPlaceHillsAtPlot(searchX, searchY);
			if placedHill == true then
				innerHammerScore = innerHammerScore + 4;
				--print("Added hills next to hammer-poor start plot at ", x, y);
				break
			elseif attempt == 6 then
				--print("FAILED to add hills next to hammer-poor start plot at ", x, y);
			end
		end
	end
	
	-- Add mandatory Iron, Horse, Oil to every start if Strategic Balance option is enabled.
	if self.resource_setting == 5 then
		self:AddStrategicBalanceResources(region_number)
	end
	
	-- If early hammers will be too short, attempt to add a small Horse or Iron to second ring.
	if innerHammerScore < 3 and earlyHammerScore < 6 then -- Add a small Horse or Iron to second ring.
		if isEvenY then
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsEven);
		else
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsOdd);
		end
		for attempt = 1, 12 do
			local plot_adjustments = randomized_second_ring_adjustments[attempt];
			local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
			-- Attempt to place a Hill at the currently chosen plot.
			local placedStrategic = self:AttemptToPlaceSmallStrategicAtPlot(searchX, searchY);
			if placedStrategic == true then
				break
			elseif attempt == 12 then
				--print("FAILED to add small strategic resource near hammer-poor start plot at ", x, y);
			end
		end
	end
	
	-- Rate the food situation.
	local innerFoodScore = (4 * innerFourFood) + (2 * innerThreeFood) + innerTwoFood;
	local outerFoodScore = (4 * outerFourFood) + (2 * outerThreeFood) + outerTwoFood;
	local totalFoodScore = innerFoodScore + outerFoodScore;
	local nativeTwoFoodTiles = iNumNativeTwoFoodFirstRing + iNumNativeTwoFoodSecondRing;

	--[[ Debug printout of food scores.
	print("-");
	print("-- - Start Point in Region #", region_number, " has Food Score of ", totalFoodScore, " with rings of ", innerFoodScore, outerFoodScore);
	]]--	
	
	-- Six levels for Bonus Resource support, from zero to five.
	if totalFoodScore < 4 and innerFoodScore == 0 then
		iNumFoodBonusNeeded = 5;
	elseif totalFoodScore < 6 then
		iNumFoodBonusNeeded = 4;
	elseif totalFoodScore < 8 then
		iNumFoodBonusNeeded = 3;
	elseif totalFoodScore < 12 and innerFoodScore < 5 then
		iNumFoodBonusNeeded = 3;
	elseif totalFoodScore < 17 and innerFoodScore < 9 then
		iNumFoodBonusNeeded = 2;
	elseif nativeTwoFoodTiles <= 1 then
		iNumFoodBonusNeeded = 2;
	elseif totalFoodScore < 24 and innerFoodScore < 11 then
		iNumFoodBonusNeeded = 1;
	elseif nativeTwoFoodTiles == 2 or iNumNativeTwoFoodFirstRing == 0 then
		iNumFoodBonusNeeded = 1;
	elseif totalFoodScore < 20 then
		iNumFoodBonusNeeded = 1;
	end
	
	-- Check for Legendary Start resource option.
	if self.resource_setting == 4 then
		iNumFoodBonusNeeded = iNumFoodBonusNeeded + 2;
	end
	
	-- Check to see if a Grass tile needs to be added at an all-plains site with zero native 2-food tiles in first two rings.
	if nativeTwoFoodTiles == 0 and iNumFoodBonusNeeded < 3 then
		local odd = self.firstRingYIsOdd;
		local even = self.firstRingYIsEven;
		local plot_list = {};
		-- For notes on how the hex-iteration works, refer to PlaceResourceImpact()
		local ripple_radius = 2;
		local currentX = x - ripple_radius;
		local currentY = y;
		for direction_index = 1, 6 do
			for plot_to_handle = 1, ripple_radius do
			 	if currentY / 2 > math.floor(currentY / 2) then
					plot_adjustments = odd[direction_index];
				else
					plot_adjustments = even[direction_index];
				end
				nextX = currentX + plot_adjustments[1];
				nextY = currentY + plot_adjustments[2];
				if wrapX == false and (nextX < 0 or nextX >= iW) then
					-- X is out of bounds.
				elseif wrapY == false and (nextY < 0 or nextY >= iH) then
					-- Y is out of bounds.
				else
					local realX = nextX;
					local realY = nextY;
					if wrapX then
						realX = realX % iW;
					end
					if wrapY then
						realY = realY % iH;
					end
					-- We've arrived at the correct x and y for the current plot.
					local plot = Map.GetPlot(realX, realY);
					if plot:GetResourceType(-1) == -1 then -- No resource here, safe to proceed.
						local plotType = plot:GetPlotType()
						local terrainType = plot:GetTerrainType()
						local featureType = plot:GetFeatureType()
						local plotIndex = realY * iW + realX + 1;
						-- Now check this plot for eligibility to be converted to flat open grassland.
						if plotType == PlotTypes.PLOT_LAND then
							if terrainType == TerrainTypes.TERRAIN_PLAINS then
								if featureType == FeatureTypes.NO_FEATURE then
									table.insert(plot_list, plotIndex);
								end
							end
						end
					end
				end
				currentX, currentY = nextX, nextY;
			end
		end
		local iNumConversionCandidates = table.maxn(plot_list);
		if iNumConversionCandidates == 0 then
			iNumFoodBonusNeeded = 3;
		else
			--print("-"); print("*** START HAD NO 2-FOOD TILES, YET ONLY QUALIFIED FOR 2 BONUS; CONVERTING A PLAINS TO GRASS! ***"); print("-");
			local diceroll = 1 + Map.Rand(iNumConversionCandidates, "Choosing plot to convert to Grass near food-poor Plains start - LUA");
			local conversionPlotIndex = plot_list[diceroll];
			local conv_x = (conversionPlotIndex - 1) % iW;
			local conv_y = (conversionPlotIndex - conv_x - 1) / iW;
			local plot = Map.GetPlot(conv_x, conv_y);
			plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, false)
			self:PlaceResourceImpact(conv_x, conv_y, 1, 0) -- Disallow strategic resources at this plot, to keep it a farm plot.
		end
	end
	-- Add Bonus Resources to food-poor start positions.
	if iNumFoodBonusNeeded > 0 then
		local maxBonusesPossible = innerCanHaveBonus + outerCanHaveBonus;

		--print("-");
		--print("Food-Poor start ", x, y, " needs ", iNumFoodBonusNeeded, " Bonus, with ", maxBonusesPossible, " eligible plots.");
		--print("-");

		local innerPlaced, outerPlaced = 0, 0;
		local randomized_first_ring_adjustments, randomized_second_ring_adjustments, randomized_third_ring_adjustments;
		if isEvenY then
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsEven);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsEven);
			randomized_third_ring_adjustments = GetShuffledCopyOfTable(self.thirdRingYIsEven);
		else
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsOdd);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsOdd);
			randomized_third_ring_adjustments = GetShuffledCopyOfTable(self.thirdRingYIsOdd);
		end
		local tried_all_first_ring = false;
		local tried_all_second_ring = false;
		local tried_all_third_ring = false;
		local allow_oasis = true; -- Permanent flag. (We don't want to place more than one Oasis per location).
		local placedOasis; -- Records returning result from each attempt.
		while iNumFoodBonusNeeded > 0 do
			if ((innerPlaced < 2 and innerCanHaveBonus > 0) or (self.resource_setting == 4 and innerPlaced < 3 and innerCanHaveBonus > 0))
			  and tried_all_first_ring == false then
				-- Add bonus to inner ring.
				for attempt = 1, 6 do
					local plot_adjustments = randomized_first_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place a Bonus at the currently chosen plot.
					local placedBonus, placedOasis = self:AttemptToPlaceBonusResourceAtPlot(searchX, searchY, allow_oasis);
					if placedBonus == true then
						if allow_oasis == true and placedOasis == true then -- First oasis was placed on this pass, so change permission.
							allow_oasis = false;
						end
						--print("Placed a Bonus in first ring at ", searchX, searchY);
						innerPlaced = innerPlaced + 1;
						innerCanHaveBonus = innerCanHaveBonus - 1;
						iNumFoodBonusNeeded = iNumFoodBonusNeeded - 1;
						break
					elseif attempt == 6 then
						tried_all_first_ring = true;
					end
				end

			elseif ((innerPlaced + outerPlaced < 5 and outerCanHaveBonus > 0) or (self.resource_setting == 4 and innerPlaced + outerPlaced < 4 and outerCanHaveBonus > 0))
			  and tried_all_second_ring == false then
				-- Add bonus to second ring.
				for attempt = 1, 12 do
					local plot_adjustments = randomized_second_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place a Bonus at the currently chosen plot.
					local placedBonus, placedOasis = self:AttemptToPlaceBonusResourceAtPlot(searchX, searchY, allow_oasis);
					if placedBonus == true then
						if allow_oasis == true and placedOasis == true then -- First oasis was placed on this pass, so change permission.
							allow_oasis = false;
						end
						--print("Placed a Bonus in second ring at ", searchX, searchY);
						outerPlaced = outerPlaced + 1;
						outerCanHaveBonus = outerCanHaveBonus - 1;
						iNumFoodBonusNeeded = iNumFoodBonusNeeded - 1;
						break
					elseif attempt == 12 then
						tried_all_second_ring = true;
					end
				end

			elseif tried_all_third_ring == false then
				-- Add bonus to third ring.
				for attempt = 1, 18 do
					local plot_adjustments = randomized_third_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place a Bonus at the currently chosen plot.
					local placedBonus, placedOasis = self:AttemptToPlaceBonusResourceAtPlot(searchX, searchY, allow_oasis);
					if placedBonus == true then
						if allow_oasis == true and placedOasis == true then -- First oasis was placed on this pass, so change permission.
							allow_oasis = false;
						end
						--print("Placed a Bonus in third ring at ", searchX, searchY);
						iNumFoodBonusNeeded = iNumFoodBonusNeeded - 1;
						break
					elseif attempt == 18 then
						tried_all_third_ring = true;
					end
				end
				
			else -- Tried everywhere, have to give up.
				break				
			end
		end
	end

	-- Check for heavy grass and light plains. Adding Stone if grass count is high and plains count is low. - May 2011, BT
	local iNumStoneNeeded = 0;
	if iNumGrass >= 9 and iNumPlains == 0 then
		iNumStoneNeeded = 2;
	elseif iNumGrass >= 6 and iNumPlains <= 4 then
		iNumStoneNeeded = 1;
	end
	if iNumStoneNeeded > 0 then -- Add Stone to this grass start.
		local stonePlaced, innerPlaced = 0, 0;
		local randomized_first_ring_adjustments, randomized_second_ring_adjustments;
		if isEvenY then
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsEven);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsEven);
		else
			randomized_first_ring_adjustments = GetShuffledCopyOfTable(self.firstRingYIsOdd);
			randomized_second_ring_adjustments = GetShuffledCopyOfTable(self.secondRingYIsOdd);
		end
		local tried_all_first_ring = false;
		local tried_all_second_ring = false;
		while iNumStoneNeeded > 0 do
			if innerPlaced < 1 and tried_all_first_ring == false then
				-- Add bonus to inner ring.
				for attempt = 1, 6 do
					local plot_adjustments = randomized_first_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place Cows at the currently chosen plot.
					local placedBonus = self:AttemptToPlaceStoneAtGrassPlot(searchX, searchY);
					if placedBonus == true then
						--print("Placed Stone in first ring at ", searchX, searchY);
						innerPlaced = innerPlaced + 1;
						iNumStoneNeeded = iNumStoneNeeded - 1;
						break
					elseif attempt == 6 then
						tried_all_first_ring = true;
					end
				end

			elseif tried_all_second_ring == false then
				-- Add bonus to second ring.
				for attempt = 1, 12 do
					local plot_adjustments = randomized_second_ring_adjustments[attempt];
					local searchX, searchY = self:ApplyHexAdjustment(x, y, plot_adjustments)
					-- Attempt to place Stone at the currently chosen plot.
					local placedBonus = self:AttemptToPlaceStoneAtGrassPlot(searchX, searchY);
					if placedBonus == true then
						--print("Placed Stone in second ring at ", searchX, searchY);
						iNumStoneNeeded = iNumStoneNeeded - 1;
						break
					elseif attempt == 12 then
						tried_all_second_ring = true;
					end
				end

			else -- Tried everywhere, have to give up.
				break				
			end
		end
	end
	
	-- Record conditions at this start location.
	local results_table = {alongOcean, nextToLake, isRiver, nearRiver, nearMountain, forestCount, jungleCount};
	self.startLocationConditions[region_number] = results_table;
end
------------------------------------------------------------------------------
function AssignStartingPlots:BalanceAndAssignCOMM()
	--TODO: While there are some changes in here, they are quite minor.
	-- This function determines what level of Bonus Resource support a location
	-- may need, identifies compatibility with civ-specific biases, and places starts.

	-- Normalize each start plot location.
	local iNumStarts = table.maxn(self.startingPlots);
	for region_number = 1, iNumStarts do
		self:NormalizeStartLocation(region_number)
	end

	-- Check Game Option for disabling civ-specific biases.
	-- If they are to be disabled, then all civs are simply assigned to start plots at random.
	local bDisableStartBias = Game.GetCustomOption("GAMEOPTION_DISABLE_START_BIAS");
	if bDisableStartBias == 1 then
		--print("-"); print("ALERT: Civ Start Biases have been selected to be Disabled!"); print("-");
		local playerList = {};
		for loop = 1, self.iNumCivs do
			local player_ID = self.player_ID_list[loop];
			table.insert(playerList, player_ID);
		end
		local playerListShuffled = GetShuffledCopyOfTable(playerList)
		for region_number, player_ID in ipairs(playerListShuffled) do
			local x = self.startingPlots[region_number][1];
			local y = self.startingPlots[region_number][2];
			local start_plot = Map.GetPlot(x, y)
			local player = Players[player_ID]
			player:SetStartingPlot(start_plot)
		end
		-- If this is a team game (any team has more than one Civ in it) then make 
		-- sure team members start near each other if possible. (This may scramble 
		-- Civ biases in some cases, but there is no cure).
		if self.bTeamGame == true then
			self:NormalizeTeamLocations()
		end
		-- Done with un-biased Civ placement.
		return
	end

	-- If the process reaches here, civ-specific start-location biases are enabled. Handle them now.
	-- Create a randomized list of all regions. As a region gets assigned, we'll remove it from the list.
	local all_regions = {};
	for loop = 1, self.iNumCivs do
		table.insert(all_regions, loop);
	end
	local regions_still_available = GetShuffledCopyOfTable(all_regions)

	local civs_needing_coastal_start = {};
	local civs_priority_coastal_start = {};
	local civs_needing_river_start = {};
	local civs_needing_region_priority = {};
	local civs_needing_region_avoid = {};
	local regions_with_coastal_start = {};
	local regions_with_lake_start = {};
	local regions_with_river_start = {};
	local regions_with_near_river_start = {};
	local civ_status = table.fill(false, GameDefines.MAX_MAJOR_CIVS); -- Have to account for possible gaps in player ID numbers, for MP.
	local region_status = table.fill(false, self.iNumCivs);
	local priority_lists = {};
	local avoid_lists = {};
	local iNumCoastalCivs, iNumRiverCivs, iNumPriorityCivs, iNumAvoidCivs = 0, 0, 0, 0;
	local iNumCoastalCivsRemaining, iNumRiverCivsRemaining, iNumPriorityCivsRemaining, iNumAvoidCivsRemaining = 0, 0, 0, 0;
	
	--print("-"); print("-"); print("--- DEBUG READOUT OF PLAYER START ASSIGNMENTS ---"); print("-");
	
	-- Generate lists of player needs. Each additional need type is subordinate to those
	-- that come before. In other words, each Civ can have only one need type.
	for loop = 1, self.iNumCivs do
		local playerNum = self.player_ID_list[loop]; -- MP games can have gaps between player numbers, so we cannot assume a sequential set of IDs.
		local player = Players[playerNum];
		local civType = GameInfo.Civilizations[player:GetCivilizationType()].Type;
		--print("Player", playerNum, "of Civ Type", civType);	--TODO: Communitas commented this out
		local bNeedsCoastalStart = CivNeedsCoastalStart(civType)
		if bNeedsCoastalStart == true then
			--print("- - - - - - - needs Coastal Start!"); print("-");	--TODO: Communitas commented this out
			iNumCoastalCivs = iNumCoastalCivs + 1;
			iNumCoastalCivsRemaining = iNumCoastalCivsRemaining + 1;
			table.insert(civs_needing_coastal_start, playerNum);
			if CivNeedsPlaceFirstCoastalStart then	--TODO: This outer if statement is new to communitas, but the inner part is in base CiV. Not sure where CivNeedsPlaceFirstCoastalStart is defined.
				local bPlaceFirst = CivNeedsPlaceFirstCoastalStart(civType);
				if bPlaceFirst then
					--print("- - - - - - - needs to Place First!"); --print("-");	--TODO: Communitas commented this out
					table.insert(civs_priority_coastal_start, playerNum);
				end
			end
		else
			local bNeedsRiverStart = CivNeedsRiverStart(civType)
			if bNeedsRiverStart == true then
				--print("- - - - - - - needs River Start!"); print("-");
				iNumRiverCivs = iNumRiverCivs + 1;
				iNumRiverCivsRemaining = iNumRiverCivsRemaining + 1;
				table.insert(civs_needing_river_start, playerNum);
			else
				local iNumRegionPriority = GetNumStartRegionPriorityForCiv(civType)
				if iNumRegionPriority > 0 then
					--print("- - - - - - - needs Region Priority!"); print("-");
					local table_of_this_civs_priority_needs = GetStartRegionPriorityListForCiv_GetIDs(civType)
					iNumPriorityCivs = iNumPriorityCivs + 1;
					iNumPriorityCivsRemaining = iNumPriorityCivsRemaining + 1;
					table.insert(civs_needing_region_priority, playerNum);
					priority_lists[playerNum] = table_of_this_civs_priority_needs;
				else
					local iNumRegionAvoid = GetNumStartRegionAvoidForCiv(civType)
					if iNumRegionAvoid > 0 then
						--print("- - - - - - - needs Region Avoid!"); print("-");
						local table_of_this_civs_avoid_needs = GetStartRegionAvoidListForCiv_GetIDs(civType)
						iNumAvoidCivs = iNumAvoidCivs + 1;
						iNumAvoidCivsRemaining = iNumAvoidCivsRemaining + 1;
						table.insert(civs_needing_region_avoid, playerNum);
						avoid_lists[playerNum] = table_of_this_civs_avoid_needs;
					end
				end
			end
		end
	end
	
	--[[ Debug printout	--TODO: This was only commented out by Communitas
	print("Civs with Coastal Bias:", iNumCoastalCivs);
	print("Civs with River Bias:", iNumRiverCivs);
	print("Civs with Region Priority:", iNumPriorityCivs);
	print("Civs with Region Avoid:", iNumAvoidCivs); print("-");
	--]]
	
	-- Handle Coastal Start Bias
	if iNumCoastalCivs > 0 then
		-- Generate lists of regions eligible to support a coastal start.
		local iNumRegionsWithCoastalStart, iNumRegionsWithLakeStart, iNumUnassignableCoastStarts = 0, 0, 0;
		for region_number, bAlreadyAssigned in ipairs(region_status) do
			if bAlreadyAssigned == false then
				if self.startLocationConditions[region_number][1] == true then
					--print("Region#", region_number, "has a Coastal Start.");	--TODO: Communitas commented this out
					iNumRegionsWithCoastalStart = iNumRegionsWithCoastalStart + 1;
					table.insert(regions_with_coastal_start, region_number);
				end
			end
		end
		if iNumRegionsWithCoastalStart < iNumCoastalCivs then
			for region_number, bAlreadyAssigned in ipairs(region_status) do
				if bAlreadyAssigned == false then
					if self.startLocationConditions[region_number][2] == true and
					   self.startLocationConditions[region_number][1] == false then
						--print("Region#", region_number, "has a Lake Start.");	--TODO: Communitas commented this out
						iNumRegionsWithLakeStart = iNumRegionsWithLakeStart + 1;
						table.insert(regions_with_lake_start, region_number);
					end
				end
			end
		end
		if iNumRegionsWithCoastalStart + iNumRegionsWithLakeStart < iNumCoastalCivs then
			iNumUnassignableCoastStarts = iNumCoastalCivs - (iNumRegionsWithCoastalStart + iNumRegionsWithLakeStart);
		end
		-- Now assign those with coastal bias to start locations, where possible.
		--TODO: The two print statements below entirely removed by Communitas here from base CiV version
		--print("iNumCoastalCivs: " .. iNumCoastalCivs);
		--print("iNumUnassignableCoastStarts: " .. iNumUnassignableCoastStarts);
		if iNumCoastalCivs - iNumUnassignableCoastStarts > 0 then
			-- create non-priority coastal start list
			local non_priority_coastal_start = {};
			for loop1, iPlayerNum1 in ipairs(civs_needing_coastal_start) do
				local bAdd = true;
				for loop2, iPlayerNum2 in ipairs(civs_priority_coastal_start) do
					if (iPlayerNum1 == iPlayerNum2) then
						bAdd = false;
					end
				end
				if bAdd then
					table.insert(non_priority_coastal_start, iPlayerNum1);
				end
			end
			
			local shuffled_priority_coastal_start = GetShuffledCopyOfTable(civs_priority_coastal_start);
			local shuffled_non_priority_coastal_start = GetShuffledCopyOfTable(non_priority_coastal_start);
			local shuffled_coastal_civs = {};
			
			-- insert priority coastal starts first
			for loop, iPlayerNum in ipairs(shuffled_priority_coastal_start) do
				table.insert(shuffled_coastal_civs, iPlayerNum);
			end
			
			-- insert non-priority coastal starts second
			for loop, iPlayerNum in ipairs(shuffled_non_priority_coastal_start) do
				table.insert(shuffled_coastal_civs, iPlayerNum);
			end			
			
			for loop, iPlayerNum in ipairs(shuffled_coastal_civs) do
				--print("shuffled_coastal_civs[" .. loop .. "]: " .. iPlayerNum);	--TODO: Communitas commented this out
			end
			
			local shuffled_coastal_civs = GetShuffledCopyOfTable(civs_needing_coastal_start);	--TODO: This line is new in Communitas
			local shuffled_coastal_regions, shuffled_lake_regions;
			local current_lake_index = 1;
			if iNumRegionsWithCoastalStart > 0 then
				shuffled_coastal_regions = GetShuffledCopyOfTable(regions_with_coastal_start);
			end
			if iNumRegionsWithLakeStart > 0 then
				shuffled_lake_regions = GetShuffledCopyOfTable(regions_with_lake_start);
			end
			for loop, playerNum in ipairs(shuffled_coastal_civs) do
				if loop > iNumCoastalCivs - iNumUnassignableCoastStarts then
					print("Ran out of Coastal and Lake start locations to assign to Coastal Bias.");	--TODO: This line had been commented out in base CiV
					break
				end
				-- Assign next randomly chosen civ in line to next randomly chosen eligible region.
				if loop <= iNumRegionsWithCoastalStart then
					-- Assign this civ to a region with coastal start.
					local choose_this_region = shuffled_coastal_regions[loop];
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[playerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", playerNum, "assigned a COASTAL START BIAS location in Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[playerNum + 1] = true;
					iNumCoastalCivsRemaining = iNumCoastalCivsRemaining - 1;
					local a, b, c = IdentifyTableIndex(civs_needing_coastal_start, playerNum)
					if a then
						table.remove(civs_needing_coastal_start, c[1]);
					end
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
				else
					-- Out of coastal starts, assign this civ to region with lake start.
					local choose_this_region = shuffled_lake_regions[current_lake_index];
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[playerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", playerNum, "with Coastal Bias assigned a fallback Lake location in Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[playerNum + 1] = true;
					iNumCoastalCivsRemaining = iNumCoastalCivsRemaining - 1;
					local a, b, c = IdentifyTableIndex(civs_needing_coastal_start, playerNum)
					if a then
						table.remove(civs_needing_coastal_start, c[1]);
					end
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
					current_lake_index = current_lake_index + 1;
				end
			end
		--else
			--print("Either no civs required a Coastal Start, or no Coastal Starts were available.");
		end
	end
	
	-- Handle River bias
	if iNumRiverCivs > 0 or iNumCoastalCivsRemaining > 0 then
		-- Generate lists of regions eligible to support a river start.
		local iNumRegionsWithRiverStart, iNumRegionsNearRiverStart, iNumUnassignableRiverStarts = 0, 0, 0;
		for region_number, bAlreadyAssigned in ipairs(region_status) do
			if bAlreadyAssigned == false then
				if self.startLocationConditions[region_number][3] == true then
					iNumRegionsWithRiverStart = iNumRegionsWithRiverStart + 1;
					table.insert(regions_with_river_start, region_number);
				end
			end
		end
		for region_number, bAlreadyAssigned in ipairs(region_status) do
			if bAlreadyAssigned == false then
				if self.startLocationConditions[region_number][4] == true and
				   self.startLocationConditions[region_number][3] == false then
					iNumRegionsNearRiverStart = iNumRegionsNearRiverStart + 1;
					table.insert(regions_with_near_river_start, region_number);
				end
			end
		end
		if iNumRegionsWithRiverStart + iNumRegionsNearRiverStart < iNumRiverCivs then
			iNumUnassignableRiverStarts = iNumRiverCivs - (iNumRegionsWithRiverStart + iNumRegionsNearRiverStart);
		end
		-- Now assign those with river bias to start locations, where possible.
		-- Also handle fallback placement for coastal bias that failed to find a match.
		if iNumRiverCivs - iNumUnassignableRiverStarts > 0 then
			local shuffled_river_civs = GetShuffledCopyOfTable(civs_needing_river_start);
			local shuffled_river_regions, shuffled_near_river_regions;
			if iNumRegionsWithRiverStart > 0 then
				shuffled_river_regions = GetShuffledCopyOfTable(regions_with_river_start);
			end
			if iNumRegionsNearRiverStart > 0 then
				shuffled_near_river_regions = GetShuffledCopyOfTable(regions_with_near_river_start);
			end
			for loop, playerNum in ipairs(shuffled_river_civs) do
				if loop > iNumRiverCivs - iNumUnassignableRiverStarts then
					print("Ran out of River and Near-River start locations to assign to River Bias.");	--TODO: line had been commented out in base CiV
					break
				end
				-- Assign next randomly chosen civ in line to next randomly chosen eligible region.
				if loop <= iNumRegionsWithRiverStart then
					-- Assign this civ to a region with river start.
					local choose_this_region = shuffled_river_regions[loop];
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[playerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", playerNum, "assigned a RIVER START BIAS location in Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[playerNum + 1] = true;
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
				else
					-- Assign this civ to a region where a river is near the start.
					local choose_this_region = shuffled_near_river_regions[loop - iNumRegionsWithRiverStart];
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[playerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", playerNum, "with River Bias assigned a fallback 'near river' location in Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[playerNum + 1] = true;
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
				end
			end
		end
		-- Now handle any fallbacks for unassigned coastal bias.
		if iNumCoastalCivsRemaining > 0 and iNumRiverCivs < iNumRegionsWithRiverStart + iNumRegionsNearRiverStart then
			local iNumFallbacksWithRiverStart, iNumFallbacksNearRiverStart = 0, 0;
			local fallbacks_with_river_start, fallbacks_with_near_river_start = {}, {};
			for region_number, bAlreadyAssigned in ipairs(region_status) do
				if bAlreadyAssigned == false then
					if self.startLocationConditions[region_number][3] == true then
						iNumFallbacksWithRiverStart = iNumFallbacksWithRiverStart + 1;
						table.insert(fallbacks_with_river_start, region_number);
					end
				end
			end
			for region_number, bAlreadyAssigned in ipairs(region_status) do
				if bAlreadyAssigned == false then
					if self.startLocationConditions[region_number][4] == true and
					   self.startLocationConditions[region_number][3] == false then
						iNumFallbacksNearRiverStart = iNumFallbacksNearRiverStart + 1;
						table.insert(fallbacks_with_near_river_start, region_number);
					end
				end
			end
			if iNumFallbacksWithRiverStart + iNumFallbacksNearRiverStart > 0 then
			
				local shuffled_coastal_fallback_civs = GetShuffledCopyOfTable(civs_needing_coastal_start);
				local shuffled_river_fallbacks, shuffled_near_river_fallbacks;
				if iNumFallbacksWithRiverStart > 0 then
					shuffled_river_fallbacks = GetShuffledCopyOfTable(fallbacks_with_river_start);
				end
				if iNumFallbacksNearRiverStart > 0 then
					shuffled_near_river_fallbacks = GetShuffledCopyOfTable(fallbacks_with_near_river_start);
				end
				for loop, playerNum in ipairs(shuffled_coastal_fallback_civs) do
					if loop > iNumFallbacksWithRiverStart + iNumFallbacksNearRiverStart then
						print("Ran out of River and Near-River start locations to assign as fallbacks for Coastal Bias.");	--TODO: Line had been commented out in base CiV
						break
					end
					-- Assign next randomly chosen civ in line to next randomly chosen eligible region.
					if loop <= iNumFallbacksWithRiverStart then
						-- Assign this civ to a region with river start.
						local choose_this_region = shuffled_river_fallbacks[loop];
						local x = self.startingPlots[choose_this_region][1];
						local y = self.startingPlots[choose_this_region][2];
						local plot = Map.GetPlot(x, y);
						local player = Players[playerNum];
						player:SetStartingPlot(plot);
						--print("Player Number", playerNum, "with Coastal Bias assigned a fallback river location in Region#", choose_this_region, "at Plot", x, y);
						region_status[choose_this_region] = true;
						civ_status[playerNum + 1] = true;
						local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
						if a then
							table.remove(regions_still_available, c[1]);
						end
					else
						-- Assign this civ to a region where a river is near the start.
						local choose_this_region = shuffled_near_river_fallbacks[loop - iNumRegionsWithRiverStart];
						local x = self.startingPlots[choose_this_region][1];
						local y = self.startingPlots[choose_this_region][2];
						local plot = Map.GetPlot(x, y);
						local player = Players[playerNum];
						player:SetStartingPlot(plot);
						--print("Player Number", playerNum, "with Coastal Bias assigned a fallback 'near river' location in Region#", choose_this_region, "at Plot", x, y);
						region_status[choose_this_region] = true;
						civ_status[playerNum + 1] = true;
						local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
						if a then
							table.remove(regions_still_available, c[1]);
						end
					end
				end
			end
		end
	end
	
	-- Handle Region Priority
	if iNumPriorityCivs > 0 then
		--print("-"); print("-"); print("--- REGION PRIORITY READOUT ---"); print("-");
		local iNumSinglePriority, iNumMultiPriority, iNumNeedFallbackPriority = 0, 0, 0;
		local single_priority, multi_priority, fallback_priority = {}, {}, {};
		local single_sorted, multi_sorted = {}, {};
		-- Separate priority civs in to two categories: single priority, multiple priority.
		for playerNum, priority_needs in pairs(priority_lists) do
			local len = table.maxn(priority_needs)
			if len == 1 then
				--print("Player#", playerNum, "has a single Region Priority of type", priority_needs[1]);
				local priority_data = {playerNum, priority_needs[1]};
				table.insert(single_priority, priority_data)
				iNumSinglePriority = iNumSinglePriority + 1;
			else
				--print("Player#", playerNum, "has multiple Region Priority, this many types:", len);
				local priority_data = {playerNum, len};
				table.insert(multi_priority, priority_data)
				iNumMultiPriority = iNumMultiPriority + 1;
			end
		end
		-- Single priority civs go first, and will engage fallback methods if no match found.
		if iNumSinglePriority > 0 then
			-- Sort the list so that proper order of execution occurs. (Going to use a blunt method for easy coding.)
			for region_type = 1, 8 do							-- Must expand if new region types are added.
				for loop, data in ipairs(single_priority) do
					if data[2] == region_type then
						--print("Adding Player#", data[1], "to sorted list of single Region Priority.");
						table.insert(single_sorted, data);
					end
				end
			end
			-- Match civs who have a single Region Priority to the region type they need, if possible.
			for loop, data in ipairs(single_sorted) do
				local iPlayerNum = data[1];
				local iPriorityType = data[2];
				--print("* Attempting to assign Player#", iPlayerNum, "to a region of Type#", iPriorityType);
				local bFoundCandidate, candidate_regions = false, {};
				for test_loop, region_number in ipairs(regions_still_available) do
					if self.regionTypes[region_number] == iPriorityType then
						table.insert(candidate_regions, region_number);
						bFoundCandidate = true;
						--print("- - Found candidate: Region#", region_number);
					end
				end
				if bFoundCandidate then
					local diceroll = 1 + Map.Rand(table.maxn(candidate_regions), "Choosing from among Candidate Regions for start bias - LUA");
					local choose_this_region = candidate_regions[diceroll];
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[iPlayerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", iPlayerNum, "with single Region Priority assigned to Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[iPlayerNum + 1] = true;
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
				else
					table.insert(fallback_priority, data)
					iNumNeedFallbackPriority = iNumNeedFallbackPriority + 1;
					--print("Player Number", iPlayerNum, "with single Region Priority was UNABLE to be matched to its type. Added to fallback list.");
				end
			end
		end
		-- Multiple priority civs go next, with fewest regions of priority going first.
		if iNumMultiPriority > 0 then
			for iNumPriorities = 2, 8 do						-- Must expand if new region types are added.
				for loop, data in ipairs(multi_priority) do
					if data[2] == iNumPriorities then
						--print("Adding Player#", data[1], "to sorted list of multi Region Priority.");
						table.insert(multi_sorted, data);
					end
				end
			end
			-- Match civs who have mulitple Region Priority to one of the region types they need, if possible.
			for loop, data in ipairs(multi_sorted) do
				local iPlayerNum = data[1];
				local iNumPriorityTypes = data[2];
				--print("* Attempting to assign Player#", iPlayerNum, "to one of its Priority Region Types.");
				local bFoundCandidate, candidate_regions = false, {};
				for test_loop, region_number in ipairs(regions_still_available) do
					for inner_loop = 1, iNumPriorityTypes do
						local region_type_to_test = priority_lists[iPlayerNum][inner_loop];
						if self.regionTypes[region_number] == region_type_to_test then
							table.insert(candidate_regions, region_number);
							bFoundCandidate = true;
							--print("- - Found candidate: Region#", region_number);
						end
					end
				end
				if bFoundCandidate then
					local diceroll = 1 + Map.Rand(table.maxn(candidate_regions), "Choosing from among Candidate Regions for start bias - LUA");
					local choose_this_region = candidate_regions[diceroll];
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[iPlayerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", iPlayerNum, "with multiple Region Priority assigned to Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[iPlayerNum + 1] = true;
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
				--else
					--print("Player Number", iPlayerNum, "with multiple Region Priority was unable to be matched.");
				end
			end
		end
		-- Fallbacks are done (if needed) after multiple-region priority is handled. The list is pre-sorted.
		if iNumNeedFallbackPriority > 0 then
			for loop, data in ipairs(fallback_priority) do
				local iPlayerNum = data[1];
				local iPriorityType = data[2];
				--print("* Attempting to assign Player#", iPlayerNum, "to a fallback region as similar as possible to Region Type#", iPriorityType);
				local choose_this_region = self:FindFallbackForUnmatchedRegionPriority(iPriorityType, regions_still_available)
				if choose_this_region == -1 then
					--print("FAILED to find fallback region bias for player#", iPlayerNum);
				else
					local x = self.startingPlots[choose_this_region][1];
					local y = self.startingPlots[choose_this_region][2];
					local plot = Map.GetPlot(x, y);
					local player = Players[iPlayerNum];
					player:SetStartingPlot(plot);
					--print("Player Number", iPlayerNum, "with single Region Priority assigned to FALLBACK Region#", choose_this_region, "at Plot", x, y);
					region_status[choose_this_region] = true;
					civ_status[iPlayerNum + 1] = true;
					local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
					if a then
						table.remove(regions_still_available, c[1]);
					end
				end
			end
		end
	end
	
	-- Handle Region Avoid
	if iNumAvoidCivs > 0 then
		--print("-"); print("-"); print("--- REGION AVOID READOUT ---"); print("-");
		local avoid_sorted, avoid_unsorted, avoid_counts = {}, {}, {};
		-- Sort list of civs with Avoid needs, then process in reverse order, so most needs goes first.
		for playerNum, avoid_needs in pairs(avoid_lists) do
			local len = table.maxn(avoid_needs)
			--print("- Player#", playerNum, "has this number of Region Avoid needs:", len);
			local avoid_data = {playerNum, len};
			table.insert(avoid_unsorted, avoid_data)
			table.insert(avoid_counts, len)
		end
		table.sort(avoid_counts)
		for loop, avoid_count in ipairs(avoid_counts) do
			for test_loop, avoid_data in ipairs(avoid_unsorted) do
				if avoid_count == avoid_data[2] then
					table.insert(avoid_sorted, avoid_data[1])
					table.remove(avoid_unsorted, test_loop)
				end
			end
		end
		-- Process the Region Avoid needs.
		for loop = iNumAvoidCivs, 1, -1 do
			local iPlayerNum = avoid_sorted[loop];
			local candidate_regions = {};
			for test_loop, region_number in ipairs(regions_still_available) do
				local bFoundCandidate = true;
				for inner_loop, region_type_to_avoid in ipairs(avoid_lists[iPlayerNum]) do
					if self.regionTypes[region_number] == region_type_to_avoid then
						bFoundCandidate = false;
					end
				end
				if bFoundCandidate == true then
					table.insert(candidate_regions, region_number);
					--print("- - Found candidate: Region#", region_number)
				end
			end
			if table.maxn(candidate_regions) > 0 then
				local diceroll = 1 + Map.Rand(table.maxn(candidate_regions), "Choosing from among Candidate Regions for start bias - LUA");
				local choose_this_region = candidate_regions[diceroll];
				local x = self.startingPlots[choose_this_region][1];
				local y = self.startingPlots[choose_this_region][2];
				local plot = Map.GetPlot(x, y);
				local player = Players[iPlayerNum];
				player:SetStartingPlot(plot);
				--print("Player Number", iPlayerNum, "with Region Avoid assigned to allowed region type in Region#", choose_this_region, "at Plot", x, y);
				region_status[choose_this_region] = true;
				civ_status[iPlayerNum + 1] = true;
				local a, b, c = IdentifyTableIndex(regions_still_available, choose_this_region)
				if a then
					table.remove(regions_still_available, c[1]);
				end
			--else
				--print("Player Number", iPlayerNum, "with Region Avoid was unable to avoid the undesired region types.");
			end
		end
	end
				
	-- Assign remaining civs to start plots.
	local playerList, regionList = {}, {};
	for loop = 1, self.iNumCivs do
		local player_ID = self.player_ID_list[loop];
		if civ_status[player_ID + 1] == false then -- Using C++ player ID, which starts at zero. Add 1 for Lua indexing.
			table.insert(playerList, player_ID);
		end
		if region_status[loop] == false then
			table.insert(regionList, loop);
		end
	end
	local iNumRemainingPlayers = table.maxn(playerList);
	local iNumRemainingRegions = table.maxn(regionList);
	if iNumRemainingPlayers > 0 or iNumRemainingRegions > 0 then
		--print("-"); print("Table of players with no start bias:");
		--PrintContentsOfTable(playerList);
		--print("-"); print("Table of regions still available after bias handling:");
		--PrintContentsOfTable(regionList);
		if iNumRemainingPlayers ~= iNumRemainingRegions then
			print("-"); print("ERROR: Number of civs remaining after handling biases does not match number of regions remaining!"); print("-");
		end
		local playerListShuffled = GetShuffledCopyOfTable(playerList)
		for index, player_ID in ipairs(playerListShuffled) do
			local region_number = regionList[index];
			local x = self.startingPlots[region_number][1];
			local y = self.startingPlots[region_number][2];
			--print("Now placing Player#", player_ID, "in Region#", region_number, "at start plot:", x, y);
			local start_plot = Map.GetPlot(x, y)
			local player = Players[player_ID]
			player:SetStartingPlot(start_plot)
		end
	end

	-- If this is a team game (any team has more than one Civ in it) then make 
	-- sure team members start near each other if possible. (This may scramble 
	-- Civ biases in some cases, but there is no cure).
	if self.bTeamGame == true then
		self:NormalizeTeamLocations()
	end
	--	
end
------------------------------------------------------------------------------



