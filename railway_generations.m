function gens = railway_generations()
%RAILWAY_GENERATIONS  Parameter database of the five railway generations.
%
%   gens = railway_generations()
%
%   OUTPUT gens : struct with one field per generation, in chronological order:
%                   gens.Steam, gens.DieselElectric, gens.ElectricEMU,
%                   gens.HighSpeed, gens.SmartTrain
%
%   IMPORTANT
%   All numbers are REPRESENTATIVE ENGINEERING ESTIMATES of a typical train of each
%   class. They are NOT data of a specific real train. For a report, replace them
%   with sourced data and keep a list of references.
%
%   Common test journey (same for every generation, so results are comparable):
%     300 km with 4 intermediate stops, average load factor 0.7.
%
%   avg_accel_ms2 is a CONSTANT average acceleration used by Phase 2 and Phase 5.
%   It is chosen so that the power needed at the end of the acceleration stays
%   below the wheel power, so it is lower than the real acceleration.
%   Phase 3 (ode45) gives the more realistic acceleration.
%
%   Units: SI unless the field name says otherwise.

    %% Common test journey and operating assumptions
    route_km  = 300;      % [km] journey distance
    n_stops   = 4;        % intermediate stops
    load_fac  = 0.7;      % average passenger load factor [-]

    %% ================= 1. STEAM TRAIN =================
    g = struct();
    % --- Phase 1: architecture
    g.name                    = 'Steam Train';
    g.era                     = '19th - early 20th century';
    g.energy_source           = 'Coal';
    g.propulsion_type         = 'Steam engine';
    g.transmission_type       = 'Mechanical';
    g.braking_type            = 'Mechanical (vacuum / air brake)';
    g.control_type            = 'Manual';
    g.architecture            = 'Locomotive';
    g.automation_level        = 0;
    g.train_mass_kg           = 340e3;     % locomotive + tender + 6 coaches
    g.n_cars                  = 7;
    g.passenger_capacity      = 360;
    g.train_length_m          = 145;
    g.wheel_radius_m          = 0.95;      % driving wheel radius
    g.n_axles                 = 30;
    g.n_powered_axles         = 3;         % three coupled driving axles
    g.rated_power_kW          = 1500;      % power at the steam engine output
    g.prime_mover_efficiency  = 0.08;      % coal -> engine output (boiler + engine)
    g.transmission_efficiency = 0.90;      % rods and linkage
    g.adhesion_coeff          = 0.25;
    % --- Phase 2 to 5: journey, resistance, braking
    g.cruise_speed_kmh        = 100;
    g.max_speed_kmh           = 120;
    g.max_tractive_effort_kN  = 80;
    g.route_distance_km       = route_km;
    g.n_stops                 = n_stops;
    g.avg_accel_ms2           = 0.085;
    g.avg_decel_ms2           = 0.40;
    g.emergency_decel_ms2     = 0.70;
    g.service_buildup_s       = 3.0;
    g.emergency_buildup_s     = 5.0;
    g.rolling_coeff           = 0.003;
    g.drag_coeff              = 1.2;
    g.frontal_area_m2         = 9;
    g.rotating_mass_factor    = 1.08;      % coupling rods and large driving wheels
    g.load_factor             = load_fac;
    g.aux_power_kW            = 20;
    g.regen_fraction          = 0;
    g.electric_brake_force_kN = 0;         % no electric brake
    g.co2_factor_kg_per_kWh   = 0.34;      % per kWh of coal thermal energy (assumption)
    % --- Phase 6: reliability and signalling assumptions
    g.signalling_margin_m     = 600;
    g.failures_per_Mkm        = 80;
    g.mttr_h                  = 8;
    g.scheduled_downtime_pct  = 15;
    gens.Steam = g;

    %% ================= 2. DIESEL-ELECTRIC TRAIN =================
    g = struct();
    g.name                    = 'Diesel-Electric Train';
    g.era                     = 'Mid 20th century';
    g.energy_source           = 'Diesel';
    g.propulsion_type         = 'Diesel-electric';
    g.transmission_type       = 'Electrical (generator + traction motors)';
    g.braking_type            = 'Dynamic + pneumatic';
    g.control_type            = 'Electromechanical';
    g.architecture            = 'Locomotive';
    g.automation_level        = 1;
    g.train_mass_kg           = 430e3;     % Co-Co locomotive + 8 coaches
    g.n_cars                  = 9;
    g.passenger_capacity      = 500;
    g.train_length_m          = 190;
    g.wheel_radius_m          = 0.55;
    g.n_axles                 = 38;
    g.n_powered_axles         = 6;
    g.rated_power_kW          = 2200;      % diesel engine output
    g.prime_mover_efficiency  = 0.35;      % diesel fuel -> engine output
    g.transmission_efficiency = 0.82;      % generator + rectifier + motors + gears
    g.adhesion_coeff          = 0.30;
    g.cruise_speed_kmh        = 120;
    g.max_speed_kmh           = 140;
    g.max_tractive_effort_kN  = 190;
    g.route_distance_km       = route_km;
    g.n_stops                 = n_stops;
    g.avg_accel_ms2           = 0.075;
    g.avg_decel_ms2           = 0.50;
    g.emergency_decel_ms2     = 0.90;
    g.service_buildup_s       = 2.5;
    g.emergency_buildup_s     = 4.0;
    g.rolling_coeff           = 0.0025;
    g.drag_coeff              = 1.0;
    g.frontal_area_m2         = 10;
    g.rotating_mass_factor    = 1.06;
    g.load_factor             = load_fac;
    g.aux_power_kW            = 60;
    g.regen_fraction          = 0;         % dynamic brake energy is dissipated in resistors
    g.electric_brake_force_kN = 100;       % dynamic (rheostatic) brake
    g.co2_factor_kg_per_kWh   = 0.27;      % per kWh of diesel fuel energy (assumption)
    g.signalling_margin_m     = 500;
    g.failures_per_Mkm        = 50;
    g.mttr_h                  = 6;
    g.scheduled_downtime_pct  = 12;
    gens.DieselElectric = g;

    %% ================= 3. ELECTRIC TRAIN / EMU =================
    g = struct();
    g.name                    = 'Electric Train / EMU';
    g.era                     = 'Late 20th century';
    g.energy_source           = 'Grid';
    g.propulsion_type         = 'AC traction motor';
    g.transmission_type       = 'Power electronics (inverter + gearbox)';
    g.braking_type            = 'Regenerative + pneumatic';
    g.control_type            = 'Electronic';
    g.architecture            = 'Distributed';
    g.automation_level        = 2;
    g.train_mass_kg           = 360e3;     % 8-car EMU
    g.n_cars                  = 8;
    g.passenger_capacity      = 800;
    g.train_length_m          = 160;
    g.wheel_radius_m          = 0.46;
    g.n_axles                 = 32;
    g.n_powered_axles         = 16;        % half of the axles are driven
    g.rated_power_kW          = 3600;      % power after pantograph, transformer, converter
    g.prime_mover_efficiency  = 0.92;      % grid -> converter output
    g.transmission_efficiency = 0.88;      % inverter + motor + gearbox
    g.adhesion_coeff          = 0.25;
    g.cruise_speed_kmh        = 140;
    g.max_speed_kmh           = 160;
    g.max_tractive_effort_kN  = 270;
    g.route_distance_km       = route_km;
    g.n_stops                 = n_stops;
    g.avg_accel_ms2           = 0.16;
    g.avg_decel_ms2           = 0.90;
    g.emergency_decel_ms2     = 1.20;
    g.service_buildup_s       = 1.5;
    g.emergency_buildup_s     = 2.5;
    g.rolling_coeff           = 0.002;
    g.drag_coeff              = 0.8;
    g.frontal_area_m2         = 10;
    g.rotating_mass_factor    = 1.08;      % many driven axles
    g.load_factor             = load_fac;
    g.aux_power_kW            = 80;
    g.regen_fraction          = 0.35;
    g.electric_brake_force_kN = 220;
    g.electric_brake_power_kW = 3600;
    g.co2_factor_kg_per_kWh   = 0.40;      % grid mix, strongly country dependent (assumption)
    g.signalling_margin_m     = 400;
    g.failures_per_Mkm        = 25;
    g.mttr_h                  = 4;
    g.scheduled_downtime_pct  = 10;
    gens.ElectricEMU = g;

    %% ================= 4. HIGH-SPEED TRAIN =================
    g = struct();
    g.name                    = 'High-Speed Train';
    g.era                     = 'Late 20th - early 21st century';
    g.energy_source           = 'Grid';
    g.propulsion_type         = 'High-power AC traction motor';
    g.transmission_type       = 'Advanced inverter';
    g.braking_type            = 'Regenerative + disc brake';
    g.control_type            = 'Computer-assisted';
    g.architecture            = 'Distributed';
    g.automation_level        = 3;
    g.train_mass_kg           = 450e3;     % 8-car, 300 km/h class
    g.n_cars                  = 8;
    g.passenger_capacity      = 450;
    g.train_length_m          = 200;
    g.wheel_radius_m          = 0.46;
    g.n_axles                 = 32;
    g.n_powered_axles         = 16;
    g.rated_power_kW          = 10000;
    g.prime_mover_efficiency  = 0.93;
    g.transmission_efficiency = 0.90;
    g.adhesion_coeff          = 0.25;
    g.cruise_speed_kmh        = 300;
    g.max_speed_kmh           = 320;
    g.max_tractive_effort_kN  = 300;
    g.route_distance_km       = route_km;
    g.n_stops                 = n_stops;
    g.avg_accel_ms2           = 0.14;
    g.avg_decel_ms2           = 0.70;
    g.emergency_decel_ms2     = 1.00;
    g.service_buildup_s       = 1.5;
    g.emergency_buildup_s     = 2.5;
    g.brake_adhesion_coeff    = 0.15;      % lower wheel-rail adhesion at high speed
    g.rolling_coeff           = 0.0015;
    g.drag_coeff              = 0.6;       % streamlined nose, smooth underbody
    g.frontal_area_m2         = 9;
    g.rotating_mass_factor    = 1.06;
    g.load_factor             = load_fac;
    g.aux_power_kW            = 200;
    g.regen_fraction          = 0.50;
    g.electric_brake_force_kN = 300;
    g.electric_brake_power_kW = 9000;
    g.co2_factor_kg_per_kWh   = 0.40;
    g.signalling_margin_m     = 250;
    g.failures_per_Mkm        = 12;
    g.mttr_h                  = 3;
    g.scheduled_downtime_pct  = 8;
    gens.HighSpeed = g;

    %% ================= 5. SMART / AUTOMATED TRAIN =================
    % Automated high-speed train with sensors, ATO / ATP, predictive maintenance.
    % For a battery or hydrogen variant, change energy_source, the two
    % efficiencies and co2_factor_kg_per_kWh.
    g = struct();
    g.name                    = 'Smart / Automated Train';
    g.era                     = 'Early 21st century - present';
    g.energy_source           = 'Grid';
    g.propulsion_type         = 'Intelligent electric drive';
    g.transmission_type       = 'Digital power control (SiC inverter)';
    g.braking_type            = 'Coordinated automatic braking';
    g.control_type            = 'Automated (ATO + ATP)';
    g.architecture            = 'Distributed';
    g.automation_level        = 4;
    g.train_mass_kg           = 400e3;     % lightweight design
    g.n_cars                  = 8;
    g.passenger_capacity      = 450;
    g.train_length_m          = 200;
    g.wheel_radius_m          = 0.46;
    g.n_axles                 = 32;
    g.n_powered_axles         = 24;        % more distributed traction
    g.rated_power_kW          = 9000;
    g.prime_mover_efficiency  = 0.95;
    g.transmission_efficiency = 0.93;
    g.adhesion_coeff          = 0.25;
    g.cruise_speed_kmh        = 300;
    g.max_speed_kmh           = 320;
    g.max_tractive_effort_kN  = 300;
    g.route_distance_km       = route_km;
    g.n_stops                 = n_stops;
    g.avg_accel_ms2           = 0.15;
    g.avg_decel_ms2           = 0.70;
    g.emergency_decel_ms2     = 1.10;
    g.service_buildup_s       = 1.0;
    g.emergency_buildup_s     = 2.0;
    g.brake_adhesion_coeff    = 0.15;
    g.rolling_coeff           = 0.0013;
    g.drag_coeff              = 0.5;
    g.frontal_area_m2         = 9;
    g.rotating_mass_factor    = 1.06;
    g.load_factor             = load_fac;
    g.aux_power_kW            = 150;       % optimised HVAC and auxiliaries
    g.regen_fraction          = 0.60;
    g.electric_brake_force_kN = 320;
    g.electric_brake_power_kW = 8400;
    g.co2_factor_kg_per_kWh   = 0.40;
    g.signalling_margin_m     = 100;
    g.failures_per_Mkm        = 8;
    g.mttr_h                  = 2;
    g.scheduled_downtime_pct  = 6;
    gens.SmartTrain = g;

    %% Consistency check of the data set
    check_generations(gens);
end


%% ========================= LOCAL FUNCTIONS =========================

function check_generations(gens)
%CHECK_GENERATIONS  Warn if the parameters of a generation are inconsistent with the phase models.
%   Checks:
%     1. cruise speed <= design speed limit
%     2. peak wheel power of the assumed average acceleration <= wheel power (Phase 2 check)
%     3. the journey is long enough for the assumed accelerate-cruise-brake segments
%     4. powered axles <= total axles

    keys = fieldnames(gens);
    for i = 1:numel(keys)
        g = gens.(keys{i});

        v     = g.cruise_speed_kmh / 3.6;
        m     = g.train_mass_kg;
        a     = g.avg_accel_ms2;
        b     = g.avg_decel_ms2;
        wheel = g.rated_power_kW * g.transmission_efficiency;           % [kW]

        % 1. speed limit
        if g.cruise_speed_kmh > g.max_speed_kmh
            warning('railway:speedLimit', '[%s] cruise_speed_kmh is above max_speed_kmh.', g.name);
        end

        % 2. peak power at the end of a constant-acceleration phase
        F_roll = g.rolling_coeff * m * 9.81;
        k_aero = 0.5 * 1.2 * g.drag_coeff * g.frontal_area_m2;
        P_peak = (m * g.rotating_mass_factor * a + F_roll + k_aero * v^2) * v / 1000;   % [kW]
        if P_peak > wheel
            warning('railway:peakPower', ...
                    '[%s] Peak power %.0f kW for avg_accel_ms2 = %.3f exceeds wheel power %.0f kW.', ...
                    g.name, P_peak, a, wheel);
        end

        % 3. journey length
        d_seg = v^2 / (2 * a) + v^2 / (2 * b);                          % [m]
        if (g.n_stops + 1) * d_seg > g.route_distance_km * 1000
            warning('railway:routeTooShort', ...
                    '[%s] The route is too short for %d accelerate-cruise-brake segments.', ...
                    g.name, g.n_stops + 1);
        end

        % 4. axles
        if g.n_powered_axles > g.n_axles
            warning('railway:axles', '[%s] n_powered_axles is larger than n_axles.', g.name);
        end
    end
end