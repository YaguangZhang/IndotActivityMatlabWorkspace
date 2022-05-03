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

% For plotting.
googleMapAlpha = 0.25;

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

fieldsToGenFilteredHistogram = {'vehicleId', 'heading', ...
    'speedkph', 'speedmph'};
zoomXRanges = {[], [], [0, 150], [0, 100]};

for idxField = 1:length(fieldsToGenFilteredHistogram)
    curField = fieldsToGenFilteredHistogram{idxField};
    curData = gpsLocTable{:, curField};
    curZoomXRange = zoomXRanges{idxField};

    figure; histogram(curData);
    axis tight; grid on; grid minor;
    xlabel(curField);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '.jpg']));

    if ~isempty(curZoomXRange)
        xlim(curZoomXRange);
        saveas(gcf, fullfile(pathToSaveResults, ...
            ['OverallStatistics_Histogram_', curField, '_ZoomedIn.jpg']));
    end

    figure; ecdf(curData);
    grid on; grid minor;
    xlabel(curField);
    ylabel('Empirical CDF');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '.jpg']));

    if ~isempty(curZoomXRange)
        xlim(curZoomXRange);
        saveas(gcf, fullfile(pathToSaveResults, ...
            ['OverallStatistics_ECDF_', curField, '_ZoomedIn.jpg']));
    end
end

fieldsToGenNonZeroHistogram = {'speedkph', 'speedmph'};
fctsValidation = {@(kph) kph>0&kph<150, ...
    @(mph) mph>0&mph<convlength(150, 'km', 'mi')};
cdfAndHistFigPos = [0,0,630,420];
for idxField = 1:length(fieldsToGenNonZeroHistogram)
    curField = fieldsToGenNonZeroHistogram{idxField};
    curData = gpsLocTable{:, curField};

    curFctValidation = fctsValidation{idxField};

    % Remove invalid values.
    curValData = curData(curFctValidation(curData));

    numOfIgnoredZeroPts = sum(curData==0);
    numOfPts = size(curData,1);
    numOfTooBigPts = numOfPts - size(curValData,1) - numOfIgnoredZeroPts;

    figure('Position', cdfAndHistFigPos); histogram(curValData);
    axis tight; grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Record Count (#)');
    title({['min = ', num2str(min(curValData)), ...
        ', MAX = ', num2str(max(curValData))], ...
        ['# of ignored zero pts = ', num2str(numOfIgnoredZeroPts), ...
        ' (', num2str(numOfIgnoredZeroPts/numOfPts*100, '%.2f'), ...
        '%)'], ['# of ignored too big pts = ', ...
        num2str(numOfTooBigPts), ' (', ...
        num2str(numOfTooBigPts/numOfPts*100, '%.2f'), '%)']});

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ValidValue_Histogram_', curField, '.jpg']));

    figure('Position', cdfAndHistFigPos); ecdf(curValData);
    grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Empirical CDF');

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ValidValue_ECDF_', curField, '.jpg']));

    % Look at non-zero invalid values.
    curNonZeroInvalData = curData(~curFctValidation(curData));
    curNonZeroInvalData(curNonZeroInvalData==0) = [];

    figure('Position', cdfAndHistFigPos); histogram(curNonZeroInvalData);
    axis tight; grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curNonZeroInvalData)), ...
        ', MAX = ', num2str(max(curNonZeroInvalData))])

    saveas(gcf, fullfile(pathToSaveResults, ...
        ['OverallStatistics_NonZeroInvalidValue_Histogram_', ...
        curField, '.jpg']));

    figure('Position', cdfAndHistFigPos); ecdf(curNonZeroInvalData);
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

% Sort GPS points into days; counting from day 1.
dayCnts = 1 + floor(days( ...
    dateTimesEst - dateshift(dateTimesEst(1), 'start', 'day')));
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
[inBoundaryLatLons, inBoundaryXYs, inBoundaryUtmZone] = loadInBoundary;

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
set(gca, 'FontWeight', 'bold');
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    'k-', 'LineWidth', 3);
xlabel('Longitude (degree)'); ylabel('Latitude (degree)');
plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha);
axis manual; axisToSetIn = axis;
axisToSetIndianapolis ...
    = [-86.41144465, -85.91499717, 39.56458894, 39.96588788];
for idxDay = 1:numOfDays
    curNumOfVehs = length(unique(gpsLocTableDays{idxDay}.vehicleId));
    hTrackLines = cell(curNumOfVehs, 1);

    curGpsLonLatTracks = gpsLonLatTracksEachDay{idxDay};
    for idxTrack = 1:curNumOfVehs
        hTrackLines{idxTrack} = plot(curGpsLonLatTracks{idxTrack}(:,1), ...
            curGpsLonLatTracks{idxTrack}(:,2), '.-', ...
            'MarkerSize', 9);
    end
    [y,m,d] = ymd(gpsLocTableDays{idxDay}{1,'timestamp'});
    title(['GPS Tracks on ', ...
        num2str(m), '/', num2str(d), '/', num2str(y)]);

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

disp(['    [', datestr(now, datetimeFormat), ...
    '] Locating samples out of IN ...'])
% Samples out of Indiana.
gpsLonLatCoors = vertcat(cellfun(@(c) vertcat(c{:}), ...
    gpsLonLatTracksEachDay, 'UniformOutput', false));
gpsLonLatCoors = vertcat(gpsLonLatCoors{:});

% There are too many points to be handled by the built-in funciton
% inpolygon. We noticed some false alarms from InPolygon. Here, we will use
% another faster implementation of inpolygon, called inpoly2.
boolsGpsLonLatCoorsOutOfIn = ~inpoly2(gpsLonLatCoors, ...
    inBoundaryLatLons(:,2:-1:1));

gpsLonLatCoorsOutOfIn = gpsLonLatCoors(boolsGpsLonLatCoorsOutOfIn, :);

figure('Position', [0,0,800,800]); hold on;
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    'k-', 'LineWidth', 3);
plot(gpsLonLatCoorsOutOfIn(:,1), gpsLonLatCoorsOutOfIn(:,2), 'r.');
xlabel('Longitute'); ylabel('Latitude');
plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha);
title(['Total # of Samples Out of IN: ', ...
    num2str(size(gpsLonLatCoorsOutOfIn,1))]);

saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SamplesOutOfIndiana.jpg'));
saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SamplesOutOfIndiana.fig'));

% Zoom the map to Atlanta.
axisToSetAtlanta ...
    = [-84.23889285, -84.22676274, 33.95715299, 33.96773302];
axis(axisToSetAtlanta);
plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha);

title(['Total # of Potentially Anomaly Samples in This View: ', ...
    num2str(sum(InPolygon( ...
    gpsLonLatCoorsOutOfIn(:,1), gpsLonLatCoorsOutOfIn(:,2), ...
    axisToSetAtlanta([1,2,2,1,1]), axisToSetAtlanta([3,3,4,4,3]) ...
    )))]);

saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SamplesOutOfIndiana_Atlanta.jpg'));
saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SamplesOutOfIndiana_Atlanta.fig'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Inspect the Time Stamps

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Calculating time stamps in hours past midnight each day ...'])

timestampsInHPastMidnight = hours( ...
    dateTimesEst - dateshift(dateTimesEst, 'start', 'day'));

figure('Position', cdfAndHistFigPos); histogram(timestampsInHPastMidnight);
xlim([0, 24]); axis tight; grid on; grid minor;
xlabel(['Local Time After Midnight at ', dateTimesEst.TimeZone, ' (h)']);
ylabel('Record Count (#)');

saveas(gcf, fullfile(pathToSaveResults, ...
    ['OverallStatistics_Histogram_', curField, '.jpg']));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Calculate GPS Sampling Time

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Estimating GPS sampling time ...'])

sampTimesInSEachDay = cell(numOfDays, 1);
for idxDay = 1:numOfDays
    curNumOfVehs = length(unique(gpsLocTableDays{idxDay}.vehicleId));

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

numOfPtsForTracks = vertcat(cellfun(@(c) vertcat( ...
    cellfun(@(pts) size(pts, 1), c)), ...
    gpsLonLatTracksEachDay, 'UniformOutput', false));
numOfPtsForTracks = vertcat(numOfPtsForTracks{:});

disp(['    [', datestr(now, datetimeFormat), ...
    '] Generating overview figures for sampling time ...'])

fieldsToGenStaFig = {'sampTimesInS', 'aveSampTimesInSForTracks', ...
    'numOfPtsForTracks'};
zoomXRanges = {[0, 600], [0, 1800], [0, 600]};

for idxField = 1:length(fieldsToGenStaFig)
    curField = fieldsToGenStaFig{idxField};
    curData = eval(curField);
    curZoomXRange = zoomXRanges{idxField};

    figure('Position', cdfAndHistFigPos); histogram(curData);
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

    figure('Position', cdfAndHistFigPos); ecdf(curData);
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

%% Plot Sampling Time on Map

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Showing sampling time on map for tracks on each day ...'])

% For the overview plot.
[gpsLonLatTracks, gpsLonLatToPlot, sampTimesInMinToPlot, boolsOvertime] ...
    = deal(cell(numOfDays, 1));

% Reuse background graphics.
figure('Position', [0,0,800,800]); hold on;
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    'k-', 'LineWidth', 3);
xlabel('Longitute'); ylabel('Latitude');

curColomap = autumn; curColomap = curColomap(end:-1:1, :);
colormap(curColomap);
maxSampTimeInMinForPlot3k = 10;
overTimeSampColor = curColomap(end, :);
lonLatTrackColor = 'b';
colorbar;

plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha); axis manual;
for idxDay = 1:numOfDays
    [y,m,d] = ymd(gpsLocTableDays{idxDay}{1,'timestamp'});
    curFigTitle = ['Sampling Time for ', ...
        num2str(m), '/', num2str(d), '/', num2str(y)];
    curXLabel = 'Longitude (degree)';
    curYLabel = 'Latitude (degree)';
    curZLabel = '';
    curPlot3kCbLabel = 'Sampling Time (min)';

    % For plotting the tracks as background.
    curNumOfVehs = length(unique(gpsLocTableDays{idxDay}.vehicleId));
    hTrackLines = cell(curNumOfVehs, 1);

    curGpsLonLatTracks = gpsLonLatTracksEachDay{idxDay};
    for idxTrack = 1:curNumOfVehs
        hTrackLines{idxTrack} = plot( ...
            curGpsLonLatTracks{idxTrack}(:,1), ...
            curGpsLonLatTracks{idxTrack}(:,2), '-', ...
            'Color', lonLatTrackColor, 'LineWidth', 1);
    end

    % Get rid of the first GPS loc for each track and merge the records.
    curGpsLonLatToPlot = vertcat(cellfun( ...
        @(lonLatMat) lonLatMat(2:end, :), ...
        gpsLonLatTracksEachDay{idxDay}, ...
        'UniformOutput', false));
    curGpsLonLatToPlot = vertcat(curGpsLonLatToPlot{:});

    curSampTimesInMinToPlot = sampTimesInSEachDay{idxDay};
    curSampTimesInMinToPlot = vertcat(curSampTimesInMinToPlot{:})./60;

    curBoolsOvertime = curSampTimesInMinToPlot>maxSampTimeInMinForPlot3k;
    plot3k([curGpsLonLatToPlot(~curBoolsOvertime, :), ...
        curSampTimesInMinToPlot(~curBoolsOvertime)], ...
        'ColorRange', [0, maxSampTimeInMinForPlot3k], 'Labels', ...
        {curFigTitle, curXLabel, curYLabel, curZLabel, curPlot3kCbLabel});
    view(2); zlim([0, maxSampTimeInMinForPlot3k]);

    if any(curBoolsOvertime)
        hOverTimeRecords = plot3( ...
            curGpsLonLatToPlot(curBoolsOvertime, 1), ...
            curGpsLonLatToPlot(curBoolsOvertime, 2), ...
            maxSampTimeInMinForPlot3k.*ones(sum(curBoolsOvertime), 1), ...
            'x', 'Color', overTimeSampColor, 'LineStyle', 'none', ...
            'MarkerSize', 8, 'LineWidth', 1.1);

        legend([hOverTimeRecords, hTrackLines{1}], ...
            ['Over ', num2str(maxSampTimeInMinForPlot3k), ' min'], ...
            'Record Gap', ...
            'Location', 'northwest');
    else
        legend(hTrackLines{1}, 'Record Gap', 'Location', 'northwest');
    end

    saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['SampTimeInS_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '.jpg']));

    % Delete current figure objects.
    hSampTimePlot3k = findobj(gca,'tag','plot3k');
    delete(hSampTimePlot3k);
    delete([hTrackLines{:}]);
    if any(curBoolsOvertime)
        delete(hOverTimeRecords);
    end
    legend off;

    gpsLonLatTracks{idxDay} = curGpsLonLatTracks;
    gpsLonLatToPlot{idxDay} = curGpsLonLatToPlot;
    sampTimesInMinToPlot{idxDay} = curSampTimesInMinToPlot;
    boolsOvertime{idxDay} = curBoolsOvertime;
end

gpsLonLatTracks = vertcat(gpsLonLatTracks{:});
gpsLonLatToPlot = vertcat(gpsLonLatToPlot{:});
sampTimesInMinToPlot = vertcat(sampTimesInMinToPlot{:});
boolsOvertime = logical(vertcat(boolsOvertime{:}));

numOfVehs = length(gpsLonLatTracks);
hTrackLines = cell(numOfVehs, 1);
for idxTrack = 1:numOfVehs
    hTrackLines{idxTrack} = plot( ...
        gpsLonLatTracks{idxTrack}(:,1), ...
        gpsLonLatTracks{idxTrack}(:,2), '-', ...
        'Color', lonLatTrackColor, 'LineWidth', 1);
end

title('All GPS Tracks');
set(colorbar,'visible','off');
saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview_TracksOnly.jpg'));

curFigTitle = 'Sampling Time for All Dates';
plot3k([gpsLonLatToPlot(~boolsOvertime, :), ...
    sampTimesInMinToPlot(~boolsOvertime)], ...
    'ColorRange', [0, maxSampTimeInMinForPlot3k], 'Labels', ...
    {curFigTitle, curXLabel, curYLabel, curZLabel, curPlot3kCbLabel});
view(2); zlim([0, maxSampTimeInMinForPlot3k]);

if any(boolsOvertime)
    hOverTimeRecords = plot3( ...
        gpsLonLatToPlot(boolsOvertime, 1), ...
        gpsLonLatToPlot(boolsOvertime, 2), ...
        maxSampTimeInMinForPlot3k.*ones(sum(boolsOvertime), 1), ...
        'x', 'Color', overTimeSampColor, 'LineStyle', 'none', ...
        'MarkerSize', 8, 'LineWidth', 1.1);

    legend([hOverTimeRecords, hTrackLines{1}], ...
        ['Over ', num2str(maxSampTimeInMinForPlot3k), ' min'], ...
        'Record Gap', ...
        'Location', 'northwest');
else
    legend(hTrackLines{1}, 'Record Gap', 'Location', 'northwest');
end

saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview.jpg'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

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