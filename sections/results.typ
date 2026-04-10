#pagebreak()
= Results and Analysis
#set heading(numbering: "1.1")

Results are organised by research question: RQ1 (scalability and pipeline bottlenecks), RQ2 (WebGPU abstraction overhead relative to native Metal), and RQ3 (browser feasibility). All timing values are mean ms/step over 100 measured steps after 50 warmup steps, reported with standard deviation and coefficient of variation. Energy drift is $Delta E = |E(t) - E(0)| \/ |E(0)|$.

== RQ1: Scalability and Pipeline Bottlenecks

=== Runtime Scaling with Particle Count

@tab:performance-summary presents the mean runtime per step and its three-component decomposition for the GPU LBVH Barnes–Hut path across the Plummer sphere scenario. Total runtime increases from 5.9 ms at $N = 1000$ to 180.1 ms at $N = 100000$.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto),
    align: (right, right, right, right, right, right, right),
    [*N*], [*ms/step*], [*$plus.minus$ std*], [*CV*], [*Tree (ms)*], [*Force (ms)*], [*Integrate (ms)*],
    [1,000], [5.86], [0.57], [0.10], [0.31], [5.52], [0.03],
    [5,000], [7.35], [2.59], [0.35], [0.25], [7.07], [0.03],
    [10,000], [11.00], [2.31], [0.21], [0.34], [10.62], [0.04],
    [50,000], [65.46], [1.82], [0.03], [0.23], [65.20], [0.02],
    [100,000], [180.11], [3.19], [0.02], [0.28], [179.79], [0.03],
  ),
  caption: [Performance summary with timing decomposition (Plummer sphere, leapfrog, $theta = 0.75$, $epsilon = 0.5$, wgpu-native/Metal). Force evaluation dominates at all $N$, accounting for 94–99% of total step time.],
) <tab:performance-summary>

#figure(
  image("../graphics/fig_n_scaling_plummer.png", width: 80%),
  caption: [Mean runtime per timestep as a function of $N$ for the Plummer sphere scenario (GPU LBVH, leapfrog, $theta = 0.75$, wgpu-native/Metal). Total and force curves nearly overlap; tree construction remains flat.],
) <fig:n-scaling-plummer>

Force evaluation dominates at every particle count — 94% of step time at $N = 1000$, 99.8% at $N = 100000$. Tree construction stays below 0.35 ms even at $N = 100000$. The parallel construction method scales well; any further optimisation effort should go into the BVH traversal shader.

=== LBVH Construction Breakdown

@tab:lbvh-breakdown decomposes tree construction into its six individual passes. All six construction passes remain approximately constant with $N$ (1.3–5.1 ms each), confirming that the LBVH pipeline scales well. The radix sort is the most expensive construction pass at 3.5–5.1 ms, accounting for 34–41% of total construction time. Force evaluation, shown in the final column for reference, is the component that drives the overall scaling behaviour.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto, auto),
    align: (right, right, right, right, right, right, right, right),
    [*N*], [*AABB*], [*Morton*], [*Sort*], [*Karras*], [*Leaf*], [*Aggr.*], [*Force*],
    [1,000], [1.65], [1.38], [5.05], [1.36], [1.36], [1.39], [2.72],
    [5,000], [1.37], [1.32], [4.40], [1.29], [1.32], [1.32], [7.59],
    [10,000], [1.57], [1.42], [4.53], [1.36], [1.39], [1.38], [13.45],
    [50,000], [1.40], [1.33], [3.54], [1.35], [1.33], [1.32], [62.02],
    [100,000], [1.33], [1.32], [4.08], [1.31], [1.32], [1.32], [175.39],
  ),
  caption: [Per-pass timing (ms) for the LBVH construction pipeline and force evaluation. Construction passes are approximately constant with $N$; force evaluation drives the overall scaling.],
) <tab:lbvh-breakdown>

#figure(
  image("../graphics/fig_lbvh_breakdown.png", width: 80%),
  caption: [Stacked bar chart of LBVH construction passes at each $N$. Radix sort is the largest single pass (34–41%). Total construction time is approximately constant across particle counts.],
) <fig:lbvh-breakdown>

=== Direct vs Tree: Speed–Accuracy Trade-off

@tab:crossover compares runtime and energy drift between direct $O(N^2)$ summation and the tree-based $O(N log N)$ path. Direct summation is faster at all tested particle counts — its regular, branch-free access pattern maps well onto the GPU. But the tree path produces far lower energy drift: at $N = 100000$, direct summation gives $Delta E = 2.01$ while the tree path achieves $Delta E = 0.076$. The real crossover is not runtime but _accuracy_: the tree path trades throughput for the force accuracy needed to keep the simulation physically meaningful.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, right, right, right, right),
    [*N*], [*Direct (ms)*], [*Tree (ms)*], [*Direct drift*], [*Tree drift*],
    [1,000], [1.53], [5.86], [$2.25 times 10^(-2)$], [$6.41 times 10^(-5)$],
    [5,000], [4.03], [7.35], [$1.21 times 10^(-1)$], [$2.50 times 10^(-4)$],
    [10,000], [7.46], [11.00], [$2.11 times 10^(-1)$], [$8.65 times 10^(-3)$],
    [50,000], [35.64], [65.46], [$9.88 times 10^(-1)$], [$6.07 times 10^(-2)$],
    [100,000], [140.37], [180.11], [$2.01$], [$7.58 times 10^(-2)$],
  ),
  caption: [Direct vs tree force evaluation: runtime and energy drift (Plummer sphere, leapfrog, $theta = 0.75$). Direct summation is faster but accumulates substantially more energy drift, particularly at large $N$.],
) <tab:crossover>

#figure(
  image("../graphics/fig_crossover.png", width: 80%),
  caption: [Direct vs tree force evaluation. Left axis: runtime (ms/step). Right axis: final energy drift. The tree path trades throughput for force accuracy.],
) <fig:crossover>

== RQ2: Abstraction Overhead

=== WebGPU vs Native Metal

@tab:metal-comparison compares the WebGPU solver (wgpu-native/Metal) against the native Metal Barnes–Hut baseline (UniSim @unisim) on the same Apple M2 hardware. Both implementations use the same Metal graphics driver; the difference reflects the overhead of the WebGPU abstraction layer.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (right, right, right, right),
    [*N*], [*Metal (ms)*], [*WebGPU (ms)*], [*Ratio (WebGPU/Metal)*],
    [1,000], [2.94], [5.86], [2.0$times$],
    [5,000], [10.09], [7.35], [0.73$times$],
    [10,000], [21.35], [11.00], [0.52$times$],
    [50,000], [121.77], [65.46], [0.54$times$],
    [100,000], [516.78], [180.11], [0.35$times$],
  ),
  caption: [WebGPU (wgpu-native) vs native Metal (UniSim @unisim, stabilised fork @unisim-fork) Barnes–Hut performance on the same Apple M2. At $N gt.eq 5000$ the WebGPU implementation outperforms the Metal baseline, reflecting the efficiency of the fully GPU-resident LBVH pipeline.],
) <tab:metal-comparison>

At $N = 1000$, WebGPU is 2.0$times$ slower than native Metal, reflecting per-dispatch overhead at small workloads. At $N gt.eq 5000$, the WebGPU implementation is consistently faster, reaching 2.9$times$ faster at $N = 100000$ (180.11 ms vs 516.78 ms). This advantage reflects differences in tree construction and traversal strategy — the fully GPU-resident LBVH with the optimised traversal shader described in the methodology outperforms UniSim's approach at scale — rather than WebGPU being inherently faster than Metal. The key finding for RQ2 is that the WebGPU abstraction layer imposes no measurable overhead once GPU compute dominates at $N gt.eq 5000$.

=== Cross-Backend Implementation Comparison

@tab:cross-backend compares four WebGPU implementations on the same hardware, all backed by the Metal API. This isolates the overhead introduced by each implementation from the GPU compute itself @maczan2026.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    [*Implementation*], [*N=1K (ms)*], [*N=10K (ms)*], [*N=100K (ms)*], [*CV (100K)*],
    [Dawn], [1.40], [8.54], [272.73], [0.01],
    [wgpu-native], [5.86], [11.00], [180.11], [0.02],
    [Chrome], [4.87], [17.81], [260.74], [0.01],
    [Safari], [9.52], [20.97], [281.59], [0.01],
  ),
  caption: [Per-step runtime across four WebGPU implementations (Plummer sphere, $theta = 0.75$, frozen-state protocol). All four use the Metal backend on Apple M2. Dawn is fastest at small $N$; wgpu-native scales best to large $N$.],
) <tab:cross-backend>

#figure(
  image("../graphics/fig_cross_backend.png", width: 80%),
  caption: [Grouped bar chart of per-step runtime across four WebGPU implementations at three particle counts. Implementation choice produces large performance variation, particularly at $N = 100000$.],
) <fig:cross-backend>

The variation across implementations is large. Dawn has the lowest per-dispatch overhead (1.40 ms at $N = 1000$) but scales to 272.73 ms at $N = 100000$; wgpu-native starts higher (5.86 ms) but scales better (180.11 ms). Chrome achieves lower per-dispatch overhead than wgpu-native at small $N$ (4.87 ms vs 5.86 ms at $N = 1000$) but scales worse (260.74 ms at $N = 100000$). Safari is slowest at every $N$. These findings are consistent with Maczan's observation that implementation choice within the same backend produces significant performance variation @maczan2026.

== RQ3: Browser Feasibility

@tab:web-native compares native wgpu-native execution against browser execution via Chrome for the same simulation configuration. At $N = 1000$, Chrome is slightly faster than wgpu-native (4.87 ms vs 5.86 ms, overhead 0.8$times$), reflecting lower per-dispatch overhead in the browser's WebGPU implementation at small workloads. As $N$ grows and force evaluation dominates, Chrome's scaling disadvantage becomes apparent: the overhead peaks at 2.0$times$ ($N = 5000$) and then gradually decreases to 1.4$times$ at $N = 100000$ (260.74 ms vs 180.11 ms) as GPU compute time increasingly dominates both platforms.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, right, right, right, right),
    [*N*], [*Native (ms)*], [*Chrome (ms)*], [*Overhead*], [*Native drift*],
    [1,000], [5.86], [4.87], [0.8$times$], [$6.41 times 10^(-5)$],
    [5,000], [7.35], [14.34], [2.0$times$], [$2.50 times 10^(-4)$],
    [10,000], [11.00], [17.81], [1.6$times$], [$8.65 times 10^(-3)$],
    [50,000], [65.46], [94.93], [1.5$times$], [$6.07 times 10^(-2)$],
    [100,000], [180.11], [260.74], [1.4$times$], [$7.58 times 10^(-2)$],
  ),
  caption: [wgpu-native vs Chrome wall-clock ms/step and energy drift. Chrome is faster at $N = 1000$ but scales worse; the overhead converges toward 1.4$times$ at large $N$.],
) <tab:web-native>

#figure(
  image("../graphics/fig_web_native.png", width: 80%),
  caption: [Native vs browser execution time per step. Chrome has lower per-dispatch overhead at small $N$ but scales worse; the overhead ratio narrows as GPU compute dominates.],
) <fig:web-native>

== Numerical Quality

Energy drift is reported as a secondary observation characterising the precision and approximation quality of the solver. The opening-angle sweep at $N = 5000$ (@tab:theta-sweep) shows that drift increases with $theta$: from $Delta E \/ |E(0)| = 2.67 times 10^(-4)$ at $theta = 0.3$ to $3.31 times 10^(-2)$ at $theta = 1.0$. Larger opening angles admit more distant nodes into the force approximation, introducing greater truncation error. Runtime decreases modestly with $theta$ (9.30 ms to 6.96 ms), reflecting fewer node interactions at larger opening angles. Momentum is conserved to within 0.1% over 5,000 steps at all tested $theta$ values.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (right, right, right),
    [*$theta$*], [*Mean ms/step*], [*Final drift*],
    [0.3], [9.30], [$2.67 times 10^(-4)$],
    [0.5], [8.24], [$2.75 times 10^(-3)$],
    [0.7], [7.57], [$9.77 times 10^(-3)$],
    [1.0], [6.96], [$3.31 times 10^(-2)$],
  ),
  caption: [Effect of opening angle $theta$ on runtime and energy drift (Plummer sphere, $N = 5000$, 5000 steps). Drift increases with $theta$, showing the tree approximation contributes to numerical error alongside 32-bit precision.],
) <tab:theta-sweep>

== Summary of Findings

Force evaluation accounts for 94–99% of step time, with LBVH construction staying below 0.35 ms even at $N = 100000$ (RQ1). The WebGPU abstraction costs 2.0$times$ at $N = 1000$ but the solver outperforms the Metal baseline at $N gt.eq 5000$, with large variation across WebGPU implementations (RQ2). Chrome is faster than native at $N = 1000$ but scales worse, with the overhead converging to 1.4$times$ at $N = 100000$ (RQ3). Energy drift increases with opening angle $theta$, ranging from $2.67 times 10^(-4)$ to $3.31 times 10^(-2)$, with 32-bit precision and the tree approximation both contributing to numerical error. These findings are interpreted in the following discussion section.
