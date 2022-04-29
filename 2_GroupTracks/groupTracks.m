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
    load(pathToCachedGpsInfo, 'gpsLocTable');
end

disp(['[', datestr(now, datetimeFormat), ...
    '] Done!'])

%% Load Vehicle Type


% EOF