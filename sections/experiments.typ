#pagebreak()
= Experiments
#set heading(numbering: "1.1")

This section specifies the hardware environment and the concrete experiment configurations used to evaluate the solver against the three research questions defined in the methodology. All experiments use the headless batch mode of the simulation, eliminating rendering overhead and producing deterministic CSV logs for post-processing.

== Experimental Platform

All experiments were executed on a single workstation whose configuration is summarised in @tab:platform. The GPU adapter name and WebGPU backend are reported by the application at startup and recorded alongside each run.

#figure(
  table(
    columns: (auto, auto),
    align: (left, left),
    [*Component*], [*Specification*],
    [GPU], [Apple M2 (unified memory, Metal backend via wgpu-native)],
    [CPU], [Apple M2 (8-core, 4 performance + 4 efficiency)],
    [RAM], [8 GB unified memory],
    [Operating System], [macOS (Darwin 25.2.0)],
    [WebGPU Backend], [wgpu-native (Rust-based, Metal backend 0x5)],
    [Compiler], [Apple Clang, C++20, Release build (-O2)],
    [Build System], [CMake + FetchContent (pinned dependency versions)],
    [Timing], [`std::chrono::high_resolution_clock` (ms precision)],
    [Diagnostic Precision], [CPU double-precision (64-bit) for energy and momentum],
  ),
  caption: [Hardware and software configuration for all experiments. The Apple M2 integrated GPU uses Metal as the underlying graphics API, accessed through the wgpu-native WebGPU implementation.],
) <tab:platform>

Each run is invoked from the command line as:

```
./galaxysim --headless --scenario <S> --N <N> --dt <dt>
  --theta <θ> --softening <ε> --integrator <I>
  --tree <T> --force-method <F> --steps <steps>
  --seed <seed> --export <output.csv>
```

The CSV output records twelve columns per step: step number, simulation time, kinetic energy, potential energy (zero when $N > 5000$), total energy, energy drift, three momentum components ($p_x$, $p_y$, $p_z$), and three timing components (tree build, force evaluation, and integration in milliseconds). Timing values are averaged over all steps after discarding the first ten as warmup.

== Experiment Groups

The experiments are organised into five groups, each targeting one or more research questions. @tab:experiment-matrix provides a summary.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, left, left, left, left),
    [*Group*], [*Scenario*], [*Variable*], [*Runs*], [*RQ*],
    [1: Two-body validation], [A (two-body)], [$Delta t times$ integrator], [10], [RQ2],
    [2a: N-scaling], [B (Plummer)], [$N in {100 "–" 10^5}$], [9], [RQ1, RQ3],
    [2b: Theta sweep], [B (Plummer)], [$theta in {0.3, 0.5, 0.7, 1.0}$], [4], [RQ2],
    [2c: Timestep sweep], [B (Plummer)], [$Delta t in {5 times 10^(-5) "–" 5 times 10^(-3)}$], [5], [RQ2],
    [2d: Integrator comparison], [B (Plummer)], [Euler vs leapfrog], [1], [RQ2],
    [2e: Softening sweep], [B (Plummer)], [$epsilon in {0.1 "–" 2.0}$], [5], [RQ2],
    [2f: Seed robustness], [B (Plummer)], [seed $in {42, 123, 256}$], [3], [RQ3],
    [3a: Disk N-scaling], [C (disk)], [$N in {10^4 "–" 10^5}$], [5], [RQ1, RQ3],
    [4: Direct vs tree crossover], [B (Plummer)], [force method $times N$], [12], [RQ1],
    [5: Native vs browser], [B (Plummer)], [execution platform $times N$], [9], [RQ3],
  ),
  caption: [Summary of experiment groups, swept variables, and research questions addressed. A total of 63 individual runs were executed.],
) <tab:experiment-matrix>

=== Group 1: Two-Body Orbit Validation (Scenario A)

This group verifies integrator correctness using the two-body orbit configuration ($N = 2$, $m = 1000$ each). The timestep $Delta t$ is swept over ${0.0001, 0.0005, 0.001, 0.005, 0.01}$ for both the leapfrog and Euler integrators, yielding ten runs of 50,000 steps each. All runs use the GPU BVH tree path with $theta = 0.75$, $epsilon = 0.5$, and seed 42. The primary diagnostic is the energy drift $Delta E(t) / ( |E(0)| )$ over the full integration, with secondary attention to momentum magnitude and orbit stability.

=== Group 2: Plummer Sphere Parameter Sweeps (Scenario B)

The Plummer sphere scenario provides the primary quantitative testbed because it has symmetric initial conditions and known analytic equilibrium properties. Six sub-groups isolate individual parameter effects.

Sub-group 2a (N-scaling) varies $N$ over ${100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000}$ with all other parameters fixed at defaults ($Delta t = 0.001$, $theta = 0.75$, $epsilon = 0.5$, leapfrog, GPU LBVH). Each run executes 1,000 steps. This sub-group directly addresses RQ1 (scalability) and RQ3 (feasibility at large $N$).

Sub-groups 2b through 2e isolate the effects of individual parameters at fixed $N = 5000$ (chosen because potential energy is computed at this size, enabling full energy tracking). Sub-group 2b sweeps $theta in {0.3, 0.5, 0.7, 1.0}$; sub-group 2c sweeps $Delta t in {5 times 10^(-5), 10^(-4), 5 times 10^(-4), 10^(-3), 5 times 10^(-3)}$; sub-group 2d compares Euler to leapfrog at $Delta t = 0.001$; and sub-group 2e sweeps $epsilon in {0.1, 0.25, 0.5, 1.0, 2.0}$. All parameter-sweep runs execute 5,000 steps.

Sub-group 2f repeats the default configuration ($N = 5000$, $Delta t = 0.001$, $theta = 0.75$) with three seeds (42, 123, 256) for 1,000 steps to assess timing and diagnostic variability across stochastic initial conditions.

=== Group 3: Rotating Disk Scaling (Scenario C)

The disk scenario targets large-$N$ scalability and qualitative morphological assessment. Sub-group 3a scales $N$ over ${10000, 25000, 50000, 75000, 100000}$ with default parameters and 1,000 steps each, measuring runtime scaling and timing decomposition. Morphological evolution (spiral arm formation, bar instability) is assessed through interactive-mode visualisation at selected timesteps and reported descriptively.

#figure(
  grid(
    columns: 2,
    gutter: 12pt,
    figure(image("../graphics/fig_disk_t0.png", width: 100%), caption: [_(a)_ $t = 0$], numbering: none),
    figure(image("../graphics/fig_disk_t1.png", width: 100%), caption: [_(b)_ $t = 1$], numbering: none),
    figure(image("../graphics/fig_disk_t5.png", width: 100%), caption: [_(c)_ $t = 5$], numbering: none),
    figure(image("../graphics/fig_disk_t10.png", width: 100%), caption: [_(d)_ $t = 10$], numbering: none),
  ),
  caption: [Morphological evolution of the rotating exponential disk (Scenario C, $N = 50000$). Panels show the face-on particle distribution at four simulation times, illustrating the development of spiral structure.],
) <fig:disk-evolution>

=== Group 4: Direct vs Tree Crossover

To identify the particle count at which hierarchical force evaluation becomes faster than direct $O(N^2)$ summation, this group runs both `--force-method direct` and `--force-method tree` at $N in {100, 200, 500, 1000, 2000, 5000}$ using the Plummer sphere scenario. Each configuration runs for 500 steps with default physics parameters.

=== Group 5: Native vs Browser Execution

To evaluate WebGPU's portability promise (RQ3), the same GPU LBVH Barnes–Hut configuration used in Group 2a is executed in a browser environment via Emscripten. The native C++/wgpu-native binary is cross-compiled with Emscripten using `-sASYNCIFY` (to yield to the browser event loop each timestep) and `-sALLOW_MEMORY_GROWTH=1`. The resulting WebAssembly module runs in a headless Chromium instance on the same hardware, using the browser's WebGPU implementation (backed by the same Metal driver). Particle counts sweep $N in {100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000}$ with all other parameters matching Group 2a ($Delta t = 0.001$, $theta = 0.75$, $epsilon = 0.5$, leapfrog, GPU LBVH, 1000 steps).

Two timing metrics are collected: (1) wall-clock milliseconds per step, computed from the console-log timestamps emitted every 100 steps, which captures all overhead including event-loop scheduling and Emscripten asyncify yields; and (2) GPU-side timing from the sampled per-step tree/force/integrate breakdowns logged to the console. Energy drift at the final step is compared to the native run at each $N$ to verify numerical consistency across platforms. A GPU command-buffer flush was required after each compute dispatch in the browser path to prevent command coalescing from stalling the pipeline; this fix had no effect on native execution.
