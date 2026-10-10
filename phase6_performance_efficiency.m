function r = phase6_performance_efficiency(g, s, res, opts)
%PHASE6_PERFORMANCE_EFFICIENCY  System performance and efficiency summary of one railway generation.
%
%   r = phase6_performance_efficiency(g, s, res)
%   r = phase6_performance_efficiency(g, s, res, opts)
%
%   INPUT  g    : generation parameter struct (same struct given to Phase 1)
%          s    : output struct of phase1_system_definition
%          res  : struct with the results of the previous phases
%                   res.p2 = phase2_energy_analysis(...)
%                   res.p3 = phase3_propulsion_dynamics(...)
%                   res.p4 = phase4_braking_safety(...)
%                   res.p5 = phase5_control_automation(...)
%          opts : (optional) struct
%                   opts.plot    = true   draw the result figures
%                   opts.weights = struct with the weights of the overall index
%                                  (fields: performance, energy, capacity, safety,
%                                   automation, reliability, environment; sum = 1)
%   OUTPUT r    : struct with performance, energy, capacity, safety, reliability and
%                 environment indicators, category scores (0..1) and an overall index
%
%   This phase only combines existing results. The only new models are:
%
%   Capacity (one track, one direction, simplified):
%       headway   = (train length + emergency stopping distance + signalling margin) / speed
%       trains/h  = 3600 / headway
%       pass./h   = trains/h * passenger capacity
%
%   Reliability (simple constant failure-rate model):
%       MDBF [km]    = 1e6 / failures_per_Mkm
%       MTBF [h]     = MDBF / average speed
%       availability = MTBF / (MTBF + MTTR) * (1 - scheduled downtime)
%
%   All scores, reference values, weights and default reliability / signalling
%   values are MODELLING ASSUMPTIONS. They are model-based indices, not official
%   railway ratings.
%
%   Optional fields of g (defaults by automation level 0..4 in brackets):
%     signalling_margin_m     num   extra safety distance between trains [m]   ([600 500 400 250 100])
%     failures_per_Mkm        num   failures per million train-km              ([80 50 25 12 8])
%     mttr_h                  num   mean time to repair [h]                    ([8 6 4 3 2])
%     scheduled_downtime_pct  num   scheduled maintenance downtime [%]        ([15 12 10 8 6])

    if nargin < 4 || isempty(opts)
        opts = struct();
    end
    do_plot = isfield(opts, 'plot') && opts.plot;

    %% 1. Check inputs and read parameters
    check_results(res, s);
    p = read_parameters(g, s, opts);

    p2 = res.p2;   p3 = res.p3;   p4 = res.p4;   p5 = res.p5;

    r.name = s.name;

    %% 2. Performance
    % Journey time and average speed: prefer the dynamic simulation of Phase 3,
    % fall back to the analytical estimate of Phase 2 if Phase 3 could not compute it.
    if isfinite(p3.journey.travel_time_min)
        r.performance.travel_time_min   = p3.journey.travel_time_min;
        r.performance.average_speed_kmh = p3.journey.average_speed_kmh;
        r.performance.journey_source    = 'Phase 3 (ode45 simulation)';
    else
        r.performance.travel_time_min   = p2.journey.travel_time_min;
        r.performance.average_speed_kmh = p2.journey.average_speed_kmh;
        r.performance.journey_source    = 'Phase 2 (analytical estimate)';
    end

    r.performance.distance_km         = p2.journey.distance_km;
    r.performance.cruise_speed_kmh    = p3.journey.cruise_speed_kmh;
    r.performance.max_speed_kmh       = p3.max_speed_kmh;
    r.performance.start_accel_ms2     = p3.start_accel_ms2;
    r.performance.time_0_100_s        = time_to_speed(p3.times, 100);
    r.performance.power_to_weight     = s.power_to_weight_kW_per_t;
    r.performance.start_force_kN      = p3.start_force_kN;
    r.performance.max_grade_cruise_pct = p3.gradeability.cruise_pct;

    %% 3. Energy
    r.energy.input_kWh            = p2.energy.input_kWh;
    r.energy.kWh_per_km           = p2.specific.kWh_per_km;
    r.energy.kWh_per_pkm          = p2.specific.kWh_per_pkm;
    r.energy.MJ_per_pkm           = p2.specific.MJ_per_pkm;
    r.energy.Wh_per_tkm           = p2.specific.Wh_per_tkm;
    r.energy.drivetrain_eff       = p2.efficiency.drivetrain;
    r.energy.wheel_over_input     = p2.efficiency.wheel_over_input;
    r.energy.regen_journey_pct    = p2.efficiency.regen_recovery_pct;
    r.energy.regen_stop_pct       = p4.energy.regen_recovery_pct;
    r.energy.control_excess_pct   = p5.tracking.energy_excess_pct;

    %% 4. Capacity
    v_c = r.performance.cruise_speed_kmh / 3.6;                      % [m/s]
    d_emerg = p4.emergency.total_distance_m;                         % [m], NaN if not stopped

    r.capacity.passengers_per_train = s.passenger_capacity;
    r.capacity.train_length_m       = s.train_length_m;
    r.capacity.emergency_stop_m     = d_emerg;
    r.capacity.signalling_margin_m  = p.signalling_margin_m;
    r.capacity.min_headway_s        = (s.train_length_m + d_emerg + p.signalling_margin_m) / v_c;
    r.capacity.trains_per_hour      = 3600 / r.capacity.min_headway_s;
    r.capacity.passengers_per_hour  = r.capacity.trains_per_hour * s.passenger_capacity;
    r.capacity.train_pkm_per_hour   = s.passenger_capacity * r.performance.average_speed_kmh;
    r.capacity.passengers_per_m     = s.passenger_density_per_m;

    if ~isfinite(d_emerg)
        warning('phase6:noEmergencyStop', ...
                '[%s] Emergency stopping distance is not available. Capacity is not valid.', s.name);
    end

    %% 5. Safety (taken from Phase 4)
    r.safety.index                 = p4.safety.index;
    r.safety.emergency_distance_m  = p4.emergency.total_distance_m;
    r.safety.service_distance_m    = p4.service.total_distance_m;
    r.safety.emergency_decel_ms2   = p4.emergency.effective_decel_ms2;
    r.safety.total_delay_s         = p4.safety.total_delay_s;

    %% 6. Automation (taken from Phase 5)
    r.automation.level           = s.automation_level;
    r.automation.index           = p5.automation_index;
    r.automation.quality_index   = p5.quality.index;
    r.automation.control_score   = p5.control_score;
    r.automation.stop_error_m    = p5.tracking.stop_err_m;
    r.automation.rms_error_kmh   = p5.tracking.rms_err_kmh;

    %% 7. Reliability
    mdbf_km  = 1e6 / p.failures_per_Mkm;                             % [km]
    mtbf_h   = mdbf_km / r.performance.average_speed_kmh;            % [h of operation]
    a_inh    = mtbf_h / (mtbf_h + p.mttr_h);                         % inherent availability
    a_op     = a_inh * (1 - p.scheduled_downtime_pct / 100);         % operational availability

    r.reliability.failures_per_Mkm      = p.failures_per_Mkm;
    r.reliability.mdbf_km               = mdbf_km;
    r.reliability.mtbf_h                = mtbf_h;
    r.reliability.mttr_h                = p.mttr_h;
    r.reliability.scheduled_downtime_pct = p.scheduled_downtime_pct;
    r.reliability.inherent_availability = a_inh;
    r.reliability.availability          = a_op;
    r.reliability.failures_per_journey  = r.performance.distance_km * p.failures_per_Mkm / 1e6;

    %% 8. Environment
    r.environment.co2_total_kg       = p2.co2.total_kg;
    r.environment.co2_kg_per_km      = p2.co2.kg_per_km;
    r.environment.co2_kg_per_pkm     = p2.co2.kg_per_pkm;
    r.environment.co2_factor         = p2.co2.factor_kg_per_kWh;
    r.environment.local_emissions    = ismember(lower(char(s.energy_source)), {'coal', 'diesel'});

    %% 9. Category scores (0..1)
    r.scores = category_scores(r, s);

    %% 10. Overall index
    w = p.weights;
    names = fieldnames(w);
    r.overall_index = 0;
    for k = 1:numel(names)
        r.overall_index = r.overall_index + w.(names{k}) * r.scores.(names{k});
    end
    r.weights = w;

    %% 11. Report and optional plot
    print_summary(r);
    if do_plot
        plot_results(r, p2);
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function check_results(res, s)
%CHECK_RESULTS  Make sure all required result fields of the previous phases exist.

    if ~isstruct(res)
        error('phase6:badInput', 'Input "res" must be a struct with fields p2, p3, p4, p5.');
    end

    req = { 'p2', {'journey','energy','efficiency','specific','co2'};
            'p3', {'max_speed_kmh','start_accel_ms2','start_force_kN','times','gradeability','journey'};
            'p4', {'service','emergency','energy','safety'};
            'p5', {'automation_index','quality','tracking','control_score'} };

    for i = 1:size(req, 1)
        key = req{i, 1};
        if ~isfield(res, key) || ~isstruct(res.(key))
            error('phase6:missingResult', '[%s] Missing results of phase %s in "res".', s.name, key);
        end
        fields = req{i, 2};
        for j = 1:numel(fields)
            if ~isfield(res.(key), fields{j})
                error('phase6:missingResult', '[%s] res.%s has no field "%s".', s.name, key, fields{j});
            end
        end
    end
end


function p = read_parameters(g, s, opts)
%READ_PARAMETERS  Read reliability / signalling parameters and weights, apply defaults.

    k = s.automation_level + 1;

    margin_default   = [600 500 400 250 100];     % [m]  assumption: better signalling -> shorter margin
    failure_default  = [80  50  25  12  8  ];     % [failures / million km]  assumption
    mttr_default     = [8   6   4   3   2  ];     % [h]  assumption
    downtime_default = [15  12  10  8   6  ];     % [%]  assumption

    p.signalling_margin_m     = get_param(g, 'signalling_margin_m',    margin_default(k));
    p.failures_per_Mkm        = get_param(g, 'failures_per_Mkm',       failure_default(k));
    p.mttr_h                  = get_param(g, 'mttr_h',                 mttr_default(k));
    p.scheduled_downtime_pct  = get_param(g, 'scheduled_downtime_pct', downtime_default(k));

    if p.signalling_margin_m < 0 || p.failures_per_Mkm <= 0 || p.mttr_h < 0
        error('phase6:badValue', 'signalling_margin_m >= 0, failures_per_Mkm > 0 and mttr_h >= 0 are required.');
    end
    if p.scheduled_downtime_pct < 0 || p.scheduled_downtime_pct >= 100
        error('phase6:badValue', 'scheduled_downtime_pct must be in [0, 100).');
    end

    % Weights of the overall index (assumption)
    w = struct('performance', 0.20, 'energy', 0.20, 'capacity', 0.10, 'safety', 0.15, ...
               'automation', 0.10, 'reliability', 0.10, 'environment', 0.15);

    if isfield(opts, 'weights') && ~isempty(opts.weights)
        fn = fieldnames(opts.weights);
        for i = 1:numel(fn)
            if ~isfield(w, fn{i})
                error('phase6:badWeight', 'Unknown weight "%s".', fn{i});
            end
            w.(fn{i}) = opts.weights.(fn{i});
        end
    end

    vals = cell2mat(struct2cell(w));
    if any(vals < 0) || abs(sum(vals) - 1) > 1e-6
        error('phase6:badWeight', 'Weights must be >= 0 and their sum must be 1 (current sum: %.3f).', sum(vals));
    end
    p.weights = w;
end


function val = get_param(g, name, default)
%GET_PARAM  Return g.(name) if it exists and is not empty, otherwise the default value.

    if isfield(g, name) && ~isempty(g.(name))
        val = g.(name);
    else
        val = default;
    end
end


function t = time_to_speed(times, speed_kmh)
%TIME_TO_SPEED  Time [s] to reach a reference speed from the Phase 3 table (NaN if not reached).

    idx = find(times.speed_kmh == speed_kmh, 1);
    if isempty(idx)
        t = NaN;
    else
        t = times.time_s(idx);
    end
end


function y = clamp01(x)
%CLAMP01  Limit a value to [0, 1]. NaN becomes 0.

    y = min(1, max(0, x));
end


function sc = category_scores(r, s)
%CATEGORY_SCORES  Convert indicators to scores in [0, 1] using fixed reference values.
%   Fixed references (not relative to the other generations) keep the scores
%   comparable between runs. All reference values are modelling assumptions.

    % Performance: maximum speed (ref 350 km/h), average speed (ref 200 km/h),
    % starting acceleration (ref 1.0 m/s^2)
    sc.performance = 0.4 * clamp01(r.performance.max_speed_kmh / 350) ...
                   + 0.3 * clamp01(r.performance.average_speed_kmh / 200) ...
                   + 0.3 * clamp01(r.performance.start_accel_ms2 / 1.0);

    % Energy: specific energy on a log scale (best 0.03, worst 3 kWh/pkm) and chain efficiency (ref 0.9)
    e_best = 0.03;   e_worst = 3;
    e      = max(r.energy.kWh_per_pkm, eps);
    s_e    = clamp01((log10(e_worst) - log10(e)) / (log10(e_worst) - log10(e_best)));
    sc.energy = 0.6 * s_e + 0.4 * clamp01(r.energy.wheel_over_input / 0.9);

    % Capacity: passengers per hour per direction (ref 40000)
    sc.capacity = clamp01(r.capacity.passengers_per_hour / 40000);

    % Safety and automation come directly from Phase 4 and Phase 5
    sc.safety     = clamp01(r.safety.index);
    sc.automation = clamp01(r.automation.control_score);

    % Reliability: availability (0.80 -> 0, 0.98 -> 1) and MDBF on a log scale (1e4 -> 0, 1e6 -> 1 km)
    s_a = clamp01((r.reliability.availability - 0.80) / (0.98 - 0.80));
    s_m = clamp01(log10(r.reliability.mdbf_km / 1e4) / 2);
    sc.reliability = 0.5 * s_a + 0.5 * s_m;

    % Environment: CO2 per passenger-km (0.30 kg/pkm -> 0) and a bonus for no local emissions
    s_c = clamp01(1 - r.environment.co2_kg_per_pkm / 0.30);
    sc.environment = 0.8 * s_c + 0.2 * double(~r.environment.local_emissions);

    %#ok<*INUSD>
    s;   %#ok<VUNUS>
end


function print_summary(r)
%PRINT_SUMMARY  Print the performance and efficiency results to the command window.

    fprintf('\n==============================================\n');
    fprintf(' PHASE 6 - PERFORMANCE & EFFICIENCY\n');
    fprintf(' %s\n', r.name);
    fprintf('==============================================\n');
    fprintf(' PERFORMANCE (%s)\n', r.performance.journey_source);
    fprintf('   Max speed          : %.0f km/h\n', r.performance.max_speed_kmh);
    fprintf('   Start acceleration : %.3f m/s^2\n', r.performance.start_accel_ms2);
    fprintf('   0 -> 100 km/h      : %.1f s\n', r.performance.time_0_100_s);
    fprintf('   Travel time        : %.1f min over %.0f km (avg %.1f km/h)\n', ...
            r.performance.travel_time_min, r.performance.distance_km, r.performance.average_speed_kmh);
    fprintf('   Power-to-weight    : %.2f kW/t\n', r.performance.power_to_weight);
    fprintf('----------------------------------------------\n');
    fprintf(' ENERGY\n');
    fprintf('   Input energy       : %.1f kWh\n', r.energy.input_kWh);
    fprintf('   Per km             : %.2f kWh/km\n', r.energy.kWh_per_km);
    fprintf('   Per passenger-km   : %.4f kWh/pkm (%.3f MJ/pkm)\n', r.energy.kWh_per_pkm, r.energy.MJ_per_pkm);
    fprintf('   Per tonne-km       : %.1f Wh/tkm\n', r.energy.Wh_per_tkm);
    fprintf('   Drivetrain eff.    : %.1f %%\n', 100 * r.energy.drivetrain_eff);
    fprintf('   Wheel / input      : %.1f %%\n', 100 * r.energy.wheel_over_input);
    fprintf('   Regen recovery     : %.1f %% (journey), %.1f %% (one service stop)\n', ...
            r.energy.regen_journey_pct, r.energy.regen_stop_pct);
    fprintf('   Control excess     : %.1f %% (Phase 5)\n', r.energy.control_excess_pct);
    fprintf('----------------------------------------------\n');
    fprintf(' CAPACITY\n');
    fprintf('   Passengers / train : %d\n', r.capacity.passengers_per_train);
    fprintf('   Min headway        : %.0f s (emergency stop %.0f m + margin %.0f m)\n', ...
            r.capacity.min_headway_s, r.capacity.emergency_stop_m, r.capacity.signalling_margin_m);
    fprintf('   Trains per hour    : %.1f\n', r.capacity.trains_per_hour);
    fprintf('   Passengers / hour  : %.0f (one direction)\n', r.capacity.passengers_per_hour);
    fprintf('   Train pass.-km / h : %.0f\n', r.capacity.train_pkm_per_hour);
    fprintf('----------------------------------------------\n');
    fprintf(' SAFETY & AUTOMATION\n');
    fprintf('   Emergency stop     : %.0f m (decel %.2f m/s^2)\n', ...
            r.safety.emergency_distance_m, r.safety.emergency_decel_ms2);
    fprintf('   Safety index       : %.2f\n', r.safety.index);
    fprintf('   Automation index   : %.2f (control score %.2f)\n', r.automation.index, r.automation.control_score);
    fprintf('----------------------------------------------\n');
    fprintf(' RELIABILITY\n');
    fprintf('   Failures           : %.0f per million km (MDBF %.0f km)\n', ...
            r.reliability.failures_per_Mkm, r.reliability.mdbf_km);
    fprintf('   MTBF / MTTR        : %.1f h / %.1f h\n', r.reliability.mtbf_h, r.reliability.mttr_h);
    fprintf('   Availability       : %.1f %% (scheduled downtime %.0f %%)\n', ...
            100 * r.reliability.availability, r.reliability.scheduled_downtime_pct);
    fprintf('----------------------------------------------\n');
    fprintf(' ENVIRONMENT\n');
    fprintf('   CO2 per km         : %.2f kg/km\n', r.environment.co2_kg_per_km);
    fprintf('   CO2 per pass.-km   : %.4f kg/pkm\n', r.environment.co2_kg_per_pkm);
    if r.environment.local_emissions
        fprintf('   Local emissions    : yes\n');
    else
        fprintf('   Local emissions    : no\n');
    end
    fprintf('----------------------------------------------\n');
    fprintf(' CATEGORY SCORES (0..1, model-based)\n');
    names = fieldnames(r.scores);
    for k = 1:numel(names)
        fprintf('   %-12s : %.2f  (weight %.2f)\n', names{k}, r.scores.(names{k}), r.weights.(names{k}));
    end
    fprintf(' OVERALL INDEX        : %.3f\n', r.overall_index);
    fprintf('==============================================\n');
end


function plot_results(r, p2)
%PLOT_RESULTS  Four plots: radar of scores, score bars, energy distribution, specific energy and CO2.

    names  = fieldnames(r.scores);
    labels = {'Performance','Energy','Capacity','Safety','Automation','Reliability','Environment'};
    vals   = cellfun(@(n) r.scores.(n), names)';
    n      = numel(vals);

    figure('Name', ['Phase 6 - ' r.name], 'Color', 'w');

    % ---- Radar chart drawn in Cartesian coordinates
    subplot(2, 2, 1);
    ang = linspace(pi/2, pi/2 - 2*pi, n + 1);           % start at the top, go clockwise
    hold on;
    for ring = [0.25 0.5 0.75 1]
        plot(ring * cos(ang), ring * sin(ang), ':', 'Color', [0.7 0.7 0.7]);
    end
    for k = 1:n
        plot([0 cos(ang(k))], [0 sin(ang(k))], '-', 'Color', [0.8 0.8 0.8]);
        text(1.18 * cos(ang(k)), 1.18 * sin(ang(k)), labels{k}, ...
             'HorizontalAlignment', 'center', 'FontSize', 8);
    end
    xr = [vals vals(1)] .* cos(ang);
    yr = [vals vals(1)] .* sin(ang);
    fill(xr, yr, [0.2 0.5 0.9], 'FaceAlpha', 0.25, 'EdgeColor', [0.1 0.3 0.7], 'LineWidth', 1.5);
    axis equal off;
    xlim([-1.5 1.5]); ylim([-1.4 1.4]);
    title('Category scores');

    % ---- Score bars
    subplot(2, 2, 2);
    bar(categorical(labels, labels), [vals, r.overall_index]);
    hold on;
    yline(r.overall_index, '--k', sprintf('Overall %.2f', r.overall_index));
    ylim([0 1]); ylabel('Score [-]');
    title('Scores and overall index'); grid on;

    % ---- Energy distribution (kWh) from Phase 2
    subplot(2, 2, 3);
    lab = {'Wheel traction','Transmission loss','Prime mover loss','Auxiliary','Regenerated (-)'};
    val = [p2.energy.wheel_kWh, p2.energy.transmission_loss_kWh, ...
           p2.energy.prime_mover_loss_kWh, p2.energy.auxiliary_kWh, -p2.energy.regenerated_kWh];
    bar(categorical(lab, lab), val);
    ylabel('Energy [kWh]');
    title(sprintf('Energy distribution (input %.1f kWh)', r.energy.input_kWh)); grid on;

    % ---- Specific energy and CO2 per passenger-km
    subplot(2, 2, 4);
    yyaxis left;
    bar(1, r.energy.kWh_per_pkm);
    ylabel('Energy [kWh/pkm]');
    yyaxis right;
    bar(2, r.environment.co2_kg_per_pkm);
    ylabel('CO_2 [kg/pkm]');
    set(gca, 'XTick', [1 2], 'XTickLabel', {'Energy','CO2'}, 'XLim', [0.3 2.7]);
    title('Specific energy and CO_2'); grid on;

    sgtitle(r.name);
end