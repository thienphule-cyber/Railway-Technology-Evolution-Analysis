function s = phase1_system_definition(g)
%PHASE1_SYSTEM_DEFINITION  Define and validate the architecture of one railway generation.
%
%   s = phase1_system_definition(g)
%
%   INPUT  g : struct with the parameters of one generation (see required fields below)
%   OUTPUT s : struct with architecture description and derived quantities
%
%   Required fields of g:
%     name                    char   generation name, e.g. 'Steam Train'
%     era                     char   e.g. '19th - early 20th century'
%     energy_source           char   'Coal' | 'Diesel' | 'Grid' | 'Battery' | 'Hydrogen'
%     propulsion_type         char   e.g. 'Steam engine', 'Diesel-electric', 'AC traction motor'
%     transmission_type       char   e.g. 'Mechanical', 'Electrical', 'Power electronics'
%     braking_type            char   e.g. 'Mechanical', 'Regenerative + pneumatic'
%     control_type            char   e.g. 'Manual', 'Electronic', 'Automated'
%     architecture            char   'Locomotive' | 'Distributed'
%     automation_level        num    0 (manual) ... 4 (fully automated)
%     train_mass_kg           num    total train mass [kg]
%     n_cars                  num    number of cars (including locomotive if any)
%     passenger_capacity      num    number of passengers
%     train_length_m          num    train length [m]
%     wheel_radius_m          num    wheel radius [m]
%     n_axles                 num    total number of axles
%     n_powered_axles         num    number of powered axles
%     rated_power_kW          num    rated power at the traction source output [kW]
%     prime_mover_efficiency  num    energy source -> mechanical/electrical power, 0..1
%     transmission_efficiency num    power source -> wheel, 0..1
%
%   Optional fields of g:
%     adhesion_coeff          num    wheel-rail adhesion coefficient (default 0.25)

    %% 1. Validate input
    g = validate_input(g);

    %% 2. Basic architecture description
    s.name              = g.name;
    s.era               = g.era;
    s.energy_source     = g.energy_source;
    s.propulsion_type   = g.propulsion_type;
    s.transmission_type = g.transmission_type;
    s.braking_type      = g.braking_type;
    s.control_type      = g.control_type;
    s.architecture      = g.architecture;
    s.automation_level  = g.automation_level;

    %% 3. Copy physical parameters (used by later phases)
    s.train_mass_kg      = g.train_mass_kg;
    s.n_cars             = g.n_cars;
    s.passenger_capacity = g.passenger_capacity;
    s.train_length_m     = g.train_length_m;
    s.wheel_radius_m     = g.wheel_radius_m;
    s.n_axles            = g.n_axles;
    s.n_powered_axles    = g.n_powered_axles;
    s.rated_power_kW     = g.rated_power_kW;

    %% 4. Derived quantities
    gravity = 9.81;                                   % [m/s^2]

    % Powered-axle ratio: 1 means every axle is driven (fully distributed traction)
    s.powered_axle_ratio = g.n_powered_axles / g.n_axles;

    % Overall drivetrain efficiency (energy source -> wheel)
    s.drivetrain_efficiency = g.prime_mover_efficiency * g.transmission_efficiency;

    % Power available at the wheel rim [kW]
    s.wheel_power_kW = g.rated_power_kW * g.transmission_efficiency;

    % Power-to-weight ratio [kW/t]
    s.power_to_weight_kW_per_t = g.rated_power_kW / (g.train_mass_kg / 1000);

    % Mass per passenger [kg/passenger]
    s.mass_per_passenger_kg = g.train_mass_kg / g.passenger_capacity;

    % Passenger density along the train [passenger/m]
    s.passenger_density_per_m = g.passenger_capacity / g.train_length_m;

    % Adhesion limit of tractive effort [N]
    % Assumes equal axle load, so adhesive weight = mass * powered-axle ratio
    s.adhesion_coeff        = g.adhesion_coeff;
    s.adhesive_mass_kg      = g.train_mass_kg * s.powered_axle_ratio;
    s.max_adhesion_force_N  = g.adhesion_coeff * s.adhesive_mass_kg * gravity;

    % Wheel angular speed per unit train speed [rad/m]
    s.wheel_omega_per_speed = 1 / g.wheel_radius_m;

    %% 5. Energy chain description (used for reporting and Phase 2)
    s.energy_chain = build_energy_chain(g.energy_source, g.architecture);

    %% 6. Control level description
    s.automation_label = automation_label(g.automation_level);

    %% 7. Print summary
    print_summary(s);
end


%% ========================= LOCAL FUNCTIONS =========================

function g = validate_input(g)
%VALIDATE_INPUT  Check required fields, value ranges and set defaults.

    required_text = {'name','era','energy_source','propulsion_type', ...
                     'transmission_type','braking_type','control_type','architecture'};
    required_num  = {'automation_level','train_mass_kg','n_cars','passenger_capacity', ...
                     'train_length_m','wheel_radius_m','n_axles','n_powered_axles', ...
                     'rated_power_kW','prime_mover_efficiency','transmission_efficiency'};

    for k = 1:numel(required_text)
        f = required_text{k};
        if ~isfield(g, f) || ~(ischar(g.(f)) || isstring(g.(f)))
            error('phase1:missingField', 'Missing or invalid text field: "%s".', f);
        end
    end

    for k = 1:numel(required_num)
        f = required_num{k};
        if ~isfield(g, f) || ~isnumeric(g.(f)) || ~isscalar(g.(f)) || ~isfinite(g.(f))
            error('phase1:missingField', 'Missing or invalid numeric field: "%s".', f);
        end
    end

    % Positive values
    positive = {'train_mass_kg','n_cars','passenger_capacity','train_length_m', ...
                'wheel_radius_m','n_axles','rated_power_kW'};
    for k = 1:numel(positive)
        if g.(positive{k}) <= 0
            error('phase1:badValue', 'Field "%s" must be > 0.', positive{k});
        end
    end

    % Efficiencies in (0, 1]
    eff = {'prime_mover_efficiency','transmission_efficiency'};
    for k = 1:numel(eff)
        if g.(eff{k}) <= 0 || g.(eff{k}) > 1
            error('phase1:badValue', 'Field "%s" must be in (0, 1].', eff{k});
        end
    end

    % Axle consistency
    if g.n_powered_axles < 0 || g.n_powered_axles > g.n_axles
        error('phase1:badValue', 'n_powered_axles must be between 0 and n_axles.');
    end
    if g.n_powered_axles == 0
        error('phase1:badValue', 'n_powered_axles must be at least 1.');
    end

    % Automation level
    if ~ismember(g.automation_level, 0:4)
        error('phase1:badValue', 'automation_level must be an integer from 0 to 4.');
    end

    % Architecture type
    if ~ismember(lower(char(g.architecture)), {'locomotive','distributed'})
        error('phase1:badValue', 'architecture must be "Locomotive" or "Distributed".');
    end

    % Optional field: adhesion coefficient
    if ~isfield(g, 'adhesion_coeff') || isempty(g.adhesion_coeff)
        g.adhesion_coeff = 0.25;
    end
    if g.adhesion_coeff <= 0 || g.adhesion_coeff > 1
        error('phase1:badValue', 'adhesion_coeff must be in (0, 1].');
    end
end


function chain = build_energy_chain(energy_source, architecture)
%BUILD_ENERGY_CHAIN  Return the energy conversion chain as a cell array of stages.

    switch lower(char(energy_source))
        case 'coal'
            chain = {'Coal','Boiler','Steam','Piston','Connecting rod','Wheel','Rail'};
        case 'diesel'
            chain = {'Diesel','Diesel engine','Generator','Power electronics', ...
                     'Traction motor','Gear','Wheel','Rail'};
        case 'grid'
            if strcmpi(architecture, 'distributed')
                chain = {'Grid','Pantograph','Transformer','Converter','Inverter', ...
                         'AC motor','Gearbox','Wheel','Rail'};
            else
                chain = {'Grid','Pantograph','Transformer','Converter', ...
                         'Traction motor','Gearbox','Wheel','Rail'};
            end
        case 'battery'
            chain = {'Battery','Power electronics','Traction motor','Gearbox','Wheel','Rail'};
        case 'hydrogen'
            chain = {'Hydrogen tank','Fuel cell','Power electronics','Traction motor', ...
                     'Gearbox','Wheel','Rail'};
        otherwise
            chain = {char(energy_source),'Traction system','Wheel','Rail'};
    end
end


function label = automation_label(level)
%AUTOMATION_LABEL  Convert automation level (0..4) to a text label.

    labels = {'Manual control', ...
              'Electromechanical control', ...
              'Electronic control', ...
              'Computer-assisted control', ...
              'Automatic / autonomous operation'};
    label = labels{level + 1};
end


function print_summary(s)
%PRINT_SUMMARY  Print a readable summary of the system definition to the command window.

    fprintf('\n==============================================\n');
    fprintf(' PHASE 1 - SYSTEM DEFINITION\n');
    fprintf(' %s (%s)\n', s.name, s.era);
    fprintf('==============================================\n');
    fprintf(' Energy source        : %s\n', s.energy_source);
    fprintf(' Propulsion type      : %s\n', s.propulsion_type);
    fprintf(' Transmission         : %s\n', s.transmission_type);
    fprintf(' Braking              : %s\n', s.braking_type);
    fprintf(' Control              : %s\n', s.control_type);
    fprintf(' Architecture         : %s\n', s.architecture);
    fprintf(' Automation level     : %d (%s)\n', s.automation_level, s.automation_label);
    fprintf('----------------------------------------------\n');
    fprintf(' Train mass           : %.1f t\n', s.train_mass_kg/1000);
    fprintf(' Cars                 : %d\n', s.n_cars);
    fprintf(' Passenger capacity   : %d\n', s.passenger_capacity);
    fprintf(' Train length         : %.1f m\n', s.train_length_m);
    fprintf(' Powered axles        : %d / %d (ratio %.2f)\n', ...
            s.n_powered_axles, s.n_axles, s.powered_axle_ratio);
    fprintf(' Rated power          : %.0f kW\n', s.rated_power_kW);
    fprintf(' Wheel power          : %.0f kW\n', s.wheel_power_kW);
    fprintf(' Drivetrain efficiency: %.1f %%\n', 100*s.drivetrain_efficiency);
    fprintf(' Power-to-weight      : %.2f kW/t\n', s.power_to_weight_kW_per_t);
    fprintf(' Mass per passenger   : %.0f kg\n', s.mass_per_passenger_kg);
    fprintf(' Max adhesion force   : %.1f kN\n', s.max_adhesion_force_N/1000);
    fprintf(' Energy chain         : %s\n', strjoin(s.energy_chain, ' -> '));
    fprintf('==============================================\n');
end