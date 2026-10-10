function railway_gui()
%RAILWAY_GUI  Graphical interface for the Railway Technology Evolution Analysis.
%
%   railway_gui
%
%   Features
%     - Select one of the five railway generations.
%     - Edit the numeric parameters of the selected generation in a table.
%     - Run phases 1-6 for the selected generation and inspect the results in tabs.
%     - Run all generations + Phase 7 comparison (Technology Index, scores, table).
%     - Export the comparison table to CSV.
%
%   Required files (same folder or subfolders):
%     railway_generations.m, phase1_system_definition.m ... phase7_evolution_comparison.m
%
%   The phase files are not modified. If a folder "_patched" exists (created by
%   main.m), it is put first on the path so the patched Phase 3 / Phase 6 are used.

    %% Paths
    root = fileparts(mfilename('fullpath'));
    if isempty(root)
        root = pwd;
    end
    addpath(genpath(root));
    patch_dir = fullfile(root, '_patched');
    if isfolder(patch_dir)
        addpath(patch_dir, '-begin');
    end
    rehash;

    required = {'railway_generations', 'phase1_system_definition', 'phase2_energy_analysis', ...
                'phase3_propulsion_dynamics', 'phase4_braking_safety', 'phase5_control_automation', ...
                'phase6_performance_efficiency', 'phase7_evolution_comparison'};
    missing = required(cellfun(@(f) exist(f, 'file') == 0, required));
    if ~isempty(missing)
        error('railway_gui:missingFile', 'Missing files: %s', strjoin(missing, ', '));
    end

    %% Application state
    S.gens = railway_generations();
    S.keys = fieldnames(S.gens)';
    S.R    = struct();          % results per generation (p1..p6)
    S.r7   = [];                % Phase 7 results

    gen_names = cellfun(@(k) S.gens.(k).name, S.keys, 'UniformOutput', false);

    %% Main window
    fig = uifigure('Name', 'Railway Technology Evolution Analysis', ...
                   'Position', [40 40 1450 820]);
    mainGrid = uigridlayout(fig, [1 2]);
    mainGrid.ColumnWidth = {330, '1x'};
    mainGrid.Padding = [8 8 8 8];

    %% Left panel
    left = uigridlayout(mainGrid, [9 1]);
    left.RowHeight = {22, 28, 22, '1x', 32, 32, 32, 32, 44};
    left.Padding = [0 0 0 0];

    uilabel(left, 'Text', 'Railway generation', 'FontWeight', 'bold');
    ddGen = uidropdown(left, 'Items', gen_names, 'ItemsData', S.keys, ...
                       'Value', S.keys{1}, 'ValueChangedFcn', @(~, ~) onDropdown());
    uilabel(left, 'Text', 'Parameters (double-click a value to edit)', 'FontWeight', 'bold');
    tblPar = uitable(left, 'ColumnName', {'Parameter', 'Value'}, ...
                     'ColumnEditable', [false true], 'ColumnFormat', {'char', 'numeric'}, ...
                     'ColumnWidth', {170, 100}, 'RowName', {}, ...
                     'CellEditCallback', @(src, evt) onEdit(evt));
    uibutton(left, 'Text', 'Run selected generation', 'FontWeight', 'bold', ...
             'ButtonPushedFcn', @(~, ~) onRunSelected());
    uibutton(left, 'Text', 'Run all + compare (Phase 7)', 'FontWeight', 'bold', ...
             'ButtonPushedFcn', @(~, ~) onRunAll());
    uibutton(left, 'Text', 'Reset all parameters', ...
             'ButtonPushedFcn', @(~, ~) onReset());
    uibutton(left, 'Text', 'Export comparison CSV', ...
             'ButtonPushedFcn', @(~, ~) onExport());
    lblStatus = uilabel(left, 'Text', 'Ready.', 'WordWrap', 'on', 'VerticalAlignment', 'top');

    %% Right panel: tabs
    tabs = uitabgroup(mainGrid);

    tabOv = uitab(tabs, 'Title', 'Overview');
    gOv = uigridlayout(tabOv, [1 1]);
    txtOv = uitextarea(gOv, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 12);

    tabEn = uitab(tabs, 'Title', 'Phase 2 Energy');
    axEn = make_axes(uigridlayout(tabEn, [1 2]), 2);

    tabDy = uitab(tabs, 'Title', 'Phase 3 Dynamics');
    axDy = make_axes(uigridlayout(tabDy, [2 2]), 4);

    tabBr = uitab(tabs, 'Title', 'Phase 4 Braking');
    axBr = make_axes(uigridlayout(tabBr, [2 2]), 4);

    tabCt = uitab(tabs, 'Title', 'Phase 5 Control');
    axCt = make_axes(uigridlayout(tabCt, [2 2]), 4);

    tabPf = uitab(tabs, 'Title', 'Phase 6 Performance');
    gPf = uigridlayout(tabPf, [1 2]);
    axPf = uiaxes(gPf);
    tblPf = uitable(gPf, 'ColumnName', {'Metric', 'Value'}, 'RowName', {}, ...
                    'ColumnWidth', {230, 100});

    tabCp = uitab(tabs, 'Title', 'Phase 7 Comparison');
    gCp = uigridlayout(tabCp, [2 2]);
    axCp = gobjects(1, 3);
    for k = 1:3
        axCp(k) = uiaxes(gCp);
    end
    tblCp = uitable(gCp, 'RowName', {}, 'ColumnName', {});

    tabLg = uitab(tabs, 'Title', 'Log');
    gLg = uigridlayout(tabLg, [1 1]);
    txtLog = uitextarea(gLg, 'Editable', 'off', 'FontName', 'Courier New', 'FontSize', 11);

    %% Initial content
    loadTable();
    clearPlots('Select a generation and click "Run selected generation".');

    %% ===================== NESTED CALLBACKS =====================

    function setStatus(msg)
        lblStatus.Text = msg;
        drawnow;
    end

    function loadTable()
        key = ddGen.Value;
        g = S.gens.(key);
        fn = fieldnames(g);
        data = cell(0, 2);
        for k = 1:numel(fn)
            v = g.(fn{k});
            if isnumeric(v) && isscalar(v)
                data(end + 1, :) = {fn{k}, v}; %#ok<AGROW>
            end
        end
        tblPar.Data = data;
    end

    function clearPlots(msg)
        allAx = [axEn, axDy, axBr, axCt, axPf];
        for k = 1:numel(allAx)
            prep(allAx(k), '', '', '');
        end
        tblPf.Data = cell(0, 2);
        txtOv.Value = {msg};
    end

    function onDropdown()
        loadTable();
        key = ddGen.Value;
        if isfield(S.R, key)
            showResults(key);
        else
            clearPlots('No results yet for this generation. Click "Run selected generation".');
        end
    end

    function onEdit(evt)
        key = ddGen.Value;
        row = evt.Indices(1);
        fname = tblPar.Data{row, 1};
        v = evt.NewData;
        if ischar(v) || isstring(v)
            v = str2double(v);
        end
        if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v)
            tblPar.Data{row, 2} = evt.PreviousData;
            uialert(fig, 'Please enter a finite numeric value.', 'Invalid value');
            return;
        end
        S.gens.(key).(fname) = v;
        tblPar.Data{row, 2} = v;
        if isfield(S.R, key)
            S.R = rmfield(S.R, key);
            clearPlots('Parameters changed. Click "Run selected generation" again.');
        end
        setStatus(sprintf('Parameter "%s" changed. Results of this generation were cleared.', fname));
    end

    function onReset()
        S.gens = railway_generations();
        S.R = struct();
        S.r7 = [];
        loadTable();
        clearPlots('Parameters reset. Click "Run selected generation".');
        tblCp.Data = {};
        for k = 1:numel(axCp)
            prep(axCp(k), '', '', '');
        end
        setStatus('All parameters were reset to the database values.');
    end

    function onRunSelected()
        key = ddGen.Value;
        dlg = uiprogressdlg(fig, 'Title', 'Running', 'Message', ...
                            ['Running phases 1-6: ' S.gens.(key).name], 'Indeterminate', 'on');
        try
            [out, lg] = run_pipeline(S.gens.(key));
            S.R.(key) = out;
            txtLog.Value = strsplit(lg, newline);
            close(dlg);
        catch ME
            if isvalid(dlg), close(dlg); end
            uialert(fig, ME.message, 'Run failed');
            setStatus(['Error: ' ME.message]);
            return;
        end
        showResults(key);
        tabs.SelectedTab = tabOv;
        setStatus(sprintf('Done: %s.', S.gens.(key).name));
    end

    function onRunAll()
        n = numel(S.keys);
        dlg = uiprogressdlg(fig, 'Title', 'Running all generations', 'Value', 0);
        logAll = '';
        try
            for i = 1:n
                key = S.keys{i};
                dlg.Message = sprintf('Generation %d / %d: %s', i, n, S.gens.(key).name);
                dlg.Value = (i - 1) / (n + 1);
                [out, lg] = run_pipeline(S.gens.(key));
                S.R.(key) = out;
                logAll = [logAll lg]; %#ok<AGROW>
            end
            dlg.Message = 'Phase 7: comparison';
            dlg.Value = n / (n + 1);
            [S.r7, lg7] = run_compare(S.R, S.keys);
            logAll = [logAll lg7];
            txtLog.Value = strsplit(logAll, newline);
            close(dlg);
        catch ME
            if isvalid(dlg), close(dlg); end
            uialert(fig, ME.message, 'Run failed');
            setStatus(['Error: ' ME.message]);
            return;
        end
        showResults(ddGen.Value);
        showComparison();
        tabs.SelectedTab = tabCp;
        setStatus('All generations done. Comparison updated.');
    end

    function onExport()
        if isempty(S.r7)
            uialert(fig, 'Run "Run all + compare" first.', 'Nothing to export');
            return;
        end
        [f, p] = uiputfile('comparison.csv', 'Save comparison table');
        if isequal(f, 0)
            return;
        end
        writetable(S.r7.table, fullfile(p, f), 'WriteRowNames', true);
        setStatus(['Saved: ' fullfile(p, f)]);
    end

    function showResults(key)
        Ri = S.R.(key);
        txtOv.Value = summary_text(Ri);
        plot_energy(axEn, Ri.p2);
        plot_dynamics(axDy, Ri.p3);
        plot_braking(axBr, Ri.p4);
        plot_control(axCt, Ri.p5);
        plot_performance(axPf, tblPf, Ri.p6);
    end

    function showComparison()
        r7 = S.r7;
        n  = numel(r7.names);
        xt = 1:n;

        prep(axCp(1), 'Technology Index (model-based)', '', 'TI [-]');
        bar(axCp(1), xt, r7.technology_index);
        set_ticks(axCp(1), xt, r7.names);
        axCp(1).YLim = [0 1];

        prep(axCp(2), 'Category scores (Phase 6)', '', 'Score [-]');
        plot(axCp(2), xt, r7.scores, '-o', 'LineWidth', 1.3);
        set_ticks(axCp(2), xt, r7.names);
        axCp(2).YLim = [0 1];
        legend(axCp(2), r7.score_names, 'Location', 'eastoutside');

        j = find(strcmp(r7.metric_labels, 'Energy per passenger-km'), 1);
        prep(axCp(3), 'Energy per passenger-km', '', 'kWh/pkm');
        plot(axCp(3), xt, r7.metric_matrix(:, j), '-o', 'LineWidth', 1.5);
        axCp(3).YScale = 'log';
        set_ticks(axCp(3), xt, r7.names);

        rows = cellfun(@(a, b) sprintf('%s [%s]', a, b), r7.metric_labels, r7.metric_units, ...
                       'UniformOutput', false);
        tblCp.Data = num2cell(r7.metric_matrix');
        tblCp.ColumnName = r7.names;
        tblCp.RowName = rows;
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function ax = make_axes(grid, n)
%MAKE_AXES  Create n axes in a grid layout.

    ax = gobjects(1, n);
    for k = 1:n
        ax(k) = uiaxes(grid);
    end
end


function prep(ax, ttl, xl, yl)
%PREP  Reset an axes before plotting.

    cla(ax);
    legend(ax, 'off');
    hold(ax, 'on');
    grid(ax, 'on');
    ax.XTickMode = 'auto';       ax.XTickLabelMode = 'auto';
    ax.YTickMode = 'auto';       ax.YTickLabelMode = 'auto';
    ax.XLimMode  = 'auto';       ax.YLimMode = 'auto';
    ax.YScale = 'linear';
    ax.XTickLabelRotation = 0;
    ax.FontSize = 11;
    title(ax, ttl);
    xlabel(ax, xl);
    ylabel(ax, yl);
end


function set_ticks(ax, xt, labels)
%SET_TICKS  Text labels on the x axis.

    ax.XTick = xt;
    ax.XTickLabel = labels;
    ax.XTickLabelRotation = 20;
    ax.FontSize = 9;
end


function [out, logTxt] = run_pipeline(g)
%RUN_PIPELINE  Run phases 1-6 for one generation and capture the console output.

    s = []; p2 = []; p3 = []; p4 = []; p5 = []; p6 = []; res = []; %#ok<NASGU>
    cmd = ['s  = phase1_system_definition(g);' ...
           'p2 = phase2_energy_analysis(g, s);' ...
           'p3 = phase3_propulsion_dynamics(g, s);' ...
           'p4 = phase4_braking_safety(g, s);' ...
           'p5 = phase5_control_automation(g, s);' ...
           'res = struct(''p2'', p2, ''p3'', p3, ''p4'', p4, ''p5'', p5);' ...
           'p6 = phase6_performance_efficiency(g, s, res);'];
    logTxt = evalc(cmd);
    out = struct('p1', s, 'p2', p2, 'p3', p3, 'p4', p4, 'p5', p5, 'p6', p6);
end


function [r7, logTxt] = run_compare(R, keys)
%RUN_COMPARE  Run Phase 7 and capture the console output.

    r7 = [];
    o7 = struct('plot', false, 'order', {keys});
    logTxt = evalc('r7 = phase7_evolution_comparison(R, o7);');
end


function lines = summary_text(Ri)
%SUMMARY_TEXT  Text overview of the results of one generation.

    p1 = Ri.p1; p2 = Ri.p2; p3 = Ri.p3; p4 = Ri.p4; p5 = Ri.p5; p6 = Ri.p6;
    t100 = p3.times.time_s(p3.times.speed_kmh == 100);
    if isempty(t100), t100 = NaN; end

    lines = {};
    lines{end + 1, 1} = sprintf('%s  (%s)', p1.name, p1.era);
    lines{end + 1, 1} = sprintf('Energy source: %s | Architecture: %s | Automation level: %d', ...
                                p1.energy_source, p1.architecture, p1.automation_level);
    lines{end + 1, 1} = '';
    lines{end + 1, 1} = '--- SYSTEM (Phase 1) ---';
    lines{end + 1, 1} = sprintf('Mass %.0f t | Capacity %d pass. | Rated power %.0f kW | Power/weight %.2f kW/t', ...
                                p1.train_mass_kg / 1000, p1.passenger_capacity, p1.rated_power_kW, ...
                                p1.power_to_weight_kW_per_t);
    lines{end + 1, 1} = sprintf('Drivetrain efficiency %.1f %% | Max adhesion force %.1f kN', ...
                                100 * p1.drivetrain_efficiency, p1.max_adhesion_force_N / 1000);
    lines{end + 1, 1} = '';
    lines{end + 1, 1} = '--- ENERGY (Phase 2) ---';
    lines{end + 1, 1} = sprintf('Input energy %.1f kWh over %.0f km', p2.energy.input_kWh, p2.journey.distance_km);
    lines{end + 1, 1} = sprintf('Specific energy %.4f kWh/pkm | CO2 %.4f kg/pkm', ...
                                p2.specific.kWh_per_pkm, p2.co2.kg_per_pkm);
    lines{end + 1, 1} = sprintf('Wheel / input energy %.1f %%', 100 * p2.efficiency.wheel_over_input);
    lines{end + 1, 1} = '';
    lines{end + 1, 1} = '--- DYNAMICS (Phase 3) ---';
    lines{end + 1, 1} = sprintf('Max speed %.1f km/h (%s)', p3.max_speed_kmh, p3.limiting_factor);
    lines{end + 1, 1} = sprintf('Start acceleration %.3f m/s^2 | 0-100 km/h %.1f s', p3.start_accel_ms2, t100);
    lines{end + 1, 1} = sprintf('Travel time %.1f min (avg %.1f km/h)', ...
                                p3.journey.travel_time_min, p3.journey.average_speed_kmh);
    lines{end + 1, 1} = '';
    lines{end + 1, 1} = '--- BRAKING (Phase 4) ---';
    lines{end + 1, 1} = sprintf('Service stop %.0f m | Emergency stop %.0f m (incl. reaction)', ...
                                p4.service.total_distance_m, p4.emergency.total_distance_m);
    lines{end + 1, 1} = sprintf('Regen recovery (one stop) %.1f %% | Safety index %.2f', ...
                                p4.energy.regen_recovery_pct, p4.safety.index);
    lines{end + 1, 1} = '';
    lines{end + 1, 1} = '--- CONTROL (Phase 5) ---';
    lines{end + 1, 1} = sprintf('Automation index %.2f | Control quality %.2f | Control score %.2f', ...
                                p5.automation_index, p5.quality.index, p5.control_score);
    lines{end + 1, 1} = sprintf('RMS speed error %.2f km/h | Stop error %.1f m', ...
                                p5.tracking.rms_err_kmh, p5.tracking.stop_err_m);
    lines{end + 1, 1} = '';
    lines{end + 1, 1} = '--- OVERALL (Phase 6) ---';
    lines{end + 1, 1} = sprintf('Overall index %.3f  (model-based, not an official rating)', p6.overall_index);
end


function plot_energy(ax, p2)
%PLOT_ENERGY  Energy breakdown and efficiencies.

    labels = {'Resistance', 'Kinetic (net)', 'Transm. loss', 'Prime mover loss', 'Auxiliary'};
    vals = [p2.energy.resistance_kWh, p2.energy.kinetic_kWh - p2.energy.regenerated_kWh, ...
            p2.energy.transmission_loss_kWh, p2.energy.prime_mover_loss_kWh, p2.energy.auxiliary_kWh];
    prep(ax(1), sprintf('Energy breakdown (input %.1f kWh)', p2.energy.input_kWh), '', 'Energy [kWh]');
    bar(ax(1), 1:5, vals);
    set_ticks(ax(1), 1:5, labels);

    labels2 = {'Drivetrain eff.', 'Wheel / input', 'Regen recovery'};
    vals2 = [100 * p2.efficiency.drivetrain, 100 * p2.efficiency.wheel_over_input, ...
             p2.efficiency.regen_recovery_pct];
    prep(ax(2), 'Efficiencies', '', '[%]');
    bar(ax(2), 1:3, vals2);
    set_ticks(ax(2), 1:3, labels2);
end


function plot_dynamics(ax, p3)
%PLOT_DYNAMICS  Speed, acceleration, forces, distance.

    pr = p3.profile;

    prep(ax(1), 'Speed vs time', 'Time [s]', 'Speed [km/h]');
    plot(ax(1), pr.t_s, pr.v_kmh, 'LineWidth', 1.5);

    prep(ax(2), 'Acceleration vs speed', 'Speed [km/h]', 'Acceleration [m/s^2]');
    plot(ax(2), pr.v_kmh, pr.acc_ms2, 'LineWidth', 1.5);

    prep(ax(3), 'Tractive effort and resistance', 'Speed [km/h]', 'Force [kN]');
    plot(ax(3), pr.v_kmh, pr.F_traction_kN, 'LineWidth', 1.5);
    plot(ax(3), pr.v_kmh, pr.F_resist_kN, 'LineWidth', 1.5);
    legend(ax(3), {'Tractive effort', 'Resistance'}, 'Location', 'best');

    prep(ax(4), 'Distance vs time', 'Time [s]', 'Distance [km]');
    plot(ax(4), pr.t_s, pr.x_m / 1000, 'LineWidth', 1.5);
end


function plot_braking(ax, p4)
%PLOT_BRAKING  Stopping profiles, brake force split, stopping distance curves.

    sv = p4.service.profile;
    em = p4.emergency.profile;

    prep(ax(1), 'Speed vs time (after brake command)', 'Time [s]', 'Speed [km/h]');
    plot(ax(1), sv.t_s, sv.v_kmh, 'LineWidth', 1.5);
    plot(ax(1), em.t_s, em.v_kmh, 'LineWidth', 1.5);
    legend(ax(1), {'Service', 'Emergency'}, 'Location', 'best');

    prep(ax(2), 'Speed vs distance (after brake command)', 'Distance [m]', 'Speed [km/h]');
    plot(ax(2), sv.x_m, sv.v_kmh, 'LineWidth', 1.5);
    plot(ax(2), em.x_m, em.v_kmh, 'LineWidth', 1.5);
    legend(ax(2), {'Service', 'Emergency'}, 'Location', 'best');

    prep(ax(3), 'Service brake force split', 'Time [s]', 'Brake force [kN]');
    area(ax(3), sv.t_s, [sv.F_electric_kN, sv.F_friction_kN]);
    legend(ax(3), {'Electric', 'Friction'}, 'Location', 'best');

    prep(ax(4), 'Total stopping distance vs speed', 'Initial speed [km/h]', 'Distance [m]');
    plot(ax(4), p4.curve.speed_kmh, p4.curve.service_total_m, '-o', 'LineWidth', 1.5);
    plot(ax(4), p4.curve.speed_kmh, p4.curve.emergency_total_m, '-s', 'LineWidth', 1.5);
    legend(ax(4), {'Service', 'Emergency'}, 'Location', 'northwest');
end


function plot_control(ax, p5)
%PLOT_CONTROL  Speed tracking, error, force and automated functions.

    pr = p5.profile;

    prep(ax(1), 'Speed tracking', 'Time [s]', 'Speed [km/h]');
    plot(ax(1), pr.t_s, pr.v_ref_kmh, '--', 'LineWidth', 1.5);
    plot(ax(1), pr.t_s, pr.v_kmh, 'LineWidth', 1.5);
    legend(ax(1), {'Reference', 'Actual'}, 'Location', 'best');

    prep(ax(2), 'Tracking error (actual - reference)', 'Time [s]', 'Error [km/h]');
    plot(ax(2), pr.t_s, pr.v_kmh - pr.v_ref_kmh, 'LineWidth', 1.2);

    prep(ax(3), 'Traction / brake force', 'Time [s]', 'Force [kN]');
    plot(ax(3), pr.t_s, pr.F_cmd_kN, 'LineWidth', 1.2);
    plot(ax(3), pr.t_s, pr.F_act_kN, 'LineWidth', 1.5);
    legend(ax(3), {'Command', 'Applied'}, 'Location', 'best');

    nf = p5.functions.n_total;
    prep(ax(4), sprintf('Automated functions (AI = %.2f)', p5.automation_index), '', '');
    barh(ax(4), double(p5.functions.flags(end:-1:1)));
    ax(4).YTick = 1:nf;
    ax(4).YTickLabel = p5.functions.names(end:-1:1);
    ax(4).XTick = [0 1];
    ax(4).XLim = [0 1.2];
    ax(4).FontSize = 9;
end


function plot_performance(ax, tbl, p6)
%PLOT_PERFORMANCE  Category scores and key metrics table.

    names = fieldnames(p6.scores)';
    vals  = cellfun(@(n) p6.scores.(n), names);
    prep(ax, sprintf('Category scores (overall %.3f)', p6.overall_index), '', 'Score [-]');
    bar(ax, 1:numel(vals), vals);
    set_ticks(ax, 1:numel(vals), names);
    ax.YLim = [0 1];

    tbl.Data = { ...
        'Max speed [km/h]',             p6.performance.max_speed_kmh; ...
        'Average speed [km/h]',         p6.performance.average_speed_kmh; ...
        'Start acceleration [m/s^2]',   p6.performance.start_accel_ms2; ...
        'Travel time [min]',            p6.performance.travel_time_min; ...
        'Energy [kWh/pkm]',             p6.energy.kWh_per_pkm; ...
        'Wheel / input energy [-]',     p6.energy.wheel_over_input; ...
        'CO2 [kg/pkm]',                 p6.environment.co2_kg_per_pkm; ...
        'Emergency stop [m]',           p6.safety.emergency_distance_m; ...
        'Safety index [-]',             p6.safety.index; ...
        'Trains per hour',              p6.capacity.trains_per_hour; ...
        'Passengers per hour',          p6.capacity.passengers_per_hour; ...
        'Availability [-]',             p6.reliability.availability; ...
        'Overall index [-]',            p6.overall_index};
end