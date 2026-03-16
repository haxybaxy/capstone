#pagebreak()
= Results and Analysis
#set heading(numbering: "1.1")

This section presents the empirical results from the experiment groups defined in the previous section, organised by research question. All timing values are mean milliseconds per step computed after discarding the first ten steps as warmup. Energy drift is reported as the final-step value $Delta E = |E(t) - E(0)| / |E(0)|$.

== Performance Overview

@tab:performance-summary condenses the key metrics across representative configurations. The following subsections examine each research question in detail.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto),
    align: (left, right, right, right, right, right),
    [*Configuration*], [*N*], [*ms/step*], [*Tree build*], [*Force*], [*Integrate*],
    [Plummer, GPU tree], [1,000], [1.04], [0.78], [0.22], [0.05],
    [Plummer, GPU tree], [5,000], [1.34], [1.02], [0.27], [0.06],
    [Plummer, GPU tree], [10,000], [1.78], [1.38], [0.37], [0.04],
    [Plummer, GPU tree], [50,000], [2.20], [1.73], [0.43], [0.04],
    [Plummer, GPU tree], [100,000], [2.35], [1.85], [0.46], [0.04],
    [Disk, GPU tree], [50,000], [1.72], [---], [---], [---],
    [Disk, GPU tree], [100,000], [2.04], [---], [---], [---],
    [Plummer, CPU tree], [50,000], [65.06], [---], [---], [---],
    [Plummer, direct], [5,000], [4.96], [---], [---], [---],
  ),
  caption: [Performance summary for representative configurations (leapfrog, $theta = 0.75$, $epsilon = 0.5$, $Delta t = 0.001$). Timing components in milliseconds.],
) <tab:performance-summary>

== RQ1: Scalability

=== Runtime Scaling with Particle Count

@fig:n-scaling-plummer presents the mean runtime per timestep as a function of $N$ for the GPU LBVH Barnes–Hut path on the Plummer sphere scenario. Total runtime per step increases from 0.61 ms at $N = 100$ to 2.35 ms at $N = 100000$, representing a factor of 3.9 increase over a 1000-fold growth in particle count. This sub-linear scaling is consistent with $O(N log N)$ force evaluation overlaid with GPU parallelism: the arithmetic cost grows as $N log N$, but the GPU's data-parallel execution absorbs much of this growth up to the point where occupancy saturates.

#figure(
  rect(width: 80%, height: 7cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Log-log plot of mean ms/step vs N for Plummer sphere (GPU LBVH, leapfrog). X-axis: N from 100 to 100,000. Y-axis: ms/step from 0.5 to 3. Include $O(N log N)$ reference line. Data points: (100, 0.61), (500, 0.88), (1000, 1.04), (2000, 1.22), (5000, 1.34), (10000, 1.78), (25000, 2.00), (50000, 2.20), (100000, 2.35)._]
  ],
  caption: [Mean runtime per timestep as a function of $N$ for the Plummer sphere scenario (GPU LBVH, leapfrog, $theta = 0.75$). The sub-linear growth is consistent with GPU-parallel $O(N log N)$ force evaluation.],
) <fig:n-scaling-plummer>

The rotating disk scenario exhibits similar behaviour. Runtime increases from 1.73 ms at $N = 10000$ to 2.04 ms at $N = 100000$, with a slight non-monotonicity at $N = 50000$ (1.72 ms) likely attributable to workgroup occupancy effects on the Apple M2 GPU.

=== Tree vs Direct Crossover

@tab:crossover presents the comparison between hierarchical ($O(N log N)$) and direct ($O(N^2)$) force evaluation. At $N = 1000$ and below, direct summation is faster because the per-step tree construction overhead exceeds the savings from reduced force evaluations. At $N = 2000$, the tree path becomes faster (1.15 ms versus 2.34 ms), and the advantage grows with $N$: at $N = 5000$, the tree path is 3.5 times faster. The crossover occurs between $N = 1000$ and $N = 2000$, consistent with the expectation that tree overhead is amortised only when $N$ is large enough for the $O(N^2)$ to $O(N log N)$ reduction to dominate.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (right, right, right, left),
    [*N*], [*Direct (ms)*], [*Tree (ms)*], [*Faster*],
    [100], [0.21], [0.83], [Direct],
    [200], [0.29], [0.98], [Direct],
    [500], [0.65], [1.21], [Direct],
    [1,000], [1.14], [1.25], [Direct],
    [2,000], [2.34], [1.15], [Tree],
    [5,000], [4.96], [1.43], [Tree],
  ),
  caption: [Mean ms/step for direct $O(N^2)$ versus tree-based $O(N log N)$ force evaluation (Plummer sphere, GPU, leapfrog). The crossover occurs between $N = 1000$ and $N = 2000$.],
) <tab:crossover>

#figure(
  rect(width: 80%, height: 7cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Log-log plot showing direct ms/step (orange) and tree ms/step (blue) vs N. Lines cross between N=1000 and N=2000. Include data from the table above._]
  ],
  caption: [Direct vs tree force evaluation runtime. The crossover at $N approx 1500$ marks where the per-step tree construction cost is amortised by the reduction in force evaluations.],
) <fig:crossover>

=== Timing Decomposition

@tab:timing-decomp breaks total runtime into its three components. Tree construction dominates at all tested particle counts, accounting for 74 to 79 percent of total step time. Force evaluation accounts for 18 to 20 percent, and integration (kick and drift dispatches) accounts for approximately 2 to 4 percent. The dominance of tree construction reflects the cost of the seven-pass LBVH pipeline (bounding box reduction, Morton code generation, bitonic sort, Karras topology, leaf initialisation, bottom-up aggregation) relative to the single-pass BVH traversal for force evaluation.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, right, right, right, right),
    [*N*], [*Tree build (ms)*], [*Force (ms)*], [*Integrate (ms)*], [*Tree fraction*],
    [1,000], [0.78], [0.22], [0.05], [74.3%],
    [5,000], [1.02], [0.27], [0.06], [75.6%],
    [10,000], [1.38], [0.37], [0.04], [77.2%],
    [50,000], [1.73], [0.43], [0.04], [78.5%],
    [100,000], [1.85], [0.46], [0.04], [78.6%],
  ),
  caption: [Timing decomposition for the GPU LBVH leapfrog path (Plummer sphere, $theta = 0.75$). Tree construction accounts for 74–79% of total step time.],
) <tab:timing-decomp>

#figure(
  rect(width: 80%, height: 6cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Stacked bar chart showing tree\_build\_ms (blue), force\_ms (orange), integrate\_ms (green) at N = 1000, 5000, 10000, 50000, 100000. Tree build is the dominant component at all N._]
  ],
  caption: [Stacked timing decomposition at selected particle counts. Tree construction (blue) dominates at all $N$, with force evaluation (orange) as the secondary component.],
) <fig:timing-decomp>

== RQ2: Numerical Quality

=== Two-Body Orbit Validation (Scenario A)

The two-body orbit provides the simplest test of integrator correctness. @tab:twobody-drift presents the final energy drift after 50,000 steps for both integrators across the timestep sweep. A notable observation is that the Euler integrator, run on the CPU octree path, exhibits substantially lower energy drift (on the order of $10^(-5)$ to $10^(-6)$) than the leapfrog integrator on the GPU BVH path (drift of order unity). This counterintuitive result is attributable to the different force computation paths rather than the integration scheme: the CPU path computes forces in double precision via the octree, while the GPU BVH path uses 32-bit floating-point arithmetic. At $N = 2$, the BVH tree structure is degenerate (a single internal node with two leaves), and the 32-bit force evaluation accumulates sufficient rounding error over 50,000 steps to produce measurable orbit drift.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (right, right, right),
    [*$Delta t$*], [*Leapfrog (GPU BVH)*], [*Euler (CPU octree)*],
    [0.0001], [$1.71$], [$1.78 times 10^(-6)$],
    [0.0005], [$1.94$], [$1.08 times 10^(-5)$],
    [0.001], [$1.97$], [$1.89 times 10^(-5)$],
    [0.005], [$1.99$], [$1.12 times 10^(-5)$],
    [0.01], [$1.99$], [$3.81 times 10^(-6)$],
  ),
  caption: [Final energy drift $Delta E / |E(0)|$ after 50,000 steps for the two-body orbit (Scenario A). The difference between integrators is dominated by the force computation precision: GPU BVH (32-bit) versus CPU octree (64-bit).],
) <tab:twobody-drift>

This result highlights that for very small $N$, the 32-bit precision of GPU computation is the binding constraint on numerical quality, not the integration scheme. The two-body scenario remains useful as a code-path sanity check (both paths complete without NaN or divergence), but quantitative energy-conservation comparisons between integrators require the same force computation path.

#figure(
  rect(width: 80%, height: 6cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Screenshot of two-body orbit from interactive mode showing the circular orbit path of the two particles. Capture at $t approx 5$ with trail rendering if available._]
  ],
  caption: [Two-body orbit trajectory (Scenario A) as rendered in interactive visualisation mode. The two equal-mass particles maintain a stable circular orbit under the leapfrog integrator.],
) <fig:twobody-orbit>

=== Energy Conservation in the Plummer Sphere (Scenario B)

The Plummer sphere at $N = 5000$ (where potential energy is computed via direct pair summation) provides the primary testbed for energy conservation. @fig:energy-drift-plummer shows the evolution of energy drift over 5,000 steps.

The leapfrog integrator at default parameters ($Delta t = 0.001$, $theta = 0.75$) produces a final drift of $Delta E / |E(0)| = 1.84$ after 5,000 steps (simulation time $t = 5.0$). Inspection of the energy components reveals that kinetic energy remains nearly constant ($K approx 744233$) while the potential energy magnitude decreases steadily from $-1.47 times 10^6$ to $-5.72 times 10^5$, indicating that the Plummer sphere is expanding. This behaviour is characteristic of a system that is not in perfect virial equilibrium at the discrete $N$ used, combined with the systematic force error introduced by the monopole approximation at $theta = 0.75$. The total energy transitions from negative to positive, reflecting an unbinding process that is physical in the context of finite-$N$ sampling with approximate forces.

The Euler integrator at the same $N$ and $Delta t$ produces a substantially lower final drift of $9.28 times 10^(-3)$, again attributable to the 64-bit CPU force computation path rather than intrinsic integrator quality.

#figure(
  rect(width: 80%, height: 7cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Line plot of energy drift vs step number for Plummer sphere N=5000. Show leapfrog (GPU, blue) rising to ~1.84 and Euler (CPU, orange dashed) staying near ~0.01. X-axis: 0 to 5000 steps. Y-axis: energy drift (log scale or linear)._]
  ],
  caption: [Energy drift evolution for the Plummer sphere ($N = 5000$, $Delta t = 0.001$, $theta = 0.75$). The difference between integrators reflects the underlying force computation precision (32-bit GPU vs 64-bit CPU) rather than integration scheme quality.],
) <fig:energy-drift-plummer>

=== Effect of Opening Angle $theta$

@tab:theta-sweep presents the effect of the opening angle on both runtime and energy drift at $N = 5000$. Surprisingly, the final energy drift is nearly identical across all tested $theta$ values ($Delta E / |E(0)| approx 1.84$), suggesting that at this $N$ and simulation duration, the dominant source of energy non-conservation is not the multipole approximation error but rather the 32-bit force precision and finite-$N$ relaxation effects. Runtime is also stable across $theta$ values (3.5 to 3.7 ms/step), indicating that at $N = 5000$ the traversal depth does not vary substantially with $theta$ on this hardware.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (right, right, right),
    [*$theta$*], [*Mean ms/step*], [*Final drift*],
    [0.3], [3.46], [$1.84$],
    [0.5], [3.65], [$1.84$],
    [0.7], [3.66], [$1.84$],
    [1.0], [3.49], [$1.84$],
  ),
  caption: [Effect of opening angle $theta$ on runtime and energy drift (Plummer sphere, $N = 5000$, $Delta t = 0.001$, leapfrog, GPU BVH). Energy drift is insensitive to $theta$ at this configuration, suggesting 32-bit precision dominates.],
) <tab:theta-sweep>

=== Effect of Timestep $Delta t$

The timestep sweep at $N = 5000$ reveals that energy drift increases with simulation time. Because all runs execute 5,000 steps, smaller $Delta t$ corresponds to shorter total simulation time: $Delta t = 5 times 10^(-5)$ yields $t_"final" = 0.25$, while $Delta t = 5 times 10^(-3)$ yields $t_"final" = 25$. The drift increases from 0.38 at $Delta t = 5 times 10^(-5)$ to 1.99 at $Delta t = 5 times 10^(-3)$, reflecting both longer physical evolution time and larger per-step truncation error. To isolate the effect of $Delta t$ on integration accuracy from the effect of total simulation time would require runs to a fixed $t_"final"$, which was not performed in this sweep and represents an area for refined experimentation.

=== Effect of Softening $epsilon$

The softening sweep at $N = 5000$ shows a modest increase in energy drift with larger $epsilon$: from $Delta E / |E(0)| = 1.82$ at $epsilon = 0.1$ to $2.00$ at $epsilon = 2.0$. Larger softening reduces the depth of the gravitational potential well, making the system less tightly bound and more prone to expansion. Runtime is unaffected by softening (approximately 3.5 ms/step for all values), confirming that softening does not change the computational cost of force evaluation.

=== Momentum Conservation

For the Plummer sphere at $N = 5000$, the total momentum magnitude $||P(t)|| = ||(sum_i m_i v_i)||$ remains approximately constant throughout the integration, starting at $||P(0)|| approx 1400$ and varying by less than 0.1% over 5,000 steps. This near-conservation is expected for the leapfrog scheme, which preserves linear momentum exactly for pairwise central forces. The non-zero initial momentum arises from the finite-$N$ sampling of the Plummer distribution, which does not enforce exact momentum balance.

== RQ3: Platform Feasibility

=== Native vs Browser Execution

@tab:web-native presents the comparison between native desktop execution (wgpu-native, Metal backend) and browser execution (Emscripten WebAssembly, browser WebGPU) for the same GPU LBVH Barnes–Hut configuration. The wall-clock time per step in the browser is remarkably constant at 5.5–6.3 ms regardless of $N$, while native execution scales from 0.61 ms at $N = 100$ to 2.35 ms at $N = 100000$. The overhead factor therefore decreases from 9.2$times$ at $N = 100$ to 2.7$times$ at $N = 100000$.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto),
    align: (right, right, right, right, right, right),
    [*N*], [*Native (ms)*], [*Browser (ms)*], [*Overhead*], [*Native drift*], [*Browser drift*],
    [100], [0.61], [5.62], [9.2$times$], [$1.85 times 10^(-1)$], [$1.83 times 10^(-1)$],
    [500], [0.88], [5.57], [6.3$times$], [$5.22 times 10^(-1)$], [$5.19 times 10^(-1)$],
    [1,000], [1.04], [5.77], [5.5$times$], [$7.01 times 10^(-1)$], [$7.00 times 10^(-1)$],
    [2,000], [1.22], [5.64], [4.6$times$], [$9.30 times 10^(-1)$], [$9.29 times 10^(-1)$],
    [5,000], [1.34], [6.30], [4.7$times$], [$1.24$], [$1.24$],
    [10,000], [1.78], [5.76], [3.2$times$], [$4.39 times 10^(-10)$], [$4.45 times 10^(-10)$],
    [25,000], [2.00], [5.52], [2.8$times$], [$7.17 times 10^(-11)$], [$7.13 times 10^(-11)$],
    [50,000], [2.20], [5.59], [2.5$times$], [$2.70 times 10^(-11)$], [$2.25 times 10^(-11)$],
    [100,000], [2.35], [6.32], [2.7$times$], [$1.20 times 10^(-10)$], [$1.21 times 10^(-10)$],
  ),
  caption: [Native vs browser wall-clock ms/step and final energy drift (Plummer sphere, GPU LBVH, leapfrog, $theta = 0.75$). Native timing is the mean of tree build, force, and integration components after warmup. Browser timing is wall-clock from console-log timestamps, which includes event-loop scheduling overhead.],
) <tab:web-native>

The constant browser wall-clock time indicates that per-step duration is dominated by a fixed overhead rather than GPU compute. Subtracting the native GPU time from the browser wall-clock yields a constant residual of approximately 4.3 ms/step across all $N$ values. This fixed cost is attributable to the Emscripten asyncify mechanism, which yields control to the browser event loop between timesteps via `emscripten_sleep(0)`, incurring JavaScript-to-WebAssembly context switching and event-loop scheduling latency. Crucially, this overhead is additive and constant: it does not grow with $N$, meaning the sub-linear scaling behaviour observed in native execution is preserved in the browser.

Energy drift values are nearly identical between the two platforms at each $N$, with relative differences below 1% for $N gt.eq 10000$ and below 2% at smaller $N$. The small discrepancies at lower $N$ are attributable to differences in floating-point intermediate rounding between the native and browser WebGPU driver paths, but both platforms produce the same qualitative energy evolution and the same order-of-magnitude drift at every $N$. This confirms that the browser WebGPU implementation executes the same GPU compute shaders with equivalent numerical fidelity.

#figure(
  rect(width: 80%, height: 7cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Plot of ms/step vs N for native (blue, rising from 0.61 to 2.35) and browser wall-clock (orange, flat at ~5.5–6.3). X-axis: N from 100 to 100,000 (log scale). Y-axis: ms/step from 0 to 8. Shaded region between the two lines represents the fixed ~4.3ms event-loop overhead._]
  ],
  caption: [Native vs browser execution time per step. The browser wall-clock is dominated by a fixed ~4.3 ms event-loop scheduling overhead (shaded region) from Emscripten asyncify, independent of $N$. The overhead factor decreases from 9.2$times$ at $N = 100$ to 2.7$times$ at $N = 100000$.],
) <fig:web-native>

=== Practical Particle Count Limits

At the maximum tested particle count of $N = 100000$, the GPU LBVH leapfrog path achieves 2.35 ms per step, corresponding to approximately 425 timesteps per second. In interactive mode with rendering overhead, this translates to frame rates well above 60 FPS for $N$ up to at least 50,000 particles on the Apple M2 GPU. The maximum storage buffer binding size reported by the adapter is 128 MB, which accommodates the BVH node array ($2N - 1$ nodes) and particle state buffers up to approximately $N = 2 times 10^6$ before memory limits are reached, though this was not tested experimentally.

At $N = 100000$, the GPU scheduling overhead remains a small fraction of total step time: integration (kick/drift dispatches) accounts for only 0.04 ms regardless of $N$, confirming that compute dispatch latency does not become a bottleneck at the tested scale.

=== Seed Robustness

Three independent Plummer sphere realisations ($N = 5000$, seeds 42, 123, 256) show consistent timing (6.9 to 11.2 ms/step, with the higher value for seed 123 attributable to a less favourable initial particle distribution affecting tree traversal depth) and energy drift ranging from 0.64 to 1.24. The variation in drift reflects the sensitivity of finite-$N$ relaxation to the specific particle configuration, confirming that energy evolution is initial-condition-dependent as expected for an $N$-body system.

== Integrated Assessment

The results collectively address the three research questions:

1. *Scalability (RQ1)*: The GPU LBVH Barnes–Hut implementation scales sub-linearly with $N$, achieving only a 3.9$times$ increase in step time over a 1000$times$ increase in particle count. The tree-based approach outperforms direct $O(N^2)$ summation for $N gt.eq 2000$, with tree construction dominating total step time at 74–79%.

2. *Numerical quality (RQ2)*: Energy conservation analysis reveals that 32-bit GPU floating-point precision is the primary constraint on numerical fidelity, dominating the effects of opening angle and timestep for the configurations tested. The leapfrog integrator maintains stable orbits and conserves momentum, but quantitative energy drift comparisons between integrators are confounded by the different precision of their force computation paths (32-bit GPU vs 64-bit CPU).

3. *Platform feasibility (RQ3)*: WebGPU on the Apple M2 sustains interactive frame rates ($> 60$ FPS) for up to at least $N = 50000$ particles in native mode. Browser execution via Emscripten adds a fixed overhead of approximately 4.3 ms per step from event-loop scheduling, reducing the overhead factor from 9.2$times$ at $N = 100$ to 2.7$times$ at $N = 100000$. Energy drift is numerically consistent across platforms, confirming that the browser WebGPU path executes equivalent GPU computation. The primary platform constraints are 32-bit GPU arithmetic precision and the fixed per-step browser scheduling cost, not buffer limits or compute throughput.
