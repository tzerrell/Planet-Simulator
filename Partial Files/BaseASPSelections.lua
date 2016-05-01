function AssignStartingPlots:__CustomInit()
	-- This function included to provide a quick and easy override for changing 
	-- any initial settings. Add your customized version to the map script.
end	
------------------------------------------------------------------------------
function AssignStartingPlots:MeasureStartPlacementFertilityOfPlot(x, y, checkForCoastalLand)
	-- Fertility of plots is used to divide continents or areas in to Regions.
	-- Regions are used to assign starting plots and place some resources.
	-- Usage: x, y are plot coords, with 0,0 in SW. The check is a boolean.
	--
	--[[ Mountain, Oasis, FloodPlain tiles = -2, 5, 6 and do not count anything else.
	     Rest of the tiles add up values of tile traits.
	     Terrain: Grass 4, Plains 3, Tundra 2, Coast 2, Desert 1, Snow -1
	     Features: Hill 1, Forest 1, FreshWater 1, River 1, Jungle -1, Marsh -1, Ice -1
	     We want players who start in Grass to have the least room to expand. ]]--
	--[[ If you modify the terrain values or add or remove any terrain elements, you
		 will need to add or modify processes here to accomodate your changes. Please 
		 be aware that the default process includes numerous assumptions that your
		 terrain changes may invalidate, so you may need to rebalance the system. ]]--
	--
	local plot = Map.GetPlot(x, y);
	local plotFertility = 0;
	local plotType = plot:GetPlotType();
	local terrainType = plot:GetTerrainType();
	local featureType = plot:GetFeatureType();
	-- Measure Fertility -- Any cases absent from the process have a 0 value.
	if plotType == PlotTypes.PLOT_MOUNTAIN then -- Note, mountains cannot belong to a landmass AreaID, so they usually go unmeasured.
		plotFertility = -2;
	elseif terrainType == TerrainTypes.TERRAIN_SNOW then
		plotFertility = -1;
	elseif featureType == FeatureTypes.FEATURE_OASIS then
		plotFertility = 4; -- Reducing Oasis value slightly. -1/26/2011 BT
	elseif featureType == FeatureTypes.FEATURE_FLOOD_PLAINS then
		plotFertility = 5; -- Reducing Flood Plains value slightly. -1/26/2011 BT
	else
		if terrainType == TerrainTypes.TERRAIN_GRASS then -- Reversing values for Grass and Plains. -1/26/2011 BT
			plotFertility = 3;
		elseif terrainType == TerrainTypes.TERRAIN_PLAINS then
			plotFertility = 4;
		elseif terrainType == TerrainTypes.TERRAIN_TUNDRA then
			plotFertility = 2;
		elseif terrainType == TerrainTypes.TERRAIN_COAST then
			plotFertility = 2;
		elseif terrainType == TerrainTypes.TERRAIN_DESERT then
			plotFertility = 1;
		end
		if plotType == PlotTypes.PLOT_HILLS then
			plotFertility = plotFertility + 1;
		end
		if featureType == FeatureTypes.FEATURE_FOREST then
			plotFertility = plotFertility + 0; -- Removing forest bonus as a balance tweak. -1/26/2011 BT
		elseif featureType == FeatureTypes.FEATURE_JUNGLE then
			plotFertility = plotFertility - 1;
		elseif featureType == FeatureTypes.FEATURE_MARSH then
			plotFertility = plotFertility - 2; -- Increasing penalty for Marsh plots. -1/26/2011 BT
		elseif featureType == FeatureTypes.FEATURE_ICE then
			plotFertility = plotFertility - 1;
		end
		if plot:IsRiverSide() then
			plotFertility = plotFertility + 1;
		end
		if plot:IsFreshWater() then
			plotFertility = plotFertility + 1;
		end
		if checkForCoastalLand == true then -- When measuring only one AreaID, this shortcut helps account for coastal plots not measured.
			if plot:IsCoastalLand() then
				plotFertility = plotFertility + 2;
			end
		end
	end

	return plotFertility
end
------------------------------------------------------------------------------
function AssignStartingPlots:GenerateRegions(args)
	print("Map Generation - Dividing the map in to Regions");
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
	print("-"); print("Civs:", self.iNumCivs); print("City States:", self.iNumCityStates);

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
		end ]]--
		print("* * * * * * * * * *");
		for AreaID, fert in pairs(land_area_fert) do
			print("Area ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *");
		--		
		
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

		for AreaID, fert in ipairs(interim_table) do
			print("Interim Table ID " .. AreaID .. " has fertility of " .. fert);
		end
		print("* * * * * * * * * *");

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
				
		-- Debug printout
		print("-"); print("--- Continental Division, Initial Readout ---"); print("-");
		print("- Global Fertility:", iGlobalFertilityOfLands);
		print("- Total Land Plots:", iNumLandPlots);
		print("- Total Areas:", iNumLandAreas);
		print("- Relevant Areas:", iNumRelevantLandAreas); print("-");
		--

		-- Debug printout
		print("* * * * * * * * * *");
		for area_loop, AreaID in ipairs(best_areas) do
			print("Area ID " .. AreaID .. " has fertility of " .. land_area_fert[AreaID]);
		end
		print("* * * * * * * * * *");
		--

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
			print("- - Searching landmasses in order to place Civ #", civToAssign); print("-");
			for area_loop, AreaID in ipairs(best_areas) do
				local thisLandmassCurrentFertility = land_area_fert[AreaID] / (1 + numberOfCivsPerArea[area_loop]);
				if thisLandmassCurrentFertility > bestRemainingFertility then
					bestRemainingArea = AreaID;
					bestRemainingFertility = thisLandmassCurrentFertility;
					bestAreaTableIndex = area_loop;
					--
					print("- Found new candidate landmass with Area ID#:", bestRemainingArea, " with fertility of ", bestRemainingFertility);
				end
			end
			-- Record results for this pass. (A landmass has been assigned to receive one more start point than it previously had).
			numberOfCivsPerArea[bestAreaTableIndex] = numberOfCivsPerArea[bestAreaTableIndex] + 1;
			if TestMembership(inhabitedAreaIDs, bestRemainingArea) == false then
				table.insert(inhabitedAreaIDs, bestRemainingArea);
			end
			print("Civ #", civToAssign, "has been assigned to Area#", bestRemainingArea); print("-");
		end
		print("-"); print("--- End of Initial Readout ---"); print("-");
		
		print("*** Number of Civs per Landmass - Table Readout ***");
		PrintContentsOfTable(numberOfCivsPerArea)
		print("--- End of Civs per Landmass readout ***"); print("-"); print("-");
				
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
			
				-- Debug printout for regional division inputs.
				print("-"); print("- Region #: ", loop);
				print("- Civs on this landmass: ", iNumCivsOnThisLandmass);
				print("- Area ID#: ", currentLandmassID);
				print("- Fertility: ", fertCount);
				print("- Plot Count: ", plotCount); print("-");
				--
			
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
	
	-- Printout is for debugging only. Deactivate otherwise.
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
	--
end
------------------------------------------------------------------------------
function AssignStartingPlots:ExaminePlotForNaturalWondersEligibility(x, y)
	-- This function checks only for eligibility requirements applicable to all 
	-- Natural Wonders. If a candidate plot passes all such checks, we will move
	-- on to checking it against specific needs for each particular NW.
	--
	-- Update, May 2011: Control over NW placement is being migrated to XML. Some checks here moved to there.
	local iW, iH = Map.GetGridSize();
	local plotIndex = iW * y + x + 1;
	-- Check for collision with player starts
	if self.naturalWondersData[plotIndex] > 0 then
		return false
	end
	return true
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceNaturalWonders()
	local NW_eligibility_order = self:GenerateNaturalWondersCandidatePlotLists()
	local iNumNWCandidates = table.maxn(NW_eligibility_order);
	if iNumNWCandidates == 0 then
		print("No Natural Wonders placed, no eligible sites found for any of them.");
		return
	end
	
	print("-"); print("--- Readout of NW Assignment Priority ---");
	for print_loop, order in ipairs(NW_eligibility_order) do
		print("NW Assignment Priority#", print_loop, "goes to NW#", order);
	end
	print("-"); print("-");
	
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
	local target_number = worldsizes[Map.GetWorldSize()];
	local iNumNWtoPlace = math.min(target_number, iNumNWCandidates);
	local selected_NWs, fallback_NWs = {}, {};
	for loop, NW in ipairs(NW_eligibility_order) do
		if loop <= iNumNWtoPlace then
			table.insert(selected_NWs, NW);
		else
			table.insert(fallback_NWs, NW);
		end
	end
	
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
	
	--
	if iNumPlaced >= iNumNWtoPlace then
		print("-- Placed all Natural Wonders --"); print("-"); print("-");
	else
		print("-- Not all Natural Wonders targeted got placed --"); print("-"); print("-");
	end
	--
		
end
------------------------------------------------------------------------------
function AssignStartingPlots:CanPlaceCityStateAt(x, y, area_ID, force_it, ignore_collisions)
	local iW, iH = Map.GetGridSize();
	local plot = Map.GetPlot(x, y)
	local area = plot:GetArea()
	if area ~= area_ID and area_ID ~= -1 then
		return false
	end
	local plotType = plot:GetPlotType()
	if plotType == PlotTypes.PLOT_OCEAN or plotType == PlotTypes.PLOT_MOUNTAIN then
		return false
	end
	local terrainType = plot:GetTerrainType()
	if terrainType == TerrainTypes.TERRAIN_SNOW then
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
function AssignStartingPlots:PlaceCityStateInRegion(city_state_number, region_number)
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
	
	-- Disabling all fallback methods of city state placement. Jon has decided that, rather than
	-- force city states in to locations where they cannot even settle, we will discard them instead.
	--
	-- I am leaving the fallback methods in the code, but disabled, in case they are of any use to modders. - BT
	--[[
	if placed_city_state == false then -- Failed with proximity checks in play. Drop the prox check and force it.
		-- Main loop, second pass, forced
		reached_middle = false;
		local curWX = iWestX;
		local curSY = iSouthY;
		local curWid = iWidth;
		local curHei = iHeight;
		while placed_city_state == false and reached_middle == false do
			-- Send the remaining unprocessed portion of the region to be processed.
			local nextWX, nextSY, nextWid, nextHei;
			eligible_coastal, eligible_inland, nextWX, nextSY, nextWid, nextHei, 
			  reached_middle = self:ObtainNextSectionInRegion(curWX, curSY, curWid, curHei, iAreaID, true, false) -- Force it, but not on top of an already placed player.
			curWX, curSY, curWid, curHei = nextWX, nextSY, nextWid, nextHei;
			-- Attempt to place city state using the two plot lists received from the last call.
			x, y, placed_city_state = self:PlaceCityState(eligible_coastal, eligible_inland, false, false) -- Don't need to re-check collisions.
		end
	end

	if placed_city_state == false then -- Failed even trying to force it. Now allow the CS to be placed on top of another.
		-- Main loop, third pass, forced with collision checks completely disabled.
		reached_middle = false;
		local curWX = iWestX;
		local curSY = iSouthY;
		local curWid = iWidth;
		local curHei = iHeight;
		while placed_city_state == false and reached_middle == false do
			-- Send the remaining unprocessed portion of the region to be processed.
			local nextWX, nextSY, nextWid, nextHei;
			eligible_coastal, eligible_inland, nextWX, nextSY, nextWid, nextHei, 
			  reached_middle = self:ObtainNextSectionInRegion(curWX, curSY, curWid, curHei, iAreaID, true, true) -- Force it any way you can.
			curWX, curSY, curWid, curHei = nextWX, nextSY, nextWid, nextHei;
			-- Attempt to place city state using the two plot lists received from the last call.
			x, y, placed_city_state = self:PlaceCityState(eligible_coastal, eligible_inland, false, false) -- Don't need to re-check collisions.
		end
	end

	if placed_city_state == false then -- Getting desperate to place this city state.
		local fallback_plots, fallback_scores, best_fallback_plots, best_fallback_score = {}, {}, {}, 99999999;
		for region_loop_y = 0, iHeight - 1 do
			for region_loop_x = 0, iWidth - 1 do
				local x = (region_loop_x + iWestX) % iW;
				local y = (region_loop_y + iSouthY) % iH;
				local plotIndex = y * iW + x + 1;
				local plot = Map.GetPlot(x, y);
				local plotType = plot:GetPlotType()
				local terrainType = plot:GetTerrainType()
				local featureType = plot:GetFeatureType()
				--
				local iPlotScore = 1 + self.cityStateData[plotIndex];
				if self.playerCollisionData[plotIndex] == true then
					iPlotScore = iPlotScore * 1000;
				end
				if plotType == PlotTypes.PLOT_OCEAN then
					iPlotScore = iPlotScore * 10;
				elseif plotType == PlotTypes.PLOT_MOUNTAIN then
					iPlotScore = iPlotScore * 2;
				elseif terrainType == TerrainTypes.TERRAIN_SNOW then
					iPlotScore = iPlotScore * 3;
				end
				table.insert(fallback_plots, plotIndex);
				table.insert(fallback_scores, iPlotScore);
			end
		end
		for loop, iPlotScore in ipairs(fallback_scores) do
			if iPlotScore < best_fallback_score then
				best_fallback_score = iPlotScore;
			end
		end
		for loop, iPlotScore in ipairs(fallback_scores) do
			if iPlotScore == best_fallback_score then
				table.insert(best_fallback_plots, fallback_plots[loop]);
			end
		end
		local iNumFallbackCandidates = table.maxn(best_fallback_plots);
		local selectedPlotIndex;
		if iNumFallbackCandidates > 0 then
			local diceroll = 1 + Map.Rand(iNumFallbackCandidates, "City State Placement fallback plot - Lua");
			selectedPlotIndex = best_fallback_plots[diceroll];
			x = (selectedPlotIndex - 1) % iW;
			y = (selectedPlotIndex - x - 1) / iW;
			placed_city_state = true;
			local plot = Map.GetPlot(x, y);
			local plotType = plot:GetPlotType()
			if plotType == PlotTypes.PLOT_OCEAN or plotType == PlotTypes.PLOT_MOUNTAIN then
				plot:SetPlotType(PlotTypes.PLOT_LAND, false, false)
			end
			plot:SetTerrainType(TerrainTypes.TERRAIN_PLAINS, false, true)
			plot:SetFeatureType(FeatureTypes.NO_FEATURE, -1)
			print("-"); print("Forced placement on emergency fallback plot for City State #", city_state_number); print("-");
		else
			print("ERROR: Can't find any water, mountains, or land in this region. ... Yup, it's bad.");
		end
	end
	]]--

	if placed_city_state == true then
		-- Record and enact the placement.
		self.cityStatePlots[city_state_number] = {x, y, region_number};
		self.city_state_validity_table[city_state_number] = true; -- This is the line that marks a city state as valid to be processed by the rest of the system.
		local city_state_ID = city_state_number + GameDefines.MAX_MAJOR_CIVS - 1;
		local cityState = Players[city_state_ID];
		local cs_start_plot = Map.GetPlot(x, y)
		cityState:SetStartingPlot(cs_start_plot)
		self:GenerateLuxuryPlotListsAtCitySite(x, y, 1, true) -- Removes Feature Ice from coasts adjacent to the city state's new location
		self:PlaceResourceImpact(x, y, 5, 4) -- City State layer
		self:PlaceResourceImpact(x, y, 2, 3) -- Luxury layer
		self:PlaceResourceImpact(x, y, 1, 0) -- Strategic layer, at start point only.
		self:PlaceResourceImpact(x, y, 3, 3) -- Bonus layer
		self:PlaceResourceImpact(x, y, 4, 3) -- Fish layer
		self:PlaceResourceImpact(x, y, 7, 3) -- Marble layer
		local impactPlotIndex = y * iW + x + 1;
		self.playerCollisionData[impactPlotIndex] = true;
		--print("-"); print("City State", city_state_number, "has been started at Plot", x, y, "in Region#", region_number);
	else
		--print("-"); print("WARNING: Crowding issues for City State #", city_state_number, " - Could not find valid site in Region#", region_number);
		self.iNumCityStatesDiscarded = self.iNumCityStatesDiscarded + 1;
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:FixSugarJungles()
	-- Sugar could not be made to look good in both jungle and open/marsh at the same time.
	-- Jon and I decided the best workaround would be to turn any Sugar/Jungle in to Marsh.
	local iW, iH = Map.GetGridSize()
	for y = 0, iH - 1 do
		for x = 0, iW - 1 do
			local plot = Map.GetPlot(x, y)
			if plot:GetResourceType(-1) == self.sugar_ID then
				local featureType = plot:GetFeatureType();
				if featureType == FeatureTypes.FEATURE_JUNGLE then
					local plotType = plot:GetPlotType()
					if plotType ~= PlotTypes.PLOT_LAND then
						plot:SetPlotType(PlotTypes.PLOT_LAND, false, true)
					end
					plot:SetFeatureType(FeatureTypes.FEATURE_MARSH, -1)
					plot:SetTerrainType(TerrainTypes.TERRAIN_GRASS, false, true)
					--
					--print("-"); print("Fixed a Sugar/Jungle at plot", x, y);
				end
			end
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:ProcessResourceList(frequency, impact_table_number, plot_list, resources_to_place)
	-- This function needs to receive two numbers and two tables.
	-- Length of the plotlist is divided by frequency to get the number of 
	-- resources to place. ... The first table is a list of plot indices.
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
						if res_plot:GetResourceType(-1) == -1 then -- Placing this strategic resource in this plot.
							local res_addition = 0;
							if res_range[use_this_res_index] ~= -1 then
								res_addition = Map.Rand(res_range[use_this_res_index], "Resource Radius - Place Resource LUA");
							end
							--print("ProcessResourceList table 1, Resource: " .. res_ID[use_this_res_index] .. ", Quantity: " .. res_quantity[use_this_res_index]);
							res_plot:SetResourceType(res_ID[use_this_res_index], res_quantity[use_this_res_index]);
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
						if res_plot:GetResourceType(-1) == -1 then -- Placing this luxury resource in this plot.
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
						if res_plot:GetResourceType(-1) == -1 then -- Placing this bonus resource in this plot.
							local res_addition = 0;
							if res_range[use_this_res_index] ~= -1 then
								res_addition = Map.Rand(res_range[use_this_res_index], "Resource Radius - Place Resource LUA");
							end
							--print("ProcessResourceList table 3, Resource: " .. res_ID[use_this_res_index] .. ", Quantity: " .. res_quantity[use_this_res_index]);
							res_plot:SetResourceType(res_ID[use_this_res_index], res_quantity[use_this_res_index]);
							self:PlaceResourceImpact(x, y, impact_table_number, res_min[use_this_res_index] + res_addition);
							placed_this_res = true;
							self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] = self.amounts_of_resources_placed[res_ID[use_this_res_index] + 1] + 1;
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
						if res_plot:GetResourceType(-1) == -1 then
							lowest_impact = self.strategicData[plotIndex];
							best_plot = plotIndex;
						end
					end
				elseif impact_table_number == 2 then
					if lowest_impact > self.luxuryData[plotIndex] then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType(-1) == -1 then
							lowest_impact = self.luxuryData[plotIndex];
							best_plot = plotIndex;
						end
					end
				elseif impact_table_number == 3 then
					if lowest_impact > self.bonusData[plotIndex] then
						local x = (plotIndex - 1) % iW;
						local y = (plotIndex - x - 1) / iW;
						local res_plot = Map.GetPlot(x, y)
						if res_plot:GetResourceType(-1) == -1 then
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
function AssignStartingPlots:PlaceSpecificNumberOfResources(resource_ID, quantity, amount,
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
	end
	local iW, iH = Map.GetGridSize();
	local iNumLeftToPlace = amount;
	local iNumPlots = table.maxn(plot_list);
	local iNumResources = math.min(amount, math.ceil(ratio * iNumPlots));
	-- Main loop
	for place_resource = 1, iNumResources do
		for loop, plotIndex in ipairs(plot_list) do
			if bCheckImpact == false or impact_table[plotIndex] == 0 then
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
function AssignStartingPlots:GetMajorStrategicResourceQuantityValues()
	-- This function determines quantity per tile for each strategic resource's major deposit size.
	-- Note: scripts that cannot place Oil in the sea need to increase amounts on land to compensate.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 4, 4, 7, 6, 7, 8;
	-- Check the resource setting.
	if self.resource_setting == 1 then -- Sparse
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 4, 5, 4, 5, 5;
	elseif self.resource_setting == 3 then -- Abundant
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 4, 6, 9, 9, 10, 10;
	end
	return uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt
end
------------------------------------------------------------------------------
function AssignStartingPlots:GetSmallStrategicResourceQuantityValues()
	-- This function determines quantity per tile for each strategic resource's small deposit size.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 2, 2, 3, 2, 3, 3;
	-- Check the resource setting.
	if self.resource_setting == 1 then -- Sparse
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 1, 1, 2, 1, 2, 2;
	elseif self.resource_setting == 3 then -- Abundant
		uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = 3, 3, 3, 3, 3, 3;
	end
	return uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceOilInTheSea()
	-- Places sources of Oil in Coastal waters, equal to half what's on the 
	-- land. If the map has too little ocean, then whatever will fit.
	--
	-- WARNING: This operation will render the Strategic Resource Impact Table useless for
	-- further operations, so should always be called last, even after minor placements.
	local sea_oil_amt = 4;
	if self.resource_setting == 3 then -- Abundant Resources, increase amount.
		sea_oil_amt = 6;
	end
	local iNumLandOilUnits = self.amounts_of_resources_placed[self.oil_ID + 1];
	local iNumToPlace = math.floor((iNumLandOilUnits / 2) / sea_oil_amt);

	--print("Adding Oil resources to the Sea.");
	self:PlaceSpecificNumberOfResources(self.oil_ID, sea_oil_amt, iNumToPlace, 0.2, 1, 4, 7, self.coast_list)
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceStrategicAndBonusResources()
	-- KEY: {Resource ID, Quantity (0 = unquantified), weighting, minimum radius, maximum radius}
	-- KEY: (frequency (1 per n plots in the list), impact list number, plot list, resource data)
	--
	-- The radius creates a zone around the plot that other resources of that
	-- type will avoid if possible. See ProcessResourceList for impact numbers.
	--
	-- Order of placement matters, so changing the order may affect a later dependency.
	
	-- Adjust amounts, if applicable, based on Resource Setting.
	local uran_amt, horse_amt, oil_amt, iron_amt, coal_amt, alum_amt = self:GetMajorStrategicResourceQuantityValues()

	-- Adjust appearance rate per Resource Setting chosen by user.
	local bonus_multiplier = 1;
	if self.resource_setting == 1 then -- Sparse, so increase the number of tiles per bonus.
		bonus_multiplier = 1.5;
	elseif self.resource_setting == 3 then -- Abundant, so reduce the number of tiles per bonus.
		bonus_multiplier = 0.66667;
	end

	-- Place Strategic resources.
	print("Map Generation - Placing Strategics");
	local resources_to_place = {
	{self.oil_ID, oil_amt, 65, 1, 1},
	{self.uranium_ID, uran_amt, 35, 0, 1} };
	self:ProcessResourceList(9, 1, self.marsh_list, resources_to_place)

	local resources_to_place = {
	{self.oil_ID, oil_amt, 40, 1, 2},
	{self.aluminum_ID, alum_amt, 15, 1, 2},
	{self.iron_ID, iron_amt, 45, 1, 2} };
	self:ProcessResourceList(16, 1, self.tundra_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.oil_ID, oil_amt, 60, 1, 1},
	{self.aluminum_ID, alum_amt, 15, 2, 3},
	{self.iron_ID, iron_amt, 25, 2, 3} };
	self:ProcessResourceList(17, 1, self.snow_flat_list, resources_to_place)

	local resources_to_place = {
	{self.oil_ID, oil_amt, 65, 0, 1},
	{self.iron_ID, iron_amt, 35, 1, 1} };
	self:ProcessResourceList(13, 1, self.desert_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.iron_ID, iron_amt, 26, 0, 2},
	{self.coal_ID, coal_amt, 35, 1, 3},
	{self.aluminum_ID, alum_amt, 39, 2, 3} };
	self:ProcessResourceList(22, 1, self.hills_list, resources_to_place)

	local resources_to_place = {
	{self.coal_ID, coal_amt, 30, 1, 2},
	{self.uranium_ID, uran_amt, 70, 1, 2} };
	self:ProcessResourceList(33, 1, self.jungle_flat_list, resources_to_place)
	local resources_to_place = {
	{self.coal_ID, coal_amt, 30, 1, 2},
	{self.uranium_ID, uran_amt, 70, 1, 1} };
	self:ProcessResourceList(39, 1, self.forest_flat_list, resources_to_place)

	local resources_to_place = {
	{self.horse_ID, horse_amt, 100, 2, 5} };
	self:ProcessResourceList(33, 1, self.dry_grass_flat_no_feature, resources_to_place)
	local resources_to_place = {
	{self.horse_ID, horse_amt, 100, 1, 4} };
	self:ProcessResourceList(33, 1, self.plains_flat_no_feature, resources_to_place)

	self:AddModernMinorStrategicsToCityStates() -- Added spring 2011
	
	self:PlaceSmallQuantitiesOfStrategics(23 * bonus_multiplier, self.land_list);
	
	self:PlaceOilInTheSea();

	
	-- Check for low or missing Strategic resources
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
	
	
	-- Place Bonus Resources
	print("Map Generation - Placing Bonuses");
	self:PlaceFish(10 * bonus_multiplier, self.coast_list);
	self:PlaceSexyBonusAtCivStarts()
	self:AddExtraBonusesToHillsRegions()
	
	local resources_to_place = {
	{self.deer_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(8 * bonus_multiplier, 3, self.extra_deer_list, resources_to_place)

	local resources_to_place = {
	{self.wheat_ID, 1, 100, 0, 2} };
	self:ProcessResourceList(10 * bonus_multiplier, 3, self.desert_wheat_list, resources_to_place)

	local resources_to_place = {
	{self.deer_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(12 * bonus_multiplier, 3, self.tundra_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.banana_ID, 1, 100, 0, 3} };
	self:ProcessResourceList(14 * bonus_multiplier, 3, self.banana_list, resources_to_place)

	local resources_to_place = {
	{self.wheat_ID, 1, 100, 2, 3} };
	self:ProcessResourceList(50 * bonus_multiplier, 3, self.plains_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.bison_ID, 1, 100, 2, 3} };
	self:ProcessResourceList(60 * bonus_multiplier, 3, self.plains_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.cow_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(18 * bonus_multiplier, 3, self.grass_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.stone_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(30 * bonus_multiplier, 3, self.dry_grass_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.bison_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(50 * bonus_multiplier, 3, self.dry_grass_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.sheep_ID, 1, 100, 1, 1} };
	self:ProcessResourceList(13 * bonus_multiplier, 3, self.hills_open_list, resources_to_place)

	local resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(15 * bonus_multiplier, 3, self.tundra_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.stone_ID, 1, 100, 1, 2} };
	self:ProcessResourceList(19 * bonus_multiplier, 3, self.desert_flat_no_feature, resources_to_place)

	local resources_to_place = {
	{self.deer_ID, 1, 100, 3, 4} };
	self:ProcessResourceList(25 * bonus_multiplier, 3, self.forest_flat_that_are_not_tundra, resources_to_place)
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceFish(frequency, plot_list)
	-- This function places fish at members of plot_list. (Sounds fishy to me!)
	if plot_list == nil then
		--print("No fish were placed! -PlaceFish");
		return
	end
	local iW, iH = Map.GetGridSize();
	local iNumTotalPlots = table.maxn(plot_list);
	local iNumFishToPlace = math.ceil(iNumTotalPlots / frequency);
	-- Main loop
	local current_index = 1;
	for place_resource = 1, iNumFishToPlace do
		local placed_this_res = false;
		if current_index <= iNumTotalPlots then
			for index_to_check = current_index, iNumTotalPlots do
				if placed_this_res == true then
					break
				else
					current_index = current_index + 1;
				end
				local plotIndex = plot_list[index_to_check];
				if self.fishData[plotIndex] == 0 then
					local x = (plotIndex - 1) % iW;
					local y = (plotIndex - x - 1) / iW;
					local res_plot = Map.GetPlot(x, y)
					if res_plot:GetResourceType(-1) == -1 then
						-- Placing fish here. First decide impact radius of this fish.
						local fish_radius = Map.Rand(7, "Fish Radius - Place Fish LUA");
						if fish_radius > 5 then
							fish_radius = 3;
						end
						res_plot:SetResourceType(self.fish_ID, 1);
						self:PlaceResourceImpact(x, y, 4, fish_radius);
						placed_this_res = true;
						self.amounts_of_resources_placed[self.fish_ID + 1] = self.amounts_of_resources_placed[self.fish_ID + 1] + 1;
					end
				end
			end
		end
	end
end
------------------------------------------------------------------------------
function AssignStartingPlots:PlaceResourcesAndCityStates()
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

	-- Place Strategic and Bonus resources.
	self:PlaceStrategicAndBonusResources()

	print("Map Generation - Normalize City State Locations");
	self:NormalizeCityStateLocations()
	
	-- Fix Sugar graphics
	self:FixSugarJungles()
	
	-- Necessary to implement placement of Natural Wonders, and possibly other plot-type changes.
	-- This operation must be saved for last, as it invalidates all regional data by resetting Area IDs.
	Map.RecalculateAreas();

	-- Activate for debug only
	self:PrintFinalResourceTotalsToLog()
	--
end
------------------------------------------------------------------------------
function AssignStartingPlots:NormalizeStartLocation(region_number)
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
function AssignStartingPlots:BalanceAndAssign()
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
		print("Player", playerNum, "of Civ Type", civType);
		local bNeedsCoastalStart = CivNeedsCoastalStart(civType)
		if bNeedsCoastalStart == true then
			print("- - - - - - - needs Coastal Start!"); print("-");
			iNumCoastalCivs = iNumCoastalCivs + 1;
			iNumCoastalCivsRemaining = iNumCoastalCivsRemaining + 1;
			table.insert(civs_needing_coastal_start, playerNum);
			local bPlaceFirst = CivNeedsPlaceFirstCoastalStart(civType);
			if bPlaceFirst then
				print("- - - - - - - needs to Place First!"); print("-");
				table.insert(civs_priority_coastal_start, playerNum);
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
	
	print("Civs with Coastal Bias:", iNumCoastalCivs);
	print("Civs with River Bias:", iNumRiverCivs);
	print("Civs with Region Priority:", iNumPriorityCivs);
	print("Civs with Region Avoid:", iNumAvoidCivs); print("-");
	
	-- Handle Coastal Start Bias
	if iNumCoastalCivs > 0 then
		-- Generate lists of regions eligible to support a coastal start.
		local iNumRegionsWithCoastalStart, iNumRegionsWithLakeStart, iNumUnassignableCoastStarts = 0, 0, 0;
		for region_number, bAlreadyAssigned in ipairs(region_status) do
			if bAlreadyAssigned == false then
				if self.startLocationConditions[region_number][1] == true then
					print("Region#", region_number, "has a Coastal Start.");
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
						print("Region#", region_number, "has a Lake Start.");
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
		print("iNumCoastalCivs: " .. iNumCoastalCivs);
		print("iNumUnassignableCoastStarts: " .. iNumUnassignableCoastStarts);
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
				print("shuffled_coastal_civs[" .. loop .. "]: " .. iPlayerNum);
			end
			
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
					--print("Ran out of Coastal and Lake start locations to assign to Coastal Bias.");
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
					--print("Ran out of River and Near-River start locations to assign to River Bias.");
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
						--print("Ran out of River and Near-River start locations to assign as fallbacks for Coastal Bias.");
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
