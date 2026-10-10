%% MAIN  Railway Technology Evolution Analysis
%  5 generations x 7 phases:
%    Steam -> Diesel-Electric -> Electric/EMU -> High-Speed -> Smart/Automated
%
%  Phases 1-6 run for every generation. Phase 7 compares all generations.
%
%  The phase files are NOT modified. Two known bugs are fixed in temporary copies
%  that are created in the folder "_patched" and placed first on the MATLAB path:
%    - phase3: event function built with deal() (ode45 error)
%    - phase6: bar() call with 8 values for 7 labels (only when plotting)
%  If a phase file is already fixed, the corresponding patch is skipped.

clear; clc; close all;

%% 0. Configuration
cfg.plot_each_phase       = false;   % true = draw the figures of phases 2-6 for every generation (many windows)
cfg.phase5_compare_levels = false;   % true = Phase 5 also compares the controllers of level 0..4
cfg.plot_comparison       = true;    % Phase 7 comparison figures
cfg.export_csv            = 'comparison.csv';          % '' = do not export
cfg.save_mat              = 'railway_results.mat';     % '' = do not save
cfg.phase6_weights        = [];      % [] = defaults, or a struct with 7 weights (sum = 1)
cfg.ti_weights            = [];      % [] = defaults, or a struct with 5 weights (sum = 1)
%   Example:
%   cfg.ti_weights = struct('energy', 0.30, 'performance', 0.20, 'safety', 0.20, ...
%                           'automation', 0.15, 'reliability', 0.15);

%% 1. Paths and runtime patches
root = fileparts(mfilename('fullpath'));
if isempty(root)
    root = pwd;
end
addpath(genpath(root));
patch_phase_files(root);

%% 2. Load the parameter database
gens = railway_generations();
keys = fieldnames(gens)';
n    = numel(keys);

%% 3. Run phases 1-6 for every generation
R = struct();
t_all = tic;

for i = 1:n
    key = keys{i};
    g   = gens.(key);

    fprintf('\n##############################################################\n');
    fprintf('# GENERATION %d / %d : %s\n', i, n, g.name);
    fprintf('##############################################################\n');

    try
        plot_opt = struct('plot', cfg.plot_each_phase);

        % Phase 1: system definition
        s = phase1_system_definition(g);

        % Phase 2: energy analysis
        p2 = phase2_energy_analysis(g, s, plot_opt);

        % Phase 3: propulsion and dynamics
        p3 = phase3_propulsion_dynamics(g, s, plot_opt);

        % Phase 4: braking and safety
        p4 = phase4_braking_safety(g, s, plot_opt);

        % Phase 5: control and automation
        o5 = struct('plot', cfg.plot_each_phase, ...
                    'compare_levels', cfg.phase5_compare_levels);
        p5 = phase5_control_automation(g, s, o5);

        % Phase 6: performance and efficiency (combines phases 2-5)
        res = struct('p2', p2, 'p3', p3, 'p4', p4, 'p5', p5);
        o6  = struct('plot', cfg.plot_each_phase);
        if ~isempty(cfg.phase6_weights)
            o6.weights = cfg.phase6_weights;
        end
        p6 = phase6_performance_efficiency(g, s, res, o6);

    catch ME
        fprintf(2, '\nGeneration "%s" (%s) failed: %s\n', key, g.name, ME.message);
        rethrow(ME);
    end

    R.(key) = struct('p1', s, 'p2', p2, 'p3', p3, 'p4', p4, 'p5', p5, 'p6', p6);
end

%% 4. Phase 7: technology evolution comparison
o7 = struct('plot', cfg.plot_comparison, 'order', {keys});
if ~isempty(cfg.export_csv)
    o7.export_csv = cfg.export_csv;
end
if ~isempty(cfg.ti_weights)
    o7.weights = cfg.ti_weights;
end

r7 = phase7_evolution_comparison(R, o7);

%% 5. Short result overview
fprintf('\n==============================================\n');
fprintf(' RESULT OVERVIEW (model-based indices)\n');
fprintf('==============================================\n');
for i = 1:n
    fprintf(' %-26s  TI = %.3f   (rank %d)\n', r7.names{i}, r7.technology_index(i), r7.rank(i));
end
fprintf('----------------------------------------------\n');
fprintf(' Total run time: %.1f s\n', toc(t_all));

%% 6. Save
if ~isempty(cfg.save_mat)
    save(cfg.save_mat, 'R', 'r7', 'gens', 'cfg');
    fprintf(' Results saved to: %s\n', cfg.save_mat);
end


%% ========================= LOCAL FUNCTIONS =========================

function patch_phase_files(root)
%PATCH_PHASE_FILES  Create fixed copies of phase3 and phase6 in <root>/_patched.
%   The original files are never modified. A patch is applied only if the known
%   faulty code is found in the original file.

    patch_dir = fullfile(root, '_patched');
    if ~exist(patch_dir, 'dir')
        mkdir(patch_dir);
    end
    n_patched = 0;

    % ---- Phase 3: event function with deal()
    name = 'phase3_propulsion_dynamics.m';
    src  = find_original(root, name);
    txt  = fileread(src);
    pat  = '@\(t,\s*y\)\s*deal\(y\(2\)\s*-\s*v_target,\s*true,\s*1\)';
    dst  = fullfile(patch_dir, name);

    if ~isempty(regexp(txt, pat, 'once'))
        txt = regexprep(txt, pat, '@(t, y) speed_event(t, y, v_target)');
        extra = strjoin({ ...
            'function [value, isterminal, direction] = speed_event(~, y, v_target)', ...
            '%SPEED_EVENT  Terminal event: speed reaches the target value (rising crossing).', ...
            '    value      = y(2) - v_target;', ...
            '    isterminal = 1;', ...
            '    direction  = 1;', ...
            'end'}, newline);
        txt = [txt, newline, newline, extra, newline];
        write_text(dst, txt);
        n_patched = n_patched + 1;
        fprintf(' Patch applied (copy): %s\n', name);
    elseif exist(dst, 'file')
        delete(dst);      % original is already fixed: remove the stale copy
    end

    % ---- Phase 6: bar() with 8 values for 7 labels (plot only)
    name = 'phase6_performance_efficiency.m';
    src  = find_original(root, name);
    txt  = fileread(src);
    bad  = '[vals, r.overall_index]';
    dst  = fullfile(patch_dir, name);

    if contains(txt, bad)
        txt = strrep(txt, bad, 'vals');
        write_text(dst, txt);
        n_patched = n_patched + 1;
        fprintf(' Patch applied (copy): %s\n', name);
    elseif exist(dst, 'file')
        delete(dst);
    end

    if n_patched > 0
        addpath(patch_dir, '-begin');
    end
    rehash;
    clear functions;
end


function src = find_original(root, name)
%FIND_ORIGINAL  Locate the original phase file (ignoring the _patched folder).

    d = dir(fullfile(root, '**', name));
    d = d(~contains({d.folder}, '_patched'));
    if isempty(d)
        error('main:missingFile', 'File "%s" was not found under %s.', name, root);
    end
    src = fullfile(d(1).folder, d(1).name);
end


function write_text(path, txt)
%WRITE_TEXT  Write a text file.

    fid = fopen(path, 'w');
    if fid < 0
        error('main:writeFailed', 'Cannot write file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, txt);
end