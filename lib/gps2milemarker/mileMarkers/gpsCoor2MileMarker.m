function [roadName, mile, nearestSegs, nearestDist, nearestSegName] = ...
    gpsCoor2MileMarker(lat, lon, flagPlotResults, mileCalcMethod)
% GPSCOOR2MILEMARKER Convert GPS coordinates on INDOT roads (centerline
% 2019) to road name and mile marker.
%
% Please remember to load in INDOT mile marker database and road database
% first.
%
% Inputs:
%   - lat, lon
%     The GPS coordinates for the point for which we want to get the high
%     way road name and mile marker.
%   - flagPlotResults
%     Optional. Default to false. Set this to be true to plot debugging
%     figures from findNearestRoadSeg.m.
%   - mileCalcMethod
%     Optional. Default to '2DScatter'. Options supported are:
%       - 2DScatter
%         Consider all mile markers on the road in the form of (x, y, mile)
%         to get the mile/post value for the point of interest via 2D
%         scattered interpolation. We will fall back to Nearest2MMs if
%         there are less than 3 reference points (mile markers) available.
%       - Nearest2MMs
%         Calculate mile value based on the nearest two mile markers to the
%         point of interest.
%
% Implicit inputs (cached in the base workspace):
%   - indotMileMarkers, indotRoads
%     Structures storing INDOT mile markers and roads respectively. Can be
%     generated by running scripts loadIndotMileMarkers.m and
%     loadIndotRoads.m respectively.
%   - MILE_MARKER_PROJ, ROAD_PROJ,
%     Specifies the parameters for converting GPS coordinates to UTM and
%     vice versa, for the mile markers and roads, respectively. They will
%     be automatically generated if loadIndotMileMarkers and loadIndotRoads
%     are run.
%   - INDOT_MILE_MARKERS_ROADNAME_LABELS
%     The road names for indotMileMarkers. This is optional but will
%     improve the speed of this function dramatically. It can be generated
%     by this function itself if it's not provided.
%
% Outputs:
%   - roadName
%     The road name for the input point.
%   - mile
%     A float value. The mile marker for the input point.
%   - nearestSegs
%     A struct array for the neareast road segment.
%   - nearestDist
%     The distance from the input point to the neareast road segment.
%   - nearestSegName
%     For debugging. The road name of the nearest road segment. This is
%     populated only when the nearest road segment is found, it has a road
%     name, and the road name for the input point is invalid (normally
%     because no mile marker with the same road name label can be found).
%
% Yaguang Zhang, Purdue, 02/02/2021

% We are less strict about the distances to nearest mile markers because
% sometimes a some segment of a road may have different names in the mile
% marker dataset vs the road centerline dataset, e.g., U_35_186 to U_35_190
% are absent in the mile marker dataset, because instead U_6_47 to U_6_51
% are covering the same road segment, even though the road centerline
% dataset shows that segment as U35. Note that 1 mile ~= 1609.34 m.
MAX_ALLOWED_DIST_IN_M_TO_NEAREST_MM = 8046.72; % ~5 miles.

if ~exist('flagPlotResults', 'var')
    flagPlotResults = false;
end

if ~exist('mileCalcMethod', 'var')
    mileCalcMethod = '2DScatter';
end

nearestSegName = '';

if ~exist('indotRoads', 'var') || ~exist('ROAD_PROJ', 'var')
    if exist('indotRoads', 'var') || exist('ROAD_PROJ', 'var')
        warning('GPS2MILEMARKER:roadCenterlineNotLoaded', ...
            ['Not both indotRoads and ROAD_PROJ ', ...
            'are specified! We will reload both of them!'])
    end
    if evalin('base', ...
            '~exist(''indotRoads'',''var'')')
        evalin('base', 'loadIndotRoads');
    end
    indotRoads = evalin('base', 'indotRoads');
    ROAD_PROJ = evalin('base', 'ROAD_PROJ');
end

if ~exist('indotMileMarkers', 'var') || ~exist('MILE_MARKER_PROJ', 'var')
    if exist('indotMileMarkers', 'var') || exist('MILE_MARKER_PROJ', 'var')
        warning('GPS2MILEMARKER:milemarkersNotLoaded', ...
            ['Not both indotMileMarkers and MILE_MARKER_PROJ ', ...
            'are specified! We will reload both of them!'])
    end
    if evalin('base', ...
            '~exist(''indotMileMarkers'',''var'')')
        evalin('base', 'loadIndotMileMarkers');
    end
    indotMileMarkers = evalin('base', 'indotMileMarkers');
    MILE_MARKER_PROJ = evalin('base', 'MILE_MARKER_PROJ');
end

roadName = '';
mile = nan;

% Project the coordinates into UMT system.
[xRoad, yRoad] = projfwd(ROAD_PROJ, lat, lon);
[xMileMaker, yMileMaker] = projfwd(MILE_MARKER_PROJ, lat, lon);

% First, we need to know the name of the road we are on.

% Find the nearest road segment(s).
[nearestSegs, nearestDist] = findNearestRoadSeg(xRoad, yRoad, ...
    indotRoads, flagPlotResults);

% If no nearest road segment is found, print an error.
if isempty(nearestSegs)
    warning('GPS2MILEMARKER:noNearestRoadSeg', ...
        'Couldn''t find the nearest road segment!');
    return
end

% Get their road name(s).
roadName = getRoadNamesForRoadSegs(nearestSegs);

% It's not likely that the input point has more than one "nearest"
% segments. When this happens, we will check the road names for those
% segments and print a warning if they don't match.
if ~all(strcmp(roadName, roadName{1}))
    warning('GPS2MILEMARKER:mutipleNearestSegsFound', ...
        'Multiple road name candidates discovered!');
end
roadName = roadName{1};

% Next we need to compute the mile marker according to the road name we've
% gotten.
flagOrderMMByMile = true;
[mileMarkersOnThisRoad, mileMarkerMiles] = getMileMarkersByRoadName( ...
    roadName, indotMileMarkers, flagOrderMMByMile);

if length(mileMarkersOnThisRoad)<=1
    warning(['Unable to find at least 2 mile markers for road: ', ...
        nearestSegs(1).FULL_STREE, ' (recognized as ', roadName, ')!']);
    nearestSegName = nearestSegs(1).FULL_STREE;
    return;
end

% Get the nearest 2 mile markers. Here we only use them to estimate the
% mile post for the input point.
locationsMileMarkersOnThisRoad = ...
    [[mileMarkersOnThisRoad.X]', [mileMarkersOnThisRoad.Y]'];
distMileMarkers = pdist2([xMileMaker, yMileMaker], ...
    locationsMileMarkersOnThisRoad);
sortedDistMileMarkersWithIndices = sortrows([distMileMarkers', ...
    (1:length(distMileMarkers))'], 1);
nearest2Markers = mileMarkersOnThisRoad(...
    sortedDistMileMarkersWithIndices(1:2,2)...
    );

% Make sure the point of interest is not too far away from the route formed
% by the mile markers.
P1.x = xMileMaker;
P1.y = yMileMaker;
P2.x = [locationsMileMarkersOnThisRoad(:, 1); nan];
P2.y = [locationsMileMarkersOnThisRoad(:, 2); nan];
distsInMToMileMarkerRoute = ...
    min_dist_between_two_polygons(P1, P2, flagPlotResults);

if distsInMToMileMarkerRoute>MAX_ALLOWED_DIST_IN_M_TO_NEAREST_MM
    warning(['Fetched mile markers are too far away ', ...
        '(distsInMToMileMarkerRoute = ',  ...
        num2str(distsInMToMileMarkerRoute), ' m)!']);
    disp(['    Road: ', nearestSegs(1).FULL_STREE, ...
        ' (recognized as ', roadName, ')']);
    nearestSegName = nearestSegs(1).FULL_STREE;
    return;
end

% It seems scatteredInterpolant needs at least 3 points to work.
if length(mileMarkersOnThisRoad)<=2
    mileCalcMethod = 'Nearest2MMs';
end

switch lower(mileCalcMethod)
    case '2dscatter'
        mileInterplator = scatteredInterpolant( ...
            locationsMileMarkersOnThisRoad(:, 1), ...
            locationsMileMarkersOnThisRoad(:, 2), mileMarkerMiles, ...
            'linear', 'linear');
        mile = mileInterplator(xMileMaker, yMileMaker);
    case 'nearest2mms'
        % Get the vector of the 2 markers from the marker with smaller
        % postnumber.
        unitMileVector = [nearest2Markers(2).X - nearest2Markers(1).X, ...
            nearest2Markers(2).Y - nearest2Markers(1).Y];
        postNumNearest2Markers = nan(2,1);
        for idxNearestMM = 1:2
            [~, postNumNearest2Markers(idxNearestMM)] ...
                = getRoadNameFromMileMarker(nearest2Markers(idxNearestMM));
        end
        if postNumNearest2Markers(1) > postNumNearest2Markers(2)
            unitMileVector = -unitMileVector;
            % Also compute the vector from the marker with smaller
            % postnumber to the input point.
            inputMileVector = [xMileMaker - nearest2Markers(2).X, ...
                yMileMaker - nearest2Markers(2).Y];
        else
            inputMileVector = [xMileMaker - nearest2Markers(1).X, ...
                yMileMaker - nearest2Markers(1).Y];
        end

        % Compute the postnumber for the input point.
        mile = min(postNumNearest2Markers) + ...
            dot(inputMileVector, unitMileVector) / ...
            dot(unitMileVector, unitMileVector);
    otherwise
        error(['Unknown mileCalcMethod: ', mileCalcMethod, '!']);
end

end
% EOF