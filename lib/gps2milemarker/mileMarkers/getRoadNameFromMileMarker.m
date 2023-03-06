function [roadName, mileage] ...
    = getRoadNameFromMileMarker(mileMarker, flagIgnoreT, flagKeepOldRecs)
%GETROADNAMEFROMMILEMARKER Get the highway name from a mile marker in the
%INDOT mile marker database (2016).
%
% Inputs:
%   - mileMarker
%     Struct. The mile marker from the INDOT mile marker database.
%   - flagIgnoreT
%     Optional. Default to true. Set this to be true to relabel toll roads
%     T80 and T90 as Interstate I80 and I90.
%   - flagKeepOldRecs
%     Optional. Default to false. Set this to be true to use old records
%     (e.g., 'OLD S_238_0' => 'S238').
%
%     There are a few old records in the mile marker dataset, e.g., 'OLD
%     S_238_0', 'U_OLD31_231', and 'OU_40_5'. They are ignored if
%     flagKeepOldRecs is set to false (i.e., output roadName is set to '').
%
%     Some other labels are ignored, too, because the format does not match
%     with what is expected, e.g., 'U_40_V9' and 'U_40_V9-1' (this could
%     mean 9-1=8).
%
% Outputs:
%   - roadName
%     String. The road name in the form like "S49". We use "S" as State,
%     "I" as Interstate, "T" as Toll (if not ignored), and "U" as US.
%   - mileage
%     An integer number for the mileage of the marker.
%
% Yaguang Zhang, Purdue, 02/02/2021

% By default, ignore toll roads in Indiana (T80 and T90) and label them as
% Interstate (I80 and I90).kj
if ~exist('flagIgnoreT', 'var')
    flagIgnoreT = true;
end

% By default, do not keep old mile marker road label records.
if ~exist('flagKeepOldRecs', 'var')
    flagKeepOldRecs = false;
end

postName = mileMarker.POST_NAME;

if flagKeepOldRecs
    postName = erase(postName, 'OLD_');
    postName = erase(postName, 'OLD');
    postName = erase(postName, 'O');
end

postName = strrep(postName, '-', '_');
[idxStart, idxEnd] = regexpi(postName, '[USIT][_]\d+_\d+');
if ~isempty(idxStart) && idxStart == 1 && idxEnd == length(postName)
    indicesUnderscore = strfind(postName, '_');
    assert(length(indicesUnderscore)==2, ...
        ['Two and only two underscores are expected! ', ...
        '(Mile marker: ', postName, ')'])
    assert(indicesUnderscore(1)==2, ...
        ['Only one character is expected for the road type! ', ...
        '(Mile marker: ', postName, ')'])
    roadName = [postName(1), ...
        postName((indicesUnderscore(1)+1):(indicesUnderscore(2)-1))];
    mileage = str2double(postName((indicesUnderscore(2)+1):end));

    if flagIgnoreT && strcmpi(roadName(1), 'T')
        tollRoads = {'T80', 'T90'};
        assert(ismember(roadName, tollRoads), ...
            ['Unknown toll road: ', roadName, '!'])

        roadName(1) = 'I';
    end
else
    roadName = '';
    mileage = nan;
end

end
% EOF