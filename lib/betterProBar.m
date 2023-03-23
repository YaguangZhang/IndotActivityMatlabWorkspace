classdef betterProBar < handle
    %BETTERPROBAR An improved version of the library ProgressBar,
    %supporting feedback frequency adjustment and clean diary output.
    %
    % Yaguang Zhang, Purdue, 09/08/2022

    properties
        proBarCnt = 0;
        proBar = nan;

        % Controls the progress bar update frequency.
        numOfProBarUpdates = 100;
        numOfLoopsPerUpdate = nan;
    end

    methods
        function obj = betterProBar(numOfLoops, ...
                numOfProBarUpdates)

            if exist('numOfProBarUpdates', 'var')
                obj.numOfProBarUpdates = numOfProBarUpdates;
            end

            if numOfLoops<obj.numOfProBarUpdates
                warning(['Setting numOfProBarUpdates to numOfLoops', ...
                    ' to ensure numOfLoops>=numOfProBarUpdates...'])
                obj.numOfProBarUpdates = numOfLoops;
            end

            obj.numOfLoopsPerUpdate = ceil( ...
                numOfLoops/obj.numOfProBarUpdates);
            obj.proBarCnt = 0;

            flagNeedToEnableDiary = false;
            % Temporarily disable diary if it is on.
            if strcmpi(get(0, 'Diary'), 'on')
                diary off;
                flagNeedToEnableDiary = true;
            end

            obj.proBar = fastProgressBar(obj.numOfProBarUpdates);

            if flagNeedToEnableDiary
                diary on;
            end
        end

        function progress(obj)
            obj.proBarCnt = obj.proBarCnt + 1;
            if mod(obj.proBarCnt, obj.numOfLoopsPerUpdate) == 0
                flagNeedToEnableDiary = false;
                % Temporarily disable diary if it is on.
                if strcmpi(get(0, 'Diary'), 'on')
                    diary off;
                    flagNeedToEnableDiary = true;
                end

                obj.proBar.progress;

                if flagNeedToEnableDiary
                    diary on;
                end
            end
        end

        function stop(obj)
            obj.proBar.stop;
        end
    end
end
% EOF