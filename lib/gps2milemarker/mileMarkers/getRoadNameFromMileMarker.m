function [roadName, mileage] ...
    = getRoadNameFromMileMarker(mileMarker, flagIgnoreT)
%GETROADNAMEFROMMILEMARKER Get the highway name from a mile marker in the
%INDOT mile marker database (2016).
%
% Inputs:
%   - mileMarker
%     Struct. The mile marker from the INDOT mile marker database.
%   - flagIgnoreT
%     Optional. Default to true. Set this to be true to relabel toll roads
%     T80 and T90 as Interstate I80 and I90.
%
% Outputs:
%   - roadName
%     String. The road name in the form like "S49". We use "S" as State,
%     "I" as Interstate, "T" as Toll (if not ignored), and "U" as US.
%   - mileage
%     An integer number for the mileage of the marker.
%
% There are a few old records in the mile marker dataset, e.g., 'OLD
% S_238_0', 'U_OLD31_231', and 'OU_40_5', are ignored (i.e., output
% roadName is set to '').
%
% Yaguang Zhang, Purdue, 02/02/2021

% By default, ignore toll roads in Indiana (T80 and T90) and label them as
% Interstate (I80 and I90).
if ~exist('flagIgnoreT', 'var')
    flagIgnoreT = true;
end

postName = mileMarker.POST_NAME;
[idxStart, idxEnd] = regexpi(postName, '[USIT]_\d+_\d+');
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
else
    roadName = '';
    mileage = nan;
end

if flagIgnoreT
    tollRoads = {'T80', 'T90'};
    assert(ismember(roadName, tollRoads), ...
        ['Unknown toll road: ', roadName, '!'])

    roadName(1) = 'I';
end

end
% EOF