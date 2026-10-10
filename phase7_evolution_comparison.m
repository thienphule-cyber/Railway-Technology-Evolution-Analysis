function r = phase7_evolution_comparison(R, opts)
%PHASE7_EVOLUTION_COMPARISON  Compare the railway generations and analyse the technology evolution.
%
%   r = phase7_evolution_comparison(R)
%   r = phase7_evolution_comparison(R, opts)
%
%   INPUT  R    : struct with one field per generation (field order = chronological order).
%                 Each R.(key) is a struct with the results of the previous phases:
%                     R.(key).p1 = phase1_system_definition(...)       (or R.(key).s)
%                     R.(key).p2 = phase2_energy_analysis(...)
%                     R.(key).p3 = phase3_propulsion_dynamics(...)
%                     R.(key).p4 = phase4_braking_safety(...)
%                     R.(key).p5 = phase5_control_automation(...)
%                     R.(key).p6 = phase6_performance_efficiency(...)
%          opts : (optional) struct
%                   opts.plot       = true   draw the comparison figures
%                   opts.order      = cell array of field names of R (chronological order)
%                   opts.weights    = struct with the Technology Index weights
%                                     (fields: energy, performance, safety, automation,
%                                      reliability; all >= 0, sum = 1)
%                   opts.export_csv = file name, e.g. 'comparison.csv' (optional)
%   OUTPUT r    : struct with the comparison table, Technology Index, step-by-step
%                 transition analysis and overall improvement ratios
%
%   Technology Index (model-based):
%       TI = w_E * E + w_P * P + w_S * S + w_A * A + w_R * R,    sum(w) = 1
%       E = energy score, P = performance score, S = safety score,
%       A = automation score (Phase 6 control score), R = reliability score.
%       All scores come from Phase 6 and use fixed reference values, so a score does
%       not change when generations are added or removed.
%
%   The weights, the scores and the rationale texts are MODELLING ASSUMPTIONS.
%   TI is a model-based engineering index, NOT an official railway rating.

    if nargin < 2 || isempty(opts)
        opts = struct();
    end

    %% 1. Read options and collect the results
    o = read_options(opts, R);
    keys = o.order;
    n    = numel(keys);

    names = cell(1, n);
    eras  = cell(1, n);
    p6    = cell(1, n);
    for i = 1:n
        Ri = R.(keys{i});
        check_generation(Ri, keys{i});
        p6{i}   = Ri.p6;
        names{i} = char(Ri.p6.name);
        eras{i}  = '';
        if isfield(Ri, 'p1') && isfield(Ri.p1, 'era')
            eras{i} = char(Ri.p1.era);
        elseif isfield(Ri, 's') && isfield(Ri.s, 'era')
            eras{i} = char(Ri.s.era);
        end
    end
    short = cellfun(@shorten, names, 'UniformOutput', false);

    %% 2. Comparison table of key metrics
    M = metric_definitions();
    nm = size(M, 1);
    values = NaN(n, nm);
    for i = 1:n
        for j = 1:nm
            values(i, j) = M{j, 3}(p6{i});
        end
    end

    labels = M(:, 1)';
    units  = M(:, 2)';
    dirs   = cell2mat(M(:, 4))';                       % +1 higher is better, -1 lower is better

    var_names = matlab.lang.makeValidName(labels);
    T = array2table(values, 'VariableNames', var_names, 'RowNames', keys);

    r.keys           = keys;
    r.names          = names;
    r.eras           = eras;
    r.table          = T;
    r.metric_labels  = labels;
    r.metric_units   = units;
    r.metric_matrix  = values;
    r.normalized     = normalise_metrics(values, dirs);

    %% 3. Technology Index
    comp_names = {'energy', 'performance', 'safety', 'automation', 'reliability'};
    comp = zeros(n, numel(comp_names));
    for i = 1:n
        for k = 1:numel(comp_names)
            comp(i, k) = p6{i}.scores.(comp_names{k});
        end
    end
    w = cellfun(@(c) o.weights.(c), comp_names);       % 1 x 5
    TI = comp * w(:);

    r.ti_components_names = comp_names;
    r.ti_components       = comp;
    r.ti_weights          = o.weights;
    r.technology_index    = TI(:)';

    [~, order_desc] = sort(TI, 'descend');
    rank_vec = zeros(1, n);
    rank_vec(order_desc) = 1:n;
    r.rank = rank_vec;
    r.monotonic = all(diff(TI) >= 0);

    if ~r.monotonic
        warning('phase7:notMonotonic', ...
                'Technology Index does not increase with every generation. Check the input data and weights.');
    end

    %% 4. Category scores of Phase 6 (used for the transition analysis)
    score_names = fieldnames(p6{1}.scores)';
    S = zeros(n, numel(score_names));
    for i = 1:n
        for k = 1:numel(score_names)
            S(i, k) = p6{i}.scores.(score_names{k});
        end
    end
    r.score_names  = score_names;
    r.scores       = S;
    r.overall_index = cellfun(@(q) q.overall_index, p6);

    %% 5. Transition analysis (generation t -> t+1)
    rationale = default_rationale(n);
    tr = struct('from', {}, 'to', {}, 'delta_TI', {}, 'drivers', {}, 'driver_delta', {}, ...
                'tradeoffs', {}, 'tradeoff_delta', {}, 'metric_change_pct', {}, 'rationale', {});
    for t = 1:n-1
        d = S(t+1, :) - S(t, :);
        [~, ix] = sort(d, 'descend');

        top = ix(1:min(2, numel(ix)));
        top = top(d(top) > 0);
        neg = find(d < 0);
        [~, jx] = sort(d(neg), 'ascend');
        neg = neg(jx);

        pct = NaN(1, nm);
        for j = 1:nm
            if isfinite(values(t, j)) && isfinite(values(t+1, j)) && values(t, j) ~= 0
                pct(j) = 100 * (values(t+1, j) - values(t, j)) / abs(values(t, j));
            end
        end

        tr(t).from              = names{t};
        tr(t).to                = names{t+1};
        tr(t).delta_TI          = TI(t+1) - TI(t);
        tr(t).drivers           = score_names(top);
        tr(t).driver_delta      = d(top);
        tr(t).tradeoffs         = score_names(neg);
        tr(t).tradeoff_delta    = d(neg);
        tr(t).metric_change_pct = pct;
        tr(t).rationale         = rationale{t};
    end
    r.transitions = tr;

    %% 6. Overall improvement from the first to the last generation
    r.overall_change = struct();
    r.overall_change.first = names{1};
    r.overall_change.last  = names{n};
    r.overall_change.max_speed_ratio     = safe_ratio(values(n, find_metric(labels, 'Max speed')), ...
                                                      values(1, find_metric(labels, 'Max speed')));
    r.overall_change.energy_per_pkm_ratio = safe_ratio(values(n, find_metric(labels, 'Energy per passenger-km')), ...
                                                       values(1, find_metric(labels, 'Energy per passenger-km')));
    r.overall_change.co2_per_pkm_ratio   = safe_ratio(values(n, find_metric(labels, 'CO2 per passenger-km')), ...
                                                      values(1, find_metric(labels, 'CO2 per passenger-km')));
    r.overall_change.capacity_ratio      = safe_ratio(values(n, find_metric(labels, 'Passengers per hour')), ...
                                                      values(1, find_metric(labels, 'Passengers per hour')));
    r.overall_change.TI_gain             = TI(n) - TI(1);

    %% 7. Report, export and plots
    print_summary(r, short);

    if ~isempty(o.export_csv)
        writetable(T, o.export_csv, 'WriteRowNames', true);
        fprintf(' Comparison table written to: %s\n', o.export_csv);
    end

    if o.plot
        plot_results(r, short);
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function o = read_options(opts, R)
%READ_OPTIONS  Read options, apply defaults and validate them.

    if ~isstruct(R) || isempty(fieldnames(R))
        error('phase7:badInput', 'Input "R" must be a non-empty struct with one field per generation.');
    end

    if isfield(opts, 'order') && ~isempty(opts.order)
        o.order = cellstr(opts.order);
        o.order = o.order(:)';
        for i = 1:numel(o.order)
            if ~isfield(R, o.order{i})
                error('phase7:badOrder', 'opts.order contains "%s", which is not a field of R.', o.order{i});
            end
        end
    else
        o.order = fieldnames(R)';
    end

    if numel(o.order) < 2
        error('phase7:tooFew', 'At least two generations are required for a comparison.');
    end

    o.plot       = isfield(opts, 'plot') && ~isempty(opts.plot) && opts.plot;
    o.export_csv = '';
    if isfield(opts, 'export_csv') && ~isempty(opts.export_csv)
        o.export_csv = char(opts.export_csv);
    end

    % Technology Index weights (assumption)
    w = struct('energy', 0.25, 'performance', 0.25, 'safety', 0.20, ...
               'automation', 0.15, 'reliability', 0.15);
    if isfield(opts, 'weights') && ~isempty(opts.weights)
        fn = fieldnames(opts.weights);
        for i = 1:numel(fn)
            if ~isfield(w, fn{i})
                error('phase7:badWeight', 'Unknown weight "%s".', fn{i});
            end
            w.(fn{i}) = opts.weights.(fn{i});
        end
    end
    vals = cell2mat(struct2cell(w));
    if any(vals < 0) || abs(sum(vals) - 1) > 1e-6
        error('phase7:badWeight', 'Weights must be >= 0 and their sum must be 1 (current sum: %.3f).', sum(vals));
    end
    o.weights = w;
end


function check_generation(Ri, key)
%CHECK_GENERATION  Make sure the Phase 6 results of one generation are available.

    if ~isstruct(Ri) || ~isfield(Ri, 'p6') || ~isstruct(Ri.p6)
        error('phase7:missingResult', 'R.%s has no Phase 6 results (field "p6").', key);
    end
    req = {'name','performance','energy','capacity','safety','automation', ...
           'reliability','environment','scores','overall_index'};
    for k = 1:numel(req)
        if ~isfield(Ri.p6, req{k})
            error('phase7:missingResult', 'R.%s.p6 has no field "%s".', key, req{k});
        end
    end
end


function M = metric_definitions()
%METRIC_DEFINITIONS  Metrics of the comparison table.
%   Columns: label, unit, getter (function of the Phase 6 struct), direction (+1 / -1).

    M = { ...
        'Max speed',               'km/h',   @(q) q.performance.max_speed_kmh,            +1; ...
        'Average speed',           'km/h',   @(q) q.performance.average_speed_kmh,        +1; ...
        'Start acceleration',      'm/s^2',  @(q) q.performance.start_accel_ms2,          +1; ...
        'Travel time',             'min',    @(q) q.performance.travel_time_min,          -1; ...
        'Energy per passenger-km', 'kWh/pkm', @(q) q.energy.kWh_per_pkm,                  -1; ...
        'Wheel / input energy',    '%',      @(q) 100 * q.energy.wheel_over_input,        +1; ...
        'Regen recovery',          '%',      @(q) q.energy.regen_journey_pct,             +1; ...
        'Emergency stop distance', 'm',      @(q) q.safety.emergency_distance_m,          -1; ...
        'Safety index',            '-',      @(q) q.safety.index,                         +1; ...
        'Automation index',        '-',      @(q) q.automation.index,                     +1; ...
        'Control quality index',   '-',      @(q) q.automation.quality_index,             +1; ...
        'Passengers per hour',     'pax/h',  @(q) q.capacity.passengers_per_hour,         +1; ...
        'Availability',            '%',      @(q) 100 * q.reliability.availability,       +1; ...
        'CO2 per passenger-km',    'kg/pkm', @(q) q.environment.co2_kg_per_pkm,           -1; ...
        'Overall index (Phase 6)', '-',      @(q) q.overall_index,                        +1};
end


function idx = find_metric(labels, name)
%FIND_METRIC  Index of a metric label.

    idx = find(strcmp(labels, name), 1);
    if isempty(idx)
        error('phase7:internal', 'Metric "%s" is not defined.', name);
    end
end


function N = normalise_metrics(V, dirs)
%NORMALISE_METRICS  Min-max normalisation per metric, 1 = best generation, 0 = worst.

    N = NaN(size(V));
    for j = 1:size(V, 2)
        col = V(:, j);
        lo = min(col(isfinite(col)));
        hi = max(col(isfinite(col)));
        if isempty(lo)
            continue;
        end
        if hi == lo
            N(isfinite(col), j) = 0.5;
        elseif dirs(j) > 0
            N(:, j) = (col - lo) / (hi - lo);
        else
            N(:, j) = (hi - col) / (hi - lo);
        end
    end
end


function y = safe_ratio(a, b)
%SAFE_RATIO  a / b, or NaN if b is zero or not finite.

    if isfinite(a) && isfinite(b) && b ~= 0
        y = a / b;
    else
        y = NaN;
    end
end


function s = shorten(name)
%SHORTEN  Short label for table headers and axis ticks.

    s = strtrim(name);
    if numel(s) > 14
        s = [s(1:13) '.'];
    end
end


function txt = default_rationale(n)
%DEFAULT_RATIONALE  Short engineering explanation of each transition.
%   Used for the standard 5-generation chain. Otherwise a generic text is returned.

    if n == 5
        txt = { ...
            'Low conversion efficiency and a large mechanical system led to diesel-electric drive with higher controllability.', ...
            'Fuel conversion on board was replaced by direct electrical supply and distributed traction with regenerative braking.', ...
            'Higher speed raised aerodynamic, suspension and wheel-rail problems, giving integrated high-speed system engineering.', ...
            'Complex operation drove more sensors, computing, automatic control and predictive maintenance.'};
    else
        txt = repmat({'See the drivers and trade-offs computed from the category scores.'}, 1, max(n - 1, 0));
    end
end


function print_summary(r, short)
%PRINT_SUMMARY  Print the comparison table, Technology Index and transition analysis.

    n  = numel(r.names);
    nm = numel(r.metric_labels);

    fprintf('\n==============================================================================\n');
    fprintf(' PHASE 7 - TECHNOLOGY EVOLUTION COMPARISON\n');
    fprintf('==============================================================================\n');

    fprintf(' %-36s', 'Metric');
    for i = 1:n
        fprintf(' %14s', short{i});
    end
    fprintf('\n %s\n', repmat('-', 1, 36 + 15 * n));

    for j = 1:nm
        fprintf(' %-36s', sprintf('%s [%s]', r.metric_labels{j}, r.metric_units{j}));
        for i = 1:n
            fprintf(' %14.4g', r.metric_matrix(i, j));
        end
        fprintf('\n');
    end

    fprintf(' %s\n', repmat('-', 1, 36 + 15 * n));
    fprintf(' TECHNOLOGY INDEX (model-based)\n');
    for k = 1:numel(r.ti_components_names)
        fprintf(' %-36s', sprintf('  %s score (w = %.2f)', r.ti_components_names{k}, ...
                                  r.ti_weights.(r.ti_components_names{k})));
        for i = 1:n
            fprintf(' %14.3f', r.ti_components(i, k));
        end
        fprintf('\n');
    end
    fprintf(' %-36s', 'Technology Index TI');
    for i = 1:n
        fprintf(' %14.3f', r.technology_index(i));
    end
    fprintf('\n %-36s', 'Rank (1 = best)');
    for i = 1:n
        fprintf(' %14d', r.rank(i));
    end
    fprintf('\n');

    % Simple text bar chart of TI
    fprintf('\n');
    for i = 1:n
        fprintf(' %-16s %s %.3f\n', short{i}, repmat(char(9608), 1, round(30 * r.technology_index(i))), ...
                r.technology_index(i));
    end

    fprintf('\n TRANSITIONS\n');
    for t = 1:numel(r.transitions)
        x = r.transitions(t);
        fprintf(' %s -> %s : dTI = %+.3f\n', x.from, x.to, x.delta_TI);
        fprintf('   Main gains  : %s\n', list_text(x.drivers, x.driver_delta));
        fprintf('   Trade-offs  : %s\n', list_text(x.tradeoffs, x.tradeoff_delta));
        fprintf('   Why         : %s\n', x.rationale);
    end

    c = r.overall_change;
    fprintf('\n OVERALL (%s -> %s)\n', c.first, c.last);
    fprintf('   Max speed          : x%.2f\n', c.max_speed_ratio);
    fprintf('   Energy / pass.-km  : x%.3f\n', c.energy_per_pkm_ratio);
    fprintf('   CO2 / pass.-km     : x%.3f\n', c.co2_per_pkm_ratio);
    fprintf('   Passengers / hour  : x%.2f\n', c.capacity_ratio);
    fprintf('   Technology Index   : %+.3f\n', c.TI_gain);
    if r.monotonic
        fprintf('   TI increases with every generation.\n');
    else
        fprintf('   WARNING: TI does not increase with every generation.\n');
    end
    fprintf(' TI and all scores are model-based indices, not official railway ratings.\n');
    fprintf('==============================================================================\n');
end


function txt = list_text(names, deltas)
%LIST_TEXT  Format a list of category names with their score changes.

    if isempty(names)
        txt = 'none';
        return;
    end
    parts = cell(1, numel(names));
    for k = 1:numel(names)
        parts{k} = sprintf('%s (%+.2f)', names{k}, deltas(k));
    end
    txt = strjoin(parts, ', ');
end


function plot_results(r, short)
%PLOT_RESULTS  Two figures: summary plots and a normalised metric heat map.

    n = numel(r.names);
    x = 1:n;

    %% Figure 1: summary
    figure('Name', 'Phase 7 - Evolution comparison', 'Color', 'w');

    subplot(2, 2, 1);
    bar(x, r.technology_index);
    set(gca, 'XTick', x, 'XTickLabel', short);
    ylim([0 1]); ylabel('Technology Index [-]');
    title('Technology Index'); grid on;
    for i = 1:n
        text(i, r.technology_index(i) + 0.02, sprintf('%.2f', r.technology_index(i)), ...
             'HorizontalAlignment', 'center');
    end

    subplot(2, 2, 2);
    plot(x, r.scores, '-o', 'LineWidth', 1.3);
    set(gca, 'XTick', x, 'XTickLabel', short);
    ylim([0 1]); ylabel('Score [-]');
    legend(r.score_names, 'Location', 'eastoutside');
    title('Category scores (Phase 6)'); grid on;

    subplot(2, 2, 3);
    hold on;
    ang = linspace(pi/2, pi/2 - 2*pi, numel(r.score_names) + 1);
    for ring = [0.25 0.5 0.75 1]
        plot(ring * cos(ang), ring * sin(ang), ':', 'Color', [0.7 0.7 0.7]);
    end
    for k = 1:numel(r.score_names)
        plot([0 cos(ang(k))], [0 sin(ang(k))], '-', 'Color', [0.85 0.85 0.85]);
        text(1.2 * cos(ang(k)), 1.2 * sin(ang(k)), r.score_names{k}, ...
             'HorizontalAlignment', 'center', 'FontSize', 8);
    end
    h = gobjects(1, n);
    for i = 1:n
        v = [r.scores(i, :) r.scores(i, 1)];
        h(i) = plot(v .* cos(ang), v .* sin(ang), '-', 'LineWidth', 1.5);
    end
    axis equal off;
    xlim([-1.6 1.6]); ylim([-1.4 1.4]);
    legend(h, short, 'Location', 'southoutside', 'Orientation', 'horizontal', 'FontSize', 7);
    title('Category scores (radar)');

    subplot(2, 2, 4);
    j_e = find_metric(r.metric_labels, 'Energy per passenger-km');
    j_v = find_metric(r.metric_labels, 'Max speed');
    yyaxis left;
    plot(x, r.metric_matrix(:, j_e), '-o', 'LineWidth', 1.5);
    set(gca, 'YScale', 'log');
    ylabel('Energy [kWh/pkm]');
    yyaxis right;
    plot(x, r.metric_matrix(:, j_v), '-s', 'LineWidth', 1.5);
    ylabel('Max speed [km/h]');
    set(gca, 'XTick', x, 'XTickLabel', short);
    title('Energy per passenger-km and max speed'); grid on;

    sgtitle('Railway technology evolution');

    %% Figure 2: normalised metrics
    figure('Name', 'Phase 7 - Normalised metrics', 'Color', 'w');
    imagesc(r.normalized', 'AlphaData', ~isnan(r.normalized'));
    set(gca, 'Color', [0.9 0.9 0.9]);
    colormap(parula);
    cb = colorbar;
    cb.Label.String = '0 = worst generation, 1 = best generation';
    set(gca, 'XTick', x, 'XTickLabel', short, ...
             'YTick', 1:numel(r.metric_labels), 'YTickLabel', r.metric_labels);
    title('Metrics normalised per row (higher = better)');
end