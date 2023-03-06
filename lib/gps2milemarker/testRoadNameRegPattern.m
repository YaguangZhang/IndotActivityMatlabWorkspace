%TESTROADNAMEREGPATTERN Test the road name label recognition pattern in
%getRoadNameFromRoadSeg using mile marker points.
%
% Note that in the INDOT centerline data set, we have in the FULL_STREE
% field various ways of naming roads, for example, "N/E/S/E SR/State
% Rd/State Road" as State, "INTERSTATE HIGHWAY/INTERSTATE/I(-)#" for
% Interstate, seemingly nothing for Toll, and "N/E/S/E US/USHY/United
% States Highway(-)#" as US. This test makes sure our regex pattern to deal
% with these labels work at least for all mile marker points in IN.
%
% This test requires path settings from the INDOT work order verification &
% generation project. More specifically, the scripts prepareSimulationEnv.m
% and setPath.m.
%
% Yaguang Zhang, Purdue, 03/03/2023

% clear;
clc; close all; dbstop if error;

% Locate the Matlab workspace and save the current filename.
cd(fileparts(mfilename('fullpath'))); cd(fullfile('..', '..'));
addpath('lib'); curFileName = mfilename;

prepareSimulationEnv;

dirToResults = fullfile(pwd, 'lib', 'gps2milemarker', 'roads');

%% Fetch Mile Markers and Road Centerlines

loadIndotMileMarkers;
loadIndotRoads;

% Extract GPS records of the mile markers and use the valid ones as the
% testing set.
mmRoadLabels = getRoadNamesForMileMarkers(indotMileMarkers);
boolsValidMmRLs = arrayfun(@(idx) ~isempty(mmRoadLabels{idx}), ...
    1:length(mmRoadLabels));
mmRoadLabels = mmRoadLabels(boolsValidMmRLs);
mmLats = [indotMileMarkers(boolsValidMmRLs).Lat]';
mmLons = [indotMileMarkers(boolsValidMmRLs).Lon]';

flagDebug = false;
debugIdxRange = 1:50;
% For debugging: test using some of the mile marker records to limit the
% execution time.
if flagDebug
    mmLats = mmLats(debugIdxRange); %#ok<UNRCH>
    mmLons = mmLons(debugIdxRange);
    mmRoadLabels = mmRoadLabels(debugIdxRange);
end

%% Fetch Road Labels Based on Centerlines

MAX_ALLOWED_DIST_FROM_ROAD_IN_M = 100;
flagShowProgress = true;
flagSuppressWarns = true;
[roadLabels, miles, nearestDistsInM, nearestSegNames] ...
    = fetchRoadNameAndMileMarker(mmLats, mmLons, ...
    MAX_ALLOWED_DIST_FROM_ROAD_IN_M, flagShowProgress, flagSuppressWarns);

% Find disagreements between road segment names and road names in mile
% marker records.
boolsMismatch = cellfun(@(segN) ~isempty(segN), nearestSegNames);
refRoadNames = mmRoadLabels(boolsMismatch);
indicesMismatch = find(boolsMismatch);

mismatchSegNames = nearestSegNames(boolsMismatch);
mismatchNamesTable = table(refRoadNames, mismatchSegNames);
% Remove duplicate rows.
[mismatchNamesTable, indicesMismatchRows] ...
    = unique(mismatchNamesTable, 'rows');
idxMileMarker = indicesMismatch(indicesMismatchRows);
mismatchNamesTable.idxMileMarker = idxMileMarker;

% Double-check the matched road names.
if all(arrayfun(@(idx) strcmpi(mmRoadLabels{idx}, roadLabels{idx}), ...
        find(~boolsMismatch)))
    disp('Matched roads passed test!')
else
    disp('New mismatched road segments detected!')

    indicesMatch = find(~boolsMismatch);
    boolsNewMismatch = ~arrayfun(@(idx) ...
        strcmpi(mmRoadLabels{idx}, roadLabels{idx}), indicesMatch);
    indicesNewMismatch = indicesMatch(boolsNewMismatch);

    roadLables = mmRoadLabels(indicesNewMismatch);
    mismatch = roadLabels(indicesNewMismatch);
    mileMarkerIdx = (1:length(mmRoadLabels))';
    mileMarkerIdx = mileMarkerIdx(indicesNewMismatch);
    extraMismatchesTable = table(roadLables, mismatch, mileMarkerIdx);

    fullPathToSaveExtraMismatchTable = fullfile(dirToResults, ...
        'extraMismatches.mat');
    save(fullPathToSaveExtraMismatchTable, 'extraMismatchesTable');
end

%% Save the Special Road Name List
% We will use these lists in funciton getRoadNameFromRoadSeg.m.

fullPathToSaveSpeCaseTable = fullfile(dirToResults, ...
    'roadNameTableForSpeCases.mat');
save(fullPathToSaveSpeCaseTable, 'mismatchNamesTable');

% EOF