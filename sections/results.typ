#pagebreak()
= Results and Analysis
#set heading(numbering: "1.1")

This section presents results organised by the three research questions: RQ1 (scalability and pipeline bottlenecks), RQ2 (WebGPU abstraction overhead relative to native Metal), and RQ3 (browser feasibility). All timing values are mean milliseconds per step over 100 measured steps after 50 warmup steps, reported with standard deviation and coefficient of variation. Energy drift is reported as $Delta E = |E(t) - E(0)| \/ |E(0)|$.

== RQ1: Scalability and Pipeline Bottlenecks

=== Runtime Scaling with Particle Count

@tab:performance-summary presents the mean runtime per step and its three-component decomposition for the GPU LBVH Barnes–Hut path across the Plummer sphere scenario. Total runtime increases from 7.0 ms at $N = 1000$ to 182.8 ms at $N = 100000$.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto),
    align: (right, right, right, right, right, right, right),
    [*N*], [*ms/step*], [*$plus.minus$ std*], [*CV*], [*Tree (ms)*], [*Force (ms)*], [*Integrate (ms)*],
    [1,000], [7.04], [1.66], [0.24], [0.38], [6.63], [0.04],
    [5,000], [7.87], [2.99], [0.38], [0.25], [7.59], [0.03],
    [10,000], [10.25], [0.94], [0.09], [0.32], [9.91], [0.03],
    [50,000], [67.53], [1.95], [0.03], [0.91], [66.51], [0.11],
    [100,000], [182.85], [3.33], [0.02], [0.96], [181.72], [0.17],
  ),
  caption: [Performance summary with timing decomposition (Plummer sphere, leapfrog, $theta = 0.75$, $epsilon = 0.5$, wgpu-native/Metal). Force evaluation dominates at all $N$, accounting for 94–99% of total step time.],
) <tab:performance-summary>

// TODO: regenerate fig_n_scaling_plummer.png with new data
// #figure(
//   image("../graphics/fig_n_scaling_plummer.png", width: 80%),
//   caption: [Mean runtime per timestep as a function of $N$ for the Plummer sphere scenario (GPU LBVH, leapfrog, $theta = 0.75$, wgpu-native/Metal).],
// ) <fig:n-scaling-plummer>

Force evaluation dominates at all particle counts, accounting for 94% of step time at $N = 1000$ and 99% at $N = 100000$. Tree construction (the seven-pass LBVH pipeline) remains below 1 ms even at $N = 100000$, indicating that the parallel construction method is efficient and that further optimisation efforts should target the BVH traversal shader rather than the tree-build pipeline.

=== LBVH Construction Breakdown

@tab:lbvh-breakdown decomposes tree construction into its seven individual passes. All six construction passes remain approximately constant with $N$ (1.3–4.6 ms each), confirming that the LBVH pipeline scales well. The radix sort is the most expensive construction pass at 4.4–4.7 ms. Force evaluation, shown in the final column for reference, is the component that drives the overall scaling behaviour.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto, auto),
    align: (right, right, right, right, right, right, right, right),
    [*N*], [*AABB*], [*Morton*], [*Sort*], [*Karras*], [*Leaf*], [*Aggr.*], [*Force*],
    [1,000], [1.51], [1.34], [4.65], [1.41], [1.38], [1.43], [3.19],
    [5,000], [1.46], [1.35], [4.44], [1.46], [1.34], [1.39], [8.27],
    [10,000], [1.47], [1.37], [4.41], [1.37], [1.44], [1.45], [13.62],
    [50,000], [1.46], [1.33], [3.57], [1.37], [1.33], [1.36], [63.04],
    [100,000], [1.42], [1.35], [4.60], [1.40], [1.37], [1.38], [176.57],
  ),
  caption: [Per-pass timing (ms) for the LBVH construction pipeline and force evaluation. Construction passes are approximately constant with $N$; force evaluation drives the overall scaling.],
) <tab:lbvh-breakdown>

=== Direct vs Tree: Speed–Accuracy Trade-off

@tab:crossover compares runtime and energy drift between direct $O(N^2)$ summation and the tree-based $O(N log N)$ path. Direct summation is faster at all tested particle counts, reflecting the high degree of GPU parallelism available for the regular, branch-free direct computation compared to the irregular memory access patterns of tree traversal. However, the tree path produces substantially lower energy drift: at $N = 100000$, direct summation yields $Delta E = 2.01$ while the tree path achieves $Delta E = 0.079$. The relevant crossover is therefore not one of runtime but of _accuracy_: the tree path sacrifices throughput for force accuracy that keeps the simulation physically meaningful over long integrations.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, right, right, right, right),
    [*N*], [*Direct (ms)*], [*Tree (ms)*], [*Direct drift*], [*Tree drift*],
    [1,000], [2.14], [6.76], [$2.25 times 10^(-2)$], [$6.45 times 10^(-5)$],
    [5,000], [4.53], [7.83], [$1.21 times 10^(-1)$], [$2.40 times 10^(-4)$],
    [10,000], [6.08], [11.11], [$2.11 times 10^(-1)$], [$9.26 times 10^(-3)$],
    [50,000], [37.63], [67.31], [$9.88 times 10^(-1)$], [$6.14 times 10^(-2)$],
    [100,000], [132.49], [171.22], [$2.01$], [$7.88 times 10^(-2)$],
  ),
  caption: [Direct vs tree force evaluation: runtime and energy drift (Plummer sphere, leapfrog, $theta = 0.75$). Direct summation is faster but accumulates substantially more energy drift, particularly at large $N$.],
) <tab:crossover>

// TODO: regenerate fig_crossover.png — dual-axis plot: runtime + drift
// #figure(
//   image("../graphics/fig_crossover.png", width: 80%),
//   caption: [Direct vs tree force evaluation. Left axis: runtime (ms/step). Right axis: final energy drift. The tree path trades throughput for force accuracy.],
// ) <fig:crossover>

== RQ2: Abstraction Overhead

=== WebGPU vs Native Metal

@tab:metal-comparison compares the WebGPU solver (wgpu-native/Metal) against the native Metal Barnes–Hut baseline (UniSim @unisim) on the same Apple M2 hardware. Both implementations use the same Metal graphics driver; the difference reflects the overhead of the WebGPU abstraction layer.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (right, right, right, right),
    [*N*], [*Metal (ms)*], [*WebGPU (ms)*], [*Ratio (WebGPU/Metal)*],
    [1,000], [2.94], [7.04], [2.4$times$],
    [5,000], [10.09], [7.87], [0.78$times$],
    [10,000], [21.35], [10.25], [0.48$times$],
    [50,000], [121.77], [67.53], [0.55$times$],
    [100,000], [516.78], [182.85], [0.35$times$],
  ),
  caption: [WebGPU (wgpu-native) vs native Metal (UniSim @unisim, stabilised fork @unisim-fork) Barnes–Hut performance on the same Apple M2. At $N gt.eq 5000$ the WebGPU implementation outperforms the Metal baseline, reflecting the efficiency of the fully GPU-resident LBVH pipeline.],
) <tab:metal-comparison>

At $N = 1000$, WebGPU is 2.4$times$ slower than native Metal, reflecting per-dispatch overhead at small workloads. At $N gt.eq 5000$, the WebGPU implementation is consistently faster, reaching 2.8$times$ faster at $N = 100000$ (182.85 ms vs 516.78 ms). This advantage reflects differences in tree construction and traversal strategy — the fully GPU-resident LBVH with the optimised traversal shader described in the methodology outperforms UniSim's approach at scale — rather than WebGPU being inherently faster than Metal. The key finding for RQ2 is that the WebGPU abstraction layer imposes no measurable overhead once GPU compute dominates at $N gt.eq 5000$.

=== Cross-Backend Implementation Comparison

@tab:cross-backend compares four WebGPU implementations on the same hardware, all backed by the Metal API. This isolates the overhead introduced by each implementation from the GPU compute itself @maczan2026.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, right, right, right, right),
    [*Implementation*], [*N=1K (ms)*], [*N=10K (ms)*], [*N=100K (ms)*], [*CV (100K)*],
    [Dawn], [1.47], [8.56], [274.57], [0.01],
    [wgpu-native], [7.04], [10.25], [182.85], [0.02],
    [Chrome], [35.86], [35.99], [219.96], [0.26],
    [Safari], [34.10], [53.18], [311.27], [0.01],
  ),
  caption: [Per-step runtime across four WebGPU implementations (Plummer sphere, $theta = 0.75$, frozen-state protocol). All four use the Metal backend on Apple M2. Dawn is fastest at small $N$; wgpu-native scales best to large $N$.],
) <tab:cross-backend>

The results reveal substantial variation across implementations. Dawn achieves the lowest per-dispatch overhead (1.47 ms at $N = 1000$) but scales to 274.57 ms at $N = 100000$, while wgpu-native starts higher (7.04 ms) but scales better (182.85 ms). The two browser implementations show a fixed floor of approximately 34–36 ms at small $N$, attributable to the Emscripten asyncify event-loop yield, above which they diverge: Chrome scales to 219.96 ms while Safari reaches 311.27 ms. These findings are consistent with Maczan's observation that implementation choice within the same backend produces significant performance variation @maczan2026.

== RQ3: Browser Feasibility

@tab:web-native compares native wgpu-native execution against browser execution via Chrome for the same simulation configuration. At small $N$, the browser wall-clock time is dominated by a fixed overhead of approximately 29 ms from the Emscripten asyncify mechanism. As $N$ grows and GPU compute time increases, this fixed cost becomes a diminishing fraction: at $N = 50000$ the browser matches native performance (67.77 ms vs 67.53 ms), and at $N = 100000$ the browser adds only a 1.2$times$ overhead (219.96 ms vs 182.85 ms).

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, right, right, right, right),
    [*N*], [*Native (ms)*], [*Chrome (ms)*], [*Overhead*], [*Native drift*],
    [1,000], [7.04], [35.86], [5.1$times$], [$6.38 times 10^(-5)$],
    [5,000], [7.87], [35.97], [4.6$times$], [$2.85 times 10^(-4)$],
    [10,000], [10.25], [35.99], [3.5$times$], [$9.31 times 10^(-3)$],
    [50,000], [67.53], [67.77], [1.0$times$], [$6.06 times 10^(-2)$],
    [100,000], [182.85], [219.96], [1.2$times$], [$7.71 times 10^(-2)$],
  ),
  caption: [Native (wgpu-native) vs browser (Chrome) wall-clock ms/step and energy drift. The browser overhead converges from 5.1$times$ at $N = 1000$ to 1.2$times$ at $N = 100000$.],
) <tab:web-native>

// TODO: regenerate fig_web_native.png with new data
// #figure(
//   image("../graphics/fig_web_native.png", width: 80%),
//   caption: [Native vs browser execution time per step. The browser wall-clock includes a fixed asyncify event-loop overhead that becomes negligible at large $N$.],
// ) <fig:web-native>

== Numerical Quality

Energy drift is reported as a secondary observation characterising the 32-bit precision floor of WebGPU rather than a primary research question. The opening angle sweep at $N = 5000$ (@tab:theta-sweep) shows identical drift ($Delta E \/ |E(0)| approx 1.84$) across all tested $theta$ values, confirming that 32-bit floating-point precision, not the tree approximation, is the dominant error source. Softening in the range 0.1–2.0 has no measurable effect on runtime and produces only modest variation in drift (1.82–2.00). Momentum is conserved to within 0.1% over 5,000 steps.

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
  caption: [Effect of opening angle $theta$ on runtime and energy drift (Plummer sphere, $N = 5000$). Drift is insensitive to $theta$, indicating 32-bit precision dominates.],
) <tab:theta-sweep>

== Summary of Findings

Force evaluation accounts for 94–99% of step time, with the LBVH construction pipeline remaining below 1 ms even at $N = 100000$ (RQ1). The WebGPU abstraction overhead relative to native Metal is 2.4$times$ at $N = 1000$ but the WebGPU solver outperforms the Metal baseline at $N gt.eq 5000$, with substantial variation across WebGPU implementations (RQ2). Browser execution adds a fixed ~29 ms overhead that becomes negligible at large $N$, with Chrome matching native throughput at $N = 50000$ (RQ3). The 32-bit precision floor is the binding constraint on numerical fidelity. These findings are interpreted in the following discussion section.
