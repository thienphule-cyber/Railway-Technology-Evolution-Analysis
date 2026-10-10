function r = phase5_control_automation(g, s, opts)
%PHASE5_CONTROL_AUTOMATION  Control and automation analysis of one railway generation.
%
%   r = phase5_control_automation(g, s)
%   r = phase5_control_automation(g, s, opts)
%
%   INPUT  g    : generation parameter struct (same struct given to Phase 1)
%          s    : output struct of phase1_system_definition
%          opts : (optional) struct
%                   opts.plot            = true  draw the result figures
%                   opts.compare_levels  = true  also run the same train with
%                                                controllers of level 0..4
%   OUTPUT r    : struct with Automation Index, tracking metrics, control quality
%                 index and (optionally) the level comparison
%
%   PART A - Automation Index
%       AI = N_automated_functions / N_total_functions   (12 functions)
%       The default function set is taken from s.automation_level. It can be
%       overridden with g.control_functions (logical vector with 12 elements).
%
%   PART B - Speed tracking simulation (point mass, straight track)
%       Reference : accelerate -> cruise -> brake to standstill (trapezoid speed profile)
%       Plant     : m * k_rot * dv/dt = F_actual - F_resistance
%       Controller (depends on automation level, see controller_settings):
%           a_cmd = Kp * e + Ki * integral(e) + ff_acc * a_ref
%           F_cmd = m * k_rot * a_cmd + ff_res * F_resistance
%           then saturation, notch quantisation (manual levels), jerk limit,
%           command delay and first-order actuator lag.
%       The controller parameters per level are MODELLING ASSUMPTIONS, not
%       measured data. The indices below are model-based, not official ratings.
%
%   Required field of g (in addition to the Phase 1 fields):
%     cruise_speed_kmh           num   cruise speed [km/h]
%
%   Optional fields of g (defaults in brackets):
%     control_functions          vec   12 logical flags (by automation level)
%     avg_accel_ms2              num   requested reference acceleration [m/s^2] (0.5)
%     avg_decel_ms2              num   reference service deceleration [m/s^2]   (0.7)
%     control_cruise_time_s      num   cruise duration in the test run [s]      (120)
%     brake_capacity_factor      num   brake capacity / reference decel         (1.3)
%     max_tractive_effort_kN     num   starting tractive effort [kN]            (adhesion limit)
%     max_speed_kmh              num   design speed limit [km/h]                (1.2 * cruise)
%     grade_pct                  num   constant track gradient [%]              (0)
%     rolling_coeff              num   rolling resistance coefficient Cr [-]    (0.002)
%     drag_coeff                 num   aerodynamic drag coefficient Cd [-]      (0.9)
%     frontal_area_m2            num   frontal area A [m^2]                     (10)
%     rotating_mass_factor       num   equivalent mass factor, rotating parts   (1.06)
%     air_density                num   air density [kg/m^3]                     (1.2)
%     comfort_jerk_limit_ms3     num   passenger comfort limit, jerk [m/s^3]    (1.5)
%     noise_seed                 num   seed of the speed-sensor noise           (1)

    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    do_plot    = isfield(opts, 'plot') && opts.plot;
    do_compare = isfield(opts, 'compare_levels') && opts.compare_levels;

    %% 1. Read parameters, build plant and reference
    p     = read_parameters(g, s);
    plant = build_plant(s, p);
    ref   = build_reference(plant, p, s);

    %% 2. Part A: Automation Index
    [fn_names, fn_flags] = function_flags(g, s);
    n_total = numel(fn_flags);
    n_auto  = nnz(fn_flags);

    r.name             = s.name;
    r.automation_level = s.automation_level;
    r.automation_label = s.automation_label;
    r.functions.names  = fn_names;
    r.functions.flags  = fn_flags;
    r.functions.n_automated = n_auto;
    r.functions.n_total     = n_total;
    r.automation_index = n_auto / n_total;

    %% 3. Part B: tracking simulation with the controller of this generation
    ctl = controller_settings(s.automation_level);
    sim = simulate_run(plant, ref, ctl, p.noise_seed);
    met = tracking_metrics(sim, ref, plant);
    q   = control_quality(met, p.comfort_jerk_limit_ms3);

    r.controller  = ctl;
    r.reference   = struct('cruise_speed_kmh', ref.v_c * 3.6, 'accel_ms2', ref.a_acc, ...
                           'decel_ms2', ref.b_dec, 'planned_distance_m', ref.D_ref, ...
                           'run_time_s', ref.t3);
    r.tracking    = met;
    r.quality     = q;

    % Model-based overall control score: half automation, half measured control quality
    r.control_score = 0.5 * r.automation_index + 0.5 * q.index;

    r.profile.t_s        = sim.t;
    r.profile.x_m        = sim.x;
    r.profile.v_kmh      = sim.v * 3.6;
    r.profile.v_ref_kmh  = ref.v * 3.6;
    r.profile.acc_ms2    = sim.a;
    r.profile.F_cmd_kN   = sim.F_cmd / 1000;
    r.profile.F_act_kN   = sim.F_eff / 1000;

    %% 4. Optional comparison of the five controller levels on the same train
    if do_compare
        r.level_comparison = compare_levels(plant, ref, p, s);
    end

    %% 5. Warnings
    if ~met.stopped
        warning('phase5:notStopped', ...
                '[%s] The train did not come to rest in the simulated time. Stop error is not valid.', s.name);
    end
    if met.rms_err_kmh > 5
        warning('phase5:poorTracking', ...
                '[%s] RMS speed error is %.1f km/h. Controller of level %d tracks the reference poorly.', ...
                s.name, met.rms_err_kmh, s.automation_level);
    end

    %% 6. Report and optional plot
    print_summary(r, p);
    if do_compare
        print_comparison(r.level_comparison);
    end
    if do_plot
        plot_results(r);
        if do_compare
            plot_comparison(r.level_comparison, r.name);
        end
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function p = read_parameters(g, s)
%READ_PARAMETERS  Read control-test parameters from g and apply defaults.

    if ~isfield(g, 'cruise_speed_kmh') || ~isnumeric(g.cruise_speed_kmh) || g.cruise_speed_kmh <= 0
        error('phase5:missingField', 'Missing or invalid field: "cruise_speed_kmh".');
    end
    p.cruise_speed_kmh = g.cruise_speed_kmh;

    p.accel_ms2              = get_param(g, 'avg_accel_ms2',          0.5);
    p.decel_ms2              = get_param(g, 'avg_decel_ms2',          0.7);
    p.cruise_hold_s          = get_param(g, 'control_cruise_time_s',  120);
    p.brake_capacity_factor  = get_param(g, 'brake_capacity_factor',  1.3);
    p.max_tractive_effort_kN = get_param(g, 'max_tractive_effort_kN', s.max_adhesion_force_N / 1000);
    p.max_speed_kmh          = get_param(g, 'max_speed_kmh',          1.2 * p.cruise_speed_kmh);
    p.grade_pct              = get_param(g, 'grade_pct',              0);
    p.rolling_coeff          = get_param(g, 'rolling_coeff',          0.002);
    p.drag_coeff             = get_param(g, 'drag_coeff',             0.9);
    p.frontal_area_m2        = get_param(g, 'frontal_area_m2',        10);
    p.rotating_mass_factor   = get_param(g, 'rotating_mass_factor',   1.06);
    p.air_density            = get_param(g, 'air_density',            1.2);
    p.comfort_jerk_limit_ms3 = get_param(g, 'comfort_jerk_limit_ms3', 1.5);
    p.noise_seed             = get_param(g, 'noise_seed',             1);

    p.settle_s = 60;                                 % [s] extra time after the reference ends
    p.dt       = 0.05;                               % [s] integration step

    % Range checks
    if p.accel_ms2 <= 0 || p.decel_ms2 <= 0 || p.cruise_hold_s < 0
        error('phase5:badValue', 'Accelerations must be > 0 and control_cruise_time_s >= 0.');
    end
    if p.brake_capacity_factor < 1
        error('phase5:badValue', 'brake_capacity_factor must be >= 1.');
    end
    if p.max_tractive_effort_kN <= 0 || p.max_speed_kmh <= 0
        error('phase5:badValue', 'max_tractive_effort_kN and max_speed_kmh must be > 0.');
    end
    if p.rotating_mass_factor < 1
        error('phase5:badValue', 'rotating_mass_factor must be >= 1.');
    end
    if abs(p.grade_pct) >= 50
        error('phase5:badValue', 'grade_pct must be within (-50, 50) percent.');
    end
    if p.comfort_jerk_limit_ms3 <= 0
        error('phase5:badValue', 'comfort_jerk_limit_ms3 must be > 0.');
    end
end


function val = get_param(g, name, default)
%GET_PARAM  Return g.(name) if it exists and is not empty, otherwise the default value.

    if isfield(g, name) && ~isempty(g.(name))
        val = g.(name);
    else
        val = default;
    end
end


function plant = build_plant(s, p)
%BUILD_PLANT  Collect all constants of the train model in one struct.

    plant.m       = s.train_mass_kg;                                   % [kg]
    plant.gravity = 9.81;                                              % [m/s^2]
    plant.k_rot   = p.rotating_mass_factor;                            % [-]
    plant.Cr      = p.rolling_coeff;                                   % [-]
    plant.k_aero  = 0.5 * p.air_density * p.drag_coeff * p.frontal_area_m2;   % F_aero = k_aero * v^2
    plant.theta   = atan(p.grade_pct / 100);                           % [rad]
    plant.F_max   = min(p.max_tractive_effort_kN * 1000, s.max_adhesion_force_N);   % [N]
    plant.P_W     = s.wheel_power_kW * 1000;                           % [W] power at the wheel
    plant.v_limit = p.max_speed_kmh / 3.6;                             % [m/s]

    % Brake capacity: a margin above the reference deceleration, limited by adhesion
    F_adh = s.adhesion_coeff * plant.m * plant.gravity;                % [N]
    plant.F_brake = min(p.brake_capacity_factor * p.decel_ms2 * plant.m * plant.k_rot, F_adh);
end


function F = traction_available(v, plant)
%TRACTION_AVAILABLE  Maximum tractive effort [N] at speed v (vectorised).

    F = min(plant.F_max, plant.P_W ./ max(v, 0.01));
    F = F .* (v <= plant.v_limit);
end


function F = resistance_force(v, plant)
%RESISTANCE_FORCE  Running resistance [N]: rolling + aerodynamic + gradient.

    F = plant.Cr * plant.m * plant.gravity * cos(plant.theta) ...
      + plant.k_aero * max(v, 0).^2 ...
      + plant.m * plant.gravity * sin(plant.theta);
end


function ref = build_reference(plant, p, s)
%BUILD_REFERENCE  Trapezoid speed reference: accelerate -> cruise -> brake to standstill.

    v_c = p.cruise_speed_kmh / 3.6;                                    % [m/s]
    mk  = plant.m * plant.k_rot;

    % The reference acceleration must be achievable by the traction system
    v_grid = linspace(0.5, v_c, 500);
    net    = traction_available(v_grid, plant) - resistance_force(v_grid, plant);
    if any(net <= 0)
        error('phase5:cruiseNotAttainable', ...
              ['[%s] The cruise speed %.0f km/h cannot be reached with the available traction. ' ...
               'Reduce cruise_speed_kmh or check power, grade_pct and max_speed_kmh.'], ...
              s.name, p.cruise_speed_kmh);
    end
    a_cap = 0.6 * min(net) / mk;                                       % keep a 40 % margin
    a_acc = min(p.accel_ms2, a_cap);
    if a_acc < 0.5 * p.accel_ms2
        warning('phase5:accelLimited', ...
                '[%s] Reference acceleration limited to %.3f m/s^2 (requested %.3f) by the traction capability.', ...
                s.name, a_acc, p.accel_ms2);
    end
    b_dec = p.decel_ms2;

    ref.v_c   = v_c;
    ref.a_acc = a_acc;
    ref.b_dec = b_dec;
    ref.dt    = p.dt;

    ref.t1 = v_c / a_acc;                                              % end of acceleration [s]
    ref.t2 = ref.t1 + p.cruise_hold_s;                                 % end of cruise [s]
    ref.t3 = ref.t2 + v_c / b_dec;                                     % end of braking [s]
    ref.D_ref = v_c^2 / (2 * a_acc) + v_c * p.cruise_hold_s + v_c^2 / (2 * b_dec);   % [m]

    T = ref.t3 + p.settle_s;
    N = floor(T / p.dt) + 1;
    t = (0:N-1)' * p.dt;

    v_ref = zeros(N, 1);
    a_ref = zeros(N, 1);

    i1 = t <= ref.t1;
    i2 = t > ref.t1 & t <= ref.t2;
    i3 = t > ref.t2 & t <= ref.t3;

    v_ref(i1) = a_acc * t(i1);          a_ref(i1) = a_acc;
    v_ref(i2) = v_c;                    a_ref(i2) = 0;
    v_ref(i3) = v_c - b_dec * (t(i3) - ref.t2);   a_ref(i3) = -b_dec;

    ref.t = t;
    ref.v = v_ref;
    ref.a = a_ref;
end


function [names, flags] = function_flags(g, s)
%FUNCTION_FLAGS  Control function names and automated/not-automated flags.
%   Columns of the default matrix correspond to automation level 0..4.

    names = { ...
        'Automatic traction regulation', ...
        'Wheel slip / slide protection', ...
        'Automatic speed regulation', ...
        'Coordinated (blended) braking control', ...
        'Overspeed protection (ATP)', ...
        'Automatic train operation (ATO)', ...
        'Driverless operation', ...
        'Digital train-ground communication', ...
        'On-board sensor integration', ...
        'Fault detection / diagnostics', ...
        'Condition monitoring / predictive maintenance', ...
        'Remote diagnostics / data analytics'};

    %            L0 L1 L2 L3 L4
    M = logical([ 0  0  1  1  1;     % traction regulation
                  0  1  1  1  1;     % wheel slip protection
                  0  0  0  1  1;     % speed regulation
                  0  0  1  1  1;     % blended braking
                  0  0  0  1  1;     % ATP
                  0  0  0  0  1;     % ATO
                  0  0  0  0  1;     % driverless
                  0  0  0  1  1;     % communication
                  0  0  1  1  1;     % sensors
                  0  0  1  1  1;     % fault detection
                  0  0  0  0  1;     % condition monitoring
                  0  0  0  0  1]);   % remote diagnostics

    if isfield(g, 'control_functions') && ~isempty(g.control_functions)
        v = g.control_functions;
        if numel(v) ~= numel(names)
            error('phase5:badValue', 'control_functions must have %d elements.', numel(names));
        end
        flags = logical(v(:));
    else
        flags = M(:, s.automation_level + 1);
    end
end


function ctl = controller_settings(level)
%CONTROLLER_SETTINGS  Controller and actuator parameters for automation level 0..4.
%   All values are modelling assumptions.
%
%   Level 0: manual driver, few discrete notches, long reaction time, noisy speedometer
%   Level 1: electromechanical control, more notches
%   Level 2: electronic control, continuous PI regulation
%   Level 3: computer-assisted, PI + full feedforward
%   Level 4: automatic operation, PI + feedforward + jerk limit

k = level + 1;

%              L0    L1    L2    L3    L4
update_s  = [5.0   2.0   0.5   0.2   0.1 ];   % decision period [s]
delay_s   = [3.0   2.0   0.5   0.2   0.05];   % command delay [s]
n_notch   = [4     8     0     0     0   ];   % notches per side (0 = continuous)
Kp        = [0.12  0.25  0.50  0.60  0.80];   % proportional gain [1/s]
Ki        = [0.01  0.02  0.05  0.08  0.10];   % integral gain [1/s^2]
ff_acc    = [0.7   0.8   0.5   1.0   1.0 ];   % acceleration feedforward gain
ff_res    = [0     0     0     1     1   ];   % resistance compensation gain
tau_act   = [2.0   1.5   0.5   0.3   0.2 ];   % actuator time constant [s]
noise_kmh = [1.0   0.5   0.2   0.1   0.05];   % speed measurement noise (std) [km/h]
jerk_lim  = [Inf   Inf   Inf   Inf   0.8 ];   % command jerk limit [m/s^3]

ctl.level      = level;
ctl.update_s   = update_s(k);
ctl.delay_s    = delay_s(k);
ctl.n_notch    = n_notch(k);
ctl.Kp         = Kp(k);
ctl.Ki         = Ki(k);
ctl.ff_acc     = ff_acc(k);
ctl.ff_res     = ff_res(k);
ctl.tau_act    = tau_act(k);
ctl.noise_kmh  = noise_kmh(k);
ctl.jerk_limit = jerk_lim(k);
end


function out = simulate_run(plant, ref, ctl, seed)
%SIMULATE_RUN  Time-domain simulation of speed tracking (explicit Euler).

    N  = numel(ref.t);
    dt = ref.dt;
    mk = plant.m * plant.k_rot;

    nd = round(ctl.delay_s / dt);                      % command delay in steps
    ns = max(1, round(ctl.update_s / dt));             % steps between controller updates

    stream = RandStream('mt19937ar', 'Seed', seed);
    noise  = randn(stream, N, 1) * ctl.noise_kmh / 3.6;   % [m/s]

    x = zeros(N, 1);   v = zeros(N, 1);   a = zeros(N, 1);
    F_cmd = zeros(N, 1);   F_act = zeros(N, 1);   F_eff = zeros(N, 1);

    I      = 0;        % integral of speed error
    F_hold = 0;        % last commanded force

    for k = 1:N
        % ---- Controller (runs every ns steps, zero-order hold in between)
        if mod(k - 1, ns) == 0
            v_meas = max(v(k) + noise(k), 0);
            e      = ref.v(k) - v_meas;

            in_stop_phase = ref.t(k) > ref.t3;
            if in_stop_phase
                I = 0;                                  % no windup after the run
            end

            a_cmd    = ctl.Kp * e + ctl.Ki * I + ctl.ff_acc * ref.a(k);
            F_target = mk * a_cmd;
            if ctl.ff_res > 0 && ref.v(k) > 0.01
                F_target = F_target + ctl.ff_res * resistance_force(v_meas, plant);
            end
            if in_stop_phase && v_meas < 0.2
                F_target = -plant.F_brake;              % holding brake at standstill
            end

            F_hi  = traction_available(v_meas, plant);
            F_sat = min(max(F_target, -plant.F_brake), F_hi);

            % Anti-windup: integrate only when the command is not saturated
            if ~in_stop_phase && F_sat == F_target
                I = I + e * ctl.update_s;
            end

            % Notch quantisation (manual levels)
            if ctl.n_notch > 0
                if F_sat >= 0
                    F_q = round(F_sat / plant.F_max * ctl.n_notch) / ctl.n_notch * plant.F_max;
                    F_q = min(F_q, F_hi);
                else
                    F_q = round(F_sat / plant.F_brake * ctl.n_notch) / ctl.n_notch * plant.F_brake;
                end
            else
                F_q = F_sat;
            end

            % Jerk limit on the command
            if isfinite(ctl.jerk_limit)
                dF_max = ctl.jerk_limit * mk * ctl.update_s;
                F_q    = F_hold + min(max(F_q - F_hold, -dF_max), dF_max);
            end

            F_hold = F_q;
        end
        F_cmd(k) = F_hold;

        % ---- Command delay and first-order actuator
        F_app = F_cmd(max(1, k - nd));
        if k == 1
            F_act(k) = 0;
        else
            F_act(k) = F_act(k-1) + dt / ctl.tau_act * (F_app - F_act(k-1));
        end

        % ---- Train dynamics
        F_eff(k) = min(F_act(k), traction_available(v(k), plant));
        a_k = (F_eff(k) - resistance_force(v(k), plant)) / mk;
        if v(k) <= 0 && a_k < 0
            a_k = 0;                                    % train cannot move backwards
        end
        a(k) = a_k;

        if k < N
            v(k+1) = max(0, v(k) + dt * a_k);
            x(k+1) = x(k) + dt * (v(k) + v(k+1)) / 2;
        end
    end

    out.t = ref.t;   out.x = x;   out.v = v;   out.a = a;
    out.F_cmd = F_cmd;   out.F_eff = F_eff;
end


function m = tracking_metrics(sim, ref, plant)
%TRACKING_METRICS  Speed tracking, stopping accuracy, comfort and energy metrics.

    t  = sim.t;   dt = ref.dt;
    mk = plant.m * plant.k_rot;
    J2kWh = 1 / 3.6e6;

    in_run    = t <= ref.t3;
    in_cruise = t > ref.t1 & t <= ref.t2;

    e = sim.v - ref.v;
    m.rms_err_kmh    = sqrt(mean(e(in_run).^2)) * 3.6;
    m.max_err_kmh    = max(abs(e(in_run))) * 3.6;
    if any(in_cruise)
        m.overshoot_kmh = max(0, max(sim.v(in_cruise)) - ref.v_c) * 3.6;
    else
        m.overshoot_kmh = 0;
    end

    % Stopping accuracy
    m.stopped     = sim.v(end) < 0.1;
    m.final_x_m   = sim.x(end);
    m.stop_err_m  = sim.x(end) - ref.D_ref;
    if ~m.stopped
        m.stop_err_m = NaN;
    end

    % Comfort: jerk from acceleration sampled every 0.5 s
    step = max(1, round(0.5 / dt));
    a_s  = sim.a(1:step:end);
    j    = diff(a_s) / (step * dt);
    m.jerk_max_ms3 = max(abs(j));
    m.jerk_rms_ms3 = sqrt(mean(j.^2));

    % Traction energy at the wheel versus the ideal (perfect tracking) profile
    F_ideal   = mk * ref.a + resistance_force(ref.v, plant);
    E_ideal   = trapz(t, max(F_ideal, 0) .* ref.v) * J2kWh;
    E_actual  = trapz(t, max(sim.F_eff, 0) .* sim.v) * J2kWh;
    m.energy_ideal_kWh  = E_ideal;
    m.energy_actual_kWh = E_actual;
    m.energy_excess_pct = 100 * (E_actual - E_ideal) / max(E_ideal, eps);
end


function q = control_quality(m, jerk_limit)
%CONTROL_QUALITY  Model-based control quality index in [0, 1].
%   Reference values (5 km/h, 50 m, comfort jerk limit) are modelling assumptions.

    q.speed   = max(0, 1 - m.rms_err_kmh / 5);
    if isnan(m.stop_err_m)
        q.stop = 0;
    else
        q.stop = max(0, 1 - abs(m.stop_err_m) / 50);
    end
    q.comfort = max(0, 1 - m.jerk_rms_ms3 / jerk_limit);
    q.index   = 0.4 * q.speed + 0.3 * q.stop + 0.3 * q.comfort;
end


function cmp = compare_levels(plant, ref, p, s)
%COMPARE_LEVELS  Run the same train and reference with the controllers of level 0..4.

    levels = 0:4;
    n = numel(levels);

    cmp.levels      = levels;
    cmp.rms_err_kmh = zeros(1, n);
    cmp.max_err_kmh = zeros(1, n);
    cmp.stop_err_m  = zeros(1, n);
    cmp.jerk_rms    = zeros(1, n);
    cmp.energy_excess_pct = zeros(1, n);
    cmp.quality     = zeros(1, n);
    cmp.automation_index = zeros(1, n);
    cmp.t_s         = ref.t;
    cmp.err_kmh     = zeros(numel(ref.t), n);

    for i = 1:n
        ctl = controller_settings(levels(i));
        sim = simulate_run(plant, ref, ctl, p.noise_seed);
        met = tracking_metrics(sim, ref, plant);
        q   = control_quality(met, p.comfort_jerk_limit_ms3);

        cmp.rms_err_kmh(i) = met.rms_err_kmh;
        cmp.max_err_kmh(i) = met.max_err_kmh;
        cmp.stop_err_m(i)  = met.stop_err_m;
        cmp.jerk_rms(i)    = met.jerk_rms_ms3;
        cmp.energy_excess_pct(i) = met.energy_excess_pct;
        cmp.quality(i)     = q.index;
        cmp.err_kmh(:, i)  = (sim.v - ref.v) * 3.6;

        % Default automation index of that level
        sl = struct('automation_level', levels(i));
        [~, fl] = function_flags(struct(), sl);
        cmp.automation_index(i) = nnz(fl) / numel(fl);
    end
    cmp.plant_name = s.name;
end


function print_summary(r, p)
%PRINT_SUMMARY  Print the control and automation results to the command window.

    fprintf('\n==============================================\n');
    fprintf(' PHASE 5 - CONTROL & AUTOMATION\n');
    fprintf(' %s\n', r.name);
    fprintf('==============================================\n');
    fprintf(' Automation level     : %d (%s)\n', r.automation_level, r.automation_label);
    fprintf(' Automated functions  : %d / %d\n', r.functions.n_automated, r.functions.n_total);
    for k = 1:r.functions.n_total
        if r.functions.flags(k), mark = 'x'; else, mark = ' '; end
        fprintf('   [%s] %s\n', mark, r.functions.names{k});
    end
    fprintf(' Automation Index     : %.2f\n', r.automation_index);
    fprintf('----------------------------------------------\n');
    fprintf(' TEST RUN: 0 -> %.0f km/h -> stop (gradient %.2f %%)\n', ...
            r.reference.cruise_speed_kmh, p.grade_pct);
    fprintf('   Reference accel.   : %.3f m/s^2, decel. %.2f m/s^2\n', ...
            r.reference.accel_ms2, r.reference.decel_ms2);
    fprintf('   Planned distance   : %.0f m in %.0f s\n', ...
            r.reference.planned_distance_m, r.reference.run_time_s);
    fprintf('   Controller         : update %.2f s, delay %.2f s, notches %d, Kp %.2f, Ki %.2f\n', ...
            r.controller.update_s, r.controller.delay_s, r.controller.n_notch, ...
            r.controller.Kp, r.controller.Ki);
    fprintf('----------------------------------------------\n');
    fprintf(' RMS speed error      : %.2f km/h (max %.2f)\n', r.tracking.rms_err_kmh, r.tracking.max_err_kmh);
    fprintf(' Speed overshoot      : %.2f km/h\n', r.tracking.overshoot_kmh);
    fprintf(' Stop position error  : %.1f m\n', r.tracking.stop_err_m);
    fprintf(' Jerk (rms / max)     : %.3f / %.3f m/s^3\n', r.tracking.jerk_rms_ms3, r.tracking.jerk_max_ms3);
    fprintf(' Traction energy      : %.2f kWh (ideal %.2f, excess %.1f %%)\n', ...
            r.tracking.energy_actual_kWh, r.tracking.energy_ideal_kWh, r.tracking.energy_excess_pct);
    fprintf('----------------------------------------------\n');
    fprintf(' Control quality idx  : %.2f (speed %.2f, stop %.2f, comfort %.2f)\n', ...
            r.quality.index, r.quality.speed, r.quality.stop, r.quality.comfort);
    fprintf(' Control score (model): %.2f (0.5 * AI + 0.5 * quality)\n', r.control_score);
    fprintf('==============================================\n');
end


function print_comparison(c)
%PRINT_COMPARISON  Print the level comparison table.

    fprintf('\n LEVEL COMPARISON ON THE SAME TRAIN (%s)\n', c.plant_name);
    fprintf(' Level |   AI | RMS err [km/h] | Stop err [m] | Jerk rms | Energy excess [%%] | Quality\n');
    fprintf(' ------+------+----------------+--------------+----------+-------------------+--------\n');
    for i = 1:numel(c.levels)
        fprintf('   %d   | %.2f | %14.2f | %12.1f | %8.3f | %17.1f | %6.2f\n', ...
                c.levels(i), c.automation_index(i), c.rms_err_kmh(i), c.stop_err_m(i), ...
                c.jerk_rms(i), c.energy_excess_pct(i), c.quality(i));
    end
    fprintf('\n');
end


function plot_results(r)
%PLOT_RESULTS  Four plots: speed tracking, speed error, force command, automated functions.

    pr = r.profile;

    figure('Name', ['Phase 5 - ' r.name], 'Color', 'w');

    subplot(2, 2, 1);
    plot(pr.t_s, pr.v_ref_kmh, '--', 'LineWidth', 1.5); hold on;
    plot(pr.t_s, pr.v_kmh, 'LineWidth', 1.5);
    xlabel('Time [s]'); ylabel('Speed [km/h]');
    legend('Reference', 'Actual', 'Location', 'northeast');
    title('Speed tracking'); grid on;

    subplot(2, 2, 2);
    plot(pr.t_s, pr.v_kmh - pr.v_ref_kmh, 'LineWidth', 1.2);
    xlabel('Time [s]'); ylabel('Speed error [km/h]');
    title('Tracking error (actual - reference)'); grid on;

    subplot(2, 2, 3);
    plot(pr.t_s, pr.F_cmd_kN, 'LineWidth', 1.2); hold on;
    plot(pr.t_s, pr.F_act_kN, 'LineWidth', 1.5);
    xlabel('Time [s]'); ylabel('Force [kN]');
    legend('Command', 'Applied (after delay and lag)', 'Location', 'northeast');
    title('Traction / brake force'); grid on;

    subplot(2, 2, 4);
    barh(double(r.functions.flags(end:-1:1)));
    set(gca, 'YTick', 1:r.functions.n_total, 'YTickLabel', r.functions.names(end:-1:1), ...
             'XTick', [0 1], 'XLim', [0 1.2]);
    title(sprintf('Automated functions (AI = %.2f)', r.automation_index));
    grid on;

    sgtitle(sprintf('%s - automation level %d', r.name, r.automation_level));
end


function plot_comparison(c, name)
%PLOT_COMPARISON  Compare tracking error and indices of the five controller levels.

    figure('Name', ['Phase 5 - level comparison - ' name], 'Color', 'w');

    subplot(1, 2, 1);
    plot(c.t_s, c.err_kmh, 'LineWidth', 1.1);
    xlabel('Time [s]'); ylabel('Speed error [km/h]');
    legend(arrayfun(@(l) sprintf('Level %d', l), c.levels, 'UniformOutput', false), ...
           'Location', 'best');
    title('Speed error by controller level'); grid on;

    subplot(1, 2, 2);
    bar(categorical(arrayfun(@num2str, c.levels, 'UniformOutput', false)), ...
        [c.automation_index(:), c.quality(:)]);
    xlabel('Automation level'); ylabel('Index [-]');
    legend('Automation Index', 'Control quality index', 'Location', 'northwest');
    title('Indices by level'); grid on;

    sgtitle(name);
end