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

	-------------------------------------------------------------------------------------------
	--Landmass constants
	-------------------------------------------------------------------------------------------
	--(Moved)mconst.landPercent = 0.31 		--Now in InitializeSeaLevel()
	mconst:InitializeSeaLevel()
	--(Moved)mconst.hillsPercent = 0.70 		--Now in InitializeWorldAge()
	--(Moved)mconst.mountainsPercent = 0.94 	--Now in InitializeWorldAge()
	mconst.landPercentCheat = 0.01	--What proportion of total tiles more continental plate tiles there are than
									--land tiles (at least in terms of the goal; actually results depend on
									--plate generation and can vary). This value tends to not create lakes or
									--islands other than ones we deliberately added. (Larger numbers may lead to
									--lakes and smaller numbers to islands, but this is inconsistent.)
									--Note that this is changed by InitializeIslands() in some cases.
	mconst.continentalPercent = mconst.landPercent + mconst.landPercentCheat	--Percent of tiles on continental/pangeal plates

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
	--Important latitude markers used for generating climate. (TODO: Consider switching to BE script values)
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
	mconst.polarRainBoost = 0.00	--TODO: Consider adjusting this and next to BE script values
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

	mconst.MultiPlayer = Game:IsNetworkMultiPlayer()

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
		
		self.treesMinTemperature = 0.22
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
		
		self.treesMinTemperature = 0.28		--Coldest absolute temperature where trees appear.
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
					"Pangaea",
					"Other (n/a)"
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
--TODO: Can remove from here?
-----------------------------------------------------------------------------
--Interpolation and Perlin functions
-----------------------------------------------------------------------------
function CubicInterpolate(v0,v1,v2,v3,mu)
	local mu2 = mu * mu
	local a0 = v3 - v2 - v0 + v1
	local a1 = v0 - v1 - a0
	local a2 = v2 - v0
	local a3 = v1

	return (a0 * mu * mu2 + a1 * mu2 + a2 * mu + a3)
end
-------------------------------------------------------------------------------------------
function BicubicInterpolate(v,muX,muY)
	local a0 = CubicInterpolate(v[1],v[2],v[3],v[4],muX);
	local a1 = CubicInterpolate(v[5],v[6],v[7],v[8],muX);
	local a2 = CubicInterpolate(v[9],v[10],v[11],v[12],muX);
	local a3 = CubicInterpolate(v[13],v[14],v[15],v[16],muX);

	return CubicInterpolate(a0,a1,a2,a3,muY)
end
-------------------------------------------------------------------------------------------
function CubicDerivative(v0,v1,v2,v3,mu)
	local mu2 = mu * mu
	local a0 = v3 - v2 - v0 + v1
	local a1 = v0 - v1 - a0
	local a2 = v2 - v0
	--local a3 = v1

	return (3 * a0 * mu2 + 2 * a1 * mu + a2)
end
-------------------------------------------------------------------------------------------
function BicubicDerivative(v,muX,muY)
	local a0 = CubicInterpolate(v[1],v[2],v[3],v[4],muX);
	local a1 = CubicInterpolate(v[5],v[6],v[7],v[8],muX);
	local a2 = CubicInterpolate(v[9],v[10],v[11],v[12],muX);
	local a3 = CubicInterpolate(v[13],v[14],v[15],v[16],muX);

	return CubicDerivative(a0,a1,a2,a3,muY)
end
-------------------------------------------------------------------------------------------
--This function gets a smoothly interpolated value from srcMap.
--x and y are non-integer coordinates of where the value is to
--be calculated, and wrap in both directions. srcMap is an object
--of type FloatMap.
function GetInterpolatedValue(X,Y,srcMap)
	local points = {}
	local fractionX = X - math.floor(X)
	local fractionY = Y - math.floor(Y)

	--wrappedX and wrappedY are set to -1,-1 of the sampled area
	--so that the sample area is in the middle quad of the 4x4 grid
	local wrappedX = ((math.floor(X) - 1) % srcMap.rectWidth) + srcMap.rectX
	local wrappedY = ((math.floor(Y) - 1) % srcMap.rectHeight) + srcMap.rectY

	local x
	local y

	for pY = 0, 4-1,1 do
		y = pY + wrappedY
		for pX = 0,4-1,1 do
			x = pX + wrappedX
			local srcIndex = srcMap:GetRectIndex(x,y)
			points[(pY * 4 + pX) + 1] = srcMap.data[srcIndex]
		end
	end

	local finalValue = BicubicInterpolate(points,fractionX,fractionY)

	return finalValue

end
-------------------------------------------------------------------------------------------
function GetDerivativeValue(X,Y,srcMap)
	local points = {}
	local fractionX = X - math.floor(X)
	local fractionY = Y - math.floor(Y)

	--wrappedX and wrappedY are set to -1,-1 of the sampled area
	--so that the sample area is in the middle quad of the 4x4 grid
	local wrappedX = ((math.floor(X) - 1) % srcMap.rectWidth) + srcMap.rectX
	local wrappedY = ((math.floor(Y) - 1) % srcMap.rectHeight) + srcMap.rectY

	local x
	local y

	for pY = 0, 4-1,1 do
		y = pY + wrappedY
		for pX = 0,4-1,1 do
			x = pX + wrappedX
			local srcIndex = srcMap:GetRectIndex(x,y)
			points[(pY * 4 + pX) + 1] = srcMap.data[srcIndex]
		end
	end

	local finalValue = BicubicDerivative(points,fractionX,fractionY)

	return finalValue

end
-------------------------------------------------------------------------------------------
--This function gets Perlin noise for the destination coordinates. Note
--that in order for the noise to wrap, the area sampled on the noise map
--must change to fit each octave.
function GetPerlinNoise(x,y,destMapWidth,destMapHeight,initialFrequency,initialAmplitude,amplitudeChange,octaves,noiseMap)
	local finalValue = 0.0
	local frequency = initialFrequency
	local amplitude = initialAmplitude
	local frequencyX --slight adjustment for seamless wrapping
	local frequencyY --''
	for i = 1,octaves,1 do
		if noiseMap.wrapX then
			noiseMap.rectX = math.floor(noiseMap.width/2 - (destMapWidth * frequency)/2)
			noiseMap.rectWidth = math.max(math.floor(destMapWidth * frequency),1)
			frequencyX = noiseMap.rectWidth/destMapWidth
		else
			noiseMap.rectX = 0
			noiseMap.rectWidth = noiseMap.width
			frequencyX = frequency
		end
		if noiseMap.wrapY then
			noiseMap.rectY = math.floor(noiseMap.height/2 - (destMapHeight * frequency)/2)
			noiseMap.rectHeight = math.max(math.floor(destMapHeight * frequency),1)
			frequencyY = noiseMap.rectHeight/destMapHeight
		else
			noiseMap.rectY = 0
			noiseMap.rectHeight = noiseMap.height
			frequencyY = frequency
		end

		finalValue = finalValue + GetInterpolatedValue(x * frequencyX, y * frequencyY, noiseMap) * amplitude
		frequency = frequency * 2.0
		amplitude = amplitude * amplitudeChange
	end
	finalValue = finalValue/octaves
	return finalValue
end
-------------------------------------------------------------------------------------------
function GetPerlinDerivative(x,y,destMapWidth,destMapHeight,initialFrequency,initialAmplitude,amplitudeChange,octaves,noiseMap)
	local finalValue = 0.0
	local frequency = initialFrequency
	local amplitude = initialAmplitude
	local frequencyX --slight adjustment for seamless wrapping
	local frequencyY --''
	for i = 1,octaves,1 do
		if noiseMap.wrapX then
			noiseMap.rectX = math.floor(noiseMap.width/2 - (destMapWidth * frequency)/2)
			noiseMap.rectWidth = math.floor(destMapWidth * frequency)
			frequencyX = noiseMap.rectWidth/destMapWidth
		else
			noiseMap.rectX = 0
			noiseMap.rectWidth = noiseMap.width
			frequencyX = frequency
		end
		if noiseMap.wrapY then
			noiseMap.rectY = math.floor(noiseMap.height/2 - (destMapHeight * frequency)/2)
			noiseMap.rectHeight = math.floor(destMapHeight * frequency)
			frequencyY = noiseMap.rectHeight/destMapHeight
		else
			noiseMap.rectY = 0
			noiseMap.rectHeight = noiseMap.height
			frequencyY = frequency
		end

		finalValue = finalValue + GetDerivativeValue(x * frequencyX, y * frequencyY, noiseMap) * amplitude
		frequency = frequency * 2.0
		amplitude = amplitude * amplitudeChange
	end
	finalValue = finalValue/octaves
	return finalValue
end
-------------------------------------------------------------------------------------------
function Push(a,item)
	table.insert(a,item)
end
-------------------------------------------------------------------------------------------
function Pop(a)
	return table.remove(a)
end
--TODO: Can remove to here?
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
							--TODO a break here prevents multiple rolls for same tile touched by multiple tiles of this plate. BE script has that, probably I should too?
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
		print(string.format("Sum of uplift coefficient values in excess of 1 insufficient at %.2f; adding failsafe mountains", currentUplifted))
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
--[[function GenerateTwistedPerlinMap(width, height, xWrap, yWrap,minFreq,maxFreq,varFreq)
	local inputNoise = FloatMap:New(width,height,xWrap,yWrap)
	inputNoise:GenerateNoise()
	inputNoise:Normalize()

	local freqMap = FloatMap:New(width,height,xWrap,yWrap)
	local i = 0
	for y = 0, freqMap.height - 1,1 do
		for x = 0,freqMap.width - 1,1 do
			local odd = y % 2
			local xx = x + odd * 0.5
			freqMap.data[i] = GetPerlinNoise(xx,y * mc.YtoXRatio,freqMap.width,freqMap.height * mc.YtoXRatio,varFreq,1.0,0.1,8,inputNoise)
			i=i+1
		end
	end
	freqMap:Normalize()
--	freqMap:Save("freqMap.csv")

	local twistMap = FloatMap:New(width,height,xWrap,yWrap)
	i = 0
	for y = 0, twistMap.height - 1,1 do
		for x = 0,twistMap.width - 1,1 do
			local freq = freqMap.data[i] * (maxFreq - minFreq) + minFreq
			local mid = (maxFreq - minFreq)/2 + minFreq
			local coordScale = freq/mid
			local offset = (1.0 - coordScale)/mid
			--print("1-coordscale = " .. (1.0 - coordScale) .. ", offset = " .. offset)
			local ampChange = 0.85 - freqMap.data[i] * 0.5
			local odd = y % 2
			local xx = x + odd * 0.5
			twistMap.data[i] = GetPerlinNoise(xx + offset,(y + offset) * mc.YtoXRatio,twistMap.width,twistMap.height * mc.YtoXRatio,mid,1.0,ampChange,8,inputNoise)
			i=i+1
		end
	end

	twistMap:Normalize()
	--twistMap:Save("twistMap.csv")
	return twistMap
end]]
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

	rainfallMap, temperatureMap = GenerateRainfallMap(elevationMap)
	riverMap = RiverMap:New(elevationMap)
	riverMap:SetJunctionAltitudes()
	riverMap:SiltifyLakes()
	riverMap:SetFlowDestinations()
	riverMap:SetRiverSizes(rainfallMap)
	--Debug -- doesn't work
	--riverMap:Save4("riverMap.data.csv",5)

	GenerateCoasts({expansion_diceroll_table = mc.coastExpansionChance});

	--removes "ocean" tiles from inland seas
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
				--print("Inland sea, covering "..PlateMap.size[n].." tiles, detected at plate: "..PlateMap.index[n].." - Planet Simulator")
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
					if plot:GetPlotType() == PlotTypes.PLOT_OCEAN then
						local lat = elevationMap:GetLatitudeForY(y)
						if lat < mc.iceNorthLatitudeLimit and lat > mc.iceSouthLatitudeLimit then
							local roll = PWRandInt(0,100)
							if roll > 15 then
								plot:SetTerrainType(GameDefines.SHALLOW_WATER_TERRAIN,false,false)
							elseif roll > 9 then
								plot:SetPlotType(PlotTypes.PLOT_HILLS,false,true)
							else
								plot:SetPlotType(PlotTypes.PLOT_LAND,false,true)
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
