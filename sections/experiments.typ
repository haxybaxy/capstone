#pagebreak()
= Experiments
#set heading(numbering: "1.1")

This section specifies the hardware environment and experiment configurations used to evaluate the solver against the three research questions. All experiments run in headless batch mode, eliminating rendering overhead and producing deterministic CSV logs for post-processing.

== Experimental Platform

All experiments were executed on a single workstation whose configuration is summarised in @tab:platform. The GPU adapter name and WebGPU backend are reported by the application at startup and recorded alongside each run.

#figure(
  table(
    columns: (auto, auto),
    align: (left, left),
    [*Component*], [*Specification*],
    [GPU / CPU], [Apple M2 (8-core GPU, 4P+4E CPU, unified memory)],
    [RAM], [16 GB unified memory],
    [Operating System], [macOS 26.2 (Darwin 25.2.0)],
    [Native WebGPU], [wgpu-native (Rust-based, Metal backend) via WebGPU-distribution v0.2.0],
    [Native WebGPU (alt.)], [Dawn (Google, Metal backend) via WebGPU-distribution v0.2.0],
    [Browser (Chromium)], [Chrome 146.0.7680.178 (arm64)],
    [Browser (WebKit)], [Safari 26.2],
    [Metal baseline], [UniSim @unisim (native Metal Barnes–Hut)],
    [Compiler], [Apple Clang 17.0.0, C++20, Release (`-O3 -DNDEBUG`)],
    [Timing], [CPU wall-clock via `std::chrono::high_resolution_clock` (sub-µs resolution), bracketing backend-specific GPU fences: `wgpuQueueOnSubmittedWorkDone` + poll (wgpu-native), buffer-map fence (Dawn / Emscripten). `--sync-timing` for total ms/step; `--benchmark-passes` for per-component breakdown.],
  ),
  caption: [Hardware and software configuration. All experiments run on the same Apple M2 system. The four WebGPU implementations and the native Metal baseline all use the same Metal graphics driver, isolating the overhead of each abstraction layer.],
) <tab:platform>

Each run is executed in headless batch mode, with all simulation parameters (scenario type, $N$, $Delta t$, $theta$, softening $epsilon$, integrator, tree type, force method, step count, and random seed) specified at invocation. The CSV output records twelve columns per step: step number, simulation time, kinetic energy, potential energy (zero when $N > 5000$), total energy, energy drift, three momentum components ($p_x$, $p_y$, $p_z$), and three timing components (tree build, force evaluation, and integration in milliseconds).

== Benchmarking Protocol

We follow established practices for GPU benchmarking @maczan2026. Each configuration is warmed up by disregarding the first 50 steps since during that time pipeline compilation, buffer allocation, and caching are all stabilising. Timing is then collected over the next 100 steps and reported as mean $plus.minus$ standard deviation, with the 95% confidence interval via the $t$-distribution. The coefficient of variation ($"CV" = sigma \/ mu$) quantifies run-to-run stability; configurations with $"CV" > 10%$ are flagged and investigated. For the cross-backend comparison (Group 6), positions are held frozen — forces are computed but not applied — to isolate dispatch and scheduling overhead from physics-dependent variation in tree structure. This frozen-state protocol ensures all backends execute identical GPU workloads, so measured differences reflect only the WebGPU implementation overhead and host-side scheduling.

== Experiment Groups

The experiments are organised into seven groups, each targeting one or more research questions or characterising numerical quality (@tab:experiment-matrix). Exact command-line invocations for reproducing each group are provided in the Appendix.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, left, left, left, left),
    [*Group*], [*Scenario*], [*Variable*], [*Runs*], [*RQ*],
    [1: Two-body validation], [A (two-body)], [$Delta t$], [5], [Qual.],
    [2a: N-scaling], [B (Plummer)], [$N in {100 "–" 10^5}$], [9], [RQ1, RQ3],
    [2b: Theta sweep], [B (Plummer)], [$theta in {0.3, 0.5, 0.7, 1.0}$], [4], [Qual.],
    [2c: Timestep sweep], [B (Plummer)], [$Delta t in {5 times 10^(-5) "–" 5 times 10^(-3)}$], [5], [Qual.],
    [2e: Softening sweep], [B (Plummer)], [$epsilon in {0.1 "–" 2.0}$], [5], [Qual.],
    [3a: Disk N-scaling], [C (disk)], [$N in {10^4 "–" 10^5}$], [5], [RQ1, RQ3],
    [4: Direct vs tree crossover], [B (Plummer)], [force method $times N$], [12], [RQ1],
    [5: Native vs browser], [B (Plummer)], [execution platform $times N$], [9], [RQ3],
    [6: Cross-backend comparison], [B (Plummer)], [WebGPU impl $times N$], [12], [RQ2, RQ3],
    [7: LBVH pass breakdown], [B (Plummer)], [per-pass timing $times N$], [5], [RQ1],
  ),
  caption: [Summary of experiment groups, swept variables, and targets. Qual. denotes numerical quality characterisation, reported as a secondary observation rather than a primary research question.],
) <tab:experiment-matrix>

=== Group 1: Two-Body Orbit Validation (Scenario A)

This group verifies integrator correctness using the two-body orbit configuration ($N = 2$, $m = 1000$ each). The timestep $Delta t$ is swept over ${0.0001, 0.0005, 0.001, 0.005, 0.01}$ using the leapfrog integrator, yielding five runs of 50,000 steps each. All runs use the GPU BVH tree path with $theta = 0.75$, $epsilon = 0.5$, and seed 42. The primary diagnostic is the energy drift $( Delta E(t) ) / ( |E(0)| )$ over the full integration, with secondary attention to momentum magnitude and orbit stability.

=== Group 2: Plummer Sphere Parameter Sweeps (Scenario B)

The Plummer sphere is the primary quantitative testbed because of its symmetric initial conditions and known analytic equilibrium properties. Four sub-groups isolate individual parameter effects.

Sub-group 2a (N-scaling) varies $N$ over ${100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000}$ with all other parameters fixed at defaults ($Delta t = 0.001$, $theta = 0.75$, $epsilon = 0.5$, leapfrog, GPU LBVH). Each run executes 1,000 steps. This sub-group directly addresses RQ1 (scalability) and RQ3 (feasibility at large $N$).

Sub-groups 2b, 2c, and 2e isolate the effects of individual parameters at fixed $N = 5000$ (chosen because potential energy is computed at this size, enabling full energy tracking). Sub-group 2b sweeps $theta in {0.3, 0.5, 0.7, 1.0}$; sub-group 2c sweeps $Delta t in {5 times 10^(-5), 10^(-4), 5 times 10^(-4), 10^(-3), 5 times 10^(-3)}$; and sub-group 2e sweeps $epsilon in {0.1, 0.25, 0.5, 1.0, 2.0}$. All parameter-sweep runs execute 5,000 steps.

=== Group 3: Rotating Disk Scaling (Scenario C)

The disk scenario targets large-$N$ scalability and qualitative morphological assessment. Sub-group 3a scales $N$ over ${10000, 25000, 50000, 75000, 100000}$ with default parameters and 1,000 steps each, measuring runtime scaling and timing decomposition. Morphological evolution (spiral arm formation, bar instability) is assessed through interactive-mode visualisation at selected timesteps (@fig:disk-evolution) and reported descriptively.

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

To identify the particle count at which hierarchical force evaluation becomes faster than direct $O(N^2)$ summation, this group runs both the direct summation and tree-based force evaluation at $N in {100, 200, 500, 1000, 2000, 5000}$ using the Plummer sphere scenario. Each configuration runs for 500 steps with default physics parameters.

=== Group 5: Native vs Browser Execution

To test WebGPU's portability promise (RQ3), we run the same GPU LBVH Barnes–Hut configuration from Group 2a in a browser via Emscripten @emscripten. The native C++ codebase is cross-compiled to WebAssembly (WASM) with two key flags: `-sASYNCIFY`, which transforms synchronous C++ code into asynchronous form so that the simulation can yield control to the browser's event loop between timesteps (required because browsers do not allow long-running synchronous code on the main thread), and `-sALLOW_MEMORY_GROWTH=1`, which permits the WebAssembly linear memory to grow dynamically as particle count increases rather than requiring a fixed-size allocation at compile time. The resulting WebAssembly module runs in a headless Chromium instance on the same hardware, using the browser's WebGPU implementation (backed by the same Metal driver). Particle counts sweep $N in {100, 500, 1000, 2000, 5000, 10000, 25000, 50000, 100000}$ with all other parameters matching Group 2a ($Delta t = 0.001$, $theta = 0.75$, $epsilon = 0.5$, leapfrog, GPU LBVH, 1000 steps).

Two timing metrics are collected: (1) wall-clock milliseconds per step, computed from the console-log timestamps emitted every 100 steps, which captures all overhead including event-loop scheduling and Emscripten asyncify yields; and (2) GPU-side timing from the sampled per-step tree/force/integrate breakdowns logged to the console. Energy drift at the final step is compared to the native run at each $N$ to verify numerical consistency across platforms. A GPU command-buffer flush was required after each compute dispatch in the browser path to prevent command coalescing from stalling the pipeline; this fix had no effect on native execution.

=== Group 6: Cross-Backend Implementation Comparison

To measure the performance impact of the WebGPU implementation layer itself, we run the same simulation across four WebGPU implementations on the same Apple M2, all backed by the Metal graphics API: wgpu-native (the default native backend), Dawn @dawn (Google's WebGPU implementation), Chrome (browser WebGPU via Emscripten), and Safari (browser WebGPU via Emscripten). This design isolates the overhead introduced by each implementation from the GPU compute itself, since all four paths execute identical WGSL shaders on the same Metal driver. Recent work on WebGPU dispatch overhead has shown that implementation choice within the same backend can produce up to 2.2$times$ variation in per-dispatch cost @maczan2026, making this comparison directly relevant to understanding the platform overhead reported in Group 5. Particle counts sweep $N in {1000, 10000, 100000}$ using the frozen-state benchmarking protocol described above (50 warmup steps, 100 measured steps, positions held constant). For each implementation and $N$, the mean milliseconds per step, standard deviation, 95% confidence interval, and coefficient of variation are reported.

=== Group 7: LBVH Construction Pass Breakdown

To identify which phases of the LBVH construction pipeline dominate total tree-build time, per-pass timing is collected at $N in {1000, 5000, 10000, 50000, 100000}$ using CPU-side timing markers placed between each compute dispatch. The six LBVH sub-passes (global AABB reduction, Morton code generation, radix sort, Karras topology construction, leaf initialisation, bottom-up aggregation) and the force evaluation pass are timed individually. This decomposition reveals whether the sort phase, the topology construction, or the bottom-up aggregation is the primary bottleneck, and how the balance shifts with $N$.
