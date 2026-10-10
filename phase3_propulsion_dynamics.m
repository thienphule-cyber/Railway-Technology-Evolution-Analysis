function r = phase3_propulsion_dynamics(g, s, opts)
%PHASE3_PROPULSION_DYNAMICS  Propulsion and longitudinal dynamics of one railway generation.
%
%   r = phase3_propulsion_dynamics(g, s)
%   r = phase3_propulsion_dynamics(g, s, opts)
%
%   INPUT  g    : generation parameter struct (same struct given to Phase 1)
%          s    : output struct of phase1_system_definition
%          opts : (optional) struct, opts.plot = true to draw the result figures
%   OUTPUT r    : struct with the speed profile, performance indicators and journey time
%
%   Model (train treated as a point mass on a straight track):
%       m * k_rot * dv/dt = F_traction(v) - F_rolling - F_aero - F_gradient
%
%       F_traction(v) = min( F_max , P_wheel / v )      (0 above the design speed)
%       F_max         = min( max tractive effort , adhesion limit from Phase 1 )
%       F_rolling     = Cr * m * g * cos(theta)
%       F_aero        = 0.5 * rho * Cd * A * v^2
%       F_gradient    = m * g * sin(theta)
%
%   The train accelerates at full traction from standstill until it reaches 99 %
%   of its maximum speed. The simulated profile is then reused to estimate the
%   travel time of the same journey as in Phase 2 (accelerate -> cruise -> brake).
%
%   Required field of g (in addition to the Phase 1 fields):
%     cruise_speed_kmh        num   cruise speed [km/h]
%
%   Optional fields of g (defaults in brackets):
%     max_speed_kmh           num   design speed limit [km/h]               (1.2 * cruise speed)
%     max_tractive_effort_kN  num   starting tractive effort [kN]           (adhesion limit)
%     grade_pct               num   constant track gradient [%]             (0)
%     route_distance_km       num   total journey distance [km]             (100)
%     n_stops                 num   number of intermediate stops            (5)
%     avg_decel_ms2           num   average service deceleration [m/s^2]    (0.7)
%     rolling_coeff           num   rolling resistance coefficient Cr [-]   (0.002)
%     drag_coeff              num   aerodynamic drag coefficient Cd [-]     (0.9)
%     frontal_area_m2         num   frontal area A [m^2]                    (10)
%     rotating_mass_factor    num   equivalent mass factor, rotating parts (1.06)
%     air_density             num   air density [kg/m^3]                   (1.2)

    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    do_plot = isfield(opts, 'plot') && opts.plot;

    %% 1. Read parameters and build the dynamic model
    p   = read_parameters(g, s);
    mdl = build_model(s, p);

    %% 2. Maximum speed at the given track gradient
    [v_max, limit_text] = find_max_speed(mdl);
    v_target = 0.99 * v_max;            % the simulation stops at 99 % of max speed

    %% 3. Acceleration simulation with ode45
    ode_fun = @(t, y) [ y(2); ...
                        (traction_force(y(2), mdl) - resistance_force(y(2), mdl, mdl.theta)) ...
                        / (mdl.m * mdl.k_rot) ];

    ode_opts = odeset('Events', @(t, y) speed_event(t, y, v_target), ...
        'RelTol', 1e-6, 'AbsTol', 1e-6, 'MaxStep', 1);

    t_max = 7200;                       % [s] safety limit of the simulation
    [t, y, te] = ode45(ode_fun, [0 t_max], [0; 0], ode_opts);

    if isempty(te)
        warning('phase3:noConvergence', ...
                '[%s] 99 %% of max speed not reached within %.0f s. Results use the last simulated point.', ...
                s.name, t_max);
    end

    x = y(:, 1);                        % position [m]
    v = y(:, 2);                        % speed [m/s]

    %% 4. Post-process the profile
    F_t = traction_force(v, mdl);                          % [N]
    F_r = resistance_force(v, mdl, mdl.theta);             % [N]
    acc = (F_t - F_r) / (mdl.m * mdl.k_rot);               % [m/s^2]
    P_w = F_t .* v / 1000;                                 % traction power at the wheel [kW]

    r.name = s.name;

    r.profile.t_s         = t;
    r.profile.x_m         = x;
    r.profile.v_ms        = v;
    r.profile.v_kmh       = v * 3.6;
    r.profile.acc_ms2     = acc;
    r.profile.F_traction_kN = F_t / 1000;
    r.profile.F_resist_kN   = F_r / 1000;
    r.profile.P_wheel_kW    = P_w;

    %% 5. Performance indicators
    r.max_speed_kmh      = v_max * 3.6;
    r.limiting_factor    = limit_text;
    r.start_force_kN     = traction_force(0, mdl) / 1000;
    r.start_accel_ms2    = acc(1);
    r.corner_speed_kmh   = (mdl.P_W / mdl.F_max) * 3.6;    % speed where force limit meets power limit
    r.sim_end_time_s     = t(end);
    r.sim_end_dist_km    = x(end) / 1000;

    % Time and distance to reach reference speeds
    ref_kmh = [40 80 100 120 160 200 250 300];
    [v_u, iu] = unique(v);
    t_u = t(iu);
    x_u = x(iu);
    r.times.speed_kmh = ref_kmh;
    r.times.time_s    = NaN(size(ref_kmh));
    r.times.dist_km   = NaN(size(ref_kmh));
    for k = 1:numel(ref_kmh)
        vk = ref_kmh(k) / 3.6;
        if vk <= v_u(end)
            r.times.time_s(k)  = interp1(v_u, t_u, vk);
            r.times.dist_km(k) = interp1(v_u, x_u, vk) / 1000;
        end
    end

    %% 6. Gradeability (maximum grade at which the train can still move)
    v_start = 1;                                           % [m/s] "standstill" reference
    r.gradeability.start_pct  = max_grade_pct(v_start, mdl);
    r.gradeability.cruise_pct = NaN;                       % filled below

    %% 7. Journey time using the simulated acceleration profile
    v_c = min(p.cruise_speed_kmh / 3.6, v_target);         % attainable cruise speed [m/s]
    if v_c < p.cruise_speed_kmh / 3.6
        warning('phase3:cruiseNotReached', ...
                '[%s] Cruise speed %.0f km/h is not attainable. Using %.1f km/h instead.', ...
                s.name, p.cruise_speed_kmh, v_c * 3.6);
    end
    r.gradeability.cruise_pct = max_grade_pct(v_c, mdl);

    n_seg = p.n_stops + 1;
    D     = p.route_distance_km * 1000;

    t_acc = interp1(v_u, t_u, v_c);                        % accelerate to cruise speed [s]
    d_acc = interp1(v_u, x_u, v_c);                        % distance while accelerating [m]
    t_brk = v_c / p.avg_decel_ms2;                         % [s]
    d_brk = v_c^2 / (2 * p.avg_decel_ms2);                 % [m]
    d_cruise = D - n_seg * (d_acc + d_brk);                % [m]

    r.journey.cruise_speed_kmh = v_c * 3.6;
    r.journey.n_stops          = p.n_stops;
    r.journey.distance_km      = p.route_distance_km;
    r.journey.accel_time_s     = t_acc;
    r.journey.accel_dist_m     = d_acc;
    r.journey.brake_time_s     = t_brk;
    r.journey.brake_dist_m     = d_brk;

    if d_cruise < 0
        warning('phase3:routeTooShort', ...
                '[%s] Route too short for the simulated acceleration and the number of stops. Journey time not computed.', ...
                s.name);
        r.journey.travel_time_min   = NaN;
        r.journey.average_speed_kmh = NaN;
    else
        t_total = n_seg * (t_acc + t_brk) + d_cruise / v_c;
        r.journey.travel_time_min   = t_total / 60;
        r.journey.average_speed_kmh = (D / t_total) * 3.6;
    end

    % Power needed to hold the cruise speed
    r.journey.cruise_power_kW   = resistance_force(v_c, mdl, mdl.theta) * v_c / 1000;
    r.journey.cruise_power_util = r.journey.cruise_power_kW / (mdl.P_W / 1000);

    %% 8. Report and optional plot
    print_summary(r, p);
    if do_plot
        plot_results(r, mdl, v_max);
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function p = read_parameters(g, s)
%READ_PARAMETERS  Read dynamics parameters from g and apply defaults.

    if ~isfield(g, 'cruise_speed_kmh') || ~isnumeric(g.cruise_speed_kmh) || g.cruise_speed_kmh <= 0
        error('phase3:missingField', 'Missing or invalid field: "cruise_speed_kmh".');
    end
    p.cruise_speed_kmh = g.cruise_speed_kmh;

    p.max_speed_kmh          = get_param(g, 'max_speed_kmh',          1.2 * p.cruise_speed_kmh);
    p.max_tractive_effort_kN = get_param(g, 'max_tractive_effort_kN', s.max_adhesion_force_N / 1000);
    p.grade_pct              = get_param(g, 'grade_pct',              0);
    p.route_distance_km      = get_param(g, 'route_distance_km',      100);
    p.n_stops                = get_param(g, 'n_stops',                5);
    p.avg_decel_ms2          = get_param(g, 'avg_decel_ms2',          0.7);
    p.rolling_coeff          = get_param(g, 'rolling_coeff',          0.002);
    p.drag_coeff             = get_param(g, 'drag_coeff',             0.9);
    p.frontal_area_m2        = get_param(g, 'frontal_area_m2',        10);
    p.rotating_mass_factor   = get_param(g, 'rotating_mass_factor',   1.06);
    p.air_density            = get_param(g, 'air_density',            1.2);

    % Range checks
    if p.max_speed_kmh <= 0 || p.max_tractive_effort_kN <= 0
        error('phase3:badValue', 'max_speed_kmh and max_tractive_effort_kN must be > 0.');
    end
    if p.route_distance_km <= 0 || p.n_stops < 0 || p.avg_decel_ms2 <= 0
        error('phase3:badValue', 'Distance and deceleration must be > 0 and n_stops >= 0.');
    end
    if p.rotating_mass_factor < 1
        error('phase3:badValue', 'rotating_mass_factor must be >= 1.');
    end
    if abs(p.grade_pct) >= 50
        error('phase3:badValue', 'grade_pct must be within (-50, 50) percent.');
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


function mdl = build_model(s, p)
%BUILD_MODEL  Collect all constants of the dynamic model in one struct.

    mdl.m       = s.train_mass_kg;                                   % [kg]
    mdl.gravity = 9.81;                                              % [m/s^2]
    mdl.k_rot   = p.rotating_mass_factor;                            % [-]
    mdl.Cr      = p.rolling_coeff;                                   % [-]
    mdl.k_aero  = 0.5 * p.air_density * p.drag_coeff * p.frontal_area_m2;   % F_aero = k_aero * v^2
    mdl.F_max   = min(p.max_tractive_effort_kN * 1000, s.max_adhesion_force_N);   % [N]
    mdl.P_W     = s.wheel_power_kW * 1000;                           % [W] power at the wheel
    mdl.v_limit = p.max_speed_kmh / 3.6;                             % [m/s] design speed
    mdl.theta   = atan(p.grade_pct / 100);                           % [rad] track slope angle
end


function F = traction_force(v, mdl)
%TRACTION_FORCE  Tractive effort [N] as a function of speed (vectorised).
%   Constant force at low speed (adhesion / design limit), constant power above the corner speed.
%   Traction is cut off above the design speed limit.

    v_safe = max(v, 0.01);                                % avoid division by zero at standstill
    F = min(mdl.F_max, mdl.P_W ./ v_safe);
    F = F .* (v <= mdl.v_limit);
end


function F = resistance_force(v, mdl, theta)
%RESISTANCE_FORCE  Total running resistance [N]: rolling + aerodynamic + gradient (vectorised in v).

    F_roll  = mdl.Cr * mdl.m * mdl.gravity * cos(theta);
    F_aero  = mdl.k_aero * v.^2;
    F_grade = mdl.m * mdl.gravity * sin(theta);
    F = F_roll + F_aero + F_grade;
end


function [v_max, text] = find_max_speed(mdl)
%FIND_MAX_SPEED  Highest speed at which traction still exceeds resistance.

    v_grid = linspace(0.5, mdl.v_limit, 5000);
    net    = traction_force(v_grid, mdl) - resistance_force(v_grid, mdl, mdl.theta);

    if net(1) <= 0
        error('phase3:cannotStart', ...
              ['The train cannot start: tractive effort is lower than the running resistance. ' ...
               'Check power, adhesion, grade_pct and mass.']);
    end

    k = find(net > 0, 1, 'last');
    if k == numel(v_grid)
        v_max = mdl.v_limit;
        text  = 'Design speed limit';
    else
        % Linear interpolation of the zero crossing between grid points k and k+1
        v_max = v_grid(k) + net(k) / (net(k) - net(k+1)) * (v_grid(k+1) - v_grid(k));
        text  = 'Power / resistance balance';
    end
end


function grade_pct = max_grade_pct(v, mdl)
%MAX_GRADE_PCT  Steepest grade [%] the train can climb at speed v (full traction).

    F_t = traction_force(v, mdl);
    f   = @(th) F_t - resistance_force(v, mdl, th);

    th_hi = 0.5;                                          % [rad], about 55 %
    if f(0) <= 0
        grade_pct = 0;
    elseif f(th_hi) >= 0
        grade_pct = 100 * tan(th_hi);
    else
        th = fzero(f, [0 th_hi]);
        grade_pct = 100 * tan(th);
    end
end


function print_summary(r, p)
%PRINT_SUMMARY  Print the propulsion and dynamics results to the command window.

    fprintf('\n==============================================\n');
    fprintf(' PHASE 3 - PROPULSION & DYNAMICS\n');
    fprintf(' %s\n', r.name);
    fprintf('==============================================\n');
    fprintf(' Track gradient       : %.2f %%\n', p.grade_pct);
    fprintf(' Starting force       : %.1f kN\n', r.start_force_kN);
    fprintf(' Starting acceleration: %.3f m/s^2\n', r.start_accel_ms2);
    fprintf(' Corner speed         : %.1f km/h (force limit -> power limit)\n', r.corner_speed_kmh);
    fprintf(' Maximum speed        : %.1f km/h (%s)\n', r.max_speed_kmh, r.limiting_factor);
    fprintf(' Time to 99%% max speed: %.1f s over %.2f km\n', r.sim_end_time_s, r.sim_end_dist_km);
    fprintf('----------------------------------------------\n');
    for k = 1:numel(r.times.speed_kmh)
        if ~isnan(r.times.time_s(k))
            fprintf(' 0 -> %3d km/h        : %7.1f s  (%.2f km)\n', ...
                    r.times.speed_kmh(k), r.times.time_s(k), r.times.dist_km(k));
        end
    end
    fprintf('----------------------------------------------\n');
    fprintf(' Max grade at start   : %.1f %%\n', r.gradeability.start_pct);
    fprintf(' Max grade at cruise  : %.1f %%\n', r.gradeability.cruise_pct);
    fprintf(' Cruise speed used    : %.1f km/h\n', r.journey.cruise_speed_kmh);
    fprintf(' Cruise wheel power   : %.0f kW (%.0f %% of wheel power)\n', ...
            r.journey.cruise_power_kW, 100 * r.journey.cruise_power_util);
    fprintf(' Accel. to cruise     : %.1f s over %.2f km\n', ...
            r.journey.accel_time_s, r.journey.accel_dist_m / 1000);
    fprintf(' Journey              : %.1f km, %d intermediate stops\n', ...
            r.journey.distance_km, r.journey.n_stops);
    fprintf(' Travel time          : %.1f min (avg %.1f km/h)\n', ...
            r.journey.travel_time_min, r.journey.average_speed_kmh);
    fprintf('==============================================\n');
end


function plot_results(r, mdl, v_max)
%PLOT_RESULTS  Four plots: speed-time, distance-time, force-speed, acceleration-speed.

    figure('Name', ['Phase 3 - ' r.name], 'Color', 'w');

    subplot(2, 2, 1);
    plot(r.profile.t_s, r.profile.v_kmh, 'LineWidth', 1.5);
    xlabel('Time [s]'); ylabel('Speed [km/h]');
    title('Speed vs time'); grid on;

    subplot(2, 2, 2);
    plot(r.profile.t_s, r.profile.x_m / 1000, 'LineWidth', 1.5);
    xlabel('Time [s]'); ylabel('Distance [km]');
    title('Distance vs time'); grid on;

    subplot(2, 2, 3);
    v_grid = linspace(0.5, mdl.v_limit, 500);
    F_t = traction_force(v_grid, mdl) / 1000;
    F_r = resistance_force(v_grid, mdl, mdl.theta) / 1000;
    plot(v_grid * 3.6, F_t, 'LineWidth', 1.5); hold on;
    plot(v_grid * 3.6, F_r, 'LineWidth', 1.5);
    xline(v_max * 3.6, '--k');
    xlabel('Speed [km/h]'); ylabel('Force [kN]');
    legend('Tractive effort', 'Total resistance', 'Max speed', 'Location', 'northeast');
    title('Tractive effort and resistance'); grid on;

    subplot(2, 2, 4);
    plot(r.profile.v_kmh, r.profile.acc_ms2, 'LineWidth', 1.5);
    xlabel('Speed [km/h]'); ylabel('Acceleration [m/s^2]');
    title('Acceleration vs speed'); grid on;

    sgtitle(r.name);
end

function [value, isterminal, direction] = speed_event(~, y, v_target)
value      = y(2) - v_target;
isterminal = 1;
direction  = 1;
end