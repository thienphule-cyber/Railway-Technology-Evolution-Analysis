# Railway Technology Evolution Analysis

A MATLAB project that analyses how a railway system evolved across five technology generations, using the same seven-phase engineering pipeline for each generation:

```
Steam -> Diesel-Electric -> Electric / EMU -> High-Speed -> Smart / Automated
```

The goal is not a historical timeline. It is an engineering comparison: for each generation the model computes energy use, dynamics, braking, control quality, performance and reliability, and then shows which technical indicators improved at each step and why.

> **Important:** all parameters in `railway_generations.m` are representative engineering estimates, not data of a specific real train. All scores and indices are model-based, not official railway ratings. See [Assumptions and limitations](#assumptions-and-limitations).

## Pipeline

| Phase | File | Question answered |
|-------|------|-------------------|
| 1 | `phase1_system_definition.m` | How is the train built? |
| 2 | `phase2_energy_analysis.m` | Where does the energy go? |
| 3 | `phase3_propulsion_dynamics.m` | How does the train move? (`ode45`) |
| 4 | `phase4_braking_safety.m` | How does the train stop? (`ode45`) |
| 5 | `phase5_control_automation.m` | How well is the train controlled? |
| 6 | `phase6_performance_efficiency.m` | How well does the whole system perform? |
| 7 | `phase7_evolution_comparison.m` | Why did the technology change? |

Phases 1-6 run once per generation. Phase 7 compares all generations and computes the Technology Index:

```
TI = w_E * E + w_P * P + w_S * S + w_A * A + w_R * R,    sum(w) = 1
```

where E, P, S, A, R are the energy, performance, safety, automation and reliability scores from Phase 6.

## Requirements

- MATLAB R2020b or newer (the GUI uses `uifigure`; `xline`/`yline` need R2018b+)
- No additional toolboxes are required

## Repository structure

```
RailwayEvolution/
├── main.m                           % command-line pipeline (5 generations x 7 phases)
├── railway_gui.m                    % graphical interface
├── railway_generations.m            % parameter database of the 5 generations
├── phase1_system_definition.m
├── phase2_energy_analysis.m
├── phase3_propulsion_dynamics.m
├── phase4_braking_safety.m
├── phase5_control_automation.m
├── phase6_performance_efficiency.m
├── phase7_evolution_comparison.m
├── README.md
├── LICENSE.md
├── references.md
└── .gitignore
```

## Usage

### Command line

```matlab
main
```

Runs all five generations through phases 1-6, runs the Phase 7 comparison, shows the comparison figures, and writes `comparison.csv` and `railway_results.mat`.

Options are set in the configuration block at the top of `main.m`, for example:

```matlab
cfg.plot_each_phase       = false;   % figures for phases 2-6 of every generation
cfg.phase5_compare_levels = false;   % compare controllers of automation level 0..4
cfg.ti_weights = struct('energy', 0.30, 'performance', 0.20, 'safety', 0.20, ...
                        'automation', 0.15, 'reliability', 0.15);
```

### Graphical interface

```matlab
railway_gui
```

- Select a generation and edit its numeric parameters in the table.
- **Run selected generation** runs phases 1-6 and shows the results in tabs.
- **Run all + compare (Phase 7)** runs everything and shows the Technology Index, category scores and the comparison table.
- **Export comparison CSV** saves the comparison table.

### Running a single phase

```matlab
gens = railway_generations();
g = gens.HighSpeed;

s  = phase1_system_definition(g);
p2 = phase2_energy_analysis(g, s, struct('plot', true));
p3 = phase3_propulsion_dynamics(g, s, struct('plot', true));
```

## Known issue: runtime patches

Two known bugs in the phase files are fixed at runtime by `main.m` in temporary copies stored in `_patched/`. The original files are not modified.

- `phase3_propulsion_dynamics.m`: the `ode45` event function built with `deal(...)` raises *"The number of outputs should match the number of inputs"*.
- `phase6_performance_efficiency.m`: `bar(...)` receives 8 values for 7 labels (only when plotting).

Run `main` once before `railway_gui` so that `_patched/` exists, or fix the two files by hand. If a phase file is already fixed, `main.m` skips the corresponding patch.

## Assumptions and limitations

- Parameters in `railway_generations.m` are representative estimates. Replace them with sourced data for any serious analysis, and list the sources in `references.md`.
- The same test journey is used for every generation (300 km, 4 intermediate stops, load factor 0.7), so the results are comparable.
- `avg_accel_ms2` is a constant average acceleration used by Phases 2 and 5. It is deliberately lower than the real acceleration. Phase 3 gives the more realistic acceleration from the `ode45` simulation.
- The train is modelled as a point mass on a straight track. Curve resistance, tunnel effects, speed-dependent adhesion and signalling dynamics are not modelled.
- Reliability values, controller parameters, reaction times, signalling margins, CO2 factors, score reference values and all weights are modelling assumptions.
- The Technology Index, safety index, automation index and category scores are model-based engineering indices. They are not official railway ratings.
- The three grid-powered generations share the same CO2 factor (0.40 kg/kWh), which in reality depends strongly on the country and the electricity mix.

## Extending the model

- Change or add a generation: edit `railway_generations.m`. Every generation needs all Phase 1 fields plus `cruise_speed_kmh`. The other parameters have defaults.
- Battery or hydrogen variant: copy the Smart / Automated entry, change `energy_source`, the two efficiencies and `co2_factor_kg_per_kWh`.
- Change the weights: see `cfg.ti_weights` and `cfg.phase6_weights` in `main.m`.

## License

Released under the MIT License. See [LICENSE.md](LICENSE.md).

## References

See [references.md](references.md).