% TESTGPSCOOR2MILEMARKER
%
% Yaguang Zhang, Purdue, 04/14/2021

close all; clc;

% Changed folder to the root Matlab script foler first.
curDir = fullfile(fileparts(which(mfilename)));
cd(curDir);
% Set path.
setPath;
ABS_PATH_TO_ROADS = fullfile(curDir, '..', 'IndotDataSets');

%% Load INDOT data sets

loadIndotRoads;
loadIndotMileMarkers;

%% Test the time to run the code below.
tic
[roadName, mile1] = ...
    gpsCoor2MileMarker(39.776301, -87.236079);
toc

%% Compare it with the other version
tic
mile2 = ...
    gpsCoorWithRoadName2MileMarker(39.776301, -87.236079, roadName);
toc

disp(['roadName = "', roadName, '", mile1 = ', num2str(mile1)])
disp(['mile2 = ', num2str(mile2)])
disp(['Difference = ', num2str(mile1-mile2)])

% EOF