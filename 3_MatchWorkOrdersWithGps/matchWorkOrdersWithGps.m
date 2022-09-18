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

% Expected time zone.
LOCAL_TIME_ZONE = 'America/Indianapolis';

% Optional. If this date range is set, only work order groups in this range
% (including both dates) will be analyzed. If it is not set (by commenting
% out this line), all work order groups will be processed.
DATE_RANGE_OF_INTEREST = datetime(2021, 1, [31,31], ...
    'TimeZone', LOCAL_TIME_ZONE);

% Create a label (and later a dedicated folder accordingly to hold the
% results) for each different analysis time range.
if exist('DATE_RANGE_OF_INTEREST', 'var')
    DATETIME_FORMAT_LABEL = 'yyyyMMdd';
    label = [datestr(DATE_RANGE_OF_INTEREST(1), ...
        DATETIME_FORMAT_LABEL), ...
        '_to_', datestr(DATE_RANGE_OF_INTEREST(2), ...
        DATETIME_FORMAT_LABEL)];
end

% The absolute path to the folder for saving results. TODO: test the 'ALL'
% case.
if ~exist('label', 'var')
    label = 'ALL';
end
pathToSaveResults = fullfile(pwd, '..', ...
    'PostProcessingResults', '3_GpsForWorkOrders', label);
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

% Hours to search before the start (00:00:00) of the work order date, just
% in case, e.g., night shifts are involved.
HOURS_BEFORE_WORK_DATE_TO_SEARCH = 0;
% Hours to search before the end (24:00:00) of the work order date, just in
% case, e.g., the work date is mislabeled.
HOURS_AFTER_WORK_DATE_TO_SEARCH = 0;

% Maximum allowed time gap in minutes between continuous activity/GPS
% tracks.
MAX_ALLOWED_TIME_GAP_IN_MIN = 60;

% Flag to enable debug plot generation.
FLAG_GEN_DEBUG_FIGS = true;
FLAG_GEN_DEBUG_FIGS_QUIETLY = true;
% We have one debug figure per work order group.
NUM_OF_ACT_TRACK_DEBUG_FIGS = 100;

% Maximum allowed distance to a road for the GPS sample to be labeled as on
% that road.
MAX_ALLOWED_DIST_FROM_ROAD_IN_M = 100;

% Set this to true to preprocess all GPS samples for their road names and
% mile markers. TODO: update the work order processing procedure for the
% case where the mile markers are not retrieved ahead of time.
FLAG_PREPROCESS_GPS_FOR_ROADNAME_AND_MILEMARKER = true;

% A list of pre-determined colors.
colorOrder = colororder;
colorGrey = ones(1,3).*0.5;

% String formatter.
strFmt = '%.1f';

%% Load IN Mile Markers and Road Centerlines

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading IN mile markers and high way centerlines ...'])

loadIndotMileMarkers;
loadIndotRoads;

% To speed road name searching up, discard non-highway roads. We have the
% patterns below copied from getRoadNameFromRoadSeg.m.
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

disp(['[', datestr(now, datetimeFormat), '] Done!'])

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

    disp(' ')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] Saving GPS tracks into a cache .mat file ...'])

    save(absPathToCachedTables, 'workOrderTable', 'gpsLocTable');
end

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Filtering Data by Time Range of Interest

if exist('DATE_RANGE_OF_INTEREST', 'var')
    disp(' ')
    disp(['[', datestr(now, datetimeFormat), ...
        '] Filtering records by time range of interest: ', ...
        datestr(DATE_RANGE_OF_INTEREST(1)),' to ', ...
        datestr(DATE_RANGE_OF_INTEREST(2)), ' ...'])

    datetimeRangeOfInterest = [ ...
        dateshift(DATE_RANGE_OF_INTEREST(1), 'start', 'day'), ...
        dateshift(DATE_RANGE_OF_INTEREST(2), 'end', 'day')];

    workOrderTable( ...
        workOrderTable.WorkDatetime<datetimeRangeOfInterest(1) ...
        | workOrderTable.WorkDatetime>datetimeRangeOfInterest(2), ...
        :) = [];
    gpsLocTable( ...
        gpsLocTable.localDatetime<datetimeRangeOfInterest(1) ...
        | gpsLocTable.localDatetime>datetimeRangeOfInterest(2), ...
        :) = [];

    disp(['    [', datestr(now, datetimeFormat), ...
        '] Updating GPS tracks in the cache .mat file ...'])

    save(absPathToCachedTables, 'workOrderTable', 'gpsLocTable');

    disp(['[', datestr(now, datetimeFormat), '] Done!'])
end

%% Preprocess GPS Samples for Road Names and Mile Markers

% Find road name and mile markers.
if FLAG_PREPROCESS_GPS_FOR_ROADNAME_AND_MILEMARKER ...
        && (~ismember('roadName', gpsLocTable.Properties.VariableNames))

    disp(' ')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] Converting GPS (lat, lon) samps to mile markers ...'])

    flagShowProgressBar = true;
    % Suppress warnings.
    flagSuppressWarns = true;
    [gpsLocTable.roadName, gpsLocTable.mile, ...
        gpsLocTable.nearestDistInM] ...
        = fetchRoadNameAndMileMarker( ...
        gpsLocTable.LATITUDE, gpsLocTable.LONGITUDE, ...
        MAX_ALLOWED_DIST_FROM_ROAD_IN_M, ...
        flagShowProgressBar, flagSuppressWarns);

    disp(' ')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] Updating GPS tracks in the cache .mat file ...'])

    save(absPathToCachedTables, 'workOrderTable', 'gpsLocTable');

    disp(['[', datestr(now, datetimeFormat), '] Done!'])
end

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
if ismember('roadName', gpsLocTable.Properties.VariableNames)
    parsedGpsLocTable.roadName = gpsLocTable.roadName;
    parsedGpsLocTable.mile = gpsLocTable.mile;
    parsedGpsLocTable.nearestDistInM = gpsLocTable.nearestDistInM;
end

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

    debugFigSizeInPixel = [960, 720];
    % Adjust markers and line based on how old they are in this day.
    %   - Format:
    %     [Value at the start of the day, value at the end of the day].
    %   - Current setting:
    %     The closer a sample is to the start of the day, the
    %     bigger/thicker/more transparent the cooresponding marker will be.
    lineWithRangeInPt = [10, 2]; % Ref: Matlab default to 0.5.
    markerSizeRangeInPt = [50, 10]; % Ref: Matlab default to 6.
    alphaRange = [0, 1];
    segPatchAlpha = 0.25;

    % Use an exponential curve to adjust the visualization so that recent
    % samples are highlighted.
    expFactorForMapping = 3;
    interpRangeForMapping = ([0,24]).^expFactorForMapping;

    lineStyle = '-';
    naLineStyle = '--';
end

numOfWorkOrderGroups = size(workOrderGroupTable, 1);

% For grouping GPS samples into continuous tracks.
maxAllowedTimeGapInS = MAX_ALLOWED_TIME_GAP_IN_MIN*60;

% Cache the discovered activity tracks.
numsOfActivityTracks = zeros(numOfWorkOrderGroups, 1);
activityTracksAsSampIndicesInParsedGLT = cell(numOfWorkOrderGroups, 1);

% For progress feedback. We will get more updates because this procedure
% takes a long time to finish.
proBar = betterProBar(numOfWorkOrderGroups, 1000);
% Debugging notes (with all records):
%   - 5435
%    - 5432: No GPS records
%   - 24863, 24864 (For example work order # 20848444; veh # 63519)
%    - 1:numOfWorkOrderGroups
for idxWOG = 1:numOfWorkOrderGroups
    % Make sure the work orders in this work order group do have the same
    % records.
    curWOs = parsedVehWorkOrderTable( ...
        workOrderGroupTable.indicesEntryInParsedVehWOT{idxWOG}, :);
    cur1stWO = curWOs(1,:);

    curWOsRecords = curWOs;
    curWOsRecords.idxInWorkOrderTable = [];
    curWOsRecords.totalHrs = [];
    cur1stWORecs = cur1stWO;
    cur1stWORecs.idxInWorkOrderTable = [];
    cur1stWORecs.totalHrs = [];
    assert(isempty(setdiff(curWOsRecords, cur1stWORecs)), ...
        'Work orders in this group have different records!')

    curDate = cur1stWO.localDatetime;
    curVehId = cur1stWO.vehId;

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

        % Generate debug figures if necessary.
        if flagGenDebugFigs
            numOfColors = size(colorOrder, 1);

            % Fetch the information on the work orders. We already have
            % curData and curVehId.
            curWOId = cur1stWO.workOrderId;
            curActId = cur1stWO.actId;
            curActName = capitalize(lower(cur1stWO.actName{1}));
            curVehName = capitalize(lower(cur1stWO.vehName{1}));

            % Fetch a list of road names encountered in this work order
            % group. Append the empty string road name (no matching road)
            % to make sure it is always considered.
            allGpsLocTableForCurWOG = parsedGpsLocTable(...
                [activityTracksAsSampIndicesInParsedGLT{idxWOG}{:}], ...
                :);
            uniqueRNs = unique([allGpsLocTableForCurWOG.roadName, '']);
            assert(strcmp(uniqueRNs{1}, ''), ...
                ['No matching road is not the first item ', ...
                'in the road name list!'])

            % Get the mile marker value range for coloring road segments.
            allMilesForCurWOG = allGpsLocTableForCurWOG.mile;
            allMilesForCurWOG(isnan(allMilesForCurWOG)) = -1;
            maxMileV = max(allMilesForCurWOG);
            minMileV = min(allMilesForCurWOG);

            curActTotalHs = sum(curWOs.totalHrs);

            % Add continuous tracks one by one to the figures.
            hFigGpsOnMap = figure( ...
                'Position', [0, 0, debugFigSizeInPixel], ...
                'Visible', ~FLAG_GEN_DEBUG_FIGS_QUIETLY);
            hold on; grid on; grid minor;
            xlabel('Longitude (Degree)'); ylabel('Latitude (Degree)')
            hFigMileOverTime = figure( ...
                'Position', [0, 0, debugFigSizeInPixel], ...
                'Visible', ~FLAG_GEN_DEBUG_FIGS_QUIETLY);
            hold on; grid on; grid minor;
            ylabel('Mile Marker')

            % Record the segment length in time and distance.
            numOfUniqueRNs = length(uniqueRNs);
            [segLengthsInH, segLengthsInM] ...
                = deal(zeros(numOfUniqueRNs, 1));
            % Record the patch style for each road.
            hsSegPatchCell = cell(numOfUniqueRNs, 1);
            % Record the aggregated work information for the legend labels.
            uniqueRNLegendLabels = cell(numOfUniqueRNs, 1);
            for idxActT = 1:curNumOfActivityTracks
                curActTrackParsedGLT = parsedGpsLocTable(...
                    activityTracksAsSampIndicesInParsedGLT{idxWOG}...
                    {idxActT}, :);

                % Show the GPS points on a map.
                latsToPlot = curActTrackParsedGLT.lat;
                lonsToPlot = curActTrackParsedGLT.lon;
                dateTimesToPlot = curActTrackParsedGLT.localDatetime;
                milesToPlot = curActTrackParsedGLT.mile;
                roadNamesToPlot = curActTrackParsedGLT.roadName;

                % Snap NaN mile values to -1 for visualization.
                milesToPlot(isnan(milesToPlot)) = -1;

                % Assign a temporary integer ID for each road name.
                roadNameIdsToPlot = cellfun( ...
                    @(rn) find(strcmp(uniqueRNs, rn)), roadNamesToPlot);

                % Color consecutive We will then plot samples one by one.
                numOfPtsToPlot = length(latsToPlot);
                for idxPt = 1:numOfPtsToPlot
                    curDatetime = dateTimesToPlot(idxPt);
                    curRoadNameId = roadNameIdsToPlot(idxPt);

                    % Assign a color to use based on the road names.
                    % Reserve grey to the "no matching road" case (ID #1).
                    if curRoadNameId==1
                        color = colorGrey;
                    else
                        color = colorOrder( ...
                            mod(curRoadNameId, numOfColors)+1, :);
                    end

                    hoursAfterStartOfDay = hours( ...
                        curDatetime - curDateStart);
                    interpQueryPt = hoursAfterStartOfDay ...
                        .^expFactorForMapping;

                    markerSize = interp1(interpRangeForMapping, ...
                        markerSizeRangeInPt, interpQueryPt);
                    lineWidth = interp1(interpRangeForMapping, ...
                        lineWithRangeInPt, interpQueryPt);
                    alpha = interp1(interpRangeForMapping, ...
                        alphaRange, interpQueryPt);

                    % A 3D view of the map.
                    figure(hFigGpsOnMap);
                    scatter3(lonsToPlot(idxPt), latsToPlot(idxPt), ...
                        dateTimesToPlot(idxPt), ...
                        markerSize, 'o', ...
                        'MarkerFaceColor', color, ...
                        'MarkerEdgeColor', color, ...
                        'MarkerFaceAlpha', alpha, ...
                        'MarkerEdgeAlpha', alpha);
                    if idxPt<numOfPtsToPlot
                        % Connect this sample with the next one.
                        if curRoadNameId == roadNameIdsToPlot(idxPt+1)
                            colorForLine = color;
                            lineStyleToUse = lineStyle;
                        else
                            colorForLine = colorGrey;
                            lineStyleToUse = naLineStyle;
                        end
                        plot3(lonsToPlot(idxPt:(idxPt+1)), ...
                            latsToPlot(idxPt:(idxPt+1)), ...
                            dateTimesToPlot(idxPt:(idxPt+1)), ...
                            lineStyleToUse, ...
                            'Color', [colorForLine, alpha], ...
                            'LineWidth', lineWidth);
                    end

                    % The mile marker over time plot.
                    figure(hFigMileOverTime);
                    scatter(dateTimesToPlot(idxPt), milesToPlot(idxPt), ...
                        markerSize, 'o', ...
                        'MarkerFaceColor', color, ...
                        'MarkerEdgeColor', color, ...
                        'MarkerFaceAlpha', alpha, ...
                        'MarkerEdgeAlpha', alpha);
                    if idxPt<numOfPtsToPlot
                        plot(dateTimesToPlot(idxPt:(idxPt+1)), ...
                            milesToPlot(idxPt:(idxPt+1)), ...
                            lineStyleToUse, ...
                            'Color', [colorForLine, alpha], ...
                            'LineWidth', lineWidth);
                    end
                end

                % Color each road segment with consecutive GPS samples from
                % the same road.
                figure(hFigMileOverTime);
                [indicesStart, indicesEnd, roadNameIds] ...
                    = findConsecutiveSubSeqs(roadNameIdsToPlot);
                numOfSegs = length(indicesStart);

                for idxS = 1:numOfSegs
                    curIdxStart = indicesStart(idxS);
                    curIdxEnd = indicesEnd(idxS);
                    curRNId = roadNameIds(idxS);
                    curRN = uniqueRNs{curRNId};

                    if isempty(curRN)
                        curRN = 'N/A';
                    end

                    % Assign color again using the same method for finding
                    % colors of the markers/lines.
                    if curRNId==1
                        color = colorGrey;
                    else
                        color = colorOrder( ...
                            mod(curRNId, numOfColors)+1, :);
                    end

                    pMinX = dateTimesToPlot(curIdxStart);
                    pMaxX = dateTimesToPlot(curIdxEnd);
                    pMinY = minMileV;
                    pMaxY = maxMileV;
                    hSegPatch = patch([pMinX, pMinX, pMaxX, pMaxX], ...
                        [pMinY, pMaxY, pMaxY, pMinY], ...
                        color, 'LineStyle', 'none', ...
                        'FaceAlpha', segPatchAlpha);
                    uistack(hSegPatch, 'bottom');
                    hsSegPatchCell{curRNId} = hSegPatch;

                    % Add road name.
                    curSegLengthInTime = pMaxX-pMinX;
                    text(pMinX+curSegLengthInTime/2, pMinY, curRN, ...
                        'Color', color, ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'bottom');
                    text(pMinX+curSegLengthInTime/2, pMaxY, curRN, ...
                        'Color', color, ...
                        'HorizontalAlignment', 'center', ...
                        'VerticalAlignment', 'top');

                    % Compute the segment length in time.
                    segLengthsInH(curRNId) ...
                        = segLengthsInH(curRNId) ...
                        + hours(curSegLengthInTime);

                    % Segment length in distance needs to be estimated in
                    % UTM.
                    segLats = latsToPlot(curIdxStart:curIdxEnd);
                    segLons = lonsToPlot(curIdxStart:curIdxEnd);
                    [~, ~, segZone] = deg2utm(segLats(1), segLons(1));
                    [deg2utm_speZone, ~] ...
                        = genUtmConvertersForFixedZone(segZone);
                    [segXs, segYs] = deg2utm_speZone(segLats, segLons);
                    moveVects = diff([segXs, segYs]);
                    segLengthsInM(curRNId) ...
                        = segLengthsInM(curRNId) ...
                        + sum(sqrt(sum(moveVects.^2, 2)));

                    % Update the legend label.
                    uniqueRNLegendLabels{curRNId} ...
                        = [curRN, ': ', ...
                        num2str(segLengthsInH(curRNId), strFmt), ...
                        ' h, ', ...
                        num2str(distdim(segLengthsInM(curRNId), ...
                        'meters', 'miles'), strFmt), ...
                        ' mil'];
                end
            end

            % Add a lengend with aggregated information, with the first
            % line (N/A) always shown separately.
            boolsSegsToHide = cellfun(@(s) isempty(s), ...
                hsSegPatchCell(2:end));
            uniqueRNLegendLabels([false; boolsSegsToHide]) = [];
            hsSegPatchCell([false; boolsSegsToHide]) = [];
            if isempty(uniqueRNLegendLabels{1})
                uniqueRNLegendLabels{1} = '0 h';
            end
            if length(hsSegPatchCell)==1
                legend(hsSegPatchCell{1}, ...
                    uniqueRNLegendLabels{1}, ...
                    'Location', 'northeastoutside');
            else
                hLeg = legend([hsSegPatchCell{2:end}], ...
                    uniqueRNLegendLabels(2:end), ...
                    'Location', 'northeastoutside');
                set(get(hLeg,'Title'), 'String', ...
                    ['(Gray) ', uniqueRNLegendLabels{1}])
            end
            axis tight;

            % Add a title with aggregated information.
            dateStrFormat = 'yyyy/mm/dd';
            titleToPlot = {[datestr(curDate, dateStrFormat), ...
                ', WO #', num2str(curWOId), ...
                ', Activity #', num2str(curActId), ...
                ' - ', curActName]; ...
                ['Veh #', num2str(curVehId), ' - ', curVehName]; ...
                ['Reported Hours: ', ...
                num2str(curActTotalHs, strFmt), ...
                ', Detected Hours: ', ...
                num2str(sum(segLengthsInH(2:end)), strFmt), ...
                ', Detected Miles: ', num2str(distdim( ...
                sum(segLengthsInM(2:end)), 'meters', 'miles' ...
                ), strFmt)]};
            title(titleToPlot);

            % Add a map background.
            figure(hFigGpsOnMap);
            title(titleToPlot);
            plot_google_map('MapType', 'streetmap');

            % Save the map figure.
            curFigName = 'Map';
            curPathToSaveFig = fullfile(pathToSaveResults, ...
                ['WO_', num2str(curWOId), ...
                '_VehID_', num2str(curVehId), ...
                '_', curFigName]);
            saveas(hFigGpsOnMap, [curPathToSaveFig, '.fig']);
            saveas(hFigGpsOnMap, [curPathToSaveFig, '.jpg']);

            % A 3D version.
            view(3);
            curFigName = 'Map_3D';
            curPathToSaveFig = fullfile(pathToSaveResults, ...
                ['WO_', num2str(curWOId), ...
                '_VehID_', num2str(curVehId), ...
                '_', curFigName]);
            saveas(hFigGpsOnMap, [curPathToSaveFig, '.fig']);
            saveas(hFigGpsOnMap, [curPathToSaveFig, '.jpg']);

            % Save the mile marker figure.
            curFigName = 'MileMarkerOverTime';
            curPathToSaveFig = fullfile(pathToSaveResults, ...
                ['WO_', num2str(curWOId), ...
                '_VehID_', num2str(curVehId), ...
                '_', curFigName]);
            saveas(hFigMileOverTime, [curPathToSaveFig, '.fig']);
            saveas(hFigMileOverTime, [curPathToSaveFig, '.jpg']);

            debugFigCnt = debugFigCnt+1;

            if (debugFigCnt == maxDebugFigCntToStop)
                flagGenDebugFigs = false;
            end
        end
    end

    proBar.progress;
end
proBar.stop;

% % TODO: Save results. totalNumOfActivityTracks =
% sum(numsOfActivityTracks);
%
% activityTracksForWOGTable = table;
%  activityTracksForWOGTable.sampIndicesInParsedGpsLocTable ...
%     = cell(totalNumOfActivityTracks, 1);
% [activityTracksForWOGTable.idxWorkOrderGroup, ...
%     activityTracksForWOGTable.idxParsedVehWorkOrder] ...
%      = deal(nan(totalNumOfActivityTracks, 1));
% activityTracksForWOGTable.boolsEndInWorkDate ...
%     = false(totalNumOfActivityTracks, 1);

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