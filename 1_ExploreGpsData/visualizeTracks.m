% VISUALIZETRACKS Visualize INDOT GPS tracks in overview figures.
%
% Yaguang Zhang, Purdue, 04/18/2022

clear; clc; close all; dbstop if error;

% Locate the Matlab workspace and save the current filename.
cd(fileparts(mfilename('fullpath'))); cd('..'); addpath('lib');
curFileName = mfilename;

prepareSimulationEnv;

% The absolute path to the folder for saving the results.
pathToSaveResults = fullfile(pwd, '..', ...
    'PostProcessingResults', '1_GpsTrackOverview');
if ~exist(pathToSaveResults, 'dir')
    mkdir(pathToSaveResults)
end

% The absolute path to the INDOT GPS data .csv file.
pathToGpsLocCsv = fullfile(pwd, '..', ...
    '20220221_ExampleData', '20210301_to_20210501_avl', ...
    '20210301_to_20210501_location.csv');

% % We will load cached results for faster processing if available.
%  dirToCachedResults = fullfile(pathToSaveResults, 'cachedResults.mat');
% if exist(dirToCachedResults, 'file')
%     disp(' ')
%      disp(['[', datestr(now, datetimeFormat), ...
%         '] Loading cached geo info for ACRE ...'])
%
%     load(dirToCachedResults);
% else
%     % Load Boundary
%      disp(' ')
%     disp(['[', datestr(now, datetimeFormat), ...
%         '] Extracting geo info for ACRE ...'])
%
%     % Cache the Results
%      disp(' ')
%     disp(['    [', datestr(now, datetimeFormat), ...
%         '] Caching results ...'])
%
%     save(dirToCachedResults, 'varsToCache');
% end

% Log the command line output.
diary(fullfile(pathToSaveResults, 'Diary.log'));

%% Load GPS Data

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading GPS location info ...'])

gpsLocTable = readtable(pathToGpsLocCsv);

% Add a new column speedmph.
gpsLocTable.speedmph =  convlength(gpsLocTable.speedkph, 'km', 'mi');

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Overall Statistics

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Generating overall statistics figures ...'])

fieldsToGenFilteredHistogram = {'vehicleId', 'heading',
    'speedkph', 'speedmph'};
for idxField = 1:length(fieldsToGenFilteredHistogram)
    curField = fieldsToGenFilteredHistogram{idxField};
    curData = gpsLocTable{:, curField};

    figure; histogram(curData);
    axis tight; grid on; grid minor;
    xlabel(curField);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '.jpg']));

    figure; ecdf(curData);
    grid on; grid minor;
    xlabel(curField);
    ylabel('Empirical CDF');

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '.jpg']));
end

fieldsToGenNonZeroHistogram = {'speedkph', 'speedmph'};
fctsValidation = {@(kph) kph>0&kph<150, ...
    @(mph) mph>0&mph<convlength(150, 'km', 'mi')};
curFigPos = [0,0,1200,800];
for idxField = 1:length(fieldsToGenNonZeroHistogram)
    curField = fieldsToGenNonZeroHistogram{idxField};
    curData = gpsLocTable{:, curField};

    curFctValidation = fctsValidation{idxField};

    % Remove invalid values.
    curValData = curData(curFctValidation(curData));

    figure('Position', curFigPos); histogram(curValData);
    axis tight; grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curValData)), ...
        ', MAX = ', num2str(max(curValData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ValidValue_Histogram_', curField, '.jpg']));

    figure('Position', curFigPos); ecdf(curValData);
    grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Empirical CDF');

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ValidValue_ECDF_', curField, '.jpg']));

    % Look at non-zero invalid values.
    curNonZeroInvalData = curData(~curFctValidation(curData));
    curNonZeroInvalData(curNonZeroInvalData==0) = [];

    figure('Position', curFigPos); histogram(curNonZeroInvalData);
    axis tight; grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curNonZeroInvalData)), ...
        ', MAX = ', num2str(max(curNonZeroInvalData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_NonZeroInvalidValue_Histogram_', ...
        curField, '.jpg']));

    figure('Position', curFigPos); ecdf(curNonZeroInvalData);
    grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Empirical CDF');

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_NonZeroInvalidValue_ECDF_', ...
        curField, '.jpg']));
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Organize Points into Tracks

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Organizing GPS points into tracks ...'])

% UTC time stamps.
dateTimesUtc = datetime(gpsLocTable.timestamp, 'TimeZone', 'UTC');
% Local time stamps.
dateTimesEst = dateTimesUtc;
dateTimesEst.TimeZone = 'America/Indianapolis';

% Sort GPS points into days;
dayCnts = day(dateTimesEst - dateTimesEst(1));
uniqueDayCnts = unique(dayCnts);
numOfDays = length(uniqueDayCnts);

% Break the complete table into smaller ones by date and sort the records
% by vehicle ID.
gpsLocTableDays = cell(numOfDays, 1);
% Break each day's record into tracks. Each element will be a column cell
% of tracks. Each track will be a Nx2 (lon, lat) matrix, where N is the
% number of GPS locs for that track.
gpsLonLatTracksEachDay = cell(numOfDays, 1);
% Also fetch the time stamps (stored as datetime) for the GPS samples.
gpsDatetimeStampsEachDay = cell(numOfDays, 1);
% The absolute path to save daily track overview figures.
pathToSaveDailyTrackOverviewFigs = fullfile(pathToSaveResults, ...
    'DailyTrackOverviews');
if ~exist(pathToSaveDailyTrackOverviewFigs, 'dir')
    mkdir(pathToSaveDailyTrackOverviewFigs)
end
% Indiana boundary as reference.
[inBoundaryLatLons, ~, ~] = loadInBoundary;

for idxDay = 1:numOfDays
    curDayCnt = uniqueDayCnts(idxDay);
    gpsLocTableDays{idxDay} = sortrows( ...
        gpsLocTable(dayCnts==curDayCnt, :), {'vehicleId', 'timestamp'});

    curVehIds = gpsLocTableDays{idxDay}.vehicleId;
    curUniqueVehIds = unique(curVehIds);
    curNumOfVehs = length(curUniqueVehIds);

    curGpsLonLatTracks = cell(curNumOfVehs, 1);
    curGpsDatetimeStamps = cell(curNumOfVehs, 1);
    for idxTrack = 1:curNumOfVehs
        curVehId = curUniqueVehIds(idxTrack);
        curGpsLonLatTracks{idxTrack} = gpsLocTableDays{idxDay}{ ...
            curVehIds == curVehId, {'geo_Long', 'geo_Lat'}};
        curGpsDatetimeStamps{idxTrack} = gpsLocTableDays{idxDay}{ ...
            curVehIds == curVehId, {'timestamp'}};
    end

    gpsLonLatTracksEachDay{idxDay} = curGpsLonLatTracks;
    gpsDatetimeStampsEachDay{idxDay} = curGpsDatetimeStamps;
end

disp(['    [', datestr(now, datetimeFormat), ...
    '] Generating overview maps for tracks on each day ...'])

% Reuse background graphics.
figure('Position', [0,0,800,800]); hold on;
hPolyIn = plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    'k-', 'LineWidth', 3);
xlabel('Longitute'); ylabel('Latitude');
plot_google_map('MapType', 'road');
axis manual; axisToSetIn = axis;
axisToSetIndianapolis ...
    = [-86.41144465, -85.91499717, 39.56458894, 39.96588788];
for idxDay = 1:numOfDays
    curNumOfVehs = length(unique(gpsLocTableDays{idxDay}.vehicleId));
    hTrackLines = cell(curNumOfVehs, 1);

    curGpsLonLatTracks = gpsLonLatTracksEachDay{idxDay};
    for idxTrack = 1:curNumOfVehs
        hTrackLines{idxTrack} = plot(curGpsLonLatTracks{idxTrack}(:,1), ...
            curGpsLonLatTracks{idxTrack}(:,2), '.--', ...
            'MarkerSize', 9, 'LineWidth', 0.2);
    end
    [y,m,d] = ymd(gpsLocTableDays{idxDay}{1,'timestamp'});

    axis(axisToSetIn);
    saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['TracksInIndiana_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '.jpg']));

    axis(axisToSetIndianapolis);
    saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['TracksInIndiana_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '_ZoomedIn.jpg']));

    delete([hTrackLines{:}]);
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Calculate GPS Sampling Time

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Estimating GPS sampling time ...'])

sampTimesInSEachDay = cell(numOfDays, 1);
for idxDay = 1:numOfDays
    curNumOfVehs = length(unique(gpsLocTableDays{idxDay}.vehicleId));
    hTrackLines = cell(curNumOfVehs, 1);

    curGpsDatetimeStamps = gpsDatetimeStampsEachDay{idxDay};
    curSampTimesInS = cell(curNumOfVehs, 1);
    for idxTrack = 1:curNumOfVehs
        curSampTimesInS{idxTrack} = diff(convertTo( ...
            curGpsDatetimeStamps{idxTrack}, 'posixtime'));
    end
    sampTimesInSEachDay{idxDay} = curSampTimesInS;
end

sampTimesInS = vertcat(cellfun(@(c) vertcat(c{:}), ...
    sampTimesInSEachDay, 'UniformOutput', false));
sampTimesInS = vertcat(sampTimesInS{:});

aveSampTimesInSForTracks = vertcat(cellfun(@(c) vertcat( ...
    cellfun(@(times) mean(times), c)), ...
    sampTimesInSEachDay, 'UniformOutput', false));
aveSampTimesInSForTracks = vertcat(aveSampTimesInSForTracks{:});

disp(['    [', datestr(now, datetimeFormat), ...
    '] Generating overview figures for sampling time ...'])

fieldsToGenStaFig = {'sampTimesInS', 'aveSampTimesInSForTracks'};
zoomXRanges = {[0, 600], [0, 1800]};

for idxField = 1:length(fieldsToGenStaFig)
    curField = fieldsToGenStaFig{idxField};
    curData = eval(curField);
    curZoomXRange = zoomXRanges{idxField};

    figure; histogram(curData);
    axis tight; grid on; grid minor;
    xlabel(curField);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '.jpg']));

    xlim(curZoomXRange);
    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '_ZoomedIn.jpg']));

    figure; ecdf(curData);
    grid on; grid minor;
    xlabel(curField);
    ylabel('Empirical CDF');

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '.jpg']));

    xlim(curZoomXRange);
    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '_ZoomedIn.jpg']));
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

% EOF