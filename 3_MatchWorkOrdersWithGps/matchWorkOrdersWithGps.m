% MATCHWORKORDERSWITHGPS Based on vehicle ID and data from work orders,
% find and analyze the corresponding GPS tracks.
%
% Developed using Matlab R2021b on Windows.
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

% Note that the input format syntax is different from that for the output
% format. For example, 'M' refers to month for 'InputFormat', but instead
% stands for minute for 'OutputFormat'.
%
% Time string formats for parsing INDOT data.
INDOT_DATE_FORMAT = 'dd-MMM-yy';
INDOT_TIMESTR_FORMAT = 'dd-MMM-yy hh.mm.ss.SSSSSSSSS a';
% Format to use for storing time as datetime objects in Matlab.
DATETIME_FORMAT = 'yyyy-MM-dd HH:mm:ss';
% Format to use when we need a label for a date.
DATESTR_FORMAT_DATE = 'yyyymmdd';

% Optional. If this date range is set, only work order groups in this range
% (including both dates) will be analyzed. If it is not set (by commenting
% out this line), all work order groups will be processed.
DATE_RANGE_OF_INTEREST = datetime(2021, 1, [31,31], ...
    'TimeZone', LOCAL_TIME_ZONE, 'Format', DATETIME_FORMAT);

% Set this to true to inspect work order entries day by day. Set this to
% false to group work order entries over multiple days with the same ID and
% inspect these groups one by one.
FLAG_INSPECT_WOS_DAY_BY_DAY = true;

if FLAG_INSPECT_WOS_DAY_BY_DAY
    % No need to load data out of the date range of interest in the
    % day-by-day inspection mode.
    [HOURS_TO_LOAD_BEFORE_DATE_RANGE, ...
        HOURS_TO_LOAD_AFTER_DATE_RANGE] = deal(0);
else
    % We need to load and pre-process GPS data (mainly to determine mile
    % markers; very time-consuming) beyond the user-defined date range of
    % interest (e.g., if a work order can last at most two days, then both
    % one day before and one day after the date range).
    %
    %   - Hours to load & preprocess GPS data before the start (00:00:00)
    %   of the date range of interest, just in case, e.g., night shifts are
    %   involved.
    HOURS_TO_LOAD_BEFORE_DATE_RANGE = 24;
    %   - Hours to load & preprocess GPS data after the end (24:00:00) of
    %   the date range of interest, just in case, e.g., the work date is
    %   mislabeled.
    HOURS_TO_LOAD_AFTER_DATE_RANGE = 24;
end

% Additionally, for any work order, GPS records before and after its date
% (or dates if the work order covers multiple days) can be analyzed for
% finding activities. We normally set these "extra time" to look at to 0,
% because the work order dates extracted from all entries (not only for
% vehicles, but also for operators and other resources) should cover all
% dates a vehicle is used, even though the work order date range extracted
% from vehicle entries alone does not garantee that.
%
%   - Hours to search activities before the start (00:00:00) of the work
%   order date, just in case, e.g., night shifts are involved.
HOURS_BEFORE_WORK_DATE_TO_SEARCH = 0;
%   - Hours to search activities after the end (24:00:00) of the work order
%   date, just in case, e.g., the work date is mislabeled.
HOURS_AFTER_WORK_DATE_TO_SEARCH = 0;

% Create a label (and later a dedicated folder accordingly to hold the
% results) for each different analysis time range.
if exist('DATE_RANGE_OF_INTEREST', 'var')
    label = [datestr(DATE_RANGE_OF_INTEREST(1), ...
        DATESTR_FORMAT_DATE), ...
        '_to_', datestr(DATE_RANGE_OF_INTEREST(2), ...
        DATESTR_FORMAT_DATE)];
end

% The absolute path to the folder for saving results. TODO: test the 'ALL'
% case.
if ~exist('label', 'var')
    label = 'ALL';
end

if HOURS_TO_LOAD_BEFORE_DATE_RANGE~=0
    label = [label, '_LookAhead_', ...
        num2str(HOURS_TO_LOAD_BEFORE_DATE_RANGE), 'h'];
end
if HOURS_TO_LOAD_AFTER_DATE_RANGE~=0
    label = [label, '_LookAfter_', ...
        num2str(HOURS_TO_LOAD_AFTER_DATE_RANGE), 'h'];
end

pathToSaveResults = fullfile(pwd, '..', ...
    'PostProcessingResults', '3_GpsForWorkOrders', label);
if ~exist(pathToSaveResults, 'dir')
    mkdir(pathToSaveResults)
end

% Store entries for multi-day work orders into a separate folder.
pathToSaveMultiDayWOEntries = fullfile(pathToSaveResults, ...
    'DetectedMultiDayWOs');
if ~exist(pathToSaveMultiDayWOEntries, 'dir')
    mkdir(pathToSaveMultiDayWOEntries)
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
pathToTruckCsv = fullfile(pwd, '..', ...
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

% Maximum allowed time gap in minutes between continuous activity/GPS
% tracks.
MAX_ALLOWED_TIME_GAP_IN_MIN = 60;

% Flag to enable debug plot generation.
FLAG_GEN_DEBUG_FIGS = true;
% We have one debug figure per work order group. This limit on the total
% number of debug figures to generate is set mainly to avoid billing from
% Google Maps.
%   - Free tier:
%     0–100,000    0.002 USD per each (2.00 USD per 1000)
%   - Ref:
% https://developers.google.com/maps/documentation/maps-static/usage-and-billing
NUM_OF_ACT_TRACK_DEBUG_FIGS = 1000; %10;

% Maximum allowed distance to a road for the GPS sample to be labeled as on
% that road.
MAX_ALLOWED_DIST_FROM_ROAD_IN_M = 50;

% Set this to true to preprocess all GPS samples for their road names and
% mile markers. TODO: update the work order processing procedure for the
% case where the mile markers are not retrieved ahead of time.
FLAG_PREPROCESS_GPS_FOR_ROADNAME_AND_MILEMARKER = true;

% Set this to be true to only sum up detected work hours and mileages for
% recognized highways.
FLAG_IGNORE_UNKNOWN_ROADS = false;

% A list of pre-determined colors.
colorOrder = colororder;
colorGrey = ones(1,3).*0.5;

% String formatter.
strFmt = '%.1f';

% We will always save figures as .jpg files. However, to speed things up,
% one can set the flag below to disable saving to .fig.
FLAG_DISABLE_SAVEAS_FIG = true;

%% Load IN Mile Markers and Road Centerlines

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading IN mile markers and highway centerlines ...'])

loadIndotMileMarkers;

% We will save this under the root directory PostProcessingResults because
% it can be used over different work order data sets.
absPathToCachedIndotHWs = fullfile(pathToSaveResults, ...
    '..', '..', 'cachedIndotHWs.mat');
if exist(absPathToCachedIndotHWs, 'file')
    disp(' ')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] INDOT road data processed before. Loading cached results ...'])
    load(absPathToCachedIndotHWs);
else
    loadIndotRoads;

    disp(['    [', datestr(now, datetimeFormat), ...
        '] Filtering out non-highway centerlines ...'])

    % To speed road name searching up, discard non-highway roads. Supported
    % methods:
    %    - 'getRoadNameFromRoadSeg' (Recommended)
    %      Use outputs from getRoadNameFromRoadSeg. We will (i) remove
    %      non-highway segments in indotRoads based on the output of the
    %      function getRoadNameFromRoadSeg and (ii) extend the remaining
    %      records with the data field roadName (the output of the function
    %      getRoadNameFromRoadSeg) to further speed up road name
    %      conversions.
    %    - 'regPats'
    %      Use hard-coded Regex patterns.
    methodToIgnoreNonHW = 'getRoadNameFromRoadSeg';

    numOfIndotRoads = length(indotRoads);
    boolsIndotRoadsToIgnore = false(1, numOfIndotRoads);

    switch methodToIgnoreNonHW
        case 'getRoadNameFromRoadSeg'
            indotRoads(1).roadName = '';

            indotRoadFullStreeCell = {indotRoads.FULL_STREE}';

            uniqueFullStrees = unique(upper(indotRoadFullStreeCell));
            for idxUniFullStree = 1:length(uniqueFullStrees)
                curFullStree = uniqueFullStrees{idxUniFullStree};

                indicesIndotRoadsToUpdate = find( ...
                    strcmpi(indotRoadFullStreeCell, curFullStree))';

                curRoadName = getRoadNameFromRoadSeg( ...
                    indotRoads(indicesIndotRoadsToUpdate(1)));

                % Check if this road is a highway. Note:
                %       highwayRegPat = '(S|I|U|T)(\d+)';
                if length(curRoadName)>1 ...
                        && any(strcmpi({'S', 'I', 'U', 'T'}, ...
                        curRoadName(1))) ...
                        && (~isnan(str2double(curRoadName(2:end))))
                    % This is a high way. No need to ignore the
                    % corresponding group of road segments. Need to extend
                    % the indotRoads records.
                    for idxIndotRoadToUpdate = indicesIndotRoadsToUpdate
                        indotRoads(idxIndotRoadToUpdate).roadName ...
                            = curRoadName; %#ok<SAGROW>
                    end
                else
                    boolsIndotRoadsToIgnore(indicesIndotRoadsToUpdate) = true;
                end
            end
        case 'regPats'
            % We have the patterns below copied from
            % getRoadNameFromRoadSeg.m.
            regPats = {'(SR|S.R.|State Rd|State Road|STATE HWY|STHY|ST RD|S R|IN)( |-|)(\d+)', ...
                '(INTERSTATE HIGHWAY|INTERSTATE|INT|I)( |-|)(\d+)', ...
                '(US|USHY|US HWY|U.S. HWY|US HIGHWAY|US ROUTE|U S ROUTE|United States Highway)( |-|)(\d+)'};

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
        otherwise
            error(['Unkown methodToIgnoreNonHW: ', methodToIgnoreNonHW, '!']);
    end

    indotRoads(boolsIndotRoadsToIgnore) = [];

    disp(' ')
    disp(['    [', datestr(now, datetimeFormat), ...
        '] Saving INDOT highway records into a cache .mat file ...'])

    save(absPathToCachedIndotHWs, 'indotRoads', 'ROAD_PROJ');
end

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
        % Manually set the datetime variables for work order to be at noon
        % to avoid ambiguity.
        workOrderTable.WorkDatetime = ...
            datetime(workOrderTable.WorkDate, ...
            'InputFormat', INDOT_DATE_FORMAT, 'TimeZone', LOCAL_TIME_ZONE, ...
            'Format', DATETIME_FORMAT) + hours(12);

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

%% Filtering Data by Date Range of Interest

if exist('DATE_RANGE_OF_INTEREST', 'var')
    disp(' ')
    disp(['[', datestr(now, datetimeFormat), ...
        '] Filtering records by time range of interest: ', ...
        datestr(DATE_RANGE_OF_INTEREST(1)),' to ', ...
        datestr(DATE_RANGE_OF_INTEREST(2)), ' ...'])

    datetimeRangeOfInterest = [ ...
        dateshift(DATE_RANGE_OF_INTEREST(1), 'start', 'day'), ...
        dateshift(DATE_RANGE_OF_INTEREST(2), 'end', 'day')];
    datetimeRangeToLoadData = [ ...
        datetimeRangeOfInterest(1) ...
        - hours(HOURS_TO_LOAD_BEFORE_DATE_RANGE), ...
        datetimeRangeOfInterest(2) ...
        + hours(HOURS_TO_LOAD_AFTER_DATE_RANGE)];

    workOrderTable( ...
        workOrderTable.WorkDatetime<datetimeRangeToLoadData(1) ...
        | workOrderTable.WorkDatetime>datetimeRangeToLoadData(2), ...
        :) = [];
    gpsLocTable( ...
        gpsLocTable.localDatetime<datetimeRangeToLoadData(1) ...
        | gpsLocTable.localDatetime>datetimeRangeToLoadData(2), ...
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
    % INDOT example dataset for winter operations V1
    % ("20220718_IndotExampleGpsData", i.e., "20201001 AVL GPS Data for
    % Purdue v1.csv").
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
    % INDOT example dataset for winter operations V2
    % ("20220804_IndotGpsData_Winter", i.e., "20220804 AVL GPS Data for
    % Purdue v2.csv").
    vehIds = gpsLocTable.COMMISION_NUMBER;

    for idxGpsSamp = 1:numOfGpsSamps
        % TODO: veh name does not seem to be available.
        vehNames{idxGpsSamp} = '';

        proBar.progress;
    end
else
    % Fallback plan: guess the vehicle information based on Howell's
    % dataset ("20220221_ExampleData", i.e.,
    % "20210301_to_20210501_avl.zip").
    %
    % We will use the inventory information to deduce vehIds and vehNames
    % based on the sensor ID.
    if ~exist('truckTable', 'var')
        truckTable = readtable(pathToTruckCsv);
    end

    for idxGpsSamp = 1:numOfGpsSamps
        % INDOT and Parson's call this vehicleId, but it is essentually the
        % ID for the Parson's GPS sensor. For example, we have sensor ID
        % "693" for vehicle "64264,LaPorte,LaPorte,MDC-006".
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
% least the number of unique work order IDs (if we allow empty entries for
% one unique work order ID). We will find work order groups for each unique
% work order ID and concatenate the results.
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

    % Make sure the current work order actually overlaps with the date
    % range of interest, DATE_RANGE_OF_INTEREST or datetimeRangeOfInterest
    % (instead of the "extended" time range for loading data,
    % datetimeRangeToLoadData).
    if exist('DATE_RANGE_OF_INTEREST', 'var')
        curLDTs = table2array(parsedVehWorkOrderTable( ...
            curEntryIndicesInParsedVehWOT, 'localDatetime'));

        if (max(curLDTs)<datetimeRangeOfInterest(1)) ...
                || (min(curLDTs)>datetimeRangeOfInterest(2))
            % No overlapping so there is no need to keep searching.
            continue;
        end
    end

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

    debugFigSizeInPixel = [1280, 720];
    % Adjust markers and line based on how old they are in this day.
    %   - Format:
    %     [Value at the start of the day, value at the end of the day].
    %   - Current setting:
    %     The closer a sample is to the start of the day, the
    %     bigger/thicker/more transparent the cooresponding marker will be.
    lineWithRangeInPt = [10, 2]; % Ref: Matlab default to 0.5.
    markerSizeRangeInPt = [50, 10]; % Ref: Matlab default to 6.
    alphaRange = [0.25, 1];
    segPatchAlpha = 0.25;
    mapAlpha = 0.4;

    % Use an exponential curve to adjust the visualization so that recent
    % samples are highlighted.
    expFactorForMapping = 3;

    LINE_STYLE = '-';
    NA_LINE_STYLE = '--';
end

numOfWorkOrderGroups = size(workOrderGroupTable, 1);

% For grouping GPS samples into continuous tracks.
maxAllowedTimeGapInS = MAX_ALLOWED_TIME_GAP_IN_MIN*60;

% Cache the discovered activity tracks.
numsOfActivityTracks = zeros(numOfWorkOrderGroups, 1);
activityTracksAsSampIndicesInParsedGLT = cell(numOfWorkOrderGroups, 1);

disp(['    [', datestr(now, datetimeFormat), ...
    '] Extracting work information and generating figures as needed ...'])

% For progress feedback.
proBar = betterProBar(numOfWorkOrderGroups);
% Debugging notes
%   With all records:
%       - 5435
%        - 5432: No GPS records
%       - 24863, 24864 (For example work order # 20848444; veh # 63519)
%   For 2021/1/31:
%       - 1146: A multi-day work order.
%
%   For (manually) creating frame-by-frame overview figs:
%       We are interested in two scenarios, as listed below (with example
%       work order entries we select).
%         - Simple one-road patrolling
%           VehId:     63100
%            WOIds: 20848885
%         - Simple one-road snow & ice removal
%           VehId:     62894
%            WOIds: 20850229
%         - Complicated multi-road snow & ice removal
%           VehId:     61290
%            WOIds: 20850220
for idxWOG = 1:numOfWorkOrderGroups
    % Make sure the work orders in this work order group do have the same
    % records.
    curVehWOs = parsedVehWorkOrderTable( ...
        workOrderGroupTable.indicesEntryInParsedVehWOT{idxWOG}, :);

    % The localDatetime field should already be sorted.
    assert(issorted(curVehWOs.localDatetime, 'ascend'), ...
        'Field localDatetime of curWOs is not sorted!')

    cur1stVehWO = curVehWOs(1,:);
    curWOId = cur1stVehWO.workOrderId;
    curVehId = cur1stVehWO.vehId;

    flagIsMultiDayVehWO = false;

    % First, check whether the vehicle work order entries span over
    % multiple days. If so, output these entries into a log file for
    % debugging.
    %
    % Fields to keep: localDatetime, workOrderId, vehId, vehName, actId,
    % actName, unixTime, and idxWorkOrderGroup.
    %
    % Note that the localDatetime should be the work order date with time
    % 12:00:00.
    curVehWOsRecords = curVehWOs;
    curVehWOsRecords.idxInWorkOrderTable = [];
    curVehWOsRecords.totalHrs = [];
    cur1stVehWORecs = cur1stVehWO;
    cur1stVehWORecs.idxInWorkOrderTable = [];
    cur1stVehWORecs.totalHrs = [];

    unexpectedVehWOs = setdiff(curVehWOsRecords, cur1stVehWORecs);
    if ~isempty(unexpectedVehWOs)
        % Compare all fields except localDatetime, unixTime, and
        % idxWorkOrderGroup (this should be the same for all these
        % entries).
        %
        % Fields that should be the same: workOrderId, vehId, vehName,
        % actId, and actName.
        if isempty(setdiff( ...
                unexpectedVehWOs(:, 2:6), cur1stVehWORecs(:, 2:6) ...
                ))
            % It can be concluded that only the time fields, i.e.,
            % localDatetime and unixTime, have different entries.
            warning(['[', datestr(now, datetimeFormat), ...
                '] Mutli-day veh work order (#', ...
                num2str(cur1stVehWORecs.workOrderId), ...
                ') detected!']);

            % Save all entries of the current work order into one .csv
            % file.
            writetable( curVehWOs, fullfile(pathToSaveMultiDayWOEntries, ...
                ['curVehWOs_WOG_', num2str(idxWOG), ...
                '_WO_', num2str(cur1stVehWORecs.workOrderId), '.csv']) );
            flagIsMultiDayVehWO = true;
        else
            warning(['[', datestr(now, datetimeFormat), ...
                '] Vehicle work orders in group #', num2str(idxWOG), ...
                ' have different records!']);

            % Save all entries of the current work order into one .csv
            % file.
            writetable( curVehWOs, fullfile(pathToSaveMultiDayWOEntries, ...
                ['ContradictingEntries_', ...
                'curVehWOs_WOG_', num2str(idxWOG), ...
                '_WO_', num2str(cur1stVehWORecs.workOrderId), '.csv']) );
        end
    end

    % Second, determine the time range of the activity. We will fetch and
    % inspect all work order entries with this work order ID.
    %
    % Note that in the previous step, we were only checking work order
    % entries for vehicles, but here, we are looking at all available work
    % orders. As a result, the answer to "is this a multi-day work order"
    % may be different.
    allWOsWithThisId = workOrderTable(workOrderTable.WO==curWOId, :);

    % We will inspect a time range, including the start date but excluding
    % the end date (24:00:00 of "today" or 00:00:00 of "tomorrow").
    curLDTs = allWOsWithThisId.WorkDatetime;
    curStartDatetime = dateshift( ...
        min(curLDTs), 'start', 'day');
    curEndDatetime = dateshift( ...
        max(curLDTs), 'end', 'day');

    % Use a time range instead of a single date to support multi-date work
    % orders.
    curDatetimeRange = [curStartDatetime, curEndDatetime];

    datetimeWindowStart = curStartDatetime ...
        - hours(HOURS_BEFORE_WORK_DATE_TO_SEARCH);
    datetimeWindowEnd = curEndDatetime ...
        + hours(HOURS_AFTER_WORK_DATE_TO_SEARCH);

    % Adjust the interpolation range based on the number of days to
    % consider.
    interpRangeForMapping ...
        = ([0, hours(datetimeWindowEnd-datetimeWindowStart)]) ...
        .^expFactorForMapping;

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
            % curWOId, curData and curVehId.
            curActId = cur1stVehWO.actId;
            curActName = capitalize(lower(regexprep( ...
                cur1stVehWO.actName{1}, ' +', ' ')));
            curVehName = capitalize(lower(regexprep( ...
                cur1stVehWO.vehName{1}, ' +', ' ')));

            % For easier information aggregation later, mark in the prefix
            % label
            %       date, vehicle, and work order
            % of that particular order, because the same "date" may
            % involves multiple vehicles, while the same "vehicle" in that
            % date may have multiple "work orders".
            %
            % Convert local date to a string as (1) one date for single-day
            % work orders or (2) a date range for multi-date work orders.
            if dateshift(curDatetimeRange(1), 'start', 'day') ...
                    == dateshift(curDatetimeRange(2)-seconds(0.001), ...
                    'start', 'day')
                % All the work order entries are in the same day.
                curDatetimeRangeStr = datestr(curDatetimeRange(1), ...
                    DATESTR_FORMAT_DATE);

                % Also make sure the old way of looking for multi-day work
                % orders agree with the new method.
                assert(~flagIsMultiDayVehWO, ...
                    'Unexpected flagIsMultiDayWO!')
            else
                % This is a multi-day work order. Note that in this case
                % flagIsMultiDayVehWO may indicate otherwise, but we will
                % use all work order entries (instead of only the vehicle
                % ones) to decide the date range for loading GPS records.
                curDatetimeRangeStr = ['MultiDay_', ...
                    datestr(curDatetimeRange(1), DATESTR_FORMAT_DATE), ...
                    ' to ', ...
                    datestr(curDatetimeRange(2), DATESTR_FORMAT_DATE)];
            end
            debugFixFileNamePrefix = [ ...
                curDatetimeRangeStr, ...
                '_VehID_', num2str(curVehId), ...
                '_WO_', num2str(curWOId) ...
                ];

            curPathToSaveMapFig = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', 'Map']);
            curPathToSaveMap3DFig = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', 'Map_3D']);
            curPathToSaveMileOverTimeFig = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', 'MileMarkerOverTime']);

            % Other versions of the mile marker over time plot.
            curPathToSaveMileOverTimeFigNoGrey ...
                = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', 'MileMarkerOverTimeNoGrey']);
            curPathToSaveMileOverTimeFigSepRoads ...
                = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', ...
                'MileMarkerOverTimeSepRoadsNoGrey']);
            curPathToSaveMileOverTimeFigSepRoadsWithGrey ...
                = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', ...
                'MileMarkerOverTimeSepRoads']);

            % The .mat file to cache extracted information for this work
            % order group.
            curPathToSaveExtractedInfo = fullfile(pathToSaveResults, ...
                [debugFixFileNamePrefix, '_', 'CachedResults.mat']);

            % Avoid plotting if the last needed figure is already created.
            if ~exist([curPathToSaveMileOverTimeFigSepRoadsWithGrey, ...
                    '.jpg'], 'file')
                % Fetch a list of road names encountered in this work order
                % group. Append the empty string road name (no matching
                % road) to make sure it is always considered.
                allGpsLocTableForCurWOG = parsedGpsLocTable(...
                    [activityTracksAsSampIndicesInParsedGLT{idxWOG}{:}], ...
                    :);
                uniqueRNs = unique([allGpsLocTableForCurWOG.roadName; ...
                    {''}]);
                assert(strcmp(uniqueRNs{1}, ''), ...
                    ['No matching road is not the first item ', ...
                    'in the road name list!'])

                % Get the mile marker value range for coloring road
                % segments.
                allMilesForCurWOG = allGpsLocTableForCurWOG.mile;
                allMilesForCurWOG(isnan(allMilesForCurWOG)) = -1;
                maxMileV = max(allMilesForCurWOG);
                minMileV = min(allMilesForCurWOG);

                curActTotalHs = sum(curVehWOs.totalHrs);

                % Add continuous tracks one by one to the figures.
                hFigGpsOnMap = figure( ...
                    'Position', [0, 0, debugFigSizeInPixel], ...
                    'Visible', ~FLAG_SILENT_FIGS);
                hold on; grid on; grid minor;
                xlabel('Longitude (Degree)');
                ylabel('Latitude (Degree)')
                hFigMileOverTime = figure( ...
                    'Position', [0, 0, debugFigSizeInPixel], ...
                    'Visible', ~FLAG_SILENT_FIGS);
                hold on; grid on; grid minor;
                ylabel('Mile Marker')

                % Record the segment length in time and distance.
                numOfUniqueRNs = length(uniqueRNs);
                [segLengthsInH, segLengthsInM] ...
                    = deal(zeros(numOfUniqueRNs, 1));
                % Record the patch style for each road via their handles.
                % Note that these patches are the colored background
                % rectangles to indicate different roads.
                hsSegPatchCell = cell(numOfUniqueRNs, 1);
                % Record the aggregated work information for the legend
                % labels.
                uniqueRNLegendLabels = cell(numOfUniqueRNs, 1);
                for idxActT = 1:curNumOfActivityTracks
                    curActTrackParsedGLT = parsedGpsLocTable(...
                        activityTracksAsSampIndicesInParsedGLT{idxWOG}...
                        {idxActT}, :);

                    % Show the GPS points on a map.
                    latsToPlot = curActTrackParsedGLT.lat;
                    lonsToPlot = curActTrackParsedGLT.lon;
                    dateTimesToPlot ...
                        = curActTrackParsedGLT.localDatetime;
                    milesToPlot = curActTrackParsedGLT.mile;
                    roadNamesToPlot = curActTrackParsedGLT.roadName;

                    % Snap NaN mile values to -1 for visualization.
                    milesToPlot(isnan(milesToPlot)) = -1;

                    % Assign a temporary integer ID for each road name.
                    roadNameIdsToPlot = cellfun( ...
                        @(rn) find(strcmp(uniqueRNs, rn)), ...
                        roadNamesToPlot);

                    % We will plot GPS samples one by one.
                    numOfPtsToPlot = length(latsToPlot);
                    for idxPt = 1:numOfPtsToPlot
                        curDatetime = dateTimesToPlot(idxPt);
                        curRoadNameId = roadNameIdsToPlot(idxPt);

                        % Assign a color to use based on the road names.
                        % Reserve grey to the "no matching road" case (ID
                        % #1).
                        if curRoadNameId==1
                            color = colorGrey;
                        else
                            color = colorOrder( ...
                                mod(curRoadNameId, numOfColors)+1, :);
                        end

                        hoursAfterStartOfDay = hours( ...
                            curDatetime - curStartDatetime);
                        interpQueryPt = hoursAfterStartOfDay ...
                            .^expFactorForMapping;

                        markerSize = interp1(interpRangeForMapping, ...
                            markerSizeRangeInPt, interpQueryPt);
                        lineWidth = interp1(interpRangeForMapping, ...
                            lineWithRangeInPt, interpQueryPt);
                        alpha = interp1(interpRangeForMapping, ...
                            alphaRange, interpQueryPt);

                        % A 3D view of the map.
                        if FLAG_SILENT_FIGS
                            set(0, 'CurrentFigure', hFigGpsOnMap);
                        else
                            figure(hFigGpsOnMap); %#ok<UNRCH>
                        end
                        scatter3(lonsToPlot(idxPt), ...
                            latsToPlot(idxPt), ...
                            dateTimesToPlot(idxPt), ...
                            markerSize, 'o', ...
                            'MarkerFaceColor', color, ...
                            'MarkerEdgeColor', color, ...
                            'MarkerFaceAlpha', alpha, ...
                            'MarkerEdgeAlpha', alpha);
                        if idxPt<numOfPtsToPlot
                            % Connect this sample with the next one.
                            if curRoadNameId ...
                                    == roadNameIdsToPlot(idxPt+1)
                                colorForLine = color;
                                lineStyleToUse = LINE_STYLE;
                            else
                                colorForLine = colorGrey;
                                lineStyleToUse = NA_LINE_STYLE;
                            end
                            hGreyLine = plot3( ...
                                lonsToPlot(idxPt:(idxPt+1)), ...
                                latsToPlot(idxPt:(idxPt+1)), ...
                                dateTimesToPlot(idxPt:(idxPt+1)), ...
                                lineStyleToUse, ...
                                'Color', [colorForLine, alpha], ...
                                'LineWidth', lineWidth);
                        end

                        % The mile marker over time plot.
                        if FLAG_SILENT_FIGS
                            set(0, 'CurrentFigure', hFigMileOverTime);
                        else
                            figure(hFigMileOverTime); %#ok<UNRCH>
                        end
                        scatter(dateTimesToPlot(idxPt), ...
                            milesToPlot(idxPt), ...
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

                    % Color each road segment with consecutive GPS samples
                    % from the same road via semi-tranparent rectangle
                    % patches.
                    if FLAG_SILENT_FIGS
                        set(0, 'CurrentFigure', hFigMileOverTime);
                    else
                        figure(hFigMileOverTime); %#ok<UNRCH>
                    end
                    [indicesStart, indicesEnd, roadNameIds] ...
                        = findConsecutiveSubSeqs(roadNameIdsToPlot);
                    numOfSegs = length(indicesStart);

                    % Cache a list of patch object so that we can move them
                    % to bottom via uistack more quickly (than repeatedly
                    % doing it for each patch).
                    hsPatchesForUistack ...
                        = matlab.graphics.primitive.Patch.empty;
                    for idxS = 1:numOfSegs
                        curIdxStart = indicesStart(idxS);
                        curIdxEnd = indicesEnd(idxS);
                        curRNId = roadNameIds(idxS);
                        curRN = uniqueRNs{curRNId};

                        if isempty(curRN)
                            curRN = 'N/A';
                        end

                        % Assign color again using the same method for
                        % finding colors of the markers/lines.
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
                        hSegPatch = patch( ...
                            [pMinX, pMinX, pMaxX, pMaxX], ...
                            [pMinY, pMaxY, pMaxY, pMinY], ...
                            color, 'LineStyle', 'none', ...
                            'FaceAlpha', segPatchAlpha);
                        hsPatchesForUistack(curRNId) = hSegPatch;
                        hsSegPatchCell{curRNId} = hSegPatch;

                        % Add road name.
                        curSegLengthInTime = pMaxX-pMinX;
                        text(pMinX+curSegLengthInTime/2, pMinY, ...
                            curRN, ...
                            'Color', color, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'bottom');
                        text(pMinX+curSegLengthInTime/2, pMaxY, ...
                            curRN, ...
                            'Color', color, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'top');

                        % Compute the segment length in time.
                        segLengthsInH(curRNId) ...
                            = segLengthsInH(curRNId) ...
                            + hours(curSegLengthInTime);

                        % Segment length in distance needs to be estimated
                        % in UTM.
                        segLats = latsToPlot(curIdxStart:curIdxEnd);
                        segLons = lonsToPlot(curIdxStart:curIdxEnd);
                        [~, ~, segZone] = deg2utm( ...
                            segLats(1), segLons(1));
                        [deg2utm_speZone, ~] ...
                            = genUtmConvertersForFixedZone(segZone);
                        [segXs, segYs] = deg2utm_speZone( ...
                            segLats, segLons);
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
                    % Get rid of non-patch element and move all patches to
                    % the bottom as background.
                    hsPatchesForUistack(~arrayfun(@(h) ...
                        isa(h, 'matlab.graphics.primitive.Patch'), ...
                        hsPatchesForUistack)) = [];
                    uistack(hsPatchesForUistack, 'bottom');
                end

                % Add a lengend with aggregated information, with the first
                % line (N/A) always shown separately.
                boolsSegsToHide = cellfun(@(s) isempty(s), ...
                    hsSegPatchCell(2:end));
                if any(boolsSegsToHide)
                    uniqueRNLegendLabels([false; boolsSegsToHide]) = [];
                    hsSegPatchCell([false; boolsSegsToHide]) = [];
                end
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
                if FLAG_IGNORE_UNKNOWN_ROADS
                    curDetectedWorkInH = sum(segLengthsInH(2:end));
                    curDetectedWorkInM = sum(segLengthsInM(2:end));
                else
                    curDetectedWorkInH = sum(segLengthsInH);
                    curDetectedWorkInM = sum(segLengthsInM);
                end
                titleToPlot = {[strrep(curDatetimeRangeStr, '_', ' '), ...
                    ', WO #', num2str(curWOId), ...
                    ', Activity #', num2str(curActId), ...
                    ' - ', curActName]; ...
                    ['Veh #', num2str(curVehId), ' - ', curVehName]; ...
                    ['Reported Hours: ', ...
                    num2str(curActTotalHs, strFmt), ...
                    ', Detected Hours: ', ...
                    num2str(curDetectedWorkInH, strFmt), ...
                    ', Detected Miles: ', num2str(distdim( ...
                    curDetectedWorkInM, 'meters', 'miles' ...
                    ), strFmt)]};
                title(titleToPlot);

                % Add a map background.
                if FLAG_SILENT_FIGS
                    set(0, 'CurrentFigure', hFigGpsOnMap);
                else
                    figure(hFigGpsOnMap); %#ok<UNRCH>
                end
                title(titleToPlot);
                plot_google_map('MapType', 'streetmap', ...
                    'Alpha', mapAlpha);

                % Save the map figure.
                if ~FLAG_DISABLE_SAVEAS_FIG
                    saveas(hFigGpsOnMap, [curPathToSaveMapFig, '.fig']);
                end
                saveas(hFigGpsOnMap, [curPathToSaveMapFig, '.jpg']);

                % A 3D version.
                view(3);

                % if ~FLAG_DISABLE_SAVEAS_FIG
                %     saveas(hFigGpsOnMap, [curPathToSaveMap3DFig,
                %     '.fig']);
                % end

                % Always save a .fig file of the 3D map for debugging
                % purposes.
                saveas(hFigGpsOnMap, [curPathToSaveMap3DFig, '.fig']);
                saveas(hFigGpsOnMap, [curPathToSaveMap3DFig, '.jpg']);

                % Save the mile marker figure.
                if ~FLAG_DISABLE_SAVEAS_FIG
                    saveas(hFigMileOverTime, ...
                        [curPathToSaveMileOverTimeFig, '.fig']);
                end
                saveas(hFigMileOverTime, ...
                    [curPathToSaveMileOverTimeFig, '.jpg']);

                % Cache the x range for the mile over time plot.
                if FLAG_SILENT_FIGS
                    set(0, 'CurrentFigure', hFigMileOverTime);
                else
                    figure(hFigMileOverTime); %#ok<UNRCH>
                end
                curMileOverTimeFigXLimit = xlim;

                % Close the figures.
                close all;

                % Save the extracted information into a .mat file.
                save(curPathToSaveExtractedInfo, ...
                    'uniqueRNs', 'segLengthsInH', 'segLengthsInM', ...
                    'titleToPlot', 'uniqueRNLegendLabels', ...
                    'curDatetimeRange', 'curDatetimeRangeStr', ...
                    'curWOId', ...
                    'curActId', 'curActName', ...
                    'curVehId', 'curVehName', ...
                    'curActTotalHs', ...
                    'curDetectedWorkInH', 'curDetectedWorkInM', ...
                    'curMileOverTimeFigXLimit');

                % Recreate the mile marker over time plot, with grey dotted
                % lines omitted.
                hFigMileOverTimeNoGrey = figure( ...
                    'Position', [0, 0, debugFigSizeInPixel], ...
                    'Visible', ~FLAG_SILENT_FIGS);
                hold on; grid on; grid minor;
                ylabel('Mile Marker')
                % Patch handles.
                hsSegPatchCellNoGrey = cell(numOfUniqueRNs, 1);

                % A better version of the mile marker over time plot, with
                % (1) road plots (patchs, dots, and lines) separated
                % vertically and (2) legend item ordered by detected work
                % hours.
                hFigMileOverTimeSepRoads = figure( ...
                    'Position', [0, 0, debugFigSizeInPixel], ...
                    'Visible', ~FLAG_SILENT_FIGS);
                % Set up tile layout figure grid, with one tile for each
                % road. TODO: Adjust tile height based on data range (could
                % be done by assigning way more than enough tiles, e.g.,
                % 100, and use a range of them for each road).
                numOfTiles = length(uniqueRNs);
                hTileLayoutMiOverTSepRs = tiledlayout(numOfTiles, 1, ...
                    'Padding', 'tight', 'TileSpacing', 'tight');

                % Construct the vectors to map between tile indices and
                % road indices.
                [~, uniRIndicesForTs] = sort( ...
                    segLengthsInH(2:end), 'descend');
                uniRIndicesForTs = uniRIndicesForTs + 1;
                uniRIndicesForTs = [uniRIndicesForTs; 1]; %#ok<AGROW>

                tileIndicesForUniRs = [(1:numOfTiles)', uniRIndicesForTs];
                tileIndicesForUniRs = sortrows(tileIndicesForUniRs, 2);
                tileIndicesForUniRs = tileIndicesForUniRs(:,1);

                % Patch handles.
                hsSegPatchCellSepRoads = cell(numOfUniqueRNs, 1);

                % Adjust subfigure appearance.
                for idxTile = 1:numOfTiles
                    nexttile(idxTile);
                    hold on; grid on; grid minor;

                    % Force using datetime for x axis.
                    plot(curMileOverTimeFigXLimit, [nan nan]);

                    curUniRIdx = uniRIndicesForTs(idxTile);
                    if curUniRIdx == 1
                        curUniRN = 'Unknown';
                        curTileYLim = [-2, 0];
                    else
                        curUniRN = uniqueRNs{curUniRIdx};
                        allGpsLocTableForCurTile ...
                            = allGpsLocTableForCurWOG(strcmp( ...
                            allGpsLocTableForCurWOG.roadName, curUniRN), :);
                        hTemp = plot(curMileOverTimeFigXLimit, ...
                            [min(allGpsLocTableForCurTile.mile), ...
                            max(allGpsLocTableForCurTile.mile)]);
                        curTileYLim = ylim;
                        delete(hTemp);
                    end

                    % Force adjust viewable region based on all points to
                    % add in the tile.
                    xlim(curMileOverTimeFigXLimit);
                    ylim(curTileYLim);
                    axis manual;

                    ylabel({curUniRN, 'Mile Marker'});

                    % No need to show x ticks except in the bottom tile.
                    if idxTile~=numOfTiles
                        xticklabels([]);
                    end
                end

                % For preallocating space for annotation line information.
                annoLineCnt = 0;
                for idxActT = 1:curNumOfActivityTracks
                    % Fetch GPS info.
                    curActTrackParsedGLT = parsedGpsLocTable(...
                        activityTracksAsSampIndicesInParsedGLT{idxWOG}...
                        {idxActT}, :);

                    % Show the GPS points on a map.
                    latsToPlot = curActTrackParsedGLT.lat;
                    lonsToPlot = curActTrackParsedGLT.lon;
                    dateTimesToPlot ...
                        = curActTrackParsedGLT.localDatetime;
                    milesToPlot = curActTrackParsedGLT.mile;
                    roadNamesToPlot = curActTrackParsedGLT.roadName;

                    % Snap NaN mile values to -1 for visualization.
                    milesToPlot(isnan(milesToPlot)) = -1;

                    % Assign a temporary integer ID for each road name.
                    roadNameIdsToPlot = cellfun( ...
                        @(rn) find(strcmp(uniqueRNs, rn)), ...
                        roadNamesToPlot);

                    % We will plot GPS samples one by one.
                    numOfPtsToPlot = length(latsToPlot);
                    for idxPt = 1:numOfPtsToPlot
                        curDatetime = dateTimesToPlot(idxPt);
                        curRoadNameId = roadNameIdsToPlot(idxPt);

                        % Assign a color to use based on the road names.
                        % Reserve grey to the "no matching road" case (ID
                        % #1).
                        if curRoadNameId==1
                            color = colorGrey;
                        else
                            color = colorOrder( ...
                                mod(curRoadNameId, numOfColors)+1, :);
                        end

                        hoursAfterStartOfDay = hours( ...
                            curDatetime - curStartDatetime);
                        interpQueryPt = hoursAfterStartOfDay ...
                            .^expFactorForMapping;

                        markerSize = interp1(interpRangeForMapping, ...
                            markerSizeRangeInPt, interpQueryPt);
                        lineWidth = interp1(interpRangeForMapping, ...
                            lineWithRangeInPt, interpQueryPt);
                        alpha = interp1(interpRangeForMapping, ...
                            alphaRange, interpQueryPt);

                        % The mile marker over time plot.
                        if FLAG_SILENT_FIGS
                            set(0, 'CurrentFigure', ...
                                hFigMileOverTimeNoGrey);
                        else
                            figure(hFigMileOverTimeNoGrey); %#ok<UNRCH>
                        end
                        if idxPt<numOfPtsToPlot
                            % Connect this sample with the next one.
                            if curRoadNameId ...
                                    == roadNameIdsToPlot(idxPt+1)
                                colorForLine = color;
                                lineStyleToUse = LINE_STYLE;
                                lineAlpha = alpha;
                            else
                                colorForLine = colorGrey;
                                lineStyleToUse = NA_LINE_STYLE;
                                lineAlpha = 0;

                                % Only need to worry about plotting between
                                % different subfigures if the next tile is
                                % different from the current one.
                                annoLineCnt = annoLineCnt + 1;
                            end
                            plot(dateTimesToPlot(idxPt:(idxPt+1)), ...
                                milesToPlot(idxPt:(idxPt+1)), ...
                                lineStyleToUse, ...
                                'Color', [colorForLine, lineAlpha], ...
                                'LineWidth', lineWidth);
                        end
                        % Make sure the GPS sample dots are plotted on top
                        % of the dotted lines.
                        scatter(dateTimesToPlot(idxPt), ...
                            milesToPlot(idxPt), ...
                            markerSize, 'o', ...
                            'MarkerFaceColor', color, ...
                            'MarkerEdgeColor', color, ...
                            'MarkerFaceAlpha', alpha, ...
                            'MarkerEdgeAlpha', alpha);

                        % For the version with roads vertically separated,
                        % we need to plot into the right tile.
                        if FLAG_SILENT_FIGS
                            set(0, 'CurrentFigure', ...
                                hFigMileOverTimeSepRoads);
                        else
                            figure(hFigMileOverTimeSepRoads); %#ok<UNRCH>
                        end
                        curTileIdx = tileIndicesForUniRs(curRoadNameId);

                        nexttile(curTileIdx);
                        scatter(dateTimesToPlot(idxPt), ...
                            milesToPlot(idxPt), ...
                            markerSize, 'o', ...
                            'MarkerFaceColor', color, ...
                            'MarkerEdgeColor', color, ...
                            'MarkerFaceAlpha', alpha, ...
                            'MarkerEdgeAlpha', alpha);
                        if idxPt<numOfPtsToPlot
                            % Connect this sample with the next one.
                            if curRoadNameId ...
                                    == roadNameIdsToPlot(idxPt+1)
                                % Same tile.
                                colorForLine = color;
                                lineStyleToUse = LINE_STYLE;
                                lineAlpha = alpha;

                                plot(dateTimesToPlot(idxPt:(idxPt+1)), ...
                                    milesToPlot(idxPt:(idxPt+1)), ...
                                    lineStyleToUse, ...
                                    'Color', [colorForLine, lineAlpha], ...
                                    'LineWidth', lineWidth);
                            else
                                % Different tiles. We have to wait until
                                % all dots are added so that the axes are
                                % fixed (in terms of xlim and ylim) to add
                                % lines via command annotation.
                            end
                        end
                    end

                    % We will adjust y axis range so that the vertical
                    % distance (workload) in different tiles match
                    % visually.
                    curYLims = nan(numOfTiles, 2);
                    for idxTile = 1:numOfTiles
                        nexttile(idxTile);
                        ylim('tight');
                        curYLims(idxTile, :) = ylim;
                    end
                    maxYLimRange = max(curYLims(:,2)-curYLims(:,1));

                    % Skip the last tile.
                    for idxTile = 1:(numOfTiles-1)
                        newYLim = (sum(curYLims(idxTile, :)) ...
                            + [-1 1].*maxYLimRange)/2;
                        if newYLim(1) < 0
                            newYLim = newYLim - newYLim(1);
                        end
                        nexttile(idxTile);
                        ylim(newYLim);
                    end

                    % Semi-tranparent rectangle patches for road segments.
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

                        % Assign color again using the same method for
                        % finding colors of the markers/lines.
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

                        if FLAG_SILENT_FIGS
                            set(0, 'CurrentFigure', ...
                                hFigMileOverTimeNoGrey);
                        else
                            figure(hFigMileOverTimeNoGrey); %#ok<UNRCH>
                        end

                        hSegPatchNoGrey = patch( ...
                            [pMinX, pMinX, pMaxX, pMaxX], ...
                            [pMinY, pMaxY, pMaxY, pMinY], ...
                            color, 'LineStyle', 'none', ...
                            'FaceAlpha', segPatchAlpha);
                        uistack(hSegPatchNoGrey, 'bottom');
                        hsSegPatchCellNoGrey{curRNId} = hSegPatchNoGrey;

                        % Add road name.
                        curSegLengthInTime = pMaxX-pMinX;
                        text(pMinX+curSegLengthInTime/2, pMinY, ...
                            curRN, ...
                            'Color', color, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'bottom');
                        text(pMinX+curSegLengthInTime/2, pMaxY, ...
                            curRN, ...
                            'Color', color, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'top');

                        % For the version with roads vertically separated,
                        % we need to plot into the right tile.
                        if FLAG_SILENT_FIGS
                            set(0, 'CurrentFigure', ...
                                hFigMileOverTimeSepRoads);
                        else
                            figure(hFigMileOverTimeSepRoads); %#ok<UNRCH>
                        end
                        curTileIdx = tileIndicesForUniRs(curRNId);

                        nexttile(curTileIdx);
                        curYLim = ylim;
                        hSegPatchSepRoads = patch( ...
                            [pMinX, pMinX, pMaxX, pMaxX], ...
                            [curYLim(1), curYLim(2), ...
                            curYLim(2), curYLim(1)], ...
                            color, 'LineStyle', 'none', ...
                            'FaceAlpha', segPatchAlpha);
                        uistack(hSegPatchSepRoads, 'bottom');
                        hsSegPatchCellSepRoads{curRNId} ...
                            = hSegPatchSepRoads;

                        % Add road name.
                        curSegLengthInTime = pMaxX-pMinX;
                        text(pMinX+curSegLengthInTime/2, curYLim(1), ...
                            curRN, ...
                            'Color', color, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'bottom');
                        text(pMinX+curSegLengthInTime/2, curYLim(2), ...
                            curRN, ...
                            'Color', color, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'top');
                    end
                end

                % Add a lengend with aggregated information, with the first
                % line (N/A) always shown separately.
                if FLAG_SILENT_FIGS
                    set(0, 'CurrentFigure', hFigMileOverTimeNoGrey);
                else
                    figure(hFigMileOverTimeNoGrey); %#ok<UNRCH>
                end
                if length(hsSegPatchCellNoGrey)==1
                    legend(hsSegPatchCellNoGrey{1}, ...
                        uniqueRNLegendLabels{1}, ...
                        'Location', 'northeastoutside');
                else
                    hLeg = legend([hsSegPatchCellNoGrey{2:end}], ...
                        uniqueRNLegendLabels(2:end), ...
                        'Location', 'northeastoutside');
                    set(get(hLeg,'Title'), 'String', ...
                        ['(Gray) ', uniqueRNLegendLabels{1}])
                end
                axis tight;

                % Add a title with aggregated information.
                title(titleToPlot);

                % Add a lengend with aggregated information, with the first
                % line (N/A) always shown separately.
                if FLAG_SILENT_FIGS
                    set(0, 'CurrentFigure', hFigMileOverTimeSepRoads);
                else
                    figure(hFigMileOverTimeSepRoads); %#ok<UNRCH>
                end
                if length(hsSegPatchCellSepRoads)==1
                    hLeg = legend(hsSegPatchCellSepRoads{1}, ...
                        uniqueRNLegendLabels{1}, ...
                        'FontSize', 9);
                else
                    hsSegPatchCellSepRsToShow ...
                        = [hsSegPatchCellSepRoads{2:end}];
                    uniRNLegLabelsToShow = uniqueRNLegendLabels(2:end);
                    segLengthsInHToShow = segLengthsInH(2:end);
                    segLengthsInHToShow = segLengthsInHToShow( ...
                        segLengthsInHToShow~=0);
                    [~, patchOrdersToShow] = sort( ...
                        segLengthsInHToShow, 'descend');

                    hLeg = legend( ...
                        hsSegPatchCellSepRsToShow(patchOrdersToShow), ...
                        uniRNLegLabelsToShow(patchOrdersToShow), ...
                        'FontSize', 9);
                    set(get(hLeg,'Title'), 'String', ...
                        ['(Gray) ', uniqueRNLegendLabels{1}])
                end
                hLeg.Layout.Tile = 'east';

                % Add a title with aggregated information. Note that the
                % title added by:
                %    title(hTileLayoutMiOverTSepRs, titleToPlot);
                % seems a little different.
                nexttile(1);
                title(titleToPlot, 'FontSize', 11);

                % Hide the mile markers (ylables) of the last tile.
                nexttile(numOfTiles);
                yticklabels([]);

                % Save the mile marker figure.
                if ~FLAG_DISABLE_SAVEAS_FIG
                    saveas(hFigMileOverTimeNoGrey, ...
                        [curPathToSaveMileOverTimeFigNoGrey, '.fig']);
                end
                saveas(hFigMileOverTimeNoGrey, ...
                    [curPathToSaveMileOverTimeFigNoGrey, '.jpg']);

                if ~FLAG_DISABLE_SAVEAS_FIG
                    saveas(hFigMileOverTimeSepRoads, ...
                        [curPathToSaveMileOverTimeFigSepRoads, '.fig']);
                end
                saveas(hFigMileOverTimeSepRoads, ...
                    [curPathToSaveMileOverTimeFigSepRoads, '.jpg']);

                % Create another SepRoads version plot (by updating
                % hFigMileOverTimeSepRoads) with grey lines indicating GPS
                % record gaps.
                if FLAG_SILENT_FIGS
                    set(0, 'CurrentFigure', hFigMileOverTimeSepRoads);
                else
                    figure(hFigMileOverTimeSepRoads); %#ok<UNRCH>
                end

                % Compute and cache the information needed to create the
                % grey dotted line indicating potential GPS gaps.
                [annoLineNormXsRelToFig, annoLineNormYsRelToFig] ...
                    = deal(nan(annoLineCnt, 2));
                annoLineStyles = cell(annoLineCnt, 1);
                annoLineColors = nan(annoLineCnt, 3);
                [annoLineAlphas, annoLineWidths] ...
                    = deal(nan(annoLineCnt, 1));

                annoLineCnt = 0;
                for idxActT = 1:curNumOfActivityTracks
                    % Fetch GPS info.
                    curActTrackParsedGLT = parsedGpsLocTable(...
                        activityTracksAsSampIndicesInParsedGLT{idxWOG}...
                        {idxActT}, :);

                    % Show the GPS points on a map.
                    latsToPlot = curActTrackParsedGLT.lat;
                    lonsToPlot = curActTrackParsedGLT.lon;
                    dateTimesToPlot ...
                        = curActTrackParsedGLT.localDatetime;
                    milesToPlot = curActTrackParsedGLT.mile;
                    roadNamesToPlot = curActTrackParsedGLT.roadName;

                    % Snap NaN mile values to -1 for visualization.
                    milesToPlot(isnan(milesToPlot)) = -1;

                    % Assign a temporary integer ID for each road name.
                    roadNameIdsToPlot = cellfun( ...
                        @(rn) find(strcmp(uniqueRNs, rn)), ...
                        roadNamesToPlot);

                    % We will plot GPS samples one by one.
                    numOfPtsToPlot = length(latsToPlot);
                    for idxPt = 1:numOfPtsToPlot
                        curDatetime = dateTimesToPlot(idxPt);
                        curRoadNameId = roadNameIdsToPlot(idxPt);

                        % For the version with roads vertically separated,
                        % we need to plot into the right tile.
                        curTileIdx = tileIndicesForUniRs(curRoadNameId);
                        nexttile(curTileIdx);

                        % Assign a color to use based on the road names.
                        % Reserve grey to the "no matching road" case (ID
                        % #1).
                        if curRoadNameId==1
                            color = colorGrey;
                        else
                            color = colorOrder( ...
                                mod(curRoadNameId, numOfColors)+1, :);
                        end

                        hoursAfterStartOfDay = hours( ...
                            curDatetime - curStartDatetime);
                        interpQueryPt = hoursAfterStartOfDay ...
                            .^expFactorForMapping;

                        markerSize = interp1(interpRangeForMapping, ...
                            markerSizeRangeInPt, interpQueryPt);
                        lineWidth = interp1(interpRangeForMapping, ...
                            lineWithRangeInPt, interpQueryPt);
                        alpha = interp1(interpRangeForMapping, ...
                            alphaRange, interpQueryPt);

                        if idxPt<numOfPtsToPlot
                            % Convert a data point (x, y) in a subfigure
                            % (indicated by tileIdx) of a tile layout to
                            % figure coordinates (xf, yf) in normalized
                            % unit.
                            [normXsRelToFig, normYsRelToFig] ...
                                = deal(nan(1, 2));

                            % Connect this sample with the next one with an
                            % annotation line. Only necessary if the next
                            % tile is different from the current one.
                            if curRoadNameId ...
                                    ~= roadNameIdsToPlot(idxPt+1)
                                colorForLine = colorGrey;
                                lineStyleToUse = NA_LINE_STYLE;
                                lineAlpha = alpha;

                                [normXsRelToFig(1), normYsRelToFig(1)] ...
                                    = tileData2FigNorm( ...
                                    dateTimesToPlot(idxPt), ...
                                    milesToPlot(idxPt), curTileIdx);

                                nextRoadNameId ...
                                    = roadNameIdsToPlot(idxPt+1);
                                nextTileIdx ...
                                    = tileIndicesForUniRs(nextRoadNameId);
                                [normXsRelToFig(2), normYsRelToFig(2)] ...
                                    = tileData2FigNorm( ...
                                    dateTimesToPlot(idxPt+1), ...
                                    milesToPlot(idxPt+1), nextTileIdx);

                                % Cache the results.
                                annoLineCnt = annoLineCnt + 1;
                                annoLineNormXsRelToFig(annoLineCnt, :) ...
                                    = normXsRelToFig;
                                annoLineNormYsRelToFig(annoLineCnt, :) ...
                                    = normYsRelToFig;
                                annoLineStyles{annoLineCnt} ...
                                    = lineStyleToUse;
                                annoLineColors(annoLineCnt, :) ...
                                    = colorForLine;
                                annoLineAlphas(annoLineCnt) = lineAlpha;
                                annoLineWidths(annoLineCnt) = lineWidth;
                            end
                        end
                    end
                end

                % Add the annotation lines. First, in order to plot lines
                % over multiple subplots, create an invisible axes as the
                % shared canvas. Note that this will interrupt with the
                % access to the tile layout (nexttile will not work after
                % this).
                hAxCanvas = axes;
                set(hAxCanvas, 'Position', [0, 0, 1, 1], 'Visible', false);
                % Then add the annotation lines one by one.
                for idxAnnoLine = 1:annoLineCnt
                    % TODOs: Adjust tranparency somehow; use dynamic line
                    % width annoLineWidths(idxAnnoLine).
                    fixLineWidth = 1;
                    hAnnoLine = annotation('line', ...
                        annoLineNormXsRelToFig(idxAnnoLine, :), ...
                        annoLineNormYsRelToFig(idxAnnoLine, :), ...
                        'LineStyle', annoLineStyles{idxAnnoLine}, ...
                        'Color', [annoLineColors(idxAnnoLine, :), ...
                        annoLineAlphas(idxAnnoLine)], ...
                        'LineWidth', fixLineWidth);
                    % TODO: this does not work either.
                    %   uistack(hAnnoLine, 'bottom');
                end

                % Save the SepRoads with grey lines figure.
                if ~FLAG_DISABLE_SAVEAS_FIG
                    saveas(hFigMileOverTimeSepRoads, ...
                        [curPathToSaveMileOverTimeFigSepRoadsWithGrey, ...
                        '.fig']);
                end
                saveas(hFigMileOverTimeSepRoads, ...
                    [curPathToSaveMileOverTimeFigSepRoadsWithGrey, ...
                    '.jpg']);

                % Close the figures.
                close all;
            end

            debugFigCnt = debugFigCnt+1;

            if (debugFigCnt == maxDebugFigCntToStop)
                flagGenDebugFigs = false;

                %% Generate a work order verification report.
                reportDateFormat = DATESTR_FORMAT_DATE;
                reportDigitsAfterDecPt = 2;
                delimiterForWOIds = ' & ';
                % We will add 'MatchingScore' and 'Note' by comparing
                %       delta = detected total hours - reported total hours
                % and the two thresholds below.
                %   - delta > maxAllowedMismatchInH
                %     Warning: Under-reporting... Missing Work Orders?
                %   - delta < -maxAllowedMismatchInH
                %     Warning: Over-reporting... Missing GPS records?
                % MatchingScore will be zero for above cases. Otherwise,
                % the score will be linearly interpolated based on three
                % (abs(delta), score) pairs:
                %    (0, 100%)
                %     (mismatchInHFor90PercScore, 90%)
                %    (maxAllowedMismatchInH, 0%).
                UNDER_REP_WARNING = ...
                    'Warning: Under-reporting';
                OVER_REP_WARNING = ...
                    'Warning: Over-reporting';

                mismatchInHFor90PercScore = 1; % => 90% score.
                maxAllowedMismatchInH = 5; % => 0% score.
                scoreFct = @(delta) interp1( ...
                    [0, mismatchInHFor90PercScore, ...
                    maxAllowedMismatchInH], ...
                    [1, 0.9, 0], abs(delta));

                % First, scan and load all extracted info into a table.
                dirCacheFiles = dir(fullfile(pathToSaveResults, ...
                    '*_CachedResults.mat'));
                numOfCacheFs = length(dirCacheFiles);

                % Only load the needed info for the report. Not needed for
                % now:
                %   'uniqueRNs', 'segLengthsInH', 'segLengthsInM',
                %   'titleToPlot', 'uniqueRNLegendLabels',
                %   'curMileOverTimeFigXLimit'.
                curVarsToLoad = { ...
                    'curDatetimeRange', 'curDatetimeRangeStr', ...
                    'curVehId', 'curVehName', ...
                    'curWOId', 'curActId', 'curActName', ...
                    'curActTotalHs', 'curDetectedWorkInH', ...
                    'curDetectedWorkInM'};

                [LocalDatetimeStart, LocalDatetimeEnd, LocalDateRangeStr] ...
                    = deal(cell(numOfCacheFs, 1));
                VehId = nan(numOfCacheFs, 1);
                VehName = cell(numOfCacheFs, 1);
                % We will eventually merge the WOId field so that it is a
                % string for a list of WOIds instead of just one number.
                WOIds = cell(numOfCacheFs, 1);
                ActId = nan(numOfCacheFs, 1);
                ActName = cell(numOfCacheFs, 1);
                ActTotalHs = nan(numOfCacheFs, 1);
                DetectedWorkInH = nan(numOfCacheFs, 1);
                DetectedWorkInM = nan(numOfCacheFs, 1);

                for idxF = 1:numOfCacheFs
                    cachedRes = load(fullfile( ...
                        dirCacheFiles(idxF).folder, ...
                        dirCacheFiles(idxF).name), curVarsToLoad{:});

                    LocalDatetimeStart{idxF} ...
                        = cachedRes.curDatetimeRange(1);
                    LocalDatetimeEnd{idxF} = cachedRes.curDatetimeRange(2);
                    LocalDateRangeStr{idxF} ...
                        = cachedRes.curDatetimeRangeStr;
                    VehId(idxF) = cachedRes.curVehId;
                    VehName{idxF} = cachedRes.curVehName;
                    WOIds{idxF} = num2str(cachedRes.curWOId);
                    ActId(idxF) = cachedRes.curActId;
                    ActName{idxF} = cachedRes.curActName;
                    ActTotalHs(idxF) = cachedRes.curActTotalHs;
                    DetectedWorkInH(idxF) = cachedRes.curDetectedWorkInH;
                    DetectedWorkInM(idxF) = cachedRes.curDetectedWorkInM;
                end

                % Add UnixTime for easier sorting.
                UnixTimeStart = cellfun(@(d) posixtime(d), ...
                    LocalDatetimeStart);

                loadedResTable = table(UnixTimeStart, ...
                    LocalDatetimeStart, LocalDatetimeEnd, ...
                    LocalDateRangeStr, VehId, VehName, ...
                    WOIds, ActId, ActName, ...
                    ActTotalHs, DetectedWorkInH, DetectedWorkInM);

                % Then order the table by start date, date range, vehicle
                % ID, work order ID, activity ID, and work hours.
                loadedResTable = sortrows(loadedResTable, ...
                    {'UnixTimeStart', 'LocalDateRangeStr', ...
                    'VehId', 'WOIds', 'ActId', 'ActTotalHs'});

                % Group work orders of the same time range for the same
                % vehicle to compute the total reported and detected work
                % hours. VeriRepTab is short for verification report table.
                VeriRepTab = loadedResTable;
                cntNewRecs = 0;
                colsToCompare = {'LocalDateRangeStr', ...
                    'VehId', 'VehName', 'ActId', 'ActName'};
                while cntNewRecs < (size(VeriRepTab, 1) - 1)
                    cntNewRecs = cntNewRecs+1;

                    if isempty( setdiff( ...
                            VeriRepTab(cntNewRecs, colsToCompare), ...
                            VeriRepTab(cntNewRecs+1, colsToCompare)) )
                        % Merge the next entry into the current one.
                        VeriRepTab.WOIds{cntNewRecs} ...
                            = [VeriRepTab.WOIds{cntNewRecs}, ...
                            delimiterForWOIds, ...
                            VeriRepTab.WOIds{cntNewRecs+1}];
                        VeriRepTab.ActTotalHs(cntNewRecs) ...
                            = VeriRepTab.ActTotalHs(cntNewRecs) ...
                            + VeriRepTab.ActTotalHs(cntNewRecs+1);

                        % Since the detected work records are for the same
                        % time range and the same vehicle, they should be
                        % identical (and thus, there is no need to sum them
                        % up).
                        assert(VeriRepTab.DetectedWorkInH(cntNewRecs) ...
                            == VeriRepTab.DetectedWorkInH(cntNewRecs+1));
                        assert(VeriRepTab.DetectedWorkInM(cntNewRecs) ...
                            == VeriRepTab.DetectedWorkInM(cntNewRecs+1));

                        % Delete next entry.
                        VeriRepTab(cntNewRecs+1, :) = [];

                        % Need to re-check this row just in case more
                        % entries can be merged.
                        cntNewRecs = cntNewRecs - 1;
                    end
                end

                % Add scores and notes.
                numOfRepEntries = size(VeriRepTab, 1);

                VeriRepTab.MatchingScore = nan(numOfRepEntries, 1);
                VeriRepTab.Note = cell(numOfRepEntries, 1);

                for idxRepE = 1:numOfRepEntries
                    curDelta = VeriRepTab.DetectedWorkInH(idxRepE) ...
                        - VeriRepTab.ActTotalHs(idxRepE);

                    if curDelta > maxAllowedMismatchInH
                        % Warning: Under-reporting... Missing Work Orders?
                        VeriRepTab.Note{idxRepE} = UNDER_REP_WARNING;
                        VeriRepTab.MatchingScore(idxRepE) = 0;
                    elseif curDelta < -maxAllowedMismatchInH
                        % Warning: Over-reporting... Missing GPS records?
                        VeriRepTab.Note{idxRepE} = OVER_REP_WARNING;
                        VeriRepTab.MatchingScore(idxRepE) = 0;
                    else
                        % Compute score via scoreFct(delta).
                        VeriRepTab.MatchingScore(idxRepE) ...
                            = scoreFct(curDelta);
                        assert( ...
                            VeriRepTab.MatchingScore(idxRepE)>=0 ...
                            && ...
                            VeriRepTab.MatchingScore(idxRepE)<=1, ...
                            ['Unexpected score: ', ...
                            num2str( ...
                            VeriRepTab.MatchingScore(idxRepE)), ...
                            '!']);
                    end
                end

                % Export the result into an .scv file, with a warning for
                % each too disagreeing pair of total reported and detected
                % work hours.
                tableToExport = VeriRepTab;

                tableToExport.ActTotalHs = round( ...
                    tableToExport.ActTotalHs, reportDigitsAfterDecPt);
                tableToExport.DetectedWorkInH = round( ...
                    tableToExport.DetectedWorkInH, ...
                    reportDigitsAfterDecPt);

                % Change meter to mile.
                tableToExport.DetectedWorkInMil = ...
                    distdim(tableToExport.DetectedWorkInM, ...
                    'meters', 'miles');
                tableToExport.DetectedWorkInMil = round( ...
                    tableToExport.DetectedWorkInMil, ...
                    reportDigitsAfterDecPt);

                % Change matching score to a percent number string.
                tableToExport.MatchingScore = arrayfun(@(s) ...
                    [num2str(round( ...
                    s.*100, max(reportDigitsAfterDecPt-2, 0))), '%'], ...
                    tableToExport.MatchingScore, ...
                    'UniformOutput', false);

                % Make sure only work orders for date range of interest is
                % exported
                if exist('DATE_RANGE_OF_INTEREST', 'var')
                    for idxTabEntryToExp = 1:size(tableToExport, 1)
                        assert(~( ...
                            tableToExport.LocalDatetimeStart{ ...
                            idxTabEntryToExp} ...
                            >=datetimeRangeOfInterest(2) ...
                            || tableToExport.LocalDatetimeEnd{ ...
                            idxTabEntryToExp} ...
                            <datetimeRangeOfInterest(1)), ...
                            ['Work order time range does not ', ...
                            'overlap with the date range of interest!']);
                    end
                end

                % Only keep important fields to export.
                tableToExport = tableToExport(:, { ...
                    'LocalDateRangeStr', 'VehId', 'VehName', 'WOIds', ...
                    'ActId', 'ActName', 'ActTotalHs', ...
                    'DetectedWorkInH', 'DetectedWorkInMil', ...
                    'MatchingScore', 'Note' ...
                    });

                absPathToSaveWorkOrderVeriReport = fullfile( ...
                    pathToSaveResults, ...
                    'Report_WorkOrderVerificaiton');
                writetable(tableToExport, ...
                    [absPathToSaveWorkOrderVeriReport, '.csv']);

                workOrderVeriReport = tableToExport;
                workOrderVeriReportRaw = VeriRepTab;
                save([absPathToSaveWorkOrderVeriReport, '.mat'], ...
                    'workOrderVeriReport', 'workOrderVeriReportRaw');

                %% Plots for MatchingScore

                hFigScoreEcdf = figure;
                ecdf(workOrderVeriReportRaw.MatchingScore);
                xlabel('Matching Score'); ylabel('ECDF');
                grid on; grid minor;
                saveas(hFigScoreEcdf, fullfile(pathToSaveResults, ...
                    'Report_MatchingScore_ECDF.jpg'));

                hFigScoreHist = figure;
                histogram(workOrderVeriReportRaw.MatchingScore);
                xlabel('Matching Score'); ylabel('Occurance');
                grid on; grid minor;
                saveas(hFigScoreHist, fullfile(pathToSaveResults, ...
                    'Report_MatchingScore_Hist.jpg'));

                diffWHs = VeriRepTab.DetectedWorkInH ...
                    - VeriRepTab.ActTotalHs;

                hFigDiffWHsEcdf = figure;
                ecdf(diffWHs);
                xlabel('Detected Work Hours Minus Reported Work Hours');
                ylabel('ECDF');
                grid on; grid minor;
                saveas(hFigDiffWHsEcdf, fullfile(pathToSaveResults, ...
                    'Report_DiffWHs_ECDF.jpg'));

                hFigDiffWHsHist = figure;
                histogram(diffWHs);
                xlabel('Detected Work Hours Minus Reported Work Hours');
                ylabel('Occurance');
                grid on; grid minor;
                saveas(hFigDiffWHsHist, fullfile(pathToSaveResults, ...
                    'Report_DiffWHs_Hist.jpg'));

                %% Automatically Generate Work Orders
                % We will pre-fill as much info as possible. First, scan
                % and load all extracted info into a table.

                % Only load the needed info for the report. Not needed for
                % now:
                %   'curWOId', 'curActId', 'curActName', 'curActTotalHs'
                %   'titleToPlot', 'uniqueRNLegendLabels',
                %   'curMileOverTimeFigXLimit'.

                %     curDatetimeRange
                %
                %     curVehId
                %
                %     curVehName
                %
                %     uniqueRNs
                %
                %     segLengthsInH
                %
                %     segLengthsInM
                %
                %     curDetectedWorkInH
                %
                %     curDetectedWorkInM

                absPathToSaveWorkOrderAutoGenReport = fullfile( ...
                    pathToSaveResults, ...
                    'Report_WorkOrderAutoGenerated.csv');


                %% TODO: wait here.
                % For now... there is nothing else to do after the debug
                % figures are generated.
                %   pause;
            end
        end
    end

    proBar.progress;
end
proBar.stop;

% % TODO: Save results.
%   totalNumOfActivityTracks = sum(numsOfActivityTracks);
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