function [mileMarkers, postNums] = getMileMarkersByRoadName( ...
    roadName, indotMileMarkers, flagOrderMMByMile)
% GETMILEMARKERSBYROADNAME Find all mile markers marked with the specified
% road name from the INDOT mile marker database (2016).
%
% Inputs:
%   - roadName
%     String. The road name in the form like "S49". We use "S" as State,
%     "I" as Interstate, "T" as Toll and "U" as US (case insensitive).
%   - indotMileMarkers
%     Loaded INDOT mile marker database. Also works with part of it.
%   - flagOrderMMByMile
%     Optional. Default to false. Set this to be true to order the output
%     mileMarkers by their mileage values (increasingly).
%
% Outputs:
%   - mileMarkers
%     The mile markers found.
%   - postNums
%     The mile marker mileage/post values.
%
% Implicit cache variable in the base workspace:
%   - INDOT_MILE_MARKERS_ROADNAME_LABELS
%     Cell. The road name labels extracted from indotMileMarkers.
%
% Yaguang Zhang, Purdue, 02/02/2021

if ~exist('flagOrderMMByMile', 'var')
    flagOrderMMByMile = false;
end

if evalin('base', ...
        '~exist(''INDOT_MILE_MARKERS_ROADNAME_LABELS'',''var'')')
    INDOT_MILE_MARKERS_ROADNAME_LABELS = ...
        getRoadNamesForMileMarkers(indotMileMarkers);
    putvar(INDOT_MILE_MARKERS_ROADNAME_LABELS);
else
    INDOT_MILE_MARKERS_ROADNAME_LABELS = ...
        evalin('base', 'INDOT_MILE_MARKERS_ROADNAME_LABELS');
end

mileMarkers = indotMileMarkers(...
    strcmpi(INDOT_MILE_MARKERS_ROADNAME_LABELS, roadName)...
    );

if nargout>1 || flagOrderMMByMile
    numOfMMs = length(mileMarkers);
    postNums = nan(numOfMMs, 1);

    for idxMM = 1:numOfMMs
        [~, postNums(idxMM)] ...
            = getRoadNameFromMileMarker(mileMarkers(idxMM));
    end
end
if flagOrderMMByMile
    [postNums, indicesOrderedMMs] = sort(postNums, 'ascend');
    mileMarkers = mileMarkers(indicesOrderedMMs);
end

end
% EOF