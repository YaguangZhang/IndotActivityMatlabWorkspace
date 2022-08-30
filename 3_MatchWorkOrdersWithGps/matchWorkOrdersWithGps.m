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

% Time string format.
INDOT_DATE_FORMAT = 'dd-MMM-yy';
INDOT_TIMESTR_FORMAT = 'dd-MMM-yy hh.mm.ss.SSSSSSSSS a';
% Expected time zone.
LOCAL_TIME_ZONE = 'America/Indianapolis';

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

parsedGpsSamps.localDatetime = datetime(vehicleTimeStamps, ...
    'InputFormat', INDOT_TIMESTR_FORMAT);
parsedGpsSamps.primeKey      = gpsLocTable.PRIMARY_KEY;
parsedGpsSamps.vehId         = gpsLocTable.VEHICLE_ID;
parsedGpsSamps.lat           = gpsLocTable.LATITUDE;
parsedGpsSamps.lon           = gpsLocTable.LONGITUDE;
parsedGpsSamps.speedMph      = gpsLocTable.SPEED_MILES_PER_HOUR;
parsedGpsSamps.heading       = gpsLocTable.VEHICLE_HEADING;

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Extracting and Formatting Needed Information - Work Orders

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Extracting and formatting needed work order information ...'])

% We only care about the work order entries for vehicles.
boolsIsEquipment = strcmp(workOrderTable.ResourceType, 'Equipment');
vehWorkOrderTable = workOrderTable(boolsIsEquipment, :);

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

parsedVehWorkOrders.localDatetime = datetime(vehWorkOrderTable.WorkDate, ...
    'Format', INDOT_DATE_FORMAT, 'TimeZone', LOCAL_TIME_ZONE);
parsedVehWorkOrders.workOrderId = vehWorkOrderTable.WO;
parsedVehWorkOrders.vehId = vehIds;
parsedVehWorkOrders.vehName = vehNames;
parsedVehWorkOrders.actId = actIds;
parsedVehWorkOrders.actName = actNames;
parsedVehWorkOrders.totalHrs = vehWorkOrderTable.TotalHrs;

disp(['[', datestr(now, datetimeFormat), '] Done!'])

%% Clean Up

close all;
diary off;

% EOF