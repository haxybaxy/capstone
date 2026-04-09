#pagebreak()
= Results and Analysis
#set heading(numbering: "1.1")

Results are organised by research question as follows: scalability and pipeline bottlenecks, WebGPU abstraction overhead relative to native Metal, and browser feasibility. All timing values are mean ms/step over 100 measured steps after 50 warmup steps, reported with standard deviation and coefficient of variation.

== RQ1: Scalability and Pipeline Bottlenecks

=== Runtime Scaling with Particle Count

@tab:performance-summary presents the mean runtime per step and its three-component decomposition for the GPU LBVH Barnes–Hut path across the Plummer sphere scenario. Total runtime scales roughly 30-fold across two orders of magnitude in $N$.

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
  caption: [Performance summary with timing decomposition.],
) <tab:performance-summary>

#figure(
  image("../graphics/fig_n_scaling_plummer.png", width: 80%),
  caption: [Mean runtime per timestep as a function of $N$.],
) <fig:n-scaling-plummer>

Force evaluation accounts for nearly all step time at every particle count tested, never dropping below 94%. Tree construction, by contrast, stays under half a millisecond regardless of $N$. The parallel construction pipeline scales well; any further optimisation effort belongs in the BVH traversal shader.

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
  caption: [Per-pass timing (ms) for the LBVH construction pipeline and force evaluation.],
) <tab:lbvh-breakdown>

#figure(
  image("../assets/fig_lbvh_breakdown.png", width: 80%),
  caption: [Stacked bar chart of LBVH construction passes at each $N$.],
) <fig:lbvh-breakdown>

=== Disk Scenario Scaling

@tab:disk-scaling presents the same timing decomposition for the rotating exponential disk scenario. The force-dominated scaling pattern holds: force evaluation accounts for 92–99% of step time, and tree construction remains under 0.5 ms. The disk is slightly slower than the Plummer sphere at the same $N$ (218 ms vs 180 ms at $N = 100000$), likely due to the non-uniform spatial distribution producing a less balanced BVH.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (right, right, right, right, right),
    [*N*], [*ms/step*], [*Tree (ms)*], [*Force (ms)*], [*Integrate (ms)*],
    [1,000], [7.42], [0.50], [6.86], [0.06],
    [5,000], [7.52], [0.20], [7.29], [0.02],
    [10,000], [12.86], [0.45], [12.35], [0.05],
    [50,000], [76.26], [0.25], [75.99], [0.02],
    [100,000], [217.95], [0.29], [217.63], [0.03],
  ),
  caption: [Disk scenario: performance summary with timing decomposition.],
) <tab:disk-scaling>

#figure(
  grid(
    columns: 2,
    gutter: 12pt,
    figure(image("../assets/disk_step1.png", width: 100%), caption: [_(a)_ Step 1], numbering: none),
    figure(image("../assets/disk_step5.png", width: 100%), caption: [_(b)_ Step 5], numbering: none),
    figure(image("../assets/disk_step20.png", width: 100%), caption: [_(c)_ Step 20], numbering: none),
    figure(image("../assets/disk_step50.png", width: 100%), caption: [_(d)_ Step 50], numbering: none),
  ),
  caption: [Morphological evolution of the rotating exponential disk.],
) <fig:disk-evolution>

=== Direct vs Tree: Speed–Accuracy Trade-off

@tab:crossover compares runtime and energy drift between direct $O(N^2)$ summation and the tree-based $O(N log N)$ path. Direct summation is faster at all tested particle counts; its regular, branch-free access pattern maps well onto the GPU. The tree path, however, drifts roughly 26 times less at the largest $N$ tested, and this gap widens with particle count. The real crossover is not runtime but _accuracy_: the tree path trades throughput for the force accuracy needed to keep the simulation physically meaningful.

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
  caption: [Direct vs tree force runtime and energy drift],
) <tab:crossover>

#figure(
  image("../graphics/fig_crossover.png", width: 80%),
  caption: [Direct vs tree force evaluation. Left axis: runtime (ms/step). Right axis: final energy drift.],
) <fig:crossover>

== RQ2: Abstraction Overhead

=== WebGPU vs Native Metal

@tab:metal-comparison compares the WebGPU solver against the native Metal Barnes–Hut baseline (@unisim-fork, fork of UniSim @unisim). The difference reflects the overhead of the WebGPU abstraction layer.

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
  caption: [WebGPU (wgpu-native) vs native Metal (UniSim @unisim, stabilised fork @unisim-fork)],
) <tab:metal-comparison>

WebGPU carries about 2$times$ overhead at the smallest particle count, where per-dispatch cost dominates. Once $N$ reaches 5 000 and GPU compute takes over, the WebGPU solver is consistently faster, reaching nearly 3$times$ at the largest $N$. This advantage reflects the fully GPU-resident LBVH pipeline and optimised traversal shader rather than WebGPU being inherently faster than Metal. The key finding for RQ2 is that the WebGPU abstraction layer imposes no measurable overhead once GPU compute dominates.

=== Cross-Backend Implementation Comparison

@tab:cross-backend compares four WebGPU implementations, all backed by the Metal API. This isolates the overhead introduced by each implementation from the GPU compute itself @maczan2026.

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
  caption: [Per-step runtime across four WebGPU implementations.],
) <tab:cross-backend>

#figure(
  image("../graphics/fig_cross_backend.png", width: 80%),
  caption: [Grouped bar chart of per-step runtime across four WebGPU backends.],
) <fig:cross-backend>

The variation across implementations is substantial: at $N = 100000$ the fastest and slowest differ by over 1.5$times$. Dawn has the lowest per-dispatch overhead at small $N$ but scales the worst; wgpu-native is the opposite, starting slower but handling large workloads most efficiently. Chrome and Safari fall in between, with Safari consistently the slowest. These findings are consistent with Maczan's observation that implementation choice within the same backend produces significant performance variation @maczan2026.

== RQ3: Browser Feasibility

@tab:web-native compares native wgpu-native execution against browser execution via Chrome for the same simulation configuration. Chrome is actually slightly faster at the smallest particle count, suggesting lower per-dispatch overhead in the browser's WebGPU path. As $N$ grows and force evaluation takes over, Chrome's scaling disadvantage becomes apparent: the overhead peaks around 2$times$ at moderate $N$ and then gradually narrows to roughly 1.4$times$ at the largest workload, as GPU compute time increasingly dominates both platforms.

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
  caption: [wgpu-native vs Chrome wall-clock ms/step and energy drift.],
) <tab:web-native>

#figure(
  image("../graphics/fig_web_native.png", width: 80%),
  caption: [Native vs browser execution time per step.],
) <fig:web-native>

== Numerical Quality

Energy drift is reported as a secondary observation characterising the precision and approximation quality of the solver. The opening-angle sweep at $N = 5000$ (@tab:theta-sweep) shows that drift spans about two orders of magnitude across the tested $theta$ range. Larger opening angles admit more distant nodes into the force approximation, introducing greater truncation error. Runtime drops modestly as $theta$ increases, reflecting fewer node interactions per particle. Momentum is conserved to within 0.1% over 5,000 steps at all tested $theta$ values.

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
  caption: [Effect of opening angle $theta$ on runtime and energy drift.],
) <tab:theta-sweep>

=== Two-Body Orbit Validation

The two-body circular orbit (@tab:twobody-validation) confirms integrator correctness: energy drift remains below $10^(-5)$ across all tested timesteps, and momentum is conserved to machine precision. The orbit stays stable over 5,000 steps at every $Delta t$ value.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (right, right, right),
    [*$Delta t$*], [*Final drift*], [*$|bold(p)|$*],
    [0.0001], [$3.14 times 10^(-6)$], [$0.00$],
    [0.0005], [$2.42 times 10^(-6)$], [$0.00$],
    [0.001], [$3.80 times 10^(-6)$], [$0.00$],
    [0.005], [$9.20 times 10^(-6)$], [$0.00$],
  ),
  caption: [Two-body orbit: energy drift and momentum conservation across $Delta t$.],
) <tab:twobody-validation>

=== Timestep Sensitivity

@tab:dt-sweep shows the effect of $Delta t$ on energy drift at fixed $N = 5000$. Drift increases roughly tenfold from $Delta t = 0.0001$ to $Delta t = 0.005$, while runtime is unaffected at fixed particle count.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (right, right, right),
    [*$Delta t$*], [*Mean ms/step*], [*Final drift*],
    [0.0001], [7.33], [$2.59 times 10^(-3)$],
    [0.0005], [7.42], [$9.53 times 10^(-3)$],
    [0.001], [7.66], [$1.32 times 10^(-2)$],
    [0.005], [7.66], [$2.73 times 10^(-2)$],
  ),
  caption: [Effect of timestep $Delta t$ on runtime and energy drift.],
) <tab:dt-sweep>

=== Softening Sensitivity

@tab:softening-sweep shows the effect of the Plummer softening parameter $epsilon$ on energy drift at fixed $N = 5000$. Drift is relatively stable across the tested range, but tight softening ($epsilon = 0.1$) increases runtime noticeably, as closer particle interactions produce deeper BVH traversals.

#figure(
  table(
    columns: (auto, auto, auto),
    align: (right, right, right),
    [*$epsilon$*], [*Mean ms/step*], [*Final drift*],
    [0.1], [12.84], [$1.15 times 10^(-2)$],
    [0.25], [7.47], [$1.16 times 10^(-2)$],
    [0.5], [7.49], [$1.26 times 10^(-2)$],
    [1.0], [7.70], [$1.55 times 10^(-2)$],
    [2.0], [7.58], [$1.59 times 10^(-2)$],
  ),
  caption: [Effect of softening $epsilon$ on runtime and energy drift.],
) <tab:softening-sweep>

== Summary of Findings

The results across all three research questions are interpreted in the following discussion section.
