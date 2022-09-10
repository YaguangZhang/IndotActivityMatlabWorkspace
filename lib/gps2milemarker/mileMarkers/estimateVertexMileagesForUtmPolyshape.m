function [roadPtMs] = estimateVertexMileagesForUtmPolyshape( ...
    roadSegUtmPolyshape, utm2deg_speZone, roadNameForMileMarkers)
%ESTIMATEVERTEXMILEAGESFORUTMPOLYSHAPE A helper function to estimate the
%mileage values for the vertices of a road segment, stored as a UTM
%polyshape.
%
% Yaguang Zhang, Purdue, 02/06/2021

curDestRoadSegPtXYs = roadSegUtmPolyshape.Vertices;
[curDestRoadSegPtLats, curDestRoadSegPtLons] ...
    = utm2deg_speZone(curDestRoadSegPtXYs(:,1), ...
    curDestRoadSegPtXYs(:,2));
roadPtMs = arrayfun( ...
    @(idxPt) gpsCoorWithRoadName2MileMarker( ...
    curDestRoadSegPtLats(idxPt), curDestRoadSegPtLons(idxPt), ...
    roadNameForMileMarkers), ...
    1:length(curDestRoadSegPtLats))';

end
% EOF