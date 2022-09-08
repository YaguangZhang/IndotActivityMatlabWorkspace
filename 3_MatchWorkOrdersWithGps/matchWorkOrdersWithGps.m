% MATCHWORKORDERSWITHGPS Based on vehicle ID and data from work orders,
% find and analyze the corresponding GPS tracks.
%
% Yaguang Zhang, Purdue, 08/12/2022

clear; clc; close all; dbstop if error;

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

% Hours to search before the work order date for GPS records, just in case
% night shifts are involved.
HOURS_BEFORE_WORK_DATE_TO_SEARCH = 24;

% Flag to enable debug plot generation.
FLAG_GEN_DEBUG_FIGS = true;

%% Load Work Orders and GPS Tracks

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading work orders and GPS tracks ...'])

% For fast debugging, avoid reloading data if they are already loaded.
if ~exist('workOrderTable', 'var')
    workOrderTable = readtable(pathToWorkOrderCsv);
    workOrderTable = renamevars(workOrderTable, 'WO_', 'WO');
end
if ~exist('gpsLocTable', 'var')
    gpsLocTable = readtable(pathToGpsLocCsv);
end

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Extracting and Formatting Needed Information - GPS

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Extracting and formatting needed GPS information ...'])

% Extract needed information.
numOfGpsLocs = size(gpsLocTable, 1);

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
assert(all( ...
    contains(gpsLocTable.VEHICLE_TIMESTAMP, upper(LOCAL_TIME_ZONE)) ...
    ), 'Unexpected time zone found!')

% Convert time string to datetime for easier processing.
vehicleTimeStamps = vertcat(gpsLocTable.VEHICLE_TIMESTAMP{:});
vehicleTimeStamps = vehicleTimeStamps(:, ...
    1:indexEndOfAmOrPmInLocalTimeStrings);

% Find vehicle IDs and names. Note that the ASSET_LABEL field may not be
% available. If it is present, we will extract vehId accordingly.
% Otherwise, we will "guess" the vehId based on other data sets.
numOfGpsSamps = size(gpsLocTable, 1);
vehIds = nan(numOfGpsSamps, 1);
vehNames = cell(numOfGpsSamps, 1);
% Use 'ASSET_LABEL' when it is available because both vehicle ID and name
% can be extracted. Switch to 'COMMISION_NUMBER' for vehicle ID if
% necessary. As the last resort, if none of these fields are present, we
% will guess the vehicle ID based on history datasets.
if isfield(gpsLocTable, 'ASSET_LABEL')
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
    end
elseif isfield(gpsLocTable, 'COMMISION_NUMBER')
    vehIds = gpsLocTable.COMMISION_NUMBER;

    for idxGpsSamp = 1:numOfGpsSamps
        % TODO: veh name does not seem to be available.
        vehNames{idxGpsSamp} = '';
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
    end
end

parsedGpsLocTable = table;
parsedGpsLocTable.localDatetime = datetime(vehicleTimeStamps, ...
    'InputFormat', INDOT_TIMESTR_FORMAT, 'TimeZone', LOCAL_TIME_ZONE, ...
    'Format', DATETIME_FORMAT);
parsedGpsLocTable.primeKey      = gpsLocTable.PRIMARY_KEY;
parsedGpsLocTable.vehId         = vehIds;
parsedGpsLocTable.vehNames      = vehNames;
parsedGpsLocTable.sensorId      = gpsLocTable.VEHICLE_ID;
parsedGpsLocTable.lat           = gpsLocTable.LATITUDE;
parsedGpsLocTable.lon           = gpsLocTable.LONGITUDE;
parsedGpsLocTable.speedMph      = gpsLocTable.SPEED_MILES_PER_HOUR;
parsedGpsLocTable.heading       = gpsLocTable.VEHICLE_HEADING;

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
end

assert(all(vehIds==round(vehIds)), 'Non-integer vehicle ID found!')
assert(all(actIds==round(actIds)), 'Non-integer activity ID found!')

parsedVehWorkOrderTable = table;
parsedVehWorkOrderTable.localDatetime = ...
    datetime(vehWorkOrderTable.WorkDate, ...
    'InputFormat', INDOT_DATE_FORMAT, 'TimeZone', LOCAL_TIME_ZONE, ...
    'Format', DATETIME_FORMAT);
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

parsedGpsLocTable.unixTime = convertTo( ...
    parsedGpsLocTable.localDatetime, 'posixtime');
parsedVehWorkOrderTable.unixTime = convertTo( ...
    parsedVehWorkOrderTable.localDatetime, 'posixtime');

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
% least the number of unique work order IDs. We will find work order
% groups for each unique work order ID and concatenate the results.
uniqueWOIds = unique(parsedVehWorkOrderTable.workOrderId);
numOfUniqueWOIds = length(uniqueWOIds);

% Cache the work order entry indices as row vectors for each found work
% order group.
cachedEntryIndicesInParsedVehWOT = cell(numOfUniqueWOIds, 1);

cntWOG = 0;
% For progress feedback.
numOfProBarUpdates = 100;
proBar = ProgressBar(floor(numOfUniqueWOIds/numOfProBarUpdates));
proBarCnt = 0;
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

    proBarCnt = proBarCnt + 1;
    if mod(proBarCnt, numOfProBarUpdates) == 0
        proBar.progress;
    end
end
proBar.stop;

% Save the results.
numOfEntriesInParsedVehWOT = size(parsedVehWorkOrderTable, 1);
parsedVehWorkOrderTable.idxWorkOrderGroup ...
    = nan(numOfEntriesInParsedVehWOT, 1);
indicesEntryInParsedVehWOT = cell(cntWOG, 1);

cntSavedWOG = 0;
proBar = ProgressBar(numOfUniqueWOIds);
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

workOrderGroupTable = table('indicesEntryInParsedVehWOT');

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Find GPS Tracks for Each Vehicle Work Order Group

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Searching for GPS records for equipment work orders ...'])

if FLAG_GEN_DEBUG_FIGS
    % Generate a limited amount of debugging figures.
    cnt = 0;
    maxCntToStop = 10;
end

for idxVehWorkOrder = 1:numOfVehWorkOrders
    curDate = parsedVehWorkOrderTable.localDatetime(idxVehWorkOrder);
    curVehId = parsedVehWorkOrderTable.vehId(idxVehWorkOrder);

    % We will inspect a time range, including the start time but excluding
    % the end time (24:00:00 of "today" or 00:00:00 of "tomorrow").
    curDateStart = dateshift(curDate, 'start', 'day');
    curDateEnd = dateshift(curDate, 'end', 'day');

    unixTimeWindowStart = curDateStart ...
        - hours(HOURS_BEFORE_WORK_DATE_TO_SEARCH);
    unixTimeWindowEnd = curDateEnd;

    % Speed the search up by filtering out candidates step by step. First,
    % by vehicle ID.
    boolsIsCandidateGpsPt = (parsedGpsLocTable.vehId == curVehId);
    % Then, by the start time.
    boolsIsCandidateGpsPt(boolsIsCandidateGpsPt) = ...
        parsedGpsLocTable.localDatetime(boolsIsCandidateGpsPt) ...
        >= unixTimeWindowStart;
    % At last, by the end time.
    boolsIsCandidateGpsPt(boolsIsCandidateGpsPt) = ...
        parsedGpsLocTable.localDatetime(boolsIsCandidateGpsPt) ...
        < unixTimeWindowEnd;

    curSampIndicesInParsedGpsLocTable = find(boolsIsCandidateGpsPt);

    % Retrieve the GPS samples accordingly.
    curParsedGpsLocTable = parsedGpsLocTable( ...
        curSampIndicesInParsedGpsLocTable, :);

    if FLAG_GEN_DEBUG_FIGS
        if ~isempty(curParsedGpsLocTable)
            cnt = cnt+1;

            % TODO: Generate a debug figure to show the GPS points on a
            % map.

        end

        if (cnt == maxCntToStop)
            break
        end
    end
end

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