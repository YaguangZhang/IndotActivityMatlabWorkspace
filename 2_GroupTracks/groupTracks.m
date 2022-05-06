% GROUPTRACKS Group INDOT GPS tracks into patching fleets.
%
% Yaguang Zhang, Purdue, 04/29/2022

clear; clc; close all; dbstop if error;

% Locate the Matlab workspace and save the current filename.
cd(fileparts(mfilename('fullpath'))); cd('..'); addpath('lib');
curFileName = mfilename;

prepareSimulationEnv;

% The absolute path to the folder for saving the results.
pathToSaveResults = fullfile(pwd, '..', ...
    'PostProcessingResults', '2_PatchingFleets');
if ~exist(pathToSaveResults, 'dir')
    mkdir(pathToSaveResults)
end

% The absolute path to the folder for saving daily (debugging) results.
pathToSaveDailyResults = fullfile(pathToSaveResults, 'DailyResults');
if ~exist(pathToSaveDailyResults, 'dir')
    mkdir(pathToSaveDailyResults)
end

% Log the command line output.
diary(fullfile(pathToSaveResults, 'Diary.log'));

% Load results about GPS tracks from 1_ExploreGpsData/visualizeTracks.m.
pathToCachedGpsInfo = fullfile(pathToSaveResults, '..', ...
    '1_GpsTrackOverview', 'workspace.mat');

% For plotting.
FLAG_SILENT_FIGS = true;
trackTimeRangeFigPos = [0,0,550,640];
defaultLineColors = [0, 0.4470, 0.7410; ...
    0.8500, 0.3250, 0.0980; ...
    0.9290, 0.6940, 0.1250; ...
    0.4940, 0.1840, 0.5560; ...
    0.4660, 0.6740, 0.1880; ...
    0.3010, 0.7450, 0.9330; ...
    0.6350, 0.0780, 0.1840];

%% Load GPS Tracks

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading GPS location info ...'])

if ~exist(pathToCachedGpsInfo, 'file')
    error(['Unable to load GPS info! ', ...
        'Please run 1_ExploreGpsData/visualizeTracks.m and try again.']);
else
    load(pathToCachedGpsInfo, 'LOCAL_TIME_ZONE', ... .
        'gpsLocTableEachDay', ... % GPS info for tracks of each day.
        'simConfigs'); % For convertions between GPS and UTM.
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Break Daily Tracks into Smaller Ones

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Clean tracks by breaking the ones with too big time gaps ...'])

% Clean tracks in each day by breaking them when the time gap is too big.
% We will use gpsLocTableEachDay.
MAX_ALLOWED_TIME_GAP_IN_MIN = 10;
numOfDays = length(gpsLocTableEachDay);

gpsLocTableCleanTracksEachDay = cell(numOfDays, 1);
for idxDay = 1:numOfDays
    curNumOfVehs = length(gpsLocTableEachDay{idxDay});

    gpsLocTableCleanTracksEachDay{idxDay} = cell(curNumOfVehs, 1);
    for idxVeh = 1:curNumOfVehs
        curGpsLocTable = gpsLocTableEachDay{idxDay}{idxVeh};
        curNumOfSamps = size(curGpsLocTable, 1);

        curGpsSampTimesInMin = minutes(diff( ...
            curGpsLocTable.timestamp_local))';
        sampIndicesToBreakTrack ...
            = [find(curGpsSampTimesInMin>MAX_ALLOWED_TIME_GAP_IN_MIN), ...
            curNumOfSamps];

        numOfCleanTracks = length(sampIndicesToBreakTrack);
        gpsLocTableCleanTracksEachDay{idxDay}{idxVeh} ...
            = cell(numOfCleanTracks, 1);
        for idxCleanTrack = 1:numOfCleanTracks
            if idxCleanTrack==1
                idxStartSamp = 1;
            else
                idxStartSamp = sampIndicesToBreakTrack(idxCleanTrack-1)+1;
            end
            idxEndSamp = sampIndicesToBreakTrack(idxCleanTrack);

            gpsLocTableCleanTracksEachDay{idxDay}{idxVeh} ...
                {idxCleanTrack} ...
                = curGpsLocTable(idxStartSamp:idxEndSamp, :);
            assert(~isempty(gpsLocTableCleanTracksEachDay ...
                {idxDay}{idxVeh}{idxCleanTrack}), ...
                'Err: Empty clean track!');
        end
    end
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Searching for Close-By Vehicle Pairs

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Searching for close-by vehicle pairs ...'])

% Two vehicles are a close-by pair if and only if they are close enough for
% long enough time.
MAX_CLOSE_BY_DIST_IN_M = 100;
MIN_CLOSE_BY_TIME_IN_MIN = 5;

% Results will be packed into a cell, closeByVehsEachDay, with tables
% organized in a similar way as gpsLocTableCleanTracksEachDay, that is, it
% will be indexed via:
%   closeByVehsEachDay{idxDay}{idxVeh}{idxCleanTrack}
% And each element is a table, each row corresponding to a GPS record in
% gpsLocTableCleanTracksEachDay, containing fields:
%   utm_x, utm_y, closeByVehsId (a column vector), closeByVehDistsInM (a
%   column vector).
closeByVehsEachDay = cell(numOfDays, 1);
% Record the time ranges for debugging.
timestampRangesEachDay = cell(numOfDays, 1);
for idxDay = 1:numOfDays
    curNumOfVehs = length(gpsLocTableCleanTracksEachDay{idxDay});
    closeByVehsEachDay{idxDay} = cell(curNumOfVehs, 1);

    % Record the time ranges of the clean tracks.
    localTimestampRanges = cell(curNumOfVehs, 1);
    for idxVeh = 1:curNumOfVehs
        curNumOfCleanTs = length( ...
            gpsLocTableCleanTracksEachDay{idxDay}{idxVeh});
        [closeByVehsEachDay{idxDay}{idxVeh}, ...
            localTimestampRanges{idxVeh}] = deal(cell(curNumOfCleanTs, 1));

        % Initialize closeByVehsEachDay with UTM (x, y) coordinates.
        for idxCleanTrack = 1:curNumOfCleanTs
            curGpsLocTrackTable = gpsLocTableCleanTracksEachDay ...
                {idxDay}{idxVeh}{idxCleanTrack};

            [utm_x, utm_y] = simConfigs.deg2utm_speZone( ...
                curGpsLocTrackTable.geo_Lat, curGpsLocTrackTable.geo_Long);
            [closeByVehsId, closeByVehDistsInM] = deal(cell(size(utm_x)));

            closeByVehsEachDay{idxDay}{idxVeh}{idxCleanTrack} ...
                = table(utm_x, utm_y, closeByVehsId, closeByVehDistsInM);

            localTimestampRanges{idxVeh}{idxCleanTrack} ...
                = curGpsLocTrackTable{[1,end], 'timestamp_local'}';
        end
    end
    timestampRangesEachDay{idxDay} = localTimestampRanges;

    % Plot debug figs for track time range.
    localDateTimeThisDay = dateshift(localTimestampRanges{1}{1}(1), ...
        'start', 'day');
    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', trackTimeRangeFigPos);
    hold on;
    vehIds = nan(curNumOfVehs, 1);
    for idxVeh = 1:curNumOfVehs
        curNumOfCleanTs = length( ...
            gpsLocTableCleanTracksEachDay{idxDay}{idxVeh});

        [curXsToPlot, curYsToPlot] = deal(nan(2, curNumOfCleanTs));
        curVehId = gpsLocTableCleanTracksEachDay ...
            {idxDay}{idxVeh}{1}{1, 'vehicleId'};
        vehIds(idxVeh) = curVehId;
        for idxCleanTrack = 1:curNumOfCleanTs
            curTimeRangeInH = hours( ...
                localTimestampRanges{idxVeh}{idxCleanTrack} ...
                - localDateTimeThisDay);
            curXsToPlot(:, idxCleanTrack) = curTimeRangeInH';
            curYsToPlot(:, idxCleanTrack) = [curVehId; curVehId];
        end

        plot(curXsToPlot, curYsToPlot, '-', 'LineWidth', 3, ...
            'Color', defaultLineColors( ...
            mod(idxVeh, size(defaultLineColors,1))+1, :));
    end
    xlim([0, 24]); ylim([0, max(vehIds)]);
    xlabel(['Local Time After Midnight at ', LOCAL_TIME_ZONE, ' (h)']);
    ylabel('Vehicle ID');
    grid on; grid minor;
    [y,m,d] = ymd(localDateTimeThisDay);
    title({['Time Range of Cleaned Tracks on ', ...
        num2str(m), '/', num2str(d), '/', num2str(y)], ...
        'Colored by Vehicle ID'});
    saveas(gcf, fullfile(pathToSaveDailyResults, ...
        ['CleanTrackTimeRanges_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '.jpg']));

    % Compute pairwise distances.
    for idxVeh = 1:curNumOfVehs
        curNumOfCleanTs = length( ...
            gpsLocTableCleanTracksEachDay{idxDay}{idxVeh});
        for idxCleanTrack = 1:curNumOfCleanTs
            curLocalTimestampRange ...
                = localTimestampRanges{idxVeh}{idxCleanTrack};
            curUtmXYs = closeByVehsEachDay ...
                {idxDay}{idxVeh}{idxCleanTrack}{:, {'utm_x', 'utm_y'}};

            for idxOtherVeh = [1:(idxVeh-1), (idxVeh+1):curNumOfVehs]
                for idxOtherCleanTrack = 1:length( ...
                        gpsLocTableCleanTracksEachDay{idxDay} ...
                        {idxOtherVeh})
                    curOtherTimesstampRange = localTimestampRanges ...
                        {idxOtherVeh}{idxOtherCleanTrack};

                    curOverlapTimestampRange = [ ...
                        max([curLocalTimestampRange(1), ...
                        curOtherTimesstampRange(1)]), ...
                        min(curLocalTimestampRange(2), ...
                        curOtherTimesstampRange(2))];

                    % Compute distances only when the time range
                    % intersection of the track pair is long enough.
                    if minutes(curOverlapTimestampRange(2) ...
                            -curOverlapTimestampRange(1)) ...
                            >=MIN_CLOSE_BY_TIME_IN_MIN
                        curOtherVehId = nan;



                    end
                end
            end
        end
    end
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Group Vehicles into Maintenance Fleets

% Results will be packed into a cell, vehGroupInfo, with each element being
% a table for a day, corresponding to elements in
% gpsLocTableCleanTracksEachDay, containing fields:
%   groupId, vehIdsInGroup, startTimestamp, endTimestamp

% disp(' ') disp(['[', datestr(now, datetimeFormat), ...
%     '] Grouping tracks into maintenance fleets ...'])
%
%
% disp(['[', datestr(now, datetimeFormat), ...
%     '] Done!'])

%% Load Vehicle Type


%% Save Workspace

% No need to keep the figures.
close all;

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Saving workspace for debugging purposes ...'])

save(fullfile(pathToSaveResults, 'workspace.mat'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

% EOF