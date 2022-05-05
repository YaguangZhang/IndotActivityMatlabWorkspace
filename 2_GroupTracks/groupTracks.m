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

% Log the command line output.
diary(fullfile(pathToSaveResults, 'Diary.log'));

% Load results about GPS tracks from 1_ExploreGpsData/visualizeTracks.m.
pathToCachedGpsInfo = fullfile(pathToSaveResults, '..', ...
    '1_GpsTrackOverview', 'workspace.mat');

%% Load GPS Tracks

disp(' ')
disp(['[', datestr(now, datetimeFormat), ...
    '] Loading GPS location info ...'])

if ~exist(pathToCachedGpsInfo, 'file')
    error(['Unable to load GPS info! ', ...
        'Please run 1_ExploreGpsData/visualizeTracks.m and try again.']);
else
    load(pathToCachedGpsInfo, 'LOCAL_TIME_ZONE', ... .
        'gpsLocTableEachDay'); % GPS info for tracks of each day.
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

        curGpsSampTimesInMin = minutes(diff(curGpsLocTable.timestamp))';
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

%% Group Vehicles into Maintenance Fleets

% disp(' ')
% disp(['[', datestr(now, datetimeFormat), ...
%     '] Searching for maintenance fleets ...'])
%
%
% disp(['[', datestr(now, datetimeFormat), ...
%     '] Done!'])

%% Load Vehicle Type


% EOF