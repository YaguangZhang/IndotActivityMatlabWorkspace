% Plot on a map the GPS tracks for work order 20848444 (collected on 1/31/2021 for
% vehicle 63519).
matchWorkOrdersWithGps;

vehGpsT = parsedGpsLocTable(parsedGpsLocTable.vehId==63519,:);
datetimeOfInt = parsedVehWorkOrderTable(parsedVehWorkOrderTable.workOrderId==20848444,:);
dtOfInt = datetimeOfInt.localDatetime(1);
startTime = dateshift(dtOfInt, 'start','day');
endTime = dateshift(dtOfInt, 'end', 'day');

vehGpsTToday = vehGpsT(vehGpsT.localDatetime>startTime & vehGpsT.localDatetime<endTime, :);

figure; plot(vehGpsTToday.lon, vehGpsTToday.lat, 'r.'); plot_google_map('mapType', 'hybrid');
vehWOsToday = parsedVehWorkOrderTable(parsedVehWorkOrderTable.workOrderId==20848444,:);

% EOF