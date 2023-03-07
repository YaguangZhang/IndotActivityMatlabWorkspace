%TESTROADNAMERECPATTERN Test the road name label recognition pattern in
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

dirToResultMats = fullfile(pwd, 'lib', 'gps2milemarker', 'roads');
dirToDiary = fullfile(ABS_PATH_TO_SHARED_FOLDER, ...
    'PostProcessingResults', ...
    'Lib_Gps2MileMarker_RoadNameRecPattern');
if ~exist(dirToDiary, 'dir')
    mkdir(dirToDiary)
end
diary(fullfile(dirToDiary, 'diary.log'));

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

MAX_ALLOWED_DIST_FROM_ROAD_IN_M = 50;
flagShowProgress = true;
flagSuppressWarns = true;
flagPlotResults = false;
[roadLabels, miles, nearestDistsInM, nearestSegNames] ...
    = fetchRoadNameAndMileMarker(mmLats, mmLons, ...
    MAX_ALLOWED_DIST_FROM_ROAD_IN_M, ...
    flagShowProgress, flagSuppressWarns, flagPlotResults);

% Find disagreements between road segment names and road names in mile
% marker records.
boolsMismatch = cellfun(@(segN) ~isempty(segN), nearestSegNames);
refRoadName = mmRoadLabels(boolsMismatch);
indicesMismatch = find(boolsMismatch);

mismatchSegName = nearestSegNames(boolsMismatch);
distToMismatchSegInM = nearestDistsInM(boolsMismatch);
mismatchTable = table(refRoadName, mismatchSegName, ...
    distToMismatchSegInM);
% Remove duplicate rows.
[mismatchTable, indicesMismatchRows] ...
    = unique(mismatchTable, 'rows');
idxMileMarker = indicesMismatch(indicesMismatchRows);
mismatchTable.idxMileMarker = idxMileMarker;

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

    roadLable = mmRoadLabels(indicesNewMismatch);
    mismatch = roadLabels(indicesNewMismatch);
    distToMismatchInM = nearestDistsInM(indicesNewMismatch);
    mileMarkerIdx = (1:length(mmRoadLabels))';
    mileMarkerIdx = mileMarkerIdx(indicesNewMismatch);
    extraMismatchTable = table(roadLable, mismatch, ...
        distToMismatchInM, mileMarkerIdx);

    % Note that we will only generate the .mat files if they do not exist.
    fullPathToSaveExtraMismatchTable = fullfile(dirToResultMats, ...
        'extraMismatches.mat');
    if ~exist(fullPathToSaveExtraMismatchTable, 'file')
        save(fullPathToSaveExtraMismatchTable, 'extraMismatchTable');
    end
end

%% Save the Special Road Name List
% We will use these lists in funciton getRoadNameFromRoadSeg.m.

% Save the full mismatch list as reference.
fullPathToSaveMismatchTable = fullfile(dirToResultMats, ...
    'mismatches.mat');
if ~exist(fullPathToSaveMismatchTable, 'file')
    save(fullPathToSaveMismatchTable, 'mismatchTable');
end

% Get a conversion list from reference road name to mismatch segment name.
% We will use cells instead of tables for faster speed.
specialCaseCell = upper(table2cell(mismatchTable(:, 1:2)));

% Only consider a special case (mismatchSegNames) if it appears more than
% once for that road.
uniqueSpecialCaseCell = upper(table2cell(unique( ...
    mismatchTable(:, 1:2), 'rows')));
for idxUniSpeCaseRow = 1:height(uniqueSpecialCaseCell)
    curUniSpeCaseRow = uniqueSpecialCaseCell(idxUniSpeCaseRow, :);

    indicesDuplicates = find( arrayfun(@(idxR) ...
        strcmpi(specialCaseCell{idxR, 1}, curUniSpeCaseRow{1, 1}) ...
        && strcmpi(specialCaseCell{idxR, 2}, curUniSpeCaseRow{1, 2}), ...
        1:height(specialCaseCell)) );

    if length(indicesDuplicates) <= 1
        specialCaseCell(indicesDuplicates, :) = [];
    end
end

% Only consider a special case (mismatchSegNames) if it maps to only one
% road (refRoadNames).
uniqueSpecialCaseCell = table2cell(unique( ...
    cell2table(specialCaseCell), 'rows'));
uniqueMismatchSegNames = unique(uniqueSpecialCaseCell(:, 2));
numOfUniMisSegNs = length(uniqueMismatchSegNames);
for idxUniMisSegN = 1:numOfUniMisSegNs
    curMismatchSegName = uniqueMismatchSegNames{idxUniMisSegN};

    % Search for this segment name in uniqueSpecialCaseTable.
    indicesRefRoadNames = find(cellfun(@(mismatchSegN) ...
        strcmpi(curMismatchSegName, mismatchSegN), ...
        uniqueSpecialCaseCell(:, 2))); % 'mismatchSegName'

    if length(indicesRefRoadNames)>1
        disp(['Discarding special case (segment name: ', ...
            curMismatchSegName, ') because it maps to multiple roads...']);
        disp(uniqueSpecialCaseCell(indicesRefRoadNames, :));

        uniqueSpecialCaseCell(indicesRefRoadNames, :) = [];
    end
end

specialCaseCell = uniqueSpecialCaseCell;

fullPathToSaveSpeCaseCell = fullfile(dirToResultMats, ...
    'specialCases.mat');
if ~exist(fullPathToSaveSpeCaseCell, 'file')
    save(fullPathToSaveSpeCaseCell, 'specialCaseCell');
end

diary off;

% EOF