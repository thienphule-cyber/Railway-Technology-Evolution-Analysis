function r = phase4_braking_safety(g, s, opts)
%PHASE4_BRAKING_SAFETY  Braking and safety analysis of one railway generation.
%
%   r = phase4_braking_safety(g, s)
%   r = phase4_braking_safety(g, s, opts)
%
%   INPUT  g    : generation parameter struct (same struct given to Phase 1)
%          s    : output struct of phase1_system_definition
%          opts : (optional) struct, opts.plot = true to draw the result figures
%   OUTPUT r    : struct with service / emergency stop results, energy split,
%                 stopping-distance curves and safety indicators
%
%   Model (point mass, straight track):
%       m * k_rot * dv/dt = -( F_electric + F_mechanical + F_resistance )
%
%       F_brake_demand = a_demand * m * k_rot, limited by the wheel-rail adhesion
%       Brake force builds up linearly over the build-up time after the command.
%
%       Service brake  : blended. Electric brake is used first (limited by force,
%                        power and low-speed fade-out), friction brake supplies the rest.
%       Emergency brake: friction brake only (electric brake ignored unless
%                        g.emergency_uses_electric = true), higher deceleration.
%
%       F_resistance = rolling + aerodynamic + gradient (helps braking uphill).
%
%   Total stopping distance = reaction distance (constant speed during the
%   reaction time) + distance travelled after the brake command.
%
%   Required field of g (in addition to the Phase 1 fields), unless
%   brake_initial_speed_kmh is given:
%     cruise_speed_kmh           num   cruise speed [km/h]
%
%   Optional fields of g (defaults in brackets):
%     brake_initial_speed_kmh    num   speed at the brake command [km/h]       (cruise speed)
%     max_speed_kmh              num   upper speed of the stopping curves      (1.2 * cruise speed)
%     avg_decel_ms2              num   service deceleration demand [m/s^2]     (0.7)
%     emergency_decel_ms2        num   emergency deceleration demand [m/s^2]   (1.2 * service)
%     service_buildup_s          num   service brake force build-up time [s]   (1.5)
%     emergency_buildup_s        num   emergency brake build-up time [s]       (2.5)
%     reaction_time_s            num   driver / system reaction time [s]       (by automation level)
%     electric_brake_force_kN    num   max electric brake force [kN]           (0 = no electric brake)
%     electric_brake_power_kW    num   max electric brake power at wheel [kW]  (wheel power)
%     electric_fade_speed_kmh    num   speed below which electric brake fades  (5)
%     emergency_uses_electric    bool  count electric brake in emergency stop  (false)
%     regenerative_braking       bool  electric brake returns energy to source (regen_fraction > 0)
%     regen_chain_efficiency     num   wheel-side -> source-side regen eff.    (0.9)
%     brake_adhesion_coeff       num   wheel-rail adhesion when braking        (Phase 1 adhesion)
%     grade_pct                  num   constant track gradient [%]             (0)
%     rolling_coeff              num   rolling resistance coefficient Cr [-]   (0.002)
%     drag_coeff                 num   aerodynamic drag coefficient Cd [-]     (0.9)
%     frontal_area_m2            num   frontal area A [m^2]                    (10)
%     rotating_mass_factor       num   equivalent mass factor, rotating parts  (1.06)
%     air_density                num   air density [kg/m^3]                    (1.2)
%     comfort_decel_limit_ms2    num   passenger comfort limit, deceleration   (1.0)
%     comfort_jerk_limit_ms3     num   passenger comfort limit, jerk           (1.5)
%     sight_distance_m           num   available sight / safe distance [m]     (NaN = not checked)

    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    do_plot = isfield(opts, 'plot') && opts.plot;

    %% 1. Read parameters and build the braking model
    p   = read_parameters(g, s);
    mdl = build_model(s, p);

    v0 = p.initial_speed_kmh / 3.6;                       % [m/s]

    %% 2. Simulate the two stops
    svc = simulate_stop(v0, 'service',   mdl);
    emg = simulate_stop(v0, 'emergency', mdl);

    %% 3. Service stop results
    r.name = s.name;
    r.initial_speed_kmh = p.initial_speed_kmh;

    r.service   = stop_results(svc, v0, mdl, p, s);
    r.emergency = stop_results(emg, v0, mdl, p, s);

    r.service.demand_decel_ms2   = p.service_decel_ms2;
    r.emergency.demand_decel_ms2 = p.emergency_decel_ms2;

    % Comfort checks of the service brake
    r.service.max_jerk_ms3     = r.service.max_decel_ms2 / max(p.service_buildup_s, 1e-3);
    r.service.comfort_decel_ok = r.service.max_decel_ms2 <= p.comfort_decel_limit_ms2;
    r.service.comfort_jerk_ok  = r.service.max_jerk_ms3  <= p.comfort_jerk_limit_ms3;

    %% 4. Energy during the service stop [kWh]
    J2kWh = 1 / 3.6e6;
    KE0   = 0.5 * mdl.m * mdl.k_rot * v0^2;

    r.energy.kinetic_kWh     = KE0 * J2kWh;
    r.energy.electric_kWh    = svc.E_elec * J2kWh;        % absorbed by the electric brake
    r.energy.friction_kWh    = svc.E_fric * J2kWh;        % dissipated as heat in friction brakes
    r.energy.resistance_kWh  = svc.E_res  * J2kWh;        % dissipated by running resistance

    if p.regenerative
        r.energy.regenerated_kWh = svc.E_elec * mdl.eta_tr * p.regen_chain_efficiency * J2kWh;
    else
        r.energy.regenerated_kWh = 0;
    end
    r.energy.regen_recovery_pct   = 100 * r.energy.regenerated_kWh / r.energy.kinetic_kWh;
    r.energy.electric_share_pct   = 100 * svc.E_elec / max(svc.E_elec + svc.E_fric, eps);
    r.energy.friction_per_axle_MJ = svc.E_fric / s.n_axles / 1e6;   % all axles assumed braked

    %% 5. Stopping-distance curves versus initial speed
    v_curve = linspace(10, max(p.max_speed_kmh, p.initial_speed_kmh), 12);
    d_svc   = NaN(size(v_curve));
    d_emg   = NaN(size(v_curve));
    for k = 1:numel(v_curve)
        vk = v_curve(k) / 3.6;
        a  = simulate_stop(vk, 'service',   mdl);
        b  = simulate_stop(vk, 'emergency', mdl);
        if a.stopped, d_svc(k) = vk * p.reaction_time_s + a.x(end); end
        if b.stopped, d_emg(k) = vk * p.reaction_time_s + b.x(end); end
    end
    r.curve.speed_kmh           = v_curve;
    r.curve.service_total_m     = d_svc;
    r.curve.emergency_total_m   = d_emg;

    %% 6. Safety indicators
    % Model-based safety index in [0, 1]. This is NOT an official railway safety
    % rating. Reference values and weights below are modelling assumptions.
    a_ref = 1.2;                                   % [m/s^2] reference effective emergency decel
    t_ref = 3.0;                                   % [s] reference total delay (reaction + build-up)
    t_delay = p.reaction_time_s + p.emergency_buildup_s;

    r.safety.reaction_time_s      = p.reaction_time_s;
    r.safety.total_delay_s        = t_delay;
    r.safety.emergency_eff_decel  = r.emergency.effective_decel_ms2;
    r.safety.index = 0.5 * min(1, r.emergency.effective_decel_ms2 / a_ref) ...
                   + 0.3 * min(1, t_ref / max(t_delay, eps)) ...
                   + 0.2 * (s.automation_level / 4);

    r.safety.sight_distance_m     = p.sight_distance_m;
    r.safety.sight_ok             = NaN;
    r.safety.max_safe_speed_kmh   = NaN;
    if ~isnan(p.sight_distance_m)
        r.safety.sight_ok = r.emergency.total_distance_m <= p.sight_distance_m;
        ok = ~isnan(d_emg);
        if nnz(ok) >= 2
            [d_u, iu] = unique(d_emg(ok));
            v_ok = v_curve(ok);
            r.safety.max_safe_speed_kmh = interp1(d_u, v_ok(iu), p.sight_distance_m, 'linear', NaN);
        end
    end

    %% 7. Consistency checks
    r.checks.service_adhesion_limited   = mdl.service_capped;
    r.checks.emergency_adhesion_limited = mdl.emergency_capped;
    r.checks.energy_balance_error_pct   = 100 * (svc.E_elec + svc.E_fric + svc.E_res - KE0) / KE0;

    if mdl.service_capped
        warning('phase4:adhesionService', ...
                '[%s] Service deceleration demand exceeds the adhesion limit. Demand was capped at %.2f m/s^2.', ...
                s.name, mdl.F_service / (mdl.m * mdl.k_rot));
    end
    if mdl.emergency_capped
        warning('phase4:adhesionEmergency', ...
                '[%s] Emergency deceleration demand exceeds the adhesion limit. Demand was capped at %.2f m/s^2.', ...
                s.name, mdl.F_emergency / (mdl.m * mdl.k_rot));
    end
    if ~svc.stopped || ~emg.stopped
        warning('phase4:notStopped', ...
                '[%s] The train does not stop within the simulation time. Check grade_pct and deceleration values.', s.name);
    end
    if p.emergency_decel_ms2 < p.service_decel_ms2
        warning('phase4:emergencyWeaker', ...
                '[%s] Emergency deceleration is lower than service deceleration.', s.name);
    end

    %% 8. Keep the profiles for plotting and later phases
    r.service.profile   = profile_struct(svc, mdl);
    r.emergency.profile = profile_struct(emg, mdl);

    %% 9. Report and optional plot
    print_summary(r, p);
    if do_plot
        plot_results(r, p);
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function p = read_parameters(g, s)
%READ_PARAMETERS  Read braking parameters from g and apply defaults.

    has_cruise = isfield(g, 'cruise_speed_kmh') && isnumeric(g.cruise_speed_kmh) && g.cruise_speed_kmh > 0;
    has_init   = isfield(g, 'brake_initial_speed_kmh') && ~isempty(g.brake_initial_speed_kmh);

    if ~has_cruise && ~has_init
        error('phase4:missingField', 'Provide "cruise_speed_kmh" or "brake_initial_speed_kmh".');
    end
    if has_cruise
        cruise = g.cruise_speed_kmh;
    else
        cruise = g.brake_initial_speed_kmh;
    end

    p.initial_speed_kmh = get_param(g, 'brake_initial_speed_kmh', cruise);
    p.max_speed_kmh     = get_param(g, 'max_speed_kmh', 1.2 * cruise);

    p.service_decel_ms2   = get_param(g, 'avg_decel_ms2', 0.7);
    p.emergency_decel_ms2 = get_param(g, 'emergency_decel_ms2', 1.2 * p.service_decel_ms2);
    p.service_buildup_s   = get_param(g, 'service_buildup_s',   1.5);
    p.emergency_buildup_s = get_param(g, 'emergency_buildup_s', 2.5);

    % Default reaction time by automation level 0..4 (modelling assumption)
    reaction_default = [3.0 2.5 2.0 1.5 0.5];
    p.reaction_time_s = get_param(g, 'reaction_time_s', reaction_default(s.automation_level + 1));

    p.electric_force_kN   = get_param(g, 'electric_brake_force_kN', 0);
    p.electric_power_kW   = get_param(g, 'electric_brake_power_kW', s.wheel_power_kW);
    p.electric_fade_kmh   = get_param(g, 'electric_fade_speed_kmh', 5);
    p.emergency_uses_elec = logical(get_param(g, 'emergency_uses_electric', false));

    regen_default = isfield(g, 'regen_fraction') && ~isempty(g.regen_fraction) && g.regen_fraction > 0;
    p.regenerative            = logical(get_param(g, 'regenerative_braking', regen_default));
    p.regen_chain_efficiency  = get_param(g, 'regen_chain_efficiency', 0.9);

    p.brake_adhesion_coeff = get_param(g, 'brake_adhesion_coeff', s.adhesion_coeff);

    p.grade_pct            = get_param(g, 'grade_pct', 0);
    p.rolling_coeff        = get_param(g, 'rolling_coeff', 0.002);
    p.drag_coeff           = get_param(g, 'drag_coeff', 0.9);
    p.frontal_area_m2      = get_param(g, 'frontal_area_m2', 10);
    p.rotating_mass_factor = get_param(g, 'rotating_mass_factor', 1.06);
    p.air_density          = get_param(g, 'air_density', 1.2);

    p.comfort_decel_limit_ms2 = get_param(g, 'comfort_decel_limit_ms2', 1.0);
    p.comfort_jerk_limit_ms3  = get_param(g, 'comfort_jerk_limit_ms3', 1.5);
    p.sight_distance_m        = get_param(g, 'sight_distance_m', NaN);

    % Range checks
    if p.initial_speed_kmh <= 0 || p.max_speed_kmh <= 0
        error('phase4:badValue', 'Speeds must be > 0.');
    end
    if p.service_decel_ms2 <= 0 || p.emergency_decel_ms2 <= 0
        error('phase4:badValue', 'Deceleration values must be > 0.');
    end
    if p.service_buildup_s < 0 || p.emergency_buildup_s < 0 || p.reaction_time_s < 0
        error('phase4:badValue', 'Build-up and reaction times must be >= 0.');
    end
    if p.electric_force_kN < 0 || p.electric_power_kW < 0 || p.electric_fade_kmh <= 0
        error('phase4:badValue', 'Electric brake parameters must be >= 0 (fade speed > 0).');
    end
    if p.regen_chain_efficiency <= 0 || p.regen_chain_efficiency > 1
        error('phase4:badValue', 'regen_chain_efficiency must be in (0, 1].');
    end
    if p.brake_adhesion_coeff <= 0 || p.brake_adhesion_coeff > 1
        error('phase4:badValue', 'brake_adhesion_coeff must be in (0, 1].');
    end
    if p.rotating_mass_factor < 1
        error('phase4:badValue', 'rotating_mass_factor must be >= 1.');
    end
    if abs(p.grade_pct) >= 50
        error('phase4:badValue', 'grade_pct must be within (-50, 50) percent.');
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
%BUILD_MODEL  Collect all constants of the braking model in one struct.

    mdl.m       = s.train_mass_kg;                                   % [kg]
    mdl.gravity = 9.81;                                              % [m/s^2]
    mdl.k_rot   = p.rotating_mass_factor;                            % [-]
    mdl.Cr      = p.rolling_coeff;                                   % [-]
    mdl.k_aero  = 0.5 * p.air_density * p.drag_coeff * p.frontal_area_m2;   % F_aero = k_aero * v^2
    mdl.theta   = atan(p.grade_pct / 100);                           % [rad] track slope angle
    mdl.eta_tr  = s.drivetrain_efficiency / max(s.drivetrain_efficiency, eps);   % placeholder, set below

    % Transmission efficiency is needed for the regenerated energy. It is not stored
    % in the Phase 1 output, so it is recovered from the wheel power ratio.
    mdl.eta_tr  = s.wheel_power_kW / max(s.rated_power_kW, eps);

    % Adhesion-limited total brake force (friction brakes act on all axles)
    F_adh = p.brake_adhesion_coeff * mdl.m * mdl.gravity;            % [N]

    F_service_demand   = p.service_decel_ms2   * mdl.m * mdl.k_rot;  % [N]
    F_emergency_demand = p.emergency_decel_ms2 * mdl.m * mdl.k_rot;  % [N]

    mdl.service_capped   = F_service_demand   > F_adh;
    mdl.emergency_capped = F_emergency_demand > F_adh;
    mdl.F_service        = min(F_service_demand,   F_adh);
    mdl.F_emergency      = min(F_emergency_demand, F_adh);

    mdl.tb_service   = max(p.service_buildup_s,   1e-3);             % [s]
    mdl.tb_emergency = max(p.emergency_buildup_s, 1e-3);             % [s]

    % Electric brake capability
    mdl.F_e_max   = min(p.electric_force_kN * 1000, s.max_adhesion_force_N);   % [N]
    mdl.P_e       = p.electric_power_kW * 1000;                      % [W]
    mdl.v_fade    = p.electric_fade_kmh / 3.6;                       % [m/s]
    mdl.emergency_uses_electric = p.emergency_uses_elec;
end


function F = electric_capability(v, mdl)
%ELECTRIC_CAPABILITY  Maximum electric brake force [N] at speed v (vectorised).
%   Constant force at low speed, constant power at high speed, fade-out near standstill.

    v_safe = max(v, 0.01);
    F = min(mdl.F_e_max, mdl.P_e ./ v_safe);
    F = F .* min(1, max(v, 0) ./ mdl.v_fade);
end


function [F_e, F_m] = brake_forces(t, v, mode, mdl)
%BRAKE_FORCES  Electric and mechanical brake force [N] (vectorised in t and v).

    switch mode
        case 'service'
            F_full = mdl.F_service;
            t_b    = mdl.tb_service;
            use_e  = true;
        case 'emergency'
            F_full = mdl.F_emergency;
            t_b    = mdl.tb_emergency;
            use_e  = mdl.emergency_uses_electric;
        otherwise
            error('phase4:badMode', 'Unknown braking mode: %s', mode);
    end

    ramp  = min(1, max(t, 0) / t_b);                  % linear build-up of the brake force
    F_dem = F_full * ramp;                            % total demanded brake force [N]

    if use_e
        F_e = min(electric_capability(v, mdl), F_dem);   % electric brake first
    else
        F_e = zeros(size(F_dem));
    end
    F_m = F_dem - F_e;                                % friction brake supplies the rest
end


function F = resistance_force(v, mdl)
%RESISTANCE_FORCE  Running resistance [N]: rolling + aerodynamic + gradient (vectorised in v).

    F_roll  = mdl.Cr * mdl.m * mdl.gravity * cos(mdl.theta);
    F_aero  = mdl.k_aero * max(v, 0).^2;
    F_grade = mdl.m * mdl.gravity * sin(mdl.theta);
    F = F_roll + F_aero + F_grade;
end


function [value, isterminal, direction] = stop_event(~, y)
%STOP_EVENT  Terminal event: the train has stopped (speed crosses zero downwards).

    value      = y(2);
    isterminal = 1;
    direction  = -1;
end


function out = simulate_stop(v0, mode, mdl)
%SIMULATE_STOP  Integrate the braking motion from the brake command until standstill.

    t_max = 1200;                                     % [s] safety limit of the simulation

    ode_fun = @(t, y) [ y(2); ...
                        -total_force(t, y(2), mode, mdl) / (mdl.m * mdl.k_rot) ];

    ode_opts = odeset('Events', @stop_event, 'RelTol', 1e-6, 'AbsTol', 1e-6, 'MaxStep', 0.5);
    [t, y, te] = ode45(ode_fun, [0 t_max], [0; v0], ode_opts);

    out.t       = t;
    out.x       = y(:, 1);
    out.v       = max(y(:, 2), 0);
    out.stopped = ~isempty(te);

    [F_e, F_m]  = brake_forces(out.t, out.v, mode, mdl);
    F_res       = resistance_force(out.v, mdl);

    out.F_e     = F_e;
    out.F_m     = F_m;
    out.F_res   = F_res;
    out.decel   = (F_e + F_m + F_res) / (mdl.m * mdl.k_rot);   % total deceleration [m/s^2]

    out.E_elec  = trapz(out.t, F_e   .* out.v);       % [J] absorbed by electric brake
    out.E_fric  = trapz(out.t, F_m   .* out.v);       % [J] dissipated by friction brakes
    out.E_res   = trapz(out.t, F_res .* out.v);       % [J] dissipated by resistance
end


function F = total_force(t, v, mode, mdl)
%TOTAL_FORCE  Total decelerating force [N] used inside the ODE.

    [F_e, F_m] = brake_forces(t, v, mode, mdl);
    F = F_e + F_m + resistance_force(v, mdl);
end


function res = stop_results(sim, v0, mdl, p, s) %#ok<INUSD>
%STOP_RESULTS  Summarise one simulated stop.

    res.stopped = sim.stopped;

    if sim.stopped
        res.reaction_distance_m = v0 * p.reaction_time_s;
        res.brake_distance_m    = sim.x(end);
        res.total_distance_m    = res.reaction_distance_m + res.brake_distance_m;
        res.brake_time_s        = sim.t(end);
        res.total_time_s        = p.reaction_time_s + sim.t(end);
        res.effective_decel_ms2 = v0^2 / (2 * sim.x(end));     % mean deceleration after the command
        res.max_decel_ms2       = max(sim.decel);
    else
        res.reaction_distance_m = v0 * p.reaction_time_s;
        res.brake_distance_m    = NaN;
        res.total_distance_m    = NaN;
        res.brake_time_s        = NaN;
        res.total_time_s        = NaN;
        res.effective_decel_ms2 = NaN;
        res.max_decel_ms2       = NaN;
    end
end


function pr = profile_struct(sim, mdl)
%PROFILE_STRUCT  Store the time history of one stop (after the brake command).

    pr.t_s          = sim.t;
    pr.x_m          = sim.x;
    pr.v_ms         = sim.v;
    pr.v_kmh        = sim.v * 3.6;
    pr.decel_ms2    = sim.decel;
    pr.F_electric_kN = sim.F_e / 1000;
    pr.F_friction_kN = sim.F_m / 1000;
    pr.F_resist_kN   = sim.F_res / 1000;
    pr.mass_kg       = mdl.m;
end


function print_summary(r, p)
%PRINT_SUMMARY  Print the braking and safety results to the command window.

    fprintf('\n==============================================\n');
    fprintf(' PHASE 4 - BRAKING & SAFETY\n');
    fprintf(' %s\n', r.name);
    fprintf('==============================================\n');
    fprintf(' Initial speed        : %.0f km/h (gradient %.2f %%)\n', r.initial_speed_kmh, p.grade_pct);
    fprintf(' Reaction time        : %.1f s\n', p.reaction_time_s);
    fprintf('----------------------------------------------\n');
    fprintf(' SERVICE STOP (demand %.2f m/s^2)\n', r.service.demand_decel_ms2);
    fprintf('   Braking distance   : %.0f m (after command)\n', r.service.brake_distance_m);
    fprintf('   Total distance     : %.0f m (incl. reaction)\n', r.service.total_distance_m);
    fprintf('   Braking time       : %.1f s\n', r.service.brake_time_s);
    fprintf('   Effective decel.   : %.2f m/s^2 (max %.2f)\n', ...
            r.service.effective_decel_ms2, r.service.max_decel_ms2);
    fprintf('   Max jerk           : %.2f m/s^3\n', r.service.max_jerk_ms3);
    fprintf('   Comfort            : decel %s, jerk %s\n', ...
            yes_no(r.service.comfort_decel_ok), yes_no(r.service.comfort_jerk_ok));
    fprintf('----------------------------------------------\n');
    fprintf(' EMERGENCY STOP (demand %.2f m/s^2)\n', r.emergency.demand_decel_ms2);
    fprintf('   Braking distance   : %.0f m (after command)\n', r.emergency.brake_distance_m);
    fprintf('   Total distance     : %.0f m (incl. reaction)\n', r.emergency.total_distance_m);
    fprintf('   Braking time       : %.1f s\n', r.emergency.brake_time_s);
    fprintf('   Effective decel.   : %.2f m/s^2 (max %.2f)\n', ...
            r.emergency.effective_decel_ms2, r.emergency.max_decel_ms2);
    fprintf('----------------------------------------------\n');
    fprintf(' ENERGY OF THE SERVICE STOP\n');
    fprintf('   Kinetic energy     : %.2f kWh\n', r.energy.kinetic_kWh);
    fprintf('   Electric brake     : %.2f kWh (%.0f %% of brake work)\n', ...
            r.energy.electric_kWh, r.energy.electric_share_pct);
    fprintf('   Friction brake     : %.2f kWh (%.2f MJ per axle)\n', ...
            r.energy.friction_kWh, r.energy.friction_per_axle_MJ);
    fprintf('   Resistance         : %.2f kWh\n', r.energy.resistance_kWh);
    fprintf('   Regenerated        : %.2f kWh (%.1f %% of kinetic energy)\n', ...
            r.energy.regenerated_kWh, r.energy.regen_recovery_pct);
    fprintf('----------------------------------------------\n');
    fprintf(' Safety index (model) : %.2f (0..1)\n', r.safety.index);
    if ~isnan(r.safety.sight_distance_m)
        fprintf(' Sight distance       : %.0f m -> emergency stop %s\n', ...
                r.safety.sight_distance_m, yes_no(r.safety.sight_ok));
        fprintf(' Max safe speed       : %.0f km/h\n', r.safety.max_safe_speed_kmh);
    end
    fprintf(' Energy balance error : %.2f %%\n', r.checks.energy_balance_error_pct);
    fprintf('==============================================\n');
end


function t = yes_no(flag)
%YES_NO  Convert a logical flag to text.

    if flag
        t = 'OK';
    else
        t = 'EXCEEDED';
    end
end


function plot_results(r, p)
%PLOT_RESULTS  Four plots: speed-time, speed-distance, service brake force split, stopping curves.

    sv = r.service.profile;
    em = r.emergency.profile;

    figure('Name', ['Phase 4 - ' r.name], 'Color', 'w');

    subplot(2, 2, 1);
    plot(sv.t_s, sv.v_kmh, 'LineWidth', 1.5); hold on;
    plot(em.t_s, em.v_kmh, 'LineWidth', 1.5);
    xlabel('Time after brake command [s]'); ylabel('Speed [km/h]');
    legend('Service', 'Emergency', 'Location', 'northeast');
    title('Speed vs time'); grid on;

    subplot(2, 2, 2);
    plot(sv.x_m, sv.v_kmh, 'LineWidth', 1.5); hold on;
    plot(em.x_m, em.v_kmh, 'LineWidth', 1.5);
    xlabel('Distance after brake command [m]'); ylabel('Speed [km/h]');
    legend('Service', 'Emergency', 'Location', 'northeast');
    title('Speed vs distance'); grid on;

    subplot(2, 2, 3);
    area(sv.t_s, [sv.F_electric_kN, sv.F_friction_kN]);
    xlabel('Time after brake command [s]'); ylabel('Brake force [kN]');
    legend('Electric', 'Friction', 'Location', 'northeast');
    title('Service brake force split'); grid on;

    subplot(2, 2, 4);
    plot(r.curve.speed_kmh, r.curve.service_total_m, '-o', 'LineWidth', 1.5); hold on;
    plot(r.curve.speed_kmh, r.curve.emergency_total_m, '-s', 'LineWidth', 1.5);
    if ~isnan(p.sight_distance_m)
        yline(p.sight_distance_m, '--k', 'Sight distance');
    end
    xlabel('Initial speed [km/h]'); ylabel('Total stopping distance [m]');
    legend('Service', 'Emergency', 'Location', 'northwest');
    title('Stopping distance vs speed'); grid on;

    sgtitle(r.name);
end