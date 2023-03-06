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

%% Fetch Mile Markers and Road Centerlines

loadIndotMileMarkers;
loadIndotRoads;

% Extract GPS records of the mile markers as the testing set.
mmLats = [indotMileMarkers(:).Lat]';
mmLons = [indotMileMarkers(:).Lon]';
mmRoadLabels = getRoadNamesForMileMarkers(indotMileMarkers);

%% Fetch Road Labels Based on Centerlines

MAX_ALLOWED_DIST_FROM_ROAD_IN_M = 100;
flagShowProgress = true;
flagSuppressWarns = true;
[roadLabels, miles, nearestDistsInM] ...
    = fetchRoadNameAndMileMarker(mmLats, mmLons, ...
    MAX_ALLOWED_DIST_FROM_ROAD_IN_M, flagShowProgress, flagSuppressWarns);

% EOF