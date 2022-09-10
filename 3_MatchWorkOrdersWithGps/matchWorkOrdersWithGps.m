% MATCHWORKORDERSWITHGPS Based on vehicle ID and data from work orders,
% find and analyze the corresponding GPS tracks.
%
% Yaguang Zhang, Purdue, 08/12/2022

clearvars -except workOrderTable ...
    gpsLocTable indotRoads ROAD_PROJ indotMileMarkers MILE_MARKER_PROJ;
clc; close all; dbstop if error;

% Locate the Matlab workspace and save the current filename.
cd(fileparts(mfilename('fullpath'))); cd('..'); addpath('lib');
curFileName = mfilename;

prepareSimulationEnv;

% The absolute path to the folder for saving results.
pathToSaveResults = fullfile(pwd, '..', ...
    'PostProcessingResults', '3_GpsForWorkOrders');
if ~exist(pathToSaveResults, 'dir')
    mkdir(pathToSaveResults)
end

% The absolute path to the INDOT GPS 2021 winter operation work order .csv
% file.
pathToWorkOrderCsv = fullfile(pwd, '..', ...
    '20220608_WinterOperationRecords', 'Data for JTRP (SPR 4605).xlsx');

% The absolute path to the INDOT GPS 2021 winter operation data .csv file.
pathToGpsLocCsv = fullfile(pwd, '..', ...
    '20220804_IndotGpsData_Winter', ...
    '20220804 AVL GPS Data for Purdue v2 csv', ...
    '20220804 AVL GPS Data for Purdue v2.csv');

% The absolute path to the Howell vehicle inventory .csv files, just in
% case the vehicle ID is not present in the GPS records.
pathToTrackCsv = fullfile(pwd, '..', ...
    '20220221_ExampleData', '20210301_to_20210501_avl', 'truck.csv');
% pathToVehicleInventoryCsv = fullfile(pwd, '..', ...
%     '20220221_ExampleData', '20210301_to_20210501_avl', ...
%     'vehicle_inventory.csv');

% Log the command line output.
diary(fullfile(pathToSaveResults, 'Diary.log'));

% For plotting.
FLAG_SILENT_FIGS = true;
defaultLineColors = [0, 0.4470, 0.7410; ...
    0.8500, 0.3250, 0.0980; ...
    0.9290, 0.6940, 0.1250; ...
    0.4940, 0.1840, 0.5560; ...
    0.4660, 0.6740, 0.1880; ...
    0.3010, 0.7450, 0.9330; ...
    0.6350, 0.0780, 0.1840];

% Time string formats for parsing INDOT data.
INDOT_DATE_FORMAT = 'dd-MMM-yy';
INDOT_TIMESTR_FORMAT = 'dd-MMM-yy hh.mm.ss.SSSSSSSSS a';
% Format to use for storing time as datetime objects in Matlab.
DATETIME_FORMAT = 'yyyy-MM-dd HH:mm:ss';

% Expected time zone.
LOCAL_TIME_ZONE = 'America/Indianapolis';

% Hours to search before the start (00:00:00) of the work order date, just
% in case, e.g., night shifts are involved.
HOURS_BEFORE_WORK_DATE_TO_SEARCH = 24;
% Hours to search before the end (24:00:00) of the work order date, just in
% case, e.g., the work date is mislabeled.
HOURS_AFTER_WORK_DATE_TO_SEARCH = 24;

% Maximum allowed time gap in minutes between continuous activity/GPS
% tracks.
MAX_ALLOWED_TIME_GAP_IN_MIN = 10;

% Flag to enable debug plot generation.
FLAG_GEN_DEBUG_FIGS = true;
NUM_OF_ACT_TRACK_DEBUG_FIGS = 10;

%% Load Work Orders and GPS Tracks

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading work orders and GPS tracks ...'])

absPathToCachedTables = fullfile(pathToSaveResults, 'cachedTables.mat');
if exist(absPathToCachedTables, 'file')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] Raw data processed before. Loading cached results ...'])
    load(absPathToCachedTables);
else
    % For fast debugging, avoid reloading data if they are already loaded.
    if ~exist('workOrderTable', 'var')
        disp(['    [', datestr(now, datetimeFormat), ...
            '] Loading work orders ...'])
        workOrderTable = readtable(pathToWorkOrderCsv);
        workOrderTable = renamevars(workOrderTable, 'WO_', 'WO');

        disp(['    [', datestr(now, datetimeFormat), ...
            '] Converting time stamps to datetime objects ...'])
        workOrderTable.WorkDatetime = ...
            datetime(workOrderTable.WorkDate, ...
            'InputFormat', INDOT_DATE_FORMAT, 'TimeZone', LOCAL_TIME_ZONE, ...
            'Format', DATETIME_FORMAT);

        % Order work order entries.
        workOrderTable = sortrows(workOrderTable, ...
            {'WorkDatetime', 'WO', ...
            'ResourceType', 'ResourceName', 'Route_Ref_'});
    end
    if ~exist('gpsLocTable', 'var')
        disp(' ')
        disp(['    [', datestr(now, datetimeFormat), ...
            '] Loading GPS tracks ...'])
        gpsLocTable = readtable(pathToGpsLocCsv);

        disp(['    [', datestr(now, datetimeFormat), ...
            '] Parsing time stamps ...'])
        indicesEndOfAmOrPmInLocalTimeStrings ...
            = strfind(gpsLocTable.VEHICLE_TIMESTAMP, 'M ');
        indicesEndOfAmOrPmInLocalTimeStrings ...
            = vertcat(indicesEndOfAmOrPmInLocalTimeStrings{:});
        indexEndOfAmOrPmInLocalTimeStrings ...
            = indicesEndOfAmOrPmInLocalTimeStrings(1);

        % Check the time string format.
        assert(all(indicesEndOfAmOrPmInLocalTimeStrings ...
            == indexEndOfAmOrPmInLocalTimeStrings), ...
            'Inconsistent VEHICLE_TIMESTAMP format!')
        % Check local time zone listed in the time string.
        assert(all(contains( ...
            gpsLocTable.VEHICLE_TIMESTAMP, upper(LOCAL_TIME_ZONE)) ...
            ), 'Unexpected time zone found!')

        % Convert time string to datetime for easier processing.
        vehicleTimeStamps = vertcat(gpsLocTable.VEHICLE_TIMESTAMP{:});
        vehicleTimeStamps = vehicleTimeStamps(:, ...
            1:indexEndOfAmOrPmInLocalTimeStrings);

        disp(['    [', datestr(now, datetimeFormat), ...
            '] Converting time stamps to datetime objects ...'])
        gpsLocTable.localDatetime = datetime(vehicleTimeStamps, ...
            'InputFormat', INDOT_TIMESTR_FORMAT, ...
            'TimeZone', LOCAL_TIME_ZONE, ...
            'Format', DATETIME_FORMAT);

        % Order GPS samples.
        gpsLocTable = sortrows(gpsLocTable, ...
            {'localDatetime', 'COMMISION_NUMBER'});
    end

    numOfGpsSamps = size(gpsLocTable, 1);

    % Find road name and mile markers.
    if ~isfield(gpsLocTable, 'roadName')
        disp(['    [', datestr(now, datetimeFormat), ...
            '] Converting GPS (lat, lon) samps to mile markers ...'])

        %   The road name is a string in the form like "S49". We use "S" as
        %   State, "I" as Interstate, "T" as Toll, and "U" as US.
        gpsLocTable.roadName = cell(numOfGpsSamps, 1);
        % The mile marker and, for debugging, the distance to the road.
        [gpsLocTable.mile, gpsLocTable.nearestDist] ...
            = deal(nan(numOfGpsSamps, 1));

        numOfRawGpsRecords = size(gpsLocTable, 1);

        loadIndotMileMarkers;
        loadIndotRoads;
        % To speed road name searching up, discard non-highway roads. We
        % have the patterns below copied from getRoadNameFromRoadSeg.m.
        regPats = {'(SR|State Rd|State Road)( |-|)(\d+)', ...
            '(INTERSTATE HIGHWAY|INTERSTATE|I)( |-|)(\d+)', ...
            '(US|USHY|US HWY|US HIGHWAY|United States Highway)( |-|)(\d+)'};
        numOfIndotRoads = length(indotRoads);
        boolsIndotRoadsToIgnore = false(1, numOfIndotRoads);
        for idxRoad = 1:numOfIndotRoads
            if isempty(regexpi(indotRoads(idxRoad).FULL_STREE, ...
                    regPats{1}, 'once')) ...
                    && isempty(regexpi(indotRoads(idxRoad).FULL_STREE, ...
                    regPats{2}, 'once')) ...
                    && isempty(regexpi(indotRoads(idxRoad).FULL_STREE, ...
                    regPats{3}, 'once'))
                boolsIndotRoadsToIgnore(idxRoad) = true;
            end
        end
        indotRoads(boolsIndotRoadsToIgnore) = [];
        
        % For progress feedback.
        proBar = betterProBar(numOfGpsSamps);
        for idxSamp = 1:numOfGpsSamps
            try
                [gpsLocTable.roadName{idxSamp}, ...
                    gpsLocTable.mile(idxSamp), ...
                    ~, gpsLocTable.nearestDist(idxSamp)] ...
                    = gpsCoor2MileMarker(gpsLocTable.LATITUDE(idxSamp), ...
                    gpsLocTable.LONGITUDE(idxSamp));
            catch
                % Fallback values.
                gpsLocTable.roadName{idxSamp} = '';
            end
            proBar.progress;
        end
        proBar.stop;
    end

    disp(' ')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] Loading GPS tracks ...'])
    save(absPathToCachedTables, 'workOrderTable', 'gpsLocTable');
end

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Extracting and Formatting Needed Information - GPS

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Extracting and formatting needed GPS information ...'])

% Extract needed information.
disp(['    [', datestr(now, datetimeFormat), ...
    '] Parsing vehicle IDs and names ...'])
% Find vehicle IDs and names. Note that the ASSET_LABEL field may not be
% available. If it is present, we will extract vehId accordingly.
% Otherwise, we will "guess" the vehId based on other data sets.
if ~exist('numOfGpsSamps', 'var')
    numOfGpsSamps = size(gpsLocTable, 1);
end
vehIds = nan(numOfGpsSamps, 1);
vehNames = cell(numOfGpsSamps, 1);

% For progress feedback.
proBar = betterProBar(numOfGpsSamps);
% Use 'ASSET_LABEL' when it is available because both vehicle ID and name
% can be extracted. Switch to 'COMMISION_NUMBER' for vehicle ID if
% necessary. As the last resort, if none of these fields are present, we
% will guess the vehicle ID based on history datasets.
if ismember('ASSET_LABEL', gpsLocTable.Properties.VariableNames)
    originalAssetLabels = gpsLocTable.ASSET_LABEL;

    % Break the string into ID and name. Example ASSET_LABEL: "64267 DODGE
    % STRATUS 2002 Automobile +".
    indicesFirstNonNumAssetLabel = strfind(originalAssetLabels, ' ');

    for idxGpsSamp = 1:numOfGpsSamps
        curIdxFirstNonNumAssetLabel ...
            = indicesFirstNonNumAssetLabel{idxGpsSamp}(1);

        % Convert string integer IDs to numbers.
        vehIds(idxGpsSamp) = sscanf( ...
            originalAssetLabels{idxGpsSamp} ...
            (1:(curIdxFirstNonNumAssetLabel-1)), ...
            '%d');

        vehNames{idxGpsSamp} = strtrim( ...
            originalAssetLabels{idxGpsSamp} ...
            ((curIdxFirstNonNumAssetLabel+1):end));

        proBar.progress;
    end
elseif ismember('COMMISION_NUMBER', gpsLocTable.Properties.VariableNames)
    vehIds = gpsLocTable.COMMISION_NUMBER;

    for idxGpsSamp = 1:numOfGpsSamps
        % TODO: veh name does not seem to be available.
        vehNames{idxGpsSamp} = '';

        proBar.progress;
    end
else
    % We will use the inventory information to deduce vehIds and vehNames
    % based on the sensor ID.
    if ~exist('truckTable', 'var')
        truckTable = readtable(pathToTrackCsv);
    end

    for idxGpsSamp = 1:numOfGpsSamps
        % INDOT and Parson's call this vehicleId, but it is essentually the
        % ID for the Parson's GPS sensor.
        curSensorId = gpsLocTable.VEHICLE_ID(idxGpsSamp);
        curIdxTruck = find(truckTable.vehicleId == curSensorId);

        if length(curIdxTruck) == 1
            vehIds(idxGpsSamp) = truckTable.name(curIdxTruck);
        else
            vehIds(idxGpsSamp) = nan;
        end

        % TODO: veh name does not seem to be available.
        vehNames{idxGpsSamp} = '';

        proBar.progress;
    end
end
proBar.stop;

disp(['    [', datestr(now, datetimeFormat), ...
    '] Caching results ...'])

parsedGpsLocTable = table;
parsedGpsLocTable.localDatetime = gpsLocTable.localDatetime;
parsedGpsLocTable.primeKey      = gpsLocTable.PRIMARY_KEY;
parsedGpsLocTable.vehId         = vehIds;
parsedGpsLocTable.vehNames      = vehNames;
parsedGpsLocTable.sensorId      = gpsLocTable.VEHICLE_ID;
parsedGpsLocTable.lat           = gpsLocTable.LATITUDE;
parsedGpsLocTable.lon           = gpsLocTable.LONGITUDE;
parsedGpsLocTable.speedMph      = gpsLocTable.SPEED_MILES_PER_HOUR;
parsedGpsLocTable.heading       = gpsLocTable.VEHICLE_HEADING;
gpsLocTable.roadName = gpsLocTable.roadName;
gpsLocTable.mile = gpsLocTable.mile;
gpsLocTable.nearestDist = gpsLocTable.nearestDist;

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Extracting and Formatting Needed Information - Work Orders

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Extracting and formatting needed work order information ...'])

% We only care about the work order entries for vehicles.
boolsIsEquipment = strcmp(workOrderTable.ResourceType, 'Equipment');
vehWorkOrderTable = workOrderTable(boolsIsEquipment, :);

% Store the indices in workOrderTable for easier raw data retrieval.
vehWorkOrderTable.idxInWorkOrderTable = find(boolsIsEquipment);

% Clean the names, e.g., by removing extra spaces.
originalResNames = vehWorkOrderTable.ResourceName;
originalActivities = vehWorkOrderTable.Activity;

% Break the string by " - " into ID and name. Note that we need to avoid
% modifying '-' in the names.
numOfVehWorkOrders = size(originalResNames, 1);
[vehIds, actIds] = deal(nan(numOfVehWorkOrders, 1));
[vehNames, actNames] = deal(cell(numOfVehWorkOrders, 1));

indicesMinusSignResName = strfind(originalResNames, '-');
indicesMinusSignAct = strfind(originalActivities, '-');

% For progress feedback.
proBar = betterProBar(numOfVehWorkOrders);
for idxVehWorkOrder = 1:numOfVehWorkOrders
    curIdxFirstMinusSignResName ...
        = indicesMinusSignResName{idxVehWorkOrder}(1);
    curIdxFirstMinusSignAct = indicesMinusSignAct{idxVehWorkOrder}(1);

    % Convert string integer IDs to numbers.
    vehIds(idxVehWorkOrder) = sscanf( ...
        originalResNames{idxVehWorkOrder} ...
        (1:(curIdxFirstMinusSignResName-1)), ...
        '%d');
    actIds(idxVehWorkOrder) = sscanf( ...
        originalActivities{idxVehWorkOrder} ...
        (1:(curIdxFirstMinusSignAct-1)), ...
        '%d');

    vehNames{idxVehWorkOrder} = strtrim( ...
        originalResNames{idxVehWorkOrder} ...
        ((curIdxFirstMinusSignResName+1):end));
    actNames{idxVehWorkOrder} = strtrim( ...
        originalActivities{idxVehWorkOrder} ...
        ((curIdxFirstMinusSignAct+1):end));

    proBar.progress;
end
proBar.stop;

assert(all(vehIds==round(vehIds)), 'Non-integer vehicle ID found!')
assert(all(actIds==round(actIds)), 'Non-integer activity ID found!')

disp(['    [', datestr(now, datetimeFormat), ...
    '] Caching results ...'])

parsedVehWorkOrderTable = table;
parsedVehWorkOrderTable.localDatetime = ...
    vehWorkOrderTable.WorkDatetime;
parsedVehWorkOrderTable.workOrderId = vehWorkOrderTable.WO;
parsedVehWorkOrderTable.idxInWorkOrderTable ...
    = vehWorkOrderTable.idxInWorkOrderTable;
parsedVehWorkOrderTable.vehId = vehIds;
parsedVehWorkOrderTable.vehName = vehNames;
parsedVehWorkOrderTable.actId = actIds;
parsedVehWorkOrderTable.actName = actNames;
parsedVehWorkOrderTable.totalHrs = vehWorkOrderTable.TotalHrs;

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Convert Datetime to Epoch
% This will be faster for later comparisons because results will be numbers
% (double) instead of objects.
%
% Example:
%     A = datetime(2013,07,26) + calyears(0:2:6);
%      B = datetime(2014,06,01);
%     AE = convertTo(A, 'posixtime');
%      BE = convertTo(B, 'posixtime');
%     numOfTs = 1000;
%      tic;
%     for idxT = 1:numOfTs
%         A>B;
%     end
%      toc;
%
%      tic;
%     for idxT = 1:numOfTs
%         AE>AE;
%     end
%      toc;
%
% Results:
%     Elapsed time is 0.051813 seconds.
%      Elapsed time is 0.013643 seconds.

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Converting datetime to epoch time ...'])

parsedGpsLocTable.unixTime = posixtime(parsedGpsLocTable.localDatetime);
parsedVehWorkOrderTable.unixTime = posixtime( ...
    parsedVehWorkOrderTable.localDatetime);

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Group Work Orders by Work Order ID and Vehicle ID
% GPS tracks need to be, first, fetched based on the time range
% (associated/indirectly determined by the work order ID) and the vehicle
% ID, and then, broken into continuous tracks. Thus, it is easier to work
% with "work order groups", where each group has all the work order entries
% with the same work order ID and vehicle ID.
%
% Work orders in the same group can be considered as "for the same
% activity". This step will avoid unnecessary/repeated GPS sample
% searching.

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Group work orders into groups based on', ...
    ' work order ID and vehicle ID ...'])

% It is not clear how many work order groups we will get, but it is at
% least the number of unique work order IDs. We will find work order groups
% for each unique work order ID and concatenate the results.
uniqueWOIds = unique(parsedVehWorkOrderTable.workOrderId);
numOfUniqueWOIds = length(uniqueWOIds);

% Cache the work order entry indices as row vectors for each found work
% order group.
cachedEntryIndicesInParsedVehWOT = cell(numOfUniqueWOIds, 1);

disp(['    [', datestr(now, datetimeFormat), ...
    '] Identifying work order groups ...'])
cntWOG = 0;
% For progress feedback.
proBar = betterProBar(numOfUniqueWOIds);
for idxUniqueWOId = 1:numOfUniqueWOIds
    curWOId = uniqueWOIds(idxUniqueWOId);
    curEntryIndicesInParsedVehWOT = find( ...
        parsedVehWorkOrderTable.workOrderId == curWOId);

    curUniqueVehIds = unique( ...
        parsedVehWorkOrderTable.vehId(curEntryIndicesInParsedVehWOT));

    curNumOfUniqueVIDs = length(curUniqueVehIds);
    cachedEntryIndicesInParsedVehWOT{idxUniqueWOId} ...
        = cell(curNumOfUniqueVIDs, 1);
    for curIdxUniqueVID = 1:curNumOfUniqueVIDs
        % Found a new work order group.
        cntWOG = cntWOG + 1;

        curVID = curUniqueVehIds(curIdxUniqueVID);
        cachedEntryIndicesInParsedVehWOT{idxUniqueWOId} ...
            {curIdxUniqueVID} ...
            = (curEntryIndicesInParsedVehWOT( ...
            parsedVehWorkOrderTable.vehId( ...
            curEntryIndicesInParsedVehWOT)==curVID))';
    end

    proBar.progress;
end
proBar.stop;

disp(['    [', datestr(now, datetimeFormat), ...
    '] Creating work order groups ...'])
% Save the results.
numOfEntriesInParsedVehWOT = size(parsedVehWorkOrderTable, 1);
parsedVehWorkOrderTable.idxWorkOrderGroup ...
    = nan(numOfEntriesInParsedVehWOT, 1);
indicesEntryInParsedVehWOT = cell(cntWOG, 1);

cntSavedWOG = 0;
% For progress feedback.
proBar = betterProBar(numOfUniqueWOIds);
for idxUniqueWOId = 1:numOfUniqueWOIds
    curNumOfWOGToSave ...
        = length(cachedEntryIndicesInParsedVehWOT{idxUniqueWOId});

    indicesEntryInParsedVehWOT( ...
        (cntSavedWOG+1):(cntSavedWOG+curNumOfWOGToSave)) ...
        = cachedEntryIndicesInParsedVehWOT{idxUniqueWOId};

    for curIdxWOGToSave = 1:curNumOfWOGToSave
        parsedVehWorkOrderTable.idxWorkOrderGroup( ...
            cachedEntryIndicesInParsedVehWOT{idxUniqueWOId} ...
            {curIdxWOGToSave}) = cntSavedWOG+curIdxWOGToSave;
    end

    cntSavedWOG = cntSavedWOG + curNumOfWOGToSave;

    proBar.progress;
end
proBar.stop;

idxWorkOrderGroup = (1:cntWOG)';
workOrderGroupTable = table(idxWorkOrderGroup, indicesEntryInParsedVehWOT);

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Find GPS Tracks for Each Vehicle Work Order Group

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Searching for GPS tracks for work order groups ...'])

flagGenDebugFigs = FLAG_GEN_DEBUG_FIGS;
if flagGenDebugFigs
    % Generate a limited amount of debugging figures.
    debugFigCnt = 0;
    maxDebugFigCntToStop = NUM_OF_ACT_TRACK_DEBUG_FIGS;
end

numOfWorkOrderGroups = size(workOrderGroupTable, 1);

% For grouping GPS samples into continuous tracks.
maxAllowedTimeGapInS = MAX_ALLOWED_TIME_GAP_IN_MIN*60;

% Cache the discovered activity tracks.
numsOfActivityTracks = zeros(numOfWorkOrderGroups, 1);
activityTracksAsSampIndicesInParsedGLT = cell(numOfWorkOrderGroups, 1);

% For progress feedback. We will get more updates because this procedure
% takes a longer time to finish.
proBar = betterProBar(numOfWorkOrderGroups, 1000);
% Debugging notes: % 5435 % 5432: No GPS records. % 1:numOfWorkOrderGroups
for idxWOG = 1:numOfWorkOrderGroups
    curDate = parsedVehWorkOrderTable.localDatetime( ...
        workOrderGroupTable.indicesEntryInParsedVehWOT{idxWOG}(1));
    curVehId = parsedVehWorkOrderTable.vehId( ...
        workOrderGroupTable.indicesEntryInParsedVehWOT{idxWOG}(1));

    % We will inspect a time range, including the start date but excluding
    % the end date (24:00:00 of "today" or 00:00:00 of "tomorrow").
    curDateStart = dateshift(curDate, 'start', 'day');
    curDateEnd = dateshift(curDate, 'end', 'day');

    datetimeWindowStart = curDateStart ...
        - hours(HOURS_BEFORE_WORK_DATE_TO_SEARCH);
    datetimeWindowEnd = curDateEnd ...
        + hours(HOURS_AFTER_WORK_DATE_TO_SEARCH);

    % Comparing the Unix time numbers is slightly faster than comparing the
    % corresponding datetime objects (4.950038 s vs 5.131865 s in the test
    % case "idxVehWOG = 1:300").
    unixTimeWindowStart = posixtime(datetimeWindowStart);
    unixTimeWindowEnd = posixtime(datetimeWindowEnd);

    % Speed the search up by filtering out candidates step by step. First,
    % by vehicle ID.
    boolsIsCandidateGpsPt = (parsedGpsLocTable.vehId == curVehId);
    % Then, by the start time.
    boolsIsCandidateGpsPt(boolsIsCandidateGpsPt) = ...
        parsedGpsLocTable.unixTime(boolsIsCandidateGpsPt) ...
        >= unixTimeWindowStart;
    % At last, by the end time.
    boolsIsCandidateGpsPt(boolsIsCandidateGpsPt) = ...
        parsedGpsLocTable.unixTime(boolsIsCandidateGpsPt) ...
        < unixTimeWindowEnd;

    curSampIndicesInParsedGpsLocTable = (find(boolsIsCandidateGpsPt))';

    if ~isempty(curSampIndicesInParsedGpsLocTable)
        % Retrieve the GPS samples accordingly.
        curParsedGpsLocTable = parsedGpsLocTable( ...
            curSampIndicesInParsedGpsLocTable, :);

        % Group GPS samples into continuous tracks.
        assert(issorted(curParsedGpsLocTable.unixTime), ...
            'Fetched GPS samples should be sorted by time!')

        curNumOfPts = size(curParsedGpsLocTable, 1);
        curTimeGapsInS = curParsedGpsLocTable.unixTime(2:end) ...
            - curParsedGpsLocTable.unixTime(1:(end-1));
        assert(all(curTimeGapsInS>=0), ...
            'All time gaps should be non-negative!')

        curIndicesToBreakTrack = 2:curNumOfPts;
        curIndicesToBreakTrack = curIndicesToBreakTrack( ...
            curTimeGapsInS>maxAllowedTimeGapInS);


        curNumOfBreaks = length(curIndicesToBreakTrack);
        curNumOfActivityTracks = curNumOfBreaks + 1;

        activityTracksAsSampIndicesInParsedGLT{idxWOG} ...
            = cell(curNumOfActivityTracks, 1);

        if isempty(curIndicesToBreakTrack)
            activityTracksAsSampIndicesInParsedGLT{idxWOG}{1} ...
                = curSampIndicesInParsedGpsLocTable;
        else
            trackStartIdx = 1;
            for idxBreakPt = 1:curNumOfBreaks
                curIdxToBreak = curIndicesToBreakTrack(idxBreakPt);

                activityTracksAsSampIndicesInParsedGLT{idxWOG} ...
                    {idxBreakPt} ...
                    = curSampIndicesInParsedGpsLocTable( ...
                    trackStartIdx:(curIdxToBreak-1));

                trackStartIdx = curIdxToBreak;
            end
            activityTracksAsSampIndicesInParsedGLT{idxWOG} ...
                {curNumOfActivityTracks} ...
                = curSampIndicesInParsedGpsLocTable(trackStartIdx:end);
        end

        numsOfActivityTracks(idxWOG) = curNumOfActivityTracks;

        if flagGenDebugFigs
            % TODO: Generate a debug figure to show the GPS points on a
            % map.

            debugFigCnt = debugFigCnt+1;

            if (debugFigCnt == maxDebugFigCntToStop)
                flagGenDebugFigs = false;
            end
        end
    end

    proBar.progress;
end
proBar.stop;




% TODO: Save results.
totalNumOfActivityTracks = sum(numsOfActivityTracks);


activityTracksForWOGTable = table;
activityTracksForWOGTable.sampIndicesInParsedGpsLocTable ...
    = cell(totalNumOfActivityTracks, 1);
[activityTracksForWOGTable.idxWorkOrderGroup, ...
    activityTracksForWOGTable.idxParsedVehWorkOrder] ...
    = deal(nan(totalNumOfActivityTracks, 1));
activityTracksForWOGTable.boolsEndInWorkDate ...
    = false(totalNumOfActivityTracks, 1);


% parsedVehWorkOrderTable.idxActivityTrack;

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Match Each Work Order with GPS Tracks

% We will append GPS track information to work orders.
parsedVehWorkOrderTable.sampIndicesGpsTracks ...
    = cell(numOfVehWorkOrders, 1);

%% Overview Figures
% TODO: Generate an overview figure for each day's work orders. GPS samples
% (dots) on the map are adjusted based how "stale" they are, e.g., by
% transparency and marker size (the older the records, the bigger and more
% transparent the corresponding markers will appear).
%plot_google_map

%% Clean Up

close all;
diary off;

% EOF