function r = phase2_energy_analysis(g, s, opts)
%PHASE2_ENERGY_ANALYSIS  Energy analysis of one railway generation over a defined journey.
%
%   r = phase2_energy_analysis(g, s)
%   r = phase2_energy_analysis(g, s, opts)
%
%   INPUT  g    : generation parameter struct (same struct given to Phase 1)
%          s    : output struct of phase1_system_definition
%          opts : (optional) struct, opts.plot = true to draw the energy breakdown
%   OUTPUT r    : struct with journey data, energy breakdown, efficiency and CO2 results
%
%   Energy chain model:
%       Energy source -> [prime mover eff.] -> [transmission eff.] -> Wheel
%
%   Journey model (each segment = accelerate -> cruise -> brake, constant a and b):
%       number of segments = number of intermediate stops + 1
%
%   Required field of g (in addition to the Phase 1 fields):
%     cruise_speed_kmh     num   cruise speed [km/h]
%
%   Optional fields of g (defaults in brackets):
%     route_distance_km    num   total journey distance [km]                 (100)
%     n_stops              num   number of intermediate stops                (5)
%     avg_accel_ms2        num   average acceleration [m/s^2]                (0.5)
%     avg_decel_ms2        num   average service deceleration [m/s^2]        (0.7)
%     rolling_coeff        num   rolling resistance coefficient Cr [-]       (0.002)
%     drag_coeff           num   aerodynamic drag coefficient Cd [-]         (0.9)
%     frontal_area_m2      num   frontal area A [m^2]                        (10)
%     rotating_mass_factor num   equivalent mass factor for rotating parts   (1.06)
%     load_factor          num   average passenger load, 0..1                (0.7)
%     aux_power_kW         num   auxiliary power (HVAC, lighting...) [kW]    (50)
%     regen_fraction       num   fraction of available braking energy
%                                returned to the source, 0..1                (0)
%     air_density          num   air density [kg/m^3]                        (1.2)
%     co2_factor_kg_per_kWh num  CO2 emitted per kWh of INPUT energy         (by source)

    if nargin < 3 || isempty(opts)
        opts = struct();
    end
    do_plot = isfield(opts, 'plot') && opts.plot;

    %% 1. Read parameters (with defaults)
    p = read_parameters(g);

    gravity = 9.81;                                % [m/s^2]
    m       = s.train_mass_kg;                     % [kg]
    eta_pm  = g.prime_mover_efficiency;            % energy source -> prime mover output
    eta_tr  = g.transmission_efficiency;           % prime mover output -> wheel

    %% 2. Journey geometry and timing
    v       = p.cruise_speed_kmh / 3.6;            % [m/s]
    a       = p.avg_accel_ms2;
    b       = p.avg_decel_ms2;
    D       = p.route_distance_km * 1000;          % [m]
    n_seg   = p.n_stops + 1;                       % number of accel-cruise-brake segments

    d_acc    = v^2 / (2*a);                        % acceleration distance per segment [m]
    d_brk    = v^2 / (2*b);                        % braking distance per segment [m]
    d_cruise = D - n_seg * (d_acc + d_brk);        % total cruise distance [m]

    if d_cruise < 0
        error('phase2:routeTooShort', ...
              ['Route is too short for the assumed speed and number of stops. ' ...
               'Reduce n_stops or cruise_speed_kmh, or increase route_distance_km.']);
    end

    t_acc    = v / a;                              % [s] per segment
    t_brk    = v / b;                              % [s] per segment
    t_cruise = d_cruise / v;                       % [s] total
    t_total  = n_seg * (t_acc + t_brk) + t_cruise; % [s]

    %% 3. Resistance forces and work at the wheel [J]
    F_roll = p.rolling_coeff * m * gravity;                  % [N], constant
    k_aero = 0.5 * p.air_density * p.drag_coeff * p.frontal_area_m2;   % F_aero = k_aero * v^2

    % Cruise: constant speed
    E_res_cruise = (F_roll + k_aero * v^2) * d_cruise;

    % Acceleration / braking: speed grows linearly with distance, so mean(v^2) = v^2 / 2
    E_res_acc_seg = (F_roll + k_aero * v^2 / 2) * d_acc;
    E_res_brk_seg = (F_roll + k_aero * v^2 / 2) * d_brk;
    E_res_acc     = n_seg * E_res_acc_seg;
    E_res_brk     = n_seg * E_res_brk_seg;

    % Kinetic energy (including rotating masses) given to the train at each start
    KE_seg  = 0.5 * m * p.rotating_mass_factor * v^2;
    E_kin   = n_seg * KE_seg;

    % Total traction energy delivered at the wheel
    E_wheel = E_res_cruise + E_res_acc + E_kin;

    %% 4. Braking energy and regeneration [J]
    % Kinetic energy that must be removed by the brakes (resistance helps during braking)
    E_brake_avail = n_seg * max(0, KE_seg - E_res_brk_seg);
    E_regen       = p.regen_fraction * E_brake_avail;   % returned to the source side
    E_brake_loss  = E_brake_avail - E_regen;            % dissipated as heat in brakes / resistors

    %% 5. Energy chain: wheel -> prime mover -> source [J]
    E_aux    = p.aux_power_kW * 1000 * t_total;         % auxiliary energy at prime mover output
    E_tr_in  = E_wheel / eta_tr;                        % prime mover output needed for traction
    E_tr_loss = E_tr_in - E_wheel;                      % transmission losses

    E_pm_out = max(E_tr_in + E_aux - E_regen, 0);       % net prime mover output
    E_input  = E_pm_out / eta_pm;                       % energy taken from the source
    E_pm_loss = E_input - E_pm_out;                     % prime mover / conversion losses

    %% 6. Convert to kWh and compute indicators
    J2kWh = 1 / 3.6e6;
    passengers = s.passenger_capacity * p.load_factor;

    r.name = s.name;

    % Journey data
    r.journey.distance_km     = D / 1000;
    r.journey.n_stops         = p.n_stops;
    r.journey.cruise_speed_kmh = p.cruise_speed_kmh;
    r.journey.travel_time_min = t_total / 60;
    r.journey.average_speed_kmh = (D / t_total) * 3.6;
    r.journey.cruise_distance_km = d_cruise / 1000;
    r.journey.passengers      = passengers;

    % Energy breakdown [kWh]
    r.energy.input_kWh              = E_input   * J2kWh;
    r.energy.wheel_kWh              = E_wheel   * J2kWh;
    r.energy.resistance_kWh         = (E_res_cruise + E_res_acc) * J2kWh;
    r.energy.kinetic_kWh            = E_kin     * J2kWh;
    r.energy.transmission_loss_kWh  = E_tr_loss * J2kWh;
    r.energy.prime_mover_loss_kWh   = E_pm_loss * J2kWh;
    r.energy.auxiliary_kWh          = E_aux     * J2kWh;
    r.energy.brake_available_kWh    = E_brake_avail * J2kWh;
    r.energy.regenerated_kWh        = E_regen   * J2kWh;
    r.energy.brake_loss_kWh         = E_brake_loss * J2kWh;
    r.energy.net_input_kWh          = r.energy.input_kWh;

    % Efficiency
    r.efficiency.drivetrain          = eta_pm * eta_tr;
    r.efficiency.wheel_over_input    = E_wheel / E_input;           % traction energy / input energy
    r.efficiency.regen_recovery_pct  = 100 * E_regen / max(E_brake_avail, eps);

    % Specific energy
    r.specific.kWh_per_km            = r.energy.input_kWh / r.journey.distance_km;
    r.specific.kWh_per_pkm           = r.energy.input_kWh / (passengers * r.journey.distance_km);
    r.specific.MJ_per_pkm            = 3.6 * r.specific.kWh_per_pkm;
    r.specific.Wh_per_tkm            = 1000 * r.energy.input_kWh / ((m/1000) * r.journey.distance_km);

    % CO2
    r.co2.factor_kg_per_kWh = p.co2_factor_kg_per_kWh;
    r.co2.total_kg          = r.energy.input_kWh * p.co2_factor_kg_per_kWh;
    r.co2.kg_per_km         = r.co2.total_kg / r.journey.distance_km;
    r.co2.kg_per_pkm        = r.co2.total_kg / (passengers * r.journey.distance_km);

    %% 7. Consistency checks against Phase 1 limits
    F_start = m * p.rotating_mass_factor * a + F_roll;             % tractive effort at start [N]
    P_peak  = (m * p.rotating_mass_factor * a + F_roll + k_aero * v^2) * v / 1000;   % [kW] at wheel
    r.checks.start_force_kN   = F_start / 1000;
    r.checks.peak_power_kW    = P_peak;

    if F_start > s.max_adhesion_force_N
        warning('phase2:adhesion', ...
                '[%s] Required starting force (%.1f kN) exceeds adhesion limit (%.1f kN).', ...
                s.name, F_start/1000, s.max_adhesion_force_N/1000);
    end
    if P_peak > s.wheel_power_kW
        warning('phase2:power', ...
                '[%s] Peak power for the assumed acceleration (%.0f kW) exceeds wheel power (%.0f kW).', ...
                s.name, P_peak, s.wheel_power_kW);
    end

    %% 8. Report and optional plot
    print_summary(r);
    if do_plot
        plot_breakdown(r);
    end
end


%% ========================= LOCAL FUNCTIONS =========================

function p = read_parameters(g)
%READ_PARAMETERS  Read journey / resistance parameters from g and apply defaults.

    if ~isfield(g, 'cruise_speed_kmh') || ~isnumeric(g.cruise_speed_kmh) || g.cruise_speed_kmh <= 0
        error('phase2:missingField', 'Missing or invalid field: "cruise_speed_kmh".');
    end
    p.cruise_speed_kmh = g.cruise_speed_kmh;

    p.route_distance_km    = get_param(g, 'route_distance_km',    100);
    p.n_stops              = get_param(g, 'n_stops',              5);
    p.avg_accel_ms2        = get_param(g, 'avg_accel_ms2',        0.5);
    p.avg_decel_ms2        = get_param(g, 'avg_decel_ms2',        0.7);
    p.rolling_coeff        = get_param(g, 'rolling_coeff',        0.002);
    p.drag_coeff           = get_param(g, 'drag_coeff',           0.9);
    p.frontal_area_m2      = get_param(g, 'frontal_area_m2',      10);
    p.rotating_mass_factor = get_param(g, 'rotating_mass_factor', 1.06);
    p.load_factor          = get_param(g, 'load_factor',          0.7);
    p.aux_power_kW         = get_param(g, 'aux_power_kW',         50);
    p.regen_fraction       = get_param(g, 'regen_fraction',       0);
    p.air_density          = get_param(g, 'air_density',          1.2);
    p.co2_factor_kg_per_kWh = get_param(g, 'co2_factor_kg_per_kWh', ...
                                        default_co2_factor(g.energy_source));

    % Range checks
    if p.route_distance_km <= 0 || p.n_stops < 0 || p.avg_accel_ms2 <= 0 || p.avg_decel_ms2 <= 0
        error('phase2:badValue', 'Distance, acceleration and deceleration must be > 0 and n_stops >= 0.');
    end
    if p.load_factor <= 0 || p.load_factor > 1
        error('phase2:badValue', 'load_factor must be in (0, 1].');
    end
    if p.regen_fraction < 0 || p.regen_fraction > 1
        error('phase2:badValue', 'regen_fraction must be in [0, 1].');
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


function f = default_co2_factor(energy_source)
%DEFAULT_CO2_FACTOR  Rough default CO2 factor per kWh of input energy [kg CO2/kWh].
%   These are placeholder values for the model. Override them with
%   g.co2_factor_kg_per_kWh using data for your country / assumptions.

    switch lower(char(energy_source))
        case 'coal',     f = 0.34;    % thermal energy of coal
        case 'diesel',   f = 0.27;    % thermal energy of diesel fuel
        case 'grid',     f = 0.40;    % electricity, depends strongly on the grid mix
        case 'battery',  f = 0.40;    % charged from the grid
        case 'hydrogen', f = 0.20;    % depends strongly on how hydrogen is produced
        otherwise,       f = 0.40;
    end
end


function print_summary(r)
%PRINT_SUMMARY  Print the energy analysis results to the command window.

    fprintf('\n==============================================\n');
    fprintf(' PHASE 2 - ENERGY ANALYSIS\n');
    fprintf(' %s\n', r.name);
    fprintf('==============================================\n');
    fprintf(' Distance             : %.1f km (%d intermediate stops)\n', ...
            r.journey.distance_km, r.journey.n_stops);
    fprintf(' Cruise speed         : %.0f km/h\n', r.journey.cruise_speed_kmh);
    fprintf(' Travel time          : %.1f min (avg %.1f km/h)\n', ...
            r.journey.travel_time_min, r.journey.average_speed_kmh);
    fprintf(' Passengers (avg)     : %.0f\n', r.journey.passengers);
    fprintf('----------------------------------------------\n');
    fprintf(' Input energy         : %.1f kWh\n', r.energy.input_kWh);
    fprintf(' Wheel traction energy: %.1f kWh\n', r.energy.wheel_kWh);
    fprintf('   - resistance work  : %.1f kWh\n', r.energy.resistance_kWh);
    fprintf('   - kinetic energy   : %.1f kWh\n', r.energy.kinetic_kWh);
    fprintf(' Transmission loss    : %.1f kWh\n', r.energy.transmission_loss_kWh);
    fprintf(' Prime mover loss     : %.1f kWh\n', r.energy.prime_mover_loss_kWh);
    fprintf(' Auxiliary energy     : %.1f kWh\n', r.energy.auxiliary_kWh);
    fprintf(' Braking energy avail.: %.1f kWh\n', r.energy.brake_available_kWh);
    fprintf(' Regenerated energy   : %.1f kWh\n', r.energy.regenerated_kWh);
    fprintf('----------------------------------------------\n');
    fprintf(' Drivetrain efficiency: %.1f %%\n', 100*r.efficiency.drivetrain);
    fprintf(' Wheel / input energy : %.1f %%\n', 100*r.efficiency.wheel_over_input);
    fprintf(' Energy per km        : %.2f kWh/km\n', r.specific.kWh_per_km);
    fprintf(' Energy per pass.-km  : %.4f kWh/pkm (%.3f MJ/pkm)\n', ...
            r.specific.kWh_per_pkm, r.specific.MJ_per_pkm);
    fprintf(' CO2 per pass.-km     : %.4f kg/pkm\n', r.co2.kg_per_pkm);
    fprintf('==============================================\n');
end


function plot_breakdown(r)
%PLOT_BREAKDOWN  Bar chart of where the input energy goes.

    labels = {'Resistance','Kinetic (net of regen)','Transmission loss', ...
              'Prime mover loss','Auxiliary'};
    values = [r.energy.resistance_kWh, ...
              r.energy.kinetic_kWh - r.energy.regenerated_kWh, ...
              r.energy.transmission_loss_kWh, ...
              r.energy.prime_mover_loss_kWh, ...
              r.energy.auxiliary_kWh];

    figure('Name', ['Phase 2 - ' r.name], 'Color', 'w');
    bar(categorical(labels, labels), values);
    ylabel('Energy [kWh]');
    title(sprintf('%s - energy breakdown (input = %.1f kWh)', r.name, r.energy.input_kWh));
    grid on;
end