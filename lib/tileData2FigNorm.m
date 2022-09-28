function [xsf, ysf] = tileData2FigNorm(xs, ys, tileIdx)
%TILEDATA2FIGNORM Convert data points [xs, ys] in a subfigure (indicated by
%tileIdx) of a tile layout to figure coordinates [xsf, ysf] in normalized
%unit.
%
% Yaguang Zhang, Purdue, 09/27/2022

if exist('tileIdx', 'var')
    nexttile(tileIdx);
end

hAxTile = gca;
assert(strcmpi(hAxTile.Units, 'normalized'), 'Expecting normalized unit!');
tileInnerPos = hAxTile.InnerPosition;

xRangeInAxes = ruler2num(xlim, hAxTile.XAxis);
xsInAxes = ruler2num(xs, hAxTile.XAxis);
xsf = tileInnerPos(1) ...
    + tileInnerPos(3).*( ...
    xsInAxes-xRangeInAxes(1))./(xRangeInAxes(2)-xRangeInAxes(1));

yRangeInAxes = ruler2num(ylim, hAxTile.YAxis);
ysInAxes = ruler2num(ys, hAxTile.YAxis);
ysf = tileInnerPos(2) ...
    + tileInnerPos(4).*( ...
    ysInAxes-yRangeInAxes(1))./(yRangeInAxes(2)-yRangeInAxes(1));

assert(all(xsf>=0 & xsf<=1 & ysf>=0 & ysf<=1), ...
    'Normalized values must be between 0 and 1!');

end
% EOF