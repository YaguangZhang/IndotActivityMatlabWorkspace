function roadName = getRoadNameFromRoadSeg(roadSeg)
%GETROADNAMEFROMROADSEG Get the road name from a road segment from the
%INDOT road database (centerline 2019).
%
% Inputs:
%   - roadSeg
%     Struct. The road segment from the INDOT centerline database.
% Outputs:
%   - roadName
%     String. The road name in the form like "S49". We use "S" as State,
%     "I" as Interstate, "T" as Toll, and "U" as US.
%
% Note that in the INDOT centerline data set, we have in the FULL_STREE
% field various ways of naming roads, for example, "N/E/S/E SR/State
% Rd/State Road" as State, "INTERSTATE HIGHWAY/INTERSTATE/I(-)#" for
% Interstate, seemingly nothing for Toll, and "N/E/S/E US/USHY/United
% States Highway(-)#" as US.
%
% Example road name starting with "HWY": {'HWY 11 SW', 'HWY 111 SE', 'HWY
% 135 NE', 'HWY 135 NW', 'HWY 135 SW', 'HWY 150 NE', 'HWY 150 NW', 'HWY 211
% SE', 'HWY 335 NE', HWY 337 NW', 'HWY 337 SE', 'HWY 462 NW', 'HWY 550'  ,
% 'HWY 62 NE', 'HWY 62 NW', 'HWY 64 NE', 'HWY 64 NW'}.
%
% Yaguang Zhang, Purdue, 02/02/2021

roadName = roadSeg.FULL_STREE;

% Some highways are known, for example:
%   specialCases = {'WALNUT', 'PIERCE RD', 'MARION RD', ...
%       'BROADWAY', 'HWY 150'};
%   roadNameForSpeCases = {'S3', 'S4', 'S9', 'S53', 'U150'};
% We can do a pattern/substring match to recognize them.
specialCasePats = {};
roadNameForSpeCasePats = {};

curSpeCasePatIdx = find(arrayfun(@(speCasePatIdx) ...
    contains(roadName, specialCasePats{speCasePatIdx}, ...
    'IgnoreCase', true), 1:length(specialCasePats)));

if ~isempty(curSpeCasePatIdx)
    assert(length(curSpeCasePatIdx) == 1, ...
        ['Unexpected duplicate special case road names (by pattern): ', ...
        roadName, '!']);
    roadName = roadNameForSpeCasePats{curSpeCasePatIdx};
    return;
end

% A reference special-case road name mapping table has been generated based
% on the IN mile marker dataset (please refer to
% gps2milemarker/testRoadNameRecPattern.m for more information). We can use
% that list to recognize some road name aliases.
if evalin('base', "exist('specialCaseCell', 'var')")
    specialCaseCell = evalin('base', 'specialCaseCell');
else
    % Cache specialCaseCell in base workspace.
    curFileDir = fileparts(mfilename('fullpath'));
    fullPathToSpecialCaseList = fullfile(curFileDir, 'specialCases.mat');
    load(fullPathToSpecialCaseList, 'specialCaseCell');
    assignin('base', 'specialCaseCell', specialCaseCell);
end

curSpeCaseIdx = find(arrayfun(@(speCaseIdx) ...
    strcmpi(roadName, specialCaseCell{speCaseIdx, 2}), ...
    1:length(specialCaseCell(:,2))));

if ~isempty(curSpeCaseIdx)
    assert(length(curSpeCaseIdx) == 1, ...
        ['Unexpected duplicate special case road names (by list): ', ...
        roadName, '!']);
    roadName = specialCaseCell{curSpeCaseIdx, 1};
    return;
end

% RegExp patterns (case-insensitive) to identify the road types.
roadTypes = {'S', 'I', 'U'};
regPats = {'(SR|S.R.|State Rd|State Road|STATE HWY|STHY|ST RD|S R|IN)( |-|)(\d+)', ...
    '(INTERSTATE HIGHWAY|INTERSTATE|INT|I)( |-|)(\d+)', ...
    '(US|USHY|US HWY|U.S. HWY|US HIGHWAY|US ROUTE|U S ROUTE|United States Highway)( |-|)(\d+)'};

for idxType = 1:length(roadTypes)
    ts = regexpi(roadName, regPats{idxType}, 'tokens');
    if ~isempty(ts)
        roadNumStr = ts{1}{3};
        roadName = [roadTypes{idxType}, roadNumStr];
        break;
    end
end

end
% EOF