# References

This file lists general literature relevant to the models used in this project, and tells where the project still needs sourced data.

> The parameter values in `railway_generations.m` are representative estimates and are **not** taken from these references. Before using the results in a report, replace them with sourced data for specific trains and cite the exact source and page. Check every entry below against the original publication before citing it.

## Railway engineering and vehicle dynamics

1. Hay, W. W. (1982). *Railroad Engineering* (2nd ed.). John Wiley & Sons.
2. Profillidis, V. A. (2014). *Railway Management and Engineering* (4th ed.). Ashgate.
3. Iwnicki, S. (Ed.) (2006). *Handbook of Railway Vehicle Dynamics*. CRC Press.
4. Wickens, A. H. (2003). *Fundamentals of Rail Vehicle Dynamics: Guidance and Stability*. Swets & Zeitlinger.

## Running resistance (Phase 3, Phase 2)

5. Davis, W. J. (1926). The tractive resistance of electric locomotives and cars. *General Electric Review*, 29.
6. Rochard, B. P., & Schmid, F. (2000). A review of methods to measure and calculate train resistances. *Proceedings of the Institution of Mechanical Engineers, Part F: Journal of Rail and Rapid Transit*, 214(4), 185-199.

## Electric traction and energy

7. Steimel, A. (2008). *Electric Traction: Motive Power and Energy Supply*. Oldenbourg Industrieverlag.
8. International Energy Agency (2019). *The Future of Rail*. IEA, Paris.

## High-speed train aerodynamics

9. Raghunathan, R. S., Kim, H.-D., & Setoguchi, T. (2002). Aerodynamics of high-speed railway train. *Progress in Aerospace Sciences*, 38(6-7), 469-514.
10. Baker, C. (2014). A review of train aerodynamics, Part 1 - Fundamentals, and Part 2 - Applications. *The Aeronautical Journal*, 118(1201).

## Train control and automation (Phase 5)

11. IEC 62290-1. *Railway applications - Urban guided transport management and command/control systems - Part 1: System principles and fundamental concepts* (defines grades of automation GoA0 to GoA4).
12. IEEE Std 1474.1. *IEEE Standard for Communications-Based Train Control (CBTC) Performance and Functional Requirements*.

## Numerical methods (MATLAB `ode45`)

13. Shampine, L. F., & Reichelt, M. W. (1997). The MATLAB ODE Suite. *SIAM Journal on Scientific Computing*, 18(1), 1-22.
14. Dormand, J. R., & Prince, P. J. (1980). A family of embedded Runge-Kutta formulae. *Journal of Computational and Applied Mathematics*, 6(1), 19-26.

## Data still to be sourced

| Parameter group | Used in | Status |
|-----------------|---------|--------|
| Train mass, length, capacity, axle layout | Phase 1 | Representative estimate |
| Power, prime mover and transmission efficiency | Phases 1, 2 | Representative estimate |
| Rolling and drag coefficients, frontal area | Phases 2, 3, 4, 5 | Representative estimate |
| Braking deceleration, build-up and reaction times | Phase 4 | Representative estimate |
| Controller parameters per automation level | Phase 5 | Modelling assumption |
| Failure rate, MTTR, scheduled downtime | Phase 6 | Modelling assumption |
| Signalling margin | Phase 6 | Modelling assumption |
| CO2 factors per kWh of input energy | Phases 2, 6 | Placeholder, depends on country / fuel / grid mix |
| Score reference values and weights | Phases 6, 7 | Modelling assumption |