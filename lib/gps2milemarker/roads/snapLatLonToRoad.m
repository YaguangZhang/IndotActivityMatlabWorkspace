function [latLonOnRoad, xYOnRoad, roadSegs, nearestSegs] ...
    = snapLatLonToRoad( ...
    latLon, roadName, deg2utm_speZone, utm2deg_speZone, flagDebug, ...
    indotRoads, ROAD_PROJ)
%SNAPLATLONTOROAD Snap a GPS location to the specified road.
% Required inputs:
%   - latLon
%     The (latitude, longitude) for the point of interest.
%   - roadName
%     The name for the destination road. Note: it shoud be based on the
%     road (instead of the mile marker) data set.
%   - deg2utm_speZone
%
% Optional inputs:
%   - deg2utm_speZone, utm2deg_speZone
%     Functions to use for conversions between GPS and UTM.
%   - flagDebug
%     Set this to be true for debugging figures.
%
% Implicit inputs (cached in the base workspace):
%   - indotRoads
%     The indotRoads generated by loadIndotRoads.m.
%   - ROAD_PROJ
%     Specifies the projection parameters for converting GPS coordinates to
%     UTM and vice versa. It will be automatically generated if
%     loadIndotRoads.m is run.
%
% Outputs:
%   - latLonOnRoad
%     The resultant (latitude, longitude) on the road.
%   - xYOnRoad
%     The resultant UTM (x, y) on the road.
%   - roadSegs
%     The road segments with the desired road name.
%   - nearestSegs
%     The road segments that have the nearest distance to the point of
%     interest.
%
% Yaguang Zhang, Purdue, 02/03/2021

if ~exist('indotRoads', 'var') || ~exist('ROAD_PROJ', 'var')
    if exist('indotRoads', 'var') || exist('ROAD_PROJ', 'var')
        warning(['Not both indotRoads and ROAD_PROJ ', ...
            'are specified! We will reload both of them!'])
    end
    if evalin('base', ...
            '~exist(''indotRoads'',''var'')')
        evalin('base', 'loadIndotRoads');
    end
    indotRoads = evalin('base', 'indotRoads');
    ROAD_PROJ = evalin('base', 'ROAD_PROJ');
end

if ~exist('flagDebug', 'var')
    flagDebug = false;
end

% We only need to worry about segments from the destination road.
roadSegs = getRoadSegsByRoadName(roadName, indotRoads);

% Project the coordinates into the UMT system used for indotRoads.
[X, Y] = projfwd(ROAD_PROJ, latLon(1), latLon(2));
% Find the nearest road segment(s).
[nearestSegs] = findNearestRoadSeg(X, Y, roadSegs);

% Find the resultant point in the specified UTM zone.
[xp, yp] = deg2utm_speZone(latLon(1), latLon(2));

nearestSegUtmPolylines = roadSegsToUtmPolylines( ...
    nearestSegs, deg2utm_speZone);
% Add a padding row [nan, nan] for each segment, just in case.
nearestSegUtmPolylinesWithNanPaddings = cellfun(@(l) [l; nan nan], ...
    nearestSegUtmPolylines, 'UniformOutput', false);
nearestSegUtmPolylinesWithNanPaddings = vertcat( ...
    nearestSegUtmPolylinesWithNanPaddings{:});
xv = nearestSegUtmPolylinesWithNanPaddings(:,1);
yv = nearestSegUtmPolylinesWithNanPaddings(:,2);
[~, x_d_min, y_d_min] = p_poly_dist(xp, yp, xv, yv, false);

xYOnRoad = [x_d_min, y_d_min];

latLonOnRoad = nan(1,2);
[latLonOnRoad(1), latLonOnRoad(2)]= utm2deg_speZone(x_d_min, y_d_min);

if flagDebug
    figure; hold on;
    plot(nearestSegs.Lon, nearestSegs.Lat, '-b.');
    plot(latLon(2), latLon(1), 'w*');
    plot(latLonOnRoad(2), latLonOnRoad(1), 'kx');
    curAxis = axis;
    for idxRS = 1:length(roadSegs)
        plot(roadSegs(idxRS).Lon, roadSegs(idxRS).Lat, 'r.');
    end
    axis(curAxis);
    plot_google_map('MapType', 'hybrid');
end

end
% EOF