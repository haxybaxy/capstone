#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#pagebreak()
= Methodology
#set heading(numbering: "1.1")

== Research Design and Objectives

We implement and evaluate a gravitational $N$-body solver with a focus on reproducibility, long-term numerical stability, and computational scalability beyond the $O(N^2)$ cost of direct summation. The solver is written in C++20 using the WebGPU C API and built from a single codebase targeting both native desktop execution (via wgpu-native and Dawn) and browser execution (compiled via Emscripten) @webgpu-spec. This dual-target approach supports interactive visualisation as well as headless batch runs, so performance and numerical behaviour can be compared under the same conditions across platforms.

On the physics side, we use Newtonian gravity with Plummer softening to avoid the $1\/r^2$ singularity @galacticdynamics2nded, and approximate forces with a Barnes–Hut tree to bring the cost down from $O(N^2)$ to roughly $O(N log N)$ @barneshut. The tree itself is a Linear Bounding Volume Hierarchy (LBVH), built and traversed entirely on the GPU each timestep using Karras's parallel construction method @maximizeparallel. We integrate with a second-order symplectic leapfrog (kick–drift–kick), which conserves energy far better than forward Euler over long integrations @springel_2005. All of this runs on WebGPU, which gives us general-purpose compute shaders through the same API on both native and browser targets.

The evaluation is structured around three main research questions:

1. *Scalability*: How does runtime per timestep scale with $N$ for a WebGPU Barnes–Hut implementation, and where are the bottlenecks within the GPU pipeline?
2. *Abstraction overhead*: What performance cost does the WebGPU abstraction layer impose relative to Apple's native Metal, and how does this vary across WebGPU implementations (wgpu-native, Dawn, browser)?
3. *Browser feasibility*: Can the same codebase, compiled to WebAssembly and running in a browser, achieve acceptable throughput and numerical consistency compared to native execution?

As discussed in the literature review, WebGPU is the only current GPU API that combines compute shaders, storage buffers, and atomic operations with browser deployability, which are the primitives our tree-based solver needs, available on both native and web targets from a single codebase. @fig:platform-comparison summarises how it compares to the alternatives. The relevant constraints for our implementation are: all GPU arithmetic is 32-bit (no `f64`), which caps numerical precision; dispatch scheduling overhead can dominate at small $N$; and buffer behaviour varies across backends and devices @realitycheck. These constraints are tested directly through the three research questions above.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (left, center, center, center, center),
    [*Criterion*], [*CUDA*], [*OpenCL*], [*WebGL*], [*WebGPU*],
    [Compute shaders], [Yes], [Yes], [No], [Yes],
    [Storage buffers], [Yes], [Yes], [No], [Yes],
    [Atomic operations], [Yes], [Yes], [No], [Yes],
    [Browser deployment], [No], [No], [Yes], [Yes],
    [Cross-vendor GPU], [No], [Yes], [Yes], [Yes],
    [Native deployment], [Yes], [Yes], [No], [Yes],
    [64-bit GPU float], [Yes], [Varies], [No], [No],
  ),
  caption: [Comparison of GPU compute APIs against the criteria required for our cross-platform hierarchical $N$-body simulation.],
) <fig:platform-comparison>

== Physical Model and State Representation

In our simulation, each particle represents a mass element evolving under self-gravity in an isolated (open) domain. We adopt a natural unit system in which the gravitational constant $G = 1$, the unit of mass $M_0$ is defined by the total system mass, and the unit of length $r_0$ is set by the characteristic scale of the initial conditions (e.g., the Plummer scale length $a$ in Scenario B). Time is measured in units of $t_0 = sqrt(r_0^3 \/ (G M_0))$, the free-fall timescale of the system. All the quantities reported in subsequent sections (energies, momenta, and timescales) are expressed in terms of these natural units unless stated otherwise. The softened acceleration of particle $i$ due to all other particles is
#math.equation(
  $
    bold(a)_i = G sum_(j eq.not i) m_j frac(bold(r)_j - bold(r)_i, (||bold(r)_j - bold(r)_i||^2 + epsilon^2)^(3/2))
  $,
)
where $bold(r)_i$ and $bold(r)_j$ are the position vectors of particles $i$ and $j$, $m_j$ is the mass of particle $j$, and $epsilon$ is a softening length (default 0.5, configurable). The softening parameter introduces a Plummer-type potential that suppresses the $1\/r^2$ singularity at short range, preventing erratic and divergent accelerations during close interactions @galacticdynamics2nded. This formulation is equivalent to treating each particle as a smooth mass distribution of characteristic radius $epsilon$ rather than a single point mass.

On the GPU, a particle's state is stored as packed four-component vectors (`vec4<f32>`), with mass in the $w$ component of the position vector: $(x, y, z, m)$. This packing cuts the number of buffer reads during force evaluation compared to separate position and mass buffers. We considered a Structure-of-Arrays (SoA) layout but rejected it after further analysis, since the BVH force shader (95–99% of step time) never reads particle masses directly, as it uses the aggregated node masses from the bottom-up pass. The shaders that do read particle mass (leaf initialisation, drift) always need to access the position and mass together, so separating them would hurt cache performance. The shaders that only read positions (bounding box, Morton code) account for less than 1% of step time, making any bandwidth saving negligible. @fig:particle-layout summarises the storage layout for all three state arrays.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (center, center, center, center, center),
    [*Component*], [`.x`], [`.y`], [`.z`], [`.w`],
    [`positions[i]`], [$x_i$], [$y_i$], [$z_i$], [$m_i$],
    [`velocities[i]`], [$v_(x,i)$], [$v_(y,i)$], [$v_(z,i)$], [0],
    [`accelerations[i]`], [$a_(x,i)$], [$a_(y,i)$], [$a_(z,i)$], [0],
  ),
  caption: [Particle state layout using `vec4<f32>` packing.],
) <fig:particle-layout>

All GPU kernels run in 32-bit floating point, which maximises throughput and matches current WebGPU capabilities. Diagnostic quantities such as the total energy and linear momentum, are computed on the CPU in double precision (64-bit) to reduce accumulation error over long integrations. This split is a practical concession, since WebGPU does not support 64-bit GPU arithmetic @realitycheck.

== Time Integration

In order to represent time in a discrete manner, we integrate with a fixed-timestep, second-order symplectic leapfrog in kick–drift–kick (KDK) form @verlet1967. In the following equations, the superscript $n$ denotes the timestep index, and $bold(r)_i^n$, $bold(v)_i^n$, $bold(a)_i^n$ represent the position, velocity, and acceleration of particle $i$ at step $n$. With timestep $Delta t$ (default $10^(-3)$), the update has three stages. A half-kick advances velocities by half a step using the current accelerations:
#math.equation(
  $
    bold(v)_i^(n+1\/2) = bold(v)_i^(n) + frac(Delta t, 2) bold(a)_i^n
  $,
)
Next, a drift advances positions using the half-stepped velocities:
#math.equation(
  $
    bold(r)_i^(n+1) = bold(r)_i^(n) + Delta t bold(v)_i^(n+1\/2)
  $,
)
Accelerations $bold(a)_i^(n+1)$ are then recomputed from the updated positions using the hierarchical force evaluation described in the following section. Finally, a second half-kick completes the velocity update:
#math.equation(
  $
    bold(v)_i^(n+1) = bold(v)_i^(n+1\/2) + frac(Delta t, 2) bold(a)_i^(n+1)
  $,
)

We chose leapfrog for its well-known long-term stability in gravitational dynamics @springel_2005. Unlike forward Euler, which introduces secular energy drift proportional to $Delta t$, the leapfrog is time-reversible and symplectic: it preserves phase-space volume, producing bounded energy oscillations rather than monotonic growth @galacticdynamics2nded. For long integrations, this matters far more than raw speed.

The most expensive step in each integration cycle is the evaluation of accelerations $bold(a)_i$, which is addressed through hierarchical approximation in the following section.

== Hierarchical Force Evaluation

Rather than computing all $N(N-1)\/2$ pairwise interactions directly, our solver groups distant particles into tree nodes and approximates each group as a single equivalent mass.

Each internal node of the tree stores a total mass $M = sum_(i in "node") m_i$ and a centre of mass $bold(R) = (sum_(i in "node") m_i bold(r)_i) \/ M$, computed by aggregating over all particles in that node's subtree. When a node is accepted as a monopole, its gravitational contribution to particle $i$ is
#math.equation(
  $
    bold(a)_(i,"node") = G M frac(bold(R) - bold(r)_i, (||bold(R) - bold(r)_i||^2 + epsilon^2)^(3/2))
  $,
)
The classical Barnes–Hut algorithm uses an octree, where space is recursively divided into eight equal sub-cubes, producing a tree whose structure is determined by the spatial partition rather than the particles themselves. On a GPU, octrees are awkward, since each node has up to eight children, many of which may be empty, and the recursive top-down construction is inherently serial. A Bounding Volume Hierarchy (BVH) avoids both problems. A BVH is a binary tree in which each internal node stores an axis-aligned bounding box (AABB) that encloses the particles in its subtree. Because the tree is binary, having 2 children per node instead of 8, traversal requires fewer branch decisions per level, and the total node count is fixed at $2N - 1$ regardless of the spatial distribution. Most importantly, a BVH can be built bottom-up from a sorted particle list in a fully parallel, non-recursive pipeline, which is the Linear BVH (LBVH) construction described below. The trade-off is that BVH bounding boxes can overlap, unlike octree cells, which partitions space without gaps, so the opening criterion must use the actual node extent rather than a uniform cell width.

We implement the tree as a BVH constructed and traversed entirely on the GPU each timestep.

An internal node is accepted as a monopole when it is sufficiently small relative to its distance from the target particle. The opening criterion tests whether the squared maximum extent of the node's axis-aligned bounding box (AABB) satisfies $"maxExtent"^2 \/ d^2 < theta^2$, where $"maxExtent" = max(Delta x, Delta y, Delta z)$ and $d^2 = ||bold(r)_i - bold(R)||^2$. This extent-based criterion reflects the non-cubic node shapes that arise in a BVH more accurately than a uniform half-width, and is expressed in squared form to avoid a per-node square root. Salmon and Warren provide rigorous error bounds for these opening criteria, showing that the conventional Barnes–Hut criterion can admit unbounded errors for $theta >= 1\/3$ in pathological configurations @skeletons_1994.

@fig:opening-criterion illustrates the geometry of both criteria. The default opening angle $theta = 0.75$ is used as a practical balance between accuracy and performance. For comparison, GADGET-2 uses $theta$ values in the range 0.5 to 0.7 for cosmological simulations where higher force accuracy is required @springel_2005, while the original Barnes and Hut paper used $theta = 1.0$ @barneshut. The parameter sweeps in the evaluation protocol (see @sec:evaluation-protocol) systematically characterize the accuracy–performance trade-off across $theta in {0.3, 0.5, 0.7, 1.0}$.

#figure(
  image("../graphics/fig_opening_criterion.png", width: 100%),
  caption: [Geometry of the opening criterion.],
) <fig:opening-criterion>

== Software Architecture and Execution Modes

The implementation is written in C++20 for host-side orchestration and WGSL for GPU compute and rendering shaders, using the WebGPU C API directly without wrapper libraries. CMake handles the build with pinned dependency versions for deterministic builds. Three backends are supported: wgpu-native @wgpu-native (Rust-based), Dawn @dawn (Google's implementation), and Emscripten (cross-compiling to WebAssembly for browser deployment).

All physics, such as the integration, tree construction, and force evaluation, runs on the GPU every step. The CPU handles only diagnostics: at configurable intervals, positions and velocities are read back through staging buffers and energy and momentum are computed in double precision. No per-step CPU physics overhead is incurred in the primary execution path.

== WebGPU Compute Methodology

Simulation state is stored in WebGPU storage buffers using the packed `vec4<f32>` layout described in @fig:particle-layout: positions (with mass in the $w$ component), velocities, and accelerations. The BVH is stored as a flat array of $2N - 1$ nodes, each containing a centre of mass, total mass, and axis-aligned bounding box. A uniform parameters buffer shares simulation parameters between host and shader code. In-place updates are used throughout: there is no double buffering of positions, velocities, or accelerations. Correct ordering between compute passes relies on WebGPU's implicit storage-buffer synchronisation between dispatches within a single command buffer submission. Bind groups are cached and reused across frames to avoid per-frame recreation overhead.

The WGSL compute shaders fall into two groups: integration and force evaluation (direct-summation baseline and BVH traversal), and LBVH construction in six passes @morton1966 @maximizeparallel. Workgroup sizes are tuned per kernel (128 for force evaluation, 256 for integration and tree building) with the rationale discussed in the optimisation section below.

=== Per-timestep execution sequence

Each timestep is recorded into a single command encoder and submitted as one command buffer. The six sequential passes, illustrated in @fig:timestep-pipeline, are: (1) a half-kick that advances velocities by $Delta t \/ 2$ using the current accelerations; (2) a drift that advances positions by $Delta t$ using the half-stepped velocities; (3) a full LBVH rebuild comprising six sub-passes (global AABB reduction, Morton code generation, radix sort, Karras topology construction, leaf initialisation, and bottom-up aggregation); (4) BVH force evaluation, in which each particle traverses the tree iteratively using a fixed-depth explicit stack (depth 64, sufficient for all tested $N$); (5) a second half-kick that completes the velocity update; and (6) an optional diagnostics readback at configurable intervals, in which positions and velocities are copied to the CPU via staging buffers for double-precision energy and momentum computation.

#include "fig_pipeline.typ"

=== GPU tree traversal

Because GPU compute shaders do not support recursion since they don't have a call stack, tree traversal is implemented iteratively in the BVH force shader. One GPU thread is assigned per particle, and the thread maintains an explicit stack of node indices (maximum depth 64), beginning from the root. At each step, a node is either accepted as a monopole (if it is a leaf, or if the opening criterion is satisfied) and its gravitational contribution is accumulated, or it is expanded by pushing its two children onto the stack. This explicit-stack approach preserves the Barnes–Hut approximation structure while accommodating the lack of a call stack on GPU hardware and limiting branch divergence across threads within a workgroup @fastnbody @cudabarnes @maximizeparallel.

=== GPU LBVH construction

The Linear Bounding Volume Hierarchy is built fully on the GPU each timestep, following the parallel construction method of Karras @maximizeparallel. The construction proceeds through six compute dispatches, illustrated in @fig:lbvh-pipeline:

+ *Global bounding box reduction.* A two-pass parallel reduction over all particle positions computes the axis-aligned bounding box of the entire system. This bounding box defines the coordinate range used to normalise positions in the next step.

+ *Morton code generation.* Each particle's position is normalised to a $[0, 1023]^3$ integer grid within the global bounding box, and the three 10-bit integer coordinates are interleaved to produce a single 30-bit Morton code @morton1966. The Morton code maps a three-dimensional position to a one-dimensional index along a Z-order (Morton) space-filling curve, so that particles that are spatially close in 3D tend to receive numerically similar codes. @fig:morton-binning illustrates this principle in two dimensions: the Z-curve (red dashed line) visits grid cells in an order that preserves spatial locality, so that after sorting by Morton code, particles in the same cell are stored contiguously in the sorted array. The same principle extends to three dimensions with octant interleaving.

#figure(
  image("../graphics/mortoncode.png", width: 70%),
  caption: [Spatial binning via a Z-order (Morton) space-filling curve in 2D. The dotted red line traces the curve through the grid. Spatially adjacent particles are stored contiguously in the sorted array. Adapted from Peláez @pelaez_thesis.],
) <fig:morton-binning>

+ *Radix sort.* The Morton codes and their associated particle indices are sorted into ascending order using a parallel radix sort. The radix sort processes the 32-bit keys in four passes (8 bits per pass), performing a prefix-sum histogram within each pass to determine output positions. This approach was chosen over the bitonic sort network @batcher1968 used in an earlier version of the implementation, because radix sort achieves $O(N)$ work complexity for fixed-width keys and scales more predictably on GPU hardware. An alternative is the onesweep radix sort, which is the most performant variant on native GPU APIs, but its reliance on fine-grained device-scope atomic operations makes it difficult to implement efficiently in WebGPU, where atomics are limited to workgroup and storage-buffer scope.

+ *Karras topology construction.* The sorted Morton codes define a binary radix tree whose internal structure is determined entirely by the codes themselves. For each internal node $i$, the Karras algorithm computes a direction and range by examining the _delta function_ $delta(i, j)$, defined as the number of leading zero bits in the bitwise XOR of Morton codes $k_i$ and $k_j$. Two codes that share a long common prefix (high $delta$) correspond to particles that are spatially close, because their Morton codes agree on the most significant bits of their interleaved coordinates. The algorithm determines each internal node's children by finding the split position within its range where the common prefix length changes. Duplicate Morton codes (which arise when two particles fall in the same grid cell) are handled by appending the particle index as a tie-breaker to ensure a unique ordering @maximizeparallel.

+ *Leaf initialisation.* Each leaf node is assigned the position, mass, and a point AABB corresponding to its sorted particle.

+ *Bottom-up aggregation.* Internal-node bounding boxes and centres of mass are computed in a bottom-up pass. An atomic counter per internal node tracks how many of its two children have been processed; the second thread to arrive at a node computes the merged AABB and mass-weighted centre of mass from both children, ensuring correctness without explicit synchronisation barriers.

The resulting BVH is immediately traversable without any CPU-side construction or data upload, eliminating what would otherwise be a per-step CPU–GPU transfer bottleneck.

#include "fig_lbvh_pipeline.typ"

== Force Traversal Optimisation

Profiling showed that BVH force evaluation accounts for 94–99% of total step time at all tested $N$, with LBVH construction contributing less than 1% even at $N = 100000$. We therefore focused all optimisation effort on the traversal shader, applying four changes and benchmarking each independently before combining them.

The baseline traversal shader performs three operations per node visit: a full 64-byte struct read from global memory, an opening-criterion computation involving approximately 20 floating-point operations including transcendental functions, and a stack-based depth-first traversal with no spatial ordering. Each represents a different bottleneck class (memory bandwidth, ALU throughput, and cache efficiency respectively), and the optimisations target all three.

*Precomputed opening radius.* The opening criterion depends only on node-intrinsic properties that are invariant across particle interactions. In the baseline, these are recomputed for every particle–node pair. The optimised version precomputes a scalar opening radius per node during the bottom-up aggregation pass, computed as $"halfExtent" = ||bold(R) - bold(c)|| dot (1 + 0.6 log_2(max(M, 1)))$ where $bold(R)$ is the centre of mass, $bold(c)$ is the nearest AABB corner, and $M$ is the node's total mass. The mass-adaptive scaling widens the opening radius for massive nodes, making the traversal more conservative (and more accurate) where gravitational influence is strongest. The precomputed radius is stored in an otherwise unused field, and the per-interaction test reduces to a single distance comparison $d^2 > r^2$. This eliminates redundant computation across all particle interactions, giving us a 1.74$times$ speedup at $N = 100000$.

*Compact traversal nodes.* The force shader reads a 64-byte BVH node per visit but uses only 28 bytes (centre of mass, opening radius, child indices). A compaction pass copies these fields into a 32-byte traversal buffer, reducing memory bandwidth per node visit. This provides an additional 3% improvement at large $N$.

*Workgroup size tuning.* Testing workgroup sizes of 64, 128, and 256 with otherwise identical code showed that 128 threads per workgroup (four SIMD groups on the Apple M2) provided the best balance between register pressure and occupancy for $N$ up to 50,000. This parameter is hardware-dependent and would require re-tuning on other GPUs.

*Morton-ordered particle access.* In the baseline, GPU thread $i$ processes particle $i$, so adjacent threads may handle spatially distant particles that traverse different parts of the tree, causing poor cache utilisation. The optimised version uses the Morton-code sort order already computed during LBVH construction: thread $i$ processes the particle at sorted index $i$, so adjacent threads handle spatially nearby particles that visit similar tree paths. This improves L1/L2 cache hit rates during traversal, yielding an additional 20% speedup at $N = 100000$.

We also tried two approaches that did not work. Near-far child ordering (pushing the farther child first so the nearer subtree is processed first) caused cache thrashing from the extra node reads, making force computation 10–30% slower. Warp-coherent traversal using subgroup operations was not feasible because WGSL subgroup support is limited to experimental extensions on Dawn.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (right, right, right, right),
    [*N*], [*Baseline (ms)*], [*Optimised (ms)*], [*Speedup*],
    [1,000], [5.8], [6.9], [0.84$times$],
    [5,000], [9.9], [8.0], [1.24$times$],
    [10,000], [11.3], [11.5], [$tilde$1.0$times$],
    [50,000], [109.5], [67.2], [1.63$times$],
    [100,000], [396.2], [183.9], [2.15$times$],
  ),
  caption: [Combined effect of all four traversal optimisations.],
) <tab:optimisation>

== Rendering and Interactive Operation

In interactive mode, particles are rendered as instanced billboard quads with additive blending. The vertex shader reads positions directly from the physics storage buffers, avoiding per-frame data uploads. A toggleable trail effect improves visibility in sparse scenarios (e.g. the two-body orbit): a screen-space accumulation buffer reprojects the previous frame's trails into the current camera view, fades them by a configurable amount, and composites new particle positions on top with additive blending, using a ping-pong texture pair. An ImGui overlay (@fig:simscreen) provides interactive control of parameters and displays diagnostics. In headless mode, rendering is skipped entirely.

#figure(
  image("../graphics/simscreen.png", width: 85%),
  caption: [Interactive mode showing the ImGui control overlay.],
) <fig:simscreen>

== Initial Conditions and Benchmark Scenarios <sec:initial-conditions>

All experiments start from synthetic initial conditions and produce derived outputs (trajectories, diagnostic scalars, timing logs), enabling  controlled and repeatable comparisons across parameter sweeps. Each experiment is fully specified by its simulation parameters: scenario type, seed, $N$, $Delta t$, $theta$, softening $epsilon$, and step count. Three benchmark scenarios are defined, with initial particle distributions shown in @fig:scenarios.

=== Scenario A: two-body circular orbit

Scenario A places two equal-mass particles ($m = 1000$ each, $N = 2$) separated by $d = 10$ units along the $x$-axis, with tangential velocities along the $z$-axis computed for a softened circular orbit:
#math.equation(
  $
    v = sqrt(frac(G m d^2, 2 (d^2 + epsilon^2)^(3/2)))
  $,
)
This is the simplest validation of integrator correctness. With the right timestep and softening, the two particles should maintain a stable circular orbit indefinitely under our leapfrog integrator. We can validate this quantitatively by measuring the energy drift over the full integration is measured directly, and any departures from the expected circularity can be isolated without confounding effects from hierarchical force approximation at a large $N$.

=== Scenario B: Plummer sphere

A Plummer sphere is a spherically symmetric, self-gravitating stellar system with a density that falls off smoothly with distance from the centre. It was first introduced by Plummer @plummer1911 as an empirical fit to the light profiles of globular clusters, and its density profile is given by $rho(r) prop (1 + r^2 \/ a^2)^(-5\/2)$, where $a$ is a scale length that sets the size of the core. Because the Plummer model has known analytic properties, such as closed-form expressions for the potential, escape velocity, and distribution function, it is used as a standard test case for $N$-body codes @galacticdynamics2nded @aarseth1974. Deviations from the expected equilibrium behaviour give us a diagnostic of force accuracy and integration stability.

Scenario B generates a Plummer sphere with scale length $a = 5$. Particle radii are sampled via the inverse cumulative distribution function
#math.equation(
  $
    r = frac(a, sqrt(u^(-2\/3) - 1))
  $,
)
with $u$ clamped to $[0.001, 0.999]$. Angular coordinates are isotropic: $cos(theta)$ is drawn uniformly and the azimuthal angle $phi.alt$ is drawn uniformly on $[0, 2 pi)$. Particle speeds are sampled with rejection sampling using
#math.equation(
  $
    g(q) = q^2 (1 - q^2)^(7/2)
  $,
)
against the local escape velocity
#math.equation(
  $
    v_e = sqrt(frac(2 G M, sqrt(r^2 + a^2)))
  $,
)
with isotropic velocity directions. This scenario tests tree accuracy and long-term stability in a compact three-dimensional distribution. The Plummer softening parameter $epsilon$ in the force model is conceptually related to the Plummer scale length $a$ in the initial conditions, though the two are independently configurable. The primary limitation is that the spherical geometry does not emphasize disk morphology such as spirals and bars.

=== Scenario C: rotating exponential disk (galaxy-like morphology test)

Scenario C generates a rotating disk to evaluate long-term evolution and visually interpretable galactic dynamics. The surface density profile follows an exponential distribution @freeman1970, with particle radii drawn from an exponential distribution (rate parameter 0.08) and clamped to a maximum of 50 units, and azimuthal angles drawn uniformly. Vertical height is drawn from a normal distribution $cal(N)(0, 0.3)$ scaled by $1 / (1 + 0.5 r)$ to produce a thinner disk at larger radii. Particle masses are drawn uniformly from $[0.5, 2.0]$.

Circular velocities are assigned using an approximate enclosed-mass estimate. For particles with $r > 0.1$, the tangential velocity is
#math.equation(
  $
    v = 0.5 sqrt(frac(M_"enclosed", r))
  $,
)
with the velocity directed tangentially. This simplified dynamical setup is not a full multi-component Milky Way model: the enclosed-mass estimate is approximate, and no bulge or halo component is included. The disk geometry provides a morphologically rich test case where the formation of spiral structure, bars, and other large-scale features validate the solver's long term behavior qualitatively.

=== Sampling and robustness across seeds

Because the initial conditions are stochastic, we assess robustness by repeating runs with different random seeds and comparing diagnostics and timing. A run is valid if it completes without NaN or overflow and produces consistent parameter logs. We deliberately retain unstable configurations (such as excessively large $Delta t$) as documented failures rather than silently excluding them.

#figure(
  stack(
    dir: ttb,
    spacing: 12pt,
    grid(
      columns: (1fr, 1fr),
      gutter: 12pt,
      figure(image("../graphics/fig_scenario_a.png", width: 100%), caption: [_(a) Two-body orbit with particle trails_], numbering: none),
      figure(image("../graphics/fig_scenario_b.png", width: 100%), caption: [_(b) Plummer sphere_], numbering: none),
    ),
    align(center,
      figure(image("../graphics/fig_scenario_c.png", width: 50%), caption: [_(c) Exponential disk_], numbering: none),
    ),
  ),
  caption: [Initial particle distributions for the three benchmark scenarios with plummer at $N = 10000$ and exponential disk with $N = 50000$.],
) <fig:scenarios>

== Evaluation Protocol <sec:evaluation-protocol>

The evaluation compares the WebGPU solver against a native Metal baseline and across multiple WebGPU implementations, using a consistent benchmarking protocol throughout.

The primary baseline is UniSim @unisim, which is an open-source galaxy simulator for a variety of integrators and backends, which we were able to use with Barnes–Hut and a Leapfrog integrator $N$-body solver written directly against the Metal API. The original UniSim contained a tree-serialisation bug: nodes were pushed bottom-up (leaves first, root last), but the GPU traversal kernel always began at index 0, which was a deep leaf rather than the root, causing most of the tree to be skipped during force evaluation. We patched the serialisation to reserve each node's slot before recursing into its children, placing the root at index 0 so that traversal covers the full tree @unisim-fork.  We use the direct $O(N^2)$ summation path within our solver as a secondary baseline for finding the crossover at which hierarchical force evaluation pays off.

The primary metric is runtime per timestep (ms/step), decomposed into three components: tree build time with the GPU LBVH construction, force evaluation time with the BVH traversal, and integration time with the kick and drift dispatches. This decomposition reveals which phase takes up the most time at each particle count. For the cross-backend comparison, we quantify abstraction overhead as the ratio of WebGPU ms/step to native Metal ms/step at matched $N$ and parameters. For the browser comparison, subtracting native GPU time from browser wall-clock time isolates the fixed per-step scheduling overhead.

Energy drift ($Delta E(t) = |E(t) - E(0)| \/ |E(0)|$) is reported as a secondary observation for $N lt.eq 5000$, where potential energy can be computed via direct pair summation. Momentum conservation is monitored throughout. These metrics characterise the 32-bit precision floor of WebGPU rather than constituting a primary research question.

Accurate GPU timing requires the CPU to wait for GPU work to complete before reading the clock. The synchronisation mechanism differs across backends: wgpu-native provides a blocking device poll, while Dawn and Emscripten use a buffer-map fence (a small staging buffer whose map callback fires only after all prior GPU work completes). Two timing modes are used: whole-step timing, in which a single command encoder records the entire timestep and the GPU is synchronised once at the end (used for total ms/step comparisons), and per-phase timing, in which separate command encoders and GPU synchronisations are issued per phase (used for the LBVH pass breakdown, at the cost of additional synchronisation overhead).

All measurements follow the benchmarking protocol described in the experiments section: 50 warmup steps discarded, 100 measured steps, with mean $plus.minus$ standard deviation, 95% confidence interval, and coefficient of variation reported for each configuration @maczan2026. All initial conditions are generated deterministically (default seed 42), and the execution environment is recorded alongside each run.

With the solver architecture, physical model, and evaluation protocol established, the following section specifies the experimental platform and the configurations used to evaluate each research question.
