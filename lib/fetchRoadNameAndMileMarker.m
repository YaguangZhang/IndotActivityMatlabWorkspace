function [roadNames, miles, nearestDistsInM] ...
    = fetchRoadNameAndMileMarker(lats, lons, ...
    MAX_ALLOWED_DIST_FROM_ROAD_IN_M, flagShowProgress)
%FETCHROADNAMEANDMILEMARKER Fetch the road name and mile marker pair for
%GPS coordinates stored in the input variables (lats, lons) one by one.
%
% Inputs:
%   - lats, lons
%     Column vectors of the GPS locations of interest.
% Optional inputs:
%   - MAX_ALLOWED_DIST_FROM_ROAD_IN_M
%     Default to inf. Maximum allowed distance to a road for the GPS sample
%     to be labeled as on
% that road.
%   - flagShowProgress
%     Default to false. Set this to true for a progress bar in the command
%     line.
%
% Outputs:
%   - roadNames, miles
%     The road name and mile marker found based on IN mile marker and road
%     centerline datasets.
%   - nearestDistsInM
%     A column vector of distance in meter between the (lat, lon) of
%     interest and the neareast road found.
%
% Yaguang Zhang, Purdue, 09/13/2022

if ~exist('MAX_ALLOWED_DIST_FROM_ROAD_IN_M', 'var')
    MAX_ALLOWED_DIST_FROM_ROAD_IN_M = inf;
end
if ~exist('flagShowProgress', 'var')
    flagShowProgress = false;
end

numOfGpsSamps = length(lats);
assert(length(lats)==length(lons), ...
    'Inputs lats and lons should have the same length!')

if flagShowProgress
    proBar = betterProBar(numOfGpsSamps);
end

% The road name is a string in the form like "S49". For highways, we use
% "S" as State, "I" as Interstate, "T" as Toll, and "U" as US.
roadNames = cell(numOfGpsSamps, 1);
% The mile marker and, for debugging, the distance to the road.
[miles, nearestDistsInM] = deal(nan(numOfGpsSamps, 1));

% Suppress warnings.
warning('off', 'GPS2MILEMARKER:all')

% parfor can be used here, too. However, that does not speed thing up too
% much on the machine Artsy. Also, if the IN mile marker or road
% centerlines are modified after they are loaded (e.g., center lines could
% be filtered to cover only highways), the parfor workers may not use the
% modified version.
for idxSamp = 1:numOfGpsSamps
    try
        [roadNames{idxSamp}, curMile, ~, curNearestDist] ...
            = gpsCoor2MileMarker(lats(idxSamp), ...
            lons(idxSamp));
    catch
        % Fallback values.
        curNearestDist = inf;
        roadNames{idxSamp} = '';
    end

    if (~isempty(curNearestDist)) ...
            && (curNearestDist <= MAX_ALLOWED_DIST_FROM_ROAD_IN_M)
        miles(idxSamp) = curMile;
        nearestDistsInM(idxSamp) = curNearestDist;
    else
        % Discard the results if the nearest road is too far away.
        roadNames{idxSamp} = '';
    end

    if flagShowProgress
        proBar.progress;
    end
end

if flagShowProgress
    proBar.stop;
end

warning('on', 'GPS2MILEMARKER:all')

end
% EOF