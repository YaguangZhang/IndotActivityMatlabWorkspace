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
FLAG_SILENT_FIGS = true;
inBoundColor = [0, 0, 0, googleMapAlpha];
xMarkerSize = 8;
dotMarkerSize = 10;
mapXLabel = 'Longitude (degree)';
mapYLabel = 'Latitude (degree)';
mapZLabel = '';

%% Load GPS Data

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading GPS location info ...'])

gpsLocTable = readtable(pathToGpsLocCsv);

% Add a new column speedmph.
gpsLocTable.speedmph =  convlength(gpsLocTable.speedkph, 'km', 'mi');

% Add a new column timestamp_local.
LOCAL_TIME_ZONE = 'America/Indianapolis';
% UTC time stamps.
dateTimesUtc = datetime(gpsLocTable.timestamp, 'TimeZone', 'UTC');
% Local time stamps.
dateTimesEst = dateTimesUtc;
dateTimesEst.TimeZone = LOCAL_TIME_ZONE;
gpsLocTable.timestamp_local = dateTimesEst;

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

    figure('Visible', ~FLAG_SILENT_FIGS); histogram(curData);
    axis tight; grid on; grid minor;
    xlabel(curField);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '.jpg']));

    if ~isempty(curZoomXRange)
        xlim(curZoomXRange);
        exportgraphics(gca, fullfile(pathToSaveResults, ...
            ['OverallStatistics_Histogram_', curField, '_ZoomedIn.jpg']));
    end

    figure('Visible', ~FLAG_SILENT_FIGS); ecdf(curData);
    grid on; grid minor;
    xlabel(curField);
    ylabel('Empirical CDF');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '.jpg']));

    if ~isempty(curZoomXRange)
        xlim(curZoomXRange);
        exportgraphics(gca, fullfile(pathToSaveResults, ...
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

    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
    histogram(curValData);
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

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ValidValue_Histogram_', curField, '.jpg']));

    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
    ecdf(curValData);
    grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Empirical CDF');

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ValidValue_ECDF_', curField, '.jpg']));

    % Look at non-zero invalid values.
    curNonZeroInvalData = curData(~curFctValidation(curData));
    curNonZeroInvalData(curNonZeroInvalData==0) = [];

    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
    histogram(curNonZeroInvalData);
    axis tight; grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curNonZeroInvalData)), ...
        ', MAX = ', num2str(max(curNonZeroInvalData))])

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_NonZeroInvalidValue_Histogram_', ...
        curField, '.jpg']));

    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
    ecdf(curNonZeroInvalData);
    grid on; grid minor;
    xlabel([curField, ' s.t. ', char(curFctValidation)]);
    ylabel('Empirical CDF');

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_NonZeroInvalidValue_ECDF_', ...
        curField, '.jpg']));
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Organize Points into Tracks

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Organizing GPS points into tracks ...'])

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
% number of GPS locs for that track. Also fetch the time stamps (stored in
% local time as datetime objects) for the GPS samples and the vehicle IDs.
[gpsLonLatTracksEachDay, gpsDatetimeStampsEachDay, vehIdsEachDay] ...
    = deal(cell(numOfDays, 1));
% Divide the complete table into tracks, too.
gpsLocTableEachDay = cell(numOfDays, 1);
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

    curVehIdsDays = gpsLocTableDays{idxDay}.vehicleId;
    curUniqueVehIds = unique(curVehIdsDays);
    curNumOfVehs = length(curUniqueVehIds);

    [curGpsLonLatTracks, curGpsDatetimeStamps, curGpsLocTable] ...
        = deal(cell(curNumOfVehs, 1));
    curVehIds = nan(curNumOfVehs, 1);
    for idxTrack = 1:curNumOfVehs
        curVehId = curUniqueVehIds(idxTrack);
        curGpsLonLatTracks{idxTrack} = gpsLocTableDays{idxDay}{ ...
            curVehIdsDays == curVehId, {'geo_Long', 'geo_Lat'}};

        curGpsDatetimeStamps{idxTrack} = datetime( ...
            gpsLocTableDays{idxDay}{curVehIdsDays == curVehId, ...
            {'timestamp'}}, 'TimeZone', 'UTC');
        curGpsDatetimeStamps{idxTrack}.TimeZone = LOCAL_TIME_ZONE;

        curVehIds(idxTrack) = curVehId;

        curGpsLocTable{idxTrack} ...
            = gpsLocTableDays{idxDay}(curVehIdsDays == curVehId,:);
    end

    gpsLonLatTracksEachDay{idxDay} = curGpsLonLatTracks;
    gpsDatetimeStampsEachDay{idxDay} = curGpsDatetimeStamps;
    vehIdsEachDay{idxDay} = curVehIds;
    gpsLocTableEachDay{idxDay} = curGpsLocTable;
end

disp(['    [', datestr(now, datetimeFormat), ...
    '] Generating overview maps for tracks on each day ...'])

% Reuse background graphics.
figure('Visible', ~FLAG_SILENT_FIGS, 'Position', [0,0,800,800]); hold on;
set(gca, 'FontWeight', 'bold');
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    '-', 'LineWidth', 3, 'Color', inBoundColor);
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
            'MarkerSize', dotMarkerSize);
    end
    [y,m,d] = ymd(gpsLocTableDays{idxDay}{1,'timestamp'});
    title(['GPS Tracks on ', ...
        num2str(m), '/', num2str(d), '/', num2str(y)]);

    axis(axisToSetIn);
    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['TracksInIndiana_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '.jpg']));

    axis(axisToSetIndianapolis);
    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['TracksInIndiana_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '_ZoomedIn.jpg']));

    delete([hTrackLines{:}]);
end

% An overview figure for all tracks (colored by track).
numOfAllTracks = sum(cellfun(@(tab) length(unique(tab.vehicleId)), ...
    gpsLocTableDays));
hTrackLines = cell(numOfAllTracks, 1);
trackCnt = 1;
for idxDay = 1:numOfDays
    curNumOfVehs = length(unique(gpsLocTableDays{idxDay}.vehicleId));
    curGpsLonLatTracks = gpsLonLatTracksEachDay{idxDay};
    for idxTrack = 1:curNumOfVehs
        hTrackLines{trackCnt} = plot(curGpsLonLatTracks{idxTrack}(:,1), ...
            curGpsLonLatTracks{idxTrack}(:,2), '.-', ...
            'MarkerSize', dotMarkerSize, 'Color', rand(1,3));
        trackCnt = trackCnt+1;
    end
end
title({'All GPS Tracks (Colored by Track)', ...
    ['Total # of Tracks = ', num2str(numOfAllTracks)]});
axis(axisToSetIn);
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'TracksInIndiana_All.jpg'));
axis(axisToSetIndianapolis);
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'TracksInIndiana_All_ZoomedIn.jpg'));
delete([hTrackLines{:}]);

% An overview figure for all tracks (colored by vehID).
uniqueVehIds = unique(gpsLocTable.vehicleId);
numOfAllVehs = length(uniqueVehIds);
for idxVeh = 1:numOfAllVehs
    curGpsLonLatTracks = vertcat(arrayfun(@(idxD) ...
        gpsLonLatTracksEachDay{idxD}( ...
        vehIdsEachDay{idxD}==uniqueVehIds(idxVeh), :), ...
        (1:numOfDays)', 'UniformOutput', false));
    % Merge tracks from different days.
    curGpsLonLatTracks = vertcat(curGpsLonLatTracks{:});
    % Merge tracks with [nan nan] paddings for plotting.
    curGpsLonLatTracks = cellfun(@(t) [t; nan nan], ...
        curGpsLonLatTracks, 'UniformOutput', false);
    curGpsLonLatTracks = vertcat(curGpsLonLatTracks{:});

    hTrackLines{idxVeh} = plot(curGpsLonLatTracks(:,1), ...
        curGpsLonLatTracks(:,2), '.-', ...
        'MarkerSize', dotMarkerSize, 'Color', rand(1,3));
end
title({'All GPS Tracks (Colored by Vehicle)', ...
    ['Total # of Vehicles = ', num2str(numOfAllVehs)]});
axis(axisToSetIn);
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'TracksInIndiana_AllVehs.jpg'));
axis(axisToSetIndianapolis);
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'TracksInIndiana_AllVehs_ZoomedIn.jpg'));
delete([hTrackLines{:}]);

% Overview figures for pts out of Indiana.
disp(['    [', datestr(now, datetimeFormat), ...
    '] Locating samples out of IN ...'])

gpsLonLatCoors = vertcat(cellfun(@(c) vertcat(c{:}), ...
    gpsLonLatTracksEachDay, 'UniformOutput', false));
gpsLonLatCoors = vertcat(gpsLonLatCoors{:});
% There are too many points to be handled by the built-in funciton
% inpolygon. We noticed some false alarms from InPolygon. Here, we will use
% another faster implementation of inpolygon, called inpoly2.
boolsGpsLonLatCoorsOutOfIn = ~inpoly2(gpsLonLatCoors, ...
    inBoundaryLatLons(:,2:-1:1));
gpsLonLatCoorsOutOfIn = gpsLonLatCoors(boolsGpsLonLatCoorsOutOfIn, :);

figure('Visible', ~FLAG_SILENT_FIGS, 'Position', [0,0,800,800]); hold on;
set(gca, 'FontWeight', 'bold');
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    '-', 'LineWidth', 3, 'Color', inBoundColor);
plot(gpsLonLatCoorsOutOfIn(:,1), gpsLonLatCoorsOutOfIn(:,2), 'r.');
xlabel('Longitute'); ylabel('Latitude');
plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha);
title(['Total # of Samples Out of IN: ', ...
    num2str(size(gpsLonLatCoorsOutOfIn,1))]);

exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
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

exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SamplesOutOfIndiana_Atlanta.jpg'));
saveas(gcf, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SamplesOutOfIndiana_Atlanta.fig'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Inspect the Time Stamps (Day)

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Calculating time stamps in hours past midnight each day ...'])

timestampsInHPastMidnight = hours( ...
    dateTimesEst - dateshift(dateTimesEst, 'start', 'day'));

figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
histogram(timestampsInHPastMidnight);
xlim([0, 24]); axis tight; grid on; grid minor;
xlabel(['Local Time After Midnight at ', dateTimesEst.TimeZone, ' (h)']);
ylabel('Record Count (#)');

exportgraphics(gca, fullfile(pathToSaveResults, ...
    'TimeStamps_HoursAfterMidnight_Histogram.jpg'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Inspect the Time Stamps (Hour)

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Calculating time stamps in minutes ' ...
    ' past the start of each hour ...'])

timestampsInSPastStartOfEachMin = minutes( ...
    dateTimesEst - dateshift(dateTimesEst, 'start', 'hour'));

figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
histogram(timestampsInSPastStartOfEachMin);
xlim([0, 60]); axis tight; grid on; grid minor;
xlabel('Time After Start of Hour (min)');
ylabel('Record Count (#)');

exportgraphics(gca, fullfile(pathToSaveResults, ...
    'TimeStamps_MinsAfterStartOfHour_Histogram.jpg'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Inspect the Time Stamps (Minute)

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Calculating time stamps in seconds' ...
    ' past the start of each minute ...'])

timestampsInSPastStartOfEachMin = seconds( ...
    dateTimesEst - dateshift(dateTimesEst, 'start', 'minute'));

figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
histogram(timestampsInSPastStartOfEachMin);
xlim([0, 60]); axis tight; grid on; grid minor;
xlabel('Time After Start of Minute (s)');
ylabel('Record Count (#)');

exportgraphics(gca, fullfile(pathToSaveResults, ...
    'TimeStamps_SecondsAfterStartOfMin_Histogram.jpg'));

% Show the locations of the [59.5, 60) time stamps.
boolsPtsToPlot = timestampsInSPastStartOfEachMin>=59 ...
    & timestampsInSPastStartOfEachMin<60;

figure('Visible', ~FLAG_SILENT_FIGS, 'Position', [0,0,800,800]);
hold on; set(gca, 'FontWeight', 'bold');
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    '-', 'LineWidth', 3, 'Color', inBoundColor);
plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha);
axis manual;
plot(gpsLocTable.geo_Long(boolsPtsToPlot), ...
    gpsLocTable.geo_Lat(boolsPtsToPlot), ...
    'r.', 'MarkerSize', dotMarkerSize);
view(2); xlabel(mapXLabel); ylabel(mapYLabel);
title('Points with Time After Start of Minute (s) in [59.5, 60)')

exportgraphics(gca, fullfile(pathToSaveResults, ...
    'TimeStamps_SecondsAfterStartOfMin_SampLocs.jpg'));

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

    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
    histogram(curData);
    axis tight; grid on; grid minor;
    xlabel(curField);
    ylabel('Record Count (#)');
    title(['min = ', num2str(min(curData)), ...
        ', MAX = ', num2str(max(curData))])

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '.jpg']));

    xlim(curZoomXRange);
    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_Histogram_', curField, '_ZoomedIn.jpg']));

    figure('Visible', ~FLAG_SILENT_FIGS, 'Position', cdfAndHistFigPos);
    ecdf(curData);
    grid on; grid minor;
    xlabel(curField);
    ylabel('Empirical CDF');

    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '.jpg']));

    xlim(curZoomXRange);
    exportgraphics(gca, fullfile(pathToSaveResults, ...
        ['OverallStatistics_ECDF_', curField, '_ZoomedIn.jpg']));
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Plot Sampling Time on Map

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Showing sampling time on map for tracks on each day ...'])

% For the overview plot.
[gpsLonLatTracks, gpsLonLatToPlot, sampTimesInMinToPlot, ...
    boolsOvertime, boolsOvertimeS] ...
    = deal(cell(numOfDays, 1));

% Reuse background graphics.
figure('Visible', ~FLAG_SILENT_FIGS, 'Position', [0,0,800,800]); hold on;
set(gca, 'FontWeight', 'bold');
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    '-', 'LineWidth', 3, 'Color', inBoundColor);
xlabel('Longitute'); ylabel('Latitude');

curColomap = turbo; % autumn; curColomap = curColomap(end:-1:1, :);
colormap(curColomap);
maxSampTimeInMinForPlot3k = 10;
maxSampTimeInMinForPlot3kLower = 3;
overTimeSampColor = curColomap(end, :);
lonLatTrackColor = 'k';
colorbar;

plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha); axis manual;

curPlot3kCbLabel = 'Sampling Time (min)';
for idxDay = 1:numOfDays
    [y,m,d] = ymd(gpsLocTableDays{idxDay}{1,'timestamp'});
    curFigTitle = ['Sampling Time for ', ...
        num2str(m), '/', num2str(d), '/', num2str(y)];

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
    [~,~,hCb] = plot3k([curGpsLonLatToPlot(~curBoolsOvertime, :), ...
        curSampTimesInMinToPlot(~curBoolsOvertime)], ...
        'ColorRange', [0, maxSampTimeInMinForPlot3k], 'Labels', ...
        {curFigTitle, mapXLabel, mapYLabel, mapZLabel, curPlot3kCbLabel});
    view(2); zlim([0, maxSampTimeInMinForPlot3k]);
    curMaxTickLabel = hCb.TickLabels{end};
    idxSpaceToReplace = find(isspace(curMaxTickLabel), 1, 'last');
    maxTickLabelToSet ...
        = [curMaxTickLabel(1:(idxSpaceToReplace-1)), '\geq', ...
        curMaxTickLabel((idxSpaceToReplace+1):end)];
    hCb.TickLabels{end} = maxTickLabelToSet;

    if any(curBoolsOvertime)
        hOverTimeRecords = plot3( ...
            curGpsLonLatToPlot(curBoolsOvertime, 1), ...
            curGpsLonLatToPlot(curBoolsOvertime, 2), ...
            maxSampTimeInMinForPlot3k.*ones(sum(curBoolsOvertime), 1), ...
            'x', 'Color', overTimeSampColor, 'LineStyle', 'none', ...
            'MarkerSize', xMarkerSize, 'LineWidth', 1.1);

        legend([hOverTimeRecords, hTrackLines{1}], ...
            ['Over ', num2str(maxSampTimeInMinForPlot3k), ' min'], ...
            'Record Gap', ...
            'Location', 'northwest');
    else
        legend(hTrackLines{1}, 'Record Gap', 'Location', 'northwest');
    end

    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['SampTimeInS_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '.jpg']));
    view(3);
    if any(curBoolsOvertime)
        legend([hOverTimeRecords, hTrackLines{1}], ...
            ['Over ', num2str(maxSampTimeInMinForPlot3k), ' min'], ...
            'GPS Tracks', ...
            'Location', 'northwest');
    else
        legend(hTrackLines{1}, 'GPS Tracks', 'Location', 'northwest');
    end
    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['SampTimeInS_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), '_3D.jpg']));

    % Delete current figure objects.
    hSampTimePlot3k = findobj(gca,'tag','plot3k');
    delete(hSampTimePlot3k);
    % delete([hTrackLines{:}]);
    if any(curBoolsOvertime)
        delete(hOverTimeRecords);
    end
    legend off;

    % Repeat the plot with a slower upper bound.
    curBoolsOvertimeS ...
        = curSampTimesInMinToPlot>maxSampTimeInMinForPlot3kLower;
    [~,~,hCb] = plot3k([curGpsLonLatToPlot(~curBoolsOvertimeS, :), ...
        curSampTimesInMinToPlot(~curBoolsOvertimeS)], ...
        'ColorRange', [0, maxSampTimeInMinForPlot3kLower], 'Labels', ...
        {curFigTitle, mapXLabel, mapYLabel, mapZLabel, curPlot3kCbLabel});
    view(2); zlim([0, maxSampTimeInMinForPlot3kLower]);
    curMaxTickLabel = hCb.TickLabels{end};
    idxSpaceToReplace = find(isspace(curMaxTickLabel), 1, 'last');
    maxTickLabelToSet ...
        = [curMaxTickLabel(1:(idxSpaceToReplace-1)), '\geq', ...
        curMaxTickLabel((idxSpaceToReplace+1):end)];
    hCb.TickLabels{end} = maxTickLabelToSet;

    if any(curBoolsOvertimeS)
        hOverTimeRecords = plot3( ...
            curGpsLonLatToPlot(curBoolsOvertimeS, 1), ...
            curGpsLonLatToPlot(curBoolsOvertimeS, 2), ...
            maxSampTimeInMinForPlot3kLower...
            .*ones(sum(curBoolsOvertimeS), 1), ...
            'x', 'Color', overTimeSampColor, 'LineStyle', 'none', ...
            'MarkerSize', xMarkerSize, 'LineWidth', 1.1);

        legend([hOverTimeRecords, hTrackLines{1}], ...
            ['Over ', num2str(maxSampTimeInMinForPlot3kLower), ' min'], ...
            'Record Gap', ...
            'Location', 'northwest');
    else
        legend(hTrackLines{1}, 'Record Gap', 'Location', 'northwest');
    end

    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['SampTimeInS_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), ...
        '_SmallerCRange.jpg']));
    view(3);
    if any(curBoolsOvertimeS)
        legend([hOverTimeRecords, hTrackLines{1}], ...
            ['Over ', num2str(maxSampTimeInMinForPlot3kLower), ' min'], ...
            'GPS Tracks', ...
            'Location', 'northwest');
    else
        legend(hTrackLines{1}, 'GPS Tracks', 'Location', 'northwest');
    end
    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['SampTimeInS_Date_', ...
        num2str(y), '_', num2str(m), '_', num2str(d), ...
        '_SmallerCRange_3D.jpg']));

    % Delete current figure objects.
    hSampTimePlot3k = findobj(gca,'tag','plot3k');
    delete(hSampTimePlot3k);
    delete([hTrackLines{:}]);
    if any(curBoolsOvertimeS)
        delete(hOverTimeRecords);
    end
    legend off;

    gpsLonLatTracks{idxDay} = curGpsLonLatTracks;
    gpsLonLatToPlot{idxDay} = curGpsLonLatToPlot;
    sampTimesInMinToPlot{idxDay} = curSampTimesInMinToPlot;
    boolsOvertime{idxDay} = curBoolsOvertime;
    boolsOvertimeS{idxDay} = curBoolsOvertimeS;
end

gpsLonLatTracks = vertcat(gpsLonLatTracks{:});
gpsLonLatToPlot = vertcat(gpsLonLatToPlot{:});
sampTimesInMinToPlot = vertcat(sampTimesInMinToPlot{:});
boolsOvertime = logical(vertcat(boolsOvertime{:}));
boolsOvertimeS = logical(vertcat(boolsOvertimeS{:}));

numOfVehs = length(gpsLonLatTracks);
hTrackLines = cell(numOfVehs, 1);
for idxTrack = 1:numOfVehs
    hTrackLines{idxTrack} = plot( ...
        gpsLonLatTracks{idxTrack}(:,1), ...
        gpsLonLatTracks{idxTrack}(:,2), '-', ...
        'Color', lonLatTrackColor, 'LineWidth', 1);
end

title('All GPS Tracks'); view(2);
set(colorbar,'visible','off');
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview_TracksOnly.jpg'));

curFigTitle = 'Sampling Time for All Dates';
[~,~,hCb] = plot3k([gpsLonLatToPlot(~boolsOvertime, :), ...
    sampTimesInMinToPlot(~boolsOvertime)], ...
    'ColorRange', [0, maxSampTimeInMinForPlot3k], 'Labels', ...
    {curFigTitle, mapXLabel, mapYLabel, mapZLabel, curPlot3kCbLabel});
view(2); zlim([0, maxSampTimeInMinForPlot3k]);
curMaxTickLabel = hCb.TickLabels{end};
idxSpaceToReplace = find(isspace(curMaxTickLabel), 1, 'last');
maxTickLabelToSet = [curMaxTickLabel(1:(idxSpaceToReplace-1)), '\geq', ...
    curMaxTickLabel((idxSpaceToReplace+1):end)];
hCb.TickLabels{end} = maxTickLabelToSet;

if any(boolsOvertime)
    hOverTimeRecords = plot3( ...
        gpsLonLatToPlot(boolsOvertime, 1), ...
        gpsLonLatToPlot(boolsOvertime, 2), ...
        maxSampTimeInMinForPlot3k.*ones(sum(boolsOvertime), 1), ...
        'x', 'Color', overTimeSampColor, 'LineStyle', 'none', ...
        'MarkerSize', xMarkerSize, 'LineWidth', 1.1);

    legend([hOverTimeRecords, hTrackLines{1}], ...
        ['Over ', num2str(maxSampTimeInMinForPlot3k), ' min'], ...
        'Record Gap', ...
        'Location', 'northwest');
else
    legend(hTrackLines{1}, 'Record Gap', 'Location', 'northwest');
end

exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview.jpg'));
view(3);
if any(boolsOvertime)
    legend([hOverTimeRecords, hTrackLines{1}], ...
        ['Over ', num2str(maxSampTimeInMinForPlot3k), ' min'], ...
        'GPS Tracks', ...
        'Location', 'northwest');
else
    legend(hTrackLines{1}, 'GPS Tracks', 'Location', 'northwest');
end
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview_3D.jpg'));

% Delete current figure objects.
hSampTimePlot3k = findobj(gca,'tag','plot3k');
delete(hSampTimePlot3k);
% delete([hTrackLines{:}]);
if any(curBoolsOvertime)
    delete(hOverTimeRecords);
end
legend off;

% Repeat the plot with a slower upper bound.
curFigTitle = 'Sampling Time for All Dates';
[~,~,hCb] = plot3k([gpsLonLatToPlot(~boolsOvertimeS, :), ...
    sampTimesInMinToPlot(~boolsOvertimeS)], ...
    'ColorRange', [0, maxSampTimeInMinForPlot3kLower], 'Labels', ...
    {curFigTitle, mapXLabel, mapYLabel, mapZLabel, curPlot3kCbLabel});
view(2); zlim([0, maxSampTimeInMinForPlot3kLower]);
curMaxTickLabel = hCb.TickLabels{end};
idxSpaceToReplace = find(isspace(curMaxTickLabel), 1, 'last');
maxTickLabelToSet = [curMaxTickLabel(1:(idxSpaceToReplace-1)), '\geq', ...
    curMaxTickLabel((idxSpaceToReplace+1):end)];
hCb.TickLabels{end} = maxTickLabelToSet;

if any(boolsOvertimeS)
    hOverTimeRecords = plot3( ...
        gpsLonLatToPlot(boolsOvertimeS, 1), ...
        gpsLonLatToPlot(boolsOvertimeS, 2), ...
        maxSampTimeInMinForPlot3kLower.*ones(sum(boolsOvertimeS), 1), ...
        'x', 'Color', overTimeSampColor, 'LineStyle', 'none', ...
        'MarkerSize', xMarkerSize, 'LineWidth', 1.1);

    legend([hOverTimeRecords, hTrackLines{1}], ...
        ['Over ', num2str(maxSampTimeInMinForPlot3kLower), ' min'], ...
        'Record Gap', ...
        'Location', 'northwest');
else
    legend(hTrackLines{1}, 'Record Gap', 'Location', 'northwest');
end

exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview_SmallerCRange.jpg'));
view(3);
if any(boolsOvertimeS)
    legend([hOverTimeRecords, hTrackLines{1}], ...
        ['Over ', num2str(maxSampTimeInMinForPlot3kLower), ' min'], ...
        'GPS Tracks', ...
        'Location', 'northwest');
else
    legend(hTrackLines{1}, 'GPS Tracks', 'Location', 'northwest');
end
exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
    'SampTimeInS_Overview_SmallerCRange_3D.jpg'));

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Estimate Over-Time GPS Sample Density

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Estimating the density of over-time GPS samples ...'])

simConfigs.NUM_OF_PIXELS_FOR_LONGER_SIDE = 100;
% For GPS and UTM conversions.
[simConfigs.deg2utm_speZone, simConfigs.utm2deg_speZone] ...
    = genUtmConvertersForFixedZone(inBoundaryUtmZone);

[gpsXsToPlot, gpsYsToPlot] = simConfigs.deg2utm_speZone( ...
    gpsLonLatToPlot(:,2), gpsLonLatToPlot(:,1));
gpsXYToPlot = [gpsXsToPlot, gpsYsToPlot];
overTimeSampXYs = gpsXYToPlot(boolsOvertime, :);
overTimeSampSXYs = gpsXYToPlot(boolsOvertimeS, :);


% Grid for density values.
inGridXYPts = buildSimGrid(inBoundaryXYs, ...
    simConfigs.NUM_OF_PIXELS_FOR_LONGER_SIDE);
numGridPts = size(inGridXYPts, 1);
[inGridLats, inGridLons] ...
    = simConfigs.utm2deg_speZone(inGridXYPts(:,1), inGridXYPts(:,2));
inGridLatLons = [inGridLats, inGridLons];

% Reuse map background.
figure('Visible', ~FLAG_SILENT_FIGS, 'Position', [0,0,800,800]);
hold on; set(gca, 'FontWeight', 'bold');
plot(inBoundaryLatLons(:,2), inBoundaryLatLons(:,1), ...
    '-', 'LineWidth', 3, 'Color', inBoundColor);
plot_google_map('MapType', 'road', 'Alpha', googleMapAlpha);
axis manual; curColomap = autumn; curColomap = curColomap(end:-1:1, :);
colormap(curColomap);

radiiToInspectInM = [1000, 5000, 10000, 20000, 50000];
for RADIUS_TO_INSPECT_IN_M = radiiToInspectInM
    [overTimeSampDenNPerSqKms, overTimeSampSDenNPerSqKms] ...
        = deal(nan(numGridPts,1));
    areaToInspectInSqKm = pi*(RADIUS_TO_INSPECT_IN_M/1000)^2;
    for idxGridPt = 1:numGridPts
        curGridXY = inGridXYPts(idxGridPt,:);
        overTimeSampDists = pdist2(curGridXY, ...
            overTimeSampXYs(:,1:2), 'euclidean');
        overTimeSampSDists = pdist2(curGridXY, ...
            overTimeSampSXYs(:,1:2), 'euclidean');

        overTimeSampDenNPerSqKms(idxGridPt) = ...
            sum(overTimeSampDists<=RADIUS_TO_INSPECT_IN_M) ...
            /areaToInspectInSqKm;
        overTimeSampSDenNPerSqKms(idxGridPt) = ...
            sum(overTimeSampSDists<=RADIUS_TO_INSPECT_IN_M) ...
            /areaToInspectInSqKm;
    end

    maxOverTimeSampDen = max(overTimeSampDenNPerSqKms);
    maxOverTimeSampSDen = max(overTimeSampSDenNPerSqKms);

    % Density map for over-time records.
    curPlot3kCbLabel = 'Sample Density (# per km^2)';

    curFigTitle = {['Over-Time GPS Sample Density (Over ', ...
        num2str(maxSampTimeInMinForPlot3k), ' min)'], ...
        ['Inspection Range = ', ...
        num2str(RADIUS_TO_INSPECT_IN_M/1000), ' km']};
    plot3k([inGridLatLons(:,2:-1:1), overTimeSampDenNPerSqKms], ...
        'ColorRange', [0, maxOverTimeSampDen], 'Labels', ...
        {curFigTitle, mapXLabel, mapYLabel, mapZLabel, curPlot3kCbLabel});
    view(2); zlim([0, maxOverTimeSampDen]);

    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['OverTimeSampTimeDensity_', ...
        num2str(RADIUS_TO_INSPECT_IN_M/1000), ...
        'km_', num2str(maxSampTimeInMinForPlot3k), 'min.jpg']));

    curFigTitle = {['Over-Time GPS Sample Density (Over ', ...
        num2str(maxSampTimeInMinForPlot3kLower), ' min)'], ...
        ['Inspection Range = ', ...
        num2str(RADIUS_TO_INSPECT_IN_M/1000), ' km']};
    plot3k([inGridLatLons(:,2:-1:1), overTimeSampSDenNPerSqKms], ...
        'ColorRange', [0, maxOverTimeSampSDen], 'Labels', ...
        {curFigTitle, mapXLabel, mapYLabel, mapZLabel, curPlot3kCbLabel});
    view(2); zlim([0, maxOverTimeSampSDen]);

    exportgraphics(gca, fullfile(pathToSaveDailyTrackOverviewFigs, ...
        ['OverTimeSampTimeDensity_', ...
        num2str(RADIUS_TO_INSPECT_IN_M/1000), ...
        'km_', num2str(maxSampTimeInMinForPlot3kLower), 'min.jpg']));
end

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