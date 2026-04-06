#pagebreak()
= Methodology
#set heading(numbering: "1.1")

== Research Design and Objectives

This work adopts a computational-methods design in which a gravitational $N$-body solver is implemented and evaluated with a focus on reproducibility, long-term numerical stability, and computational scalability beyond the $O(N^2)$ cost of direct summation. The solver is implemented in C++20 using the WebGPU C API and built from a single codebase targeting both native desktop execution (via backends such as wgpu-native and Dawn) and browser execution (compiled via Emscripten) @webgpu-spec. This dual-target approach enables interactive visualization as well as headless batch runs, allowing performance and numerical behavior to be evaluated under comparable conditions across platforms.

The physical and numerical foundations of the implementation draw directly from the literature on hierarchical $N$-body simulation and GPU parallelism. The gravitational force model adopts Newtonian gravity with Plummer-type softening to avoid the $1/r^2$ singularity and reduce spurious two-body relaxation in collisionless regimes @galacticdynamics2nded. Accelerations are computed using a Barnes–Hut-style hierarchical approximation that reduces force evaluation from $O(N^2)$ to approximately $O(N log N)$ @barneshut, with the primary code path constructing and traversing a Linear Bounding Volume Hierarchy (LBVH) entirely on the GPU using the parallel method of Karras @maximizeparallel. Time integration employs a second-order symplectic leapfrog scheme (kick–drift–kick), selected for its improved long-term energy behavior relative to forward Euler in gravitational systems @springel_2005. The compute platform, WebGPU, provides general-purpose parallel compute shaders that enable both native and browser deployment through the same low-level API surface.

The evaluation is structured around three research questions:

1. *Scalability*: How does runtime per timestep scale with $N$ for a WebGPU Barnes–Hut implementation, and where are the bottlenecks within the GPU pipeline?
2. *Abstraction overhead*: What performance cost does the WebGPU abstraction layer impose relative to native Metal, and how does this vary across WebGPU implementations (wgpu-native, Dawn, browser)?
3. *Browser feasibility*: Can the same codebase, compiled to WebAssembly and running in a browser, achieve acceptable throughput and numerical consistency compared to native execution?

The choice of WebGPU as the compute platform is central to all three research questions; the following section provides a detailed justification.

== WebGPU Platform Justification

The Barnes–Hut algorithm at $O(N log N)$ requires a full tree rebuild and traversal at every timestep, each involving operations over the entire particle set. At the particle counts targeted by this work ($N$ up to $10^5$), these operations are dominated by data-parallel phases: computing bounding boxes, sorting Morton codes, constructing tree topology, and evaluating forces across all particles simultaneously. This degree of parallelism makes GPU execution essential for interactive frame rates, a conclusion broadly supported by the literature on GPU-accelerated $N$-body simulation @fluke2011 @owens2007 @surveyofcomputation.

The specific choice of WebGPU over established GPU APIs such as CUDA and OpenCL is motivated by three factors. First, WebGPU is a cross-platform compute and rendering API that exposes general-purpose compute shaders and storage buffers through a unified interface, running natively on Vulkan @vulkan-spec, Metal @metal-spec, and Direct3D 12 backends while also being deployable in web browsers @webgpu-spec @webgpu-gpuweb. This portability is central to the research objective of evaluating $N$-body simulation across diverse execution environments, from native desktop applications to browser-based deployments. Second, WebGPU's compute shader model provides the primitives required for tree-based algorithms: random-access storage buffer reads and writes, atomic operations for bottom-up aggregation, and flexible workgroup dispatch @usta_webgpu_2024 @realtimeclothsimulation. Third, WebGPU is an emerging W3C standard with active implementation across major browsers and native runtimes, positioning it as the successor to WebGL for GPU-accelerated web applications @realitycheck.

These advantages are accompanied by constraints that inform the implementation design. GPU-side computation in WebGPU is limited to 32-bit floating-point arithmetic, imposing a precision ceiling on force evaluation and integration. Buffer size limits and memory allocation patterns vary across devices and backends. Scheduling overhead for compute dispatches can be significant relative to kernel execution time at small $N$, and device variability across integrated and discrete GPUs affects both performance and available features @realitycheck. These constraints are explicitly tested through the platform-feasibility research question.

A comparative assessment of available GPU APIs clarifies the positioning of WebGPU. CUDA provides mature tooling and high performance for tree-based $N$-body codes @cudabarnes @bedorf2010, but is locked to NVIDIA hardware and has no browser deployment path. OpenCL offers cross-vendor support on desktop but lacks browser integration and has seen declining adoption in favour of vendor-specific APIs. WebGL provides broad browser reach but was designed for rendering, not general-purpose computation: it lacks compute shaders, storage buffers, and atomic operations, limiting it to fragment-shader workarounds for GPGPU tasks @terascalewebviz. WebGPU is uniquely positioned as both browser-deployable and compute-capable, making it the only viable API for evaluating an $N$-body solver across native and web environments from a single codebase. @fig:platform-comparison summarises this comparison.

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
  caption: [Comparison of GPU compute APIs against criteria required for hierarchical $N$-body simulation. WebGPU is the only API that combines compute shader support with browser deployability.],
) <fig:platform-comparison>

== Physical Model and State Representation

This section describes the gravitational force model, the GPU data layout for particle state, and the precision strategy that governs the split between GPU computation and CPU diagnostics.

Each particle represents a mass element evolving under self-gravity in an isolated (open) domain. The simulation adopts a natural unit system in which the gravitational constant $G = 1$, the unit of mass $M_0$ is defined by the total system mass, and the unit of length $r_0$ is set by the characteristic scale of the initial conditions (e.g., the Plummer scale length $a$ in Scenario B). Time is measured in units of $t_0 = sqrt(r_0^3 \/ (G M_0))$, the free-fall timescale of the system. All quantities reported in subsequent sections (energies, momenta, and timescales) are expressed in these natural units unless stated otherwise. The softened acceleration of particle $i$ due to all other particles is
#math.equation(
  $
    bold(a)_i = G sum_(j eq.not i) m_j frac(bold(r)_j - bold(r)_i, (||bold(r)_j - bold(r)_i||^2 + epsilon^2)^(3/2))
  $,
)
where $bold(r)_i$ and $bold(r)_j$ are the position vectors of particles $i$ and $j$, $m_j$ is the mass of particle $j$, and $epsilon$ is a softening length (default 0.5, configurable). The softening parameter introduces a Plummer-type potential that suppresses the $1\/r^2$ singularity at short range, preventing divergent accelerations during close encounters @galacticdynamics2nded. This formulation is equivalent to treating each particle as a smooth mass distribution of characteristic radius $epsilon$ rather than a point mass.

On the GPU, particle state is stored as packed four-component vectors (`vec4<f32>`), with each particle's mass occupying the $w$ component of its position vector to yield a layout of $(x, y, z, m)$. This packing reduces the number of buffer reads required during force evaluation compared to maintaining separate position and mass buffers. A Structure-of-Arrays (SoA) layout separating positions and masses was considered but rejected after analysis: the BVH force shader (which accounts for 95–99% of step time) never reads particle masses directly, instead using the aggregated node masses computed during the bottom-up pass. The shaders that do read particle mass (leaf initialisation, drift) always access position and mass together, so separating them would increase cache misses. The shaders that read only position (bounding box, Morton code) account for less than 1% of step time, making the potential bandwidth saving negligible. @fig:particle-layout summarises the storage layout for all three state arrays.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto),
    align: (center, center, center, center, center),
    [*Component*], [`.x`], [`.y`], [`.z`], [`.w`],
    [`positions[i]`], [$x_i$], [$y_i$], [$z_i$], [$m_i$],
    [`velocities[i]`], [$v_(x,i)$], [$v_(y,i)$], [$v_(z,i)$], [0],
    [`accelerations[i]`], [$a_(x,i)$], [$a_(y,i)$], [$a_(z,i)$], [0],
  ),
  caption: [Particle state layout using `vec4<f32>` packing. Mass is stored in the $w$ component of the position vector to reduce buffer count and memory bandwidth during force evaluation.],
) <fig:particle-layout>

All GPU kernels operate in 32-bit floating point, which maximises throughput and matches the capabilities of current WebGPU implementations. Diagnostic quantities (total energy and linear momentum) are computed on the CPU in double precision (64-bit) to reduce accumulation error over long integrations. This split reflects the practical precision-versus-performance trade-off inherent in WebGPU, where 64-bit GPU arithmetic is not available @realitycheck.

== Time Integration

Time integration uses a fixed-timestep, second-order symplectic leapfrog integrator in kick–drift–kick (KDK) form @verlet1967. In the following equations, the superscript $n$ denotes the discrete timestep index, and $bold(r)_i^n$, $bold(v)_i^n$, $bold(a)_i^n$ are the position, velocity, and acceleration vectors of particle $i$ at step $n$ respectively. With timestep $Delta t$ (default $10^(-4)$), the update proceeds in three stages. First, a half-kick advances velocities by half a step using the current accelerations:
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

The leapfrog scheme is chosen for its well-known long-term stability in gravitational dynamics @springel_2005. Unlike forward Euler, which introduces secular energy drift proportional to $Delta t$, the leapfrog is time-reversible and symplectic: it preserves the phase-space volume of the Hamiltonian system, producing bounded energy oscillations rather than monotonic growth @galacticdynamics2nded. These properties make it substantially more suitable for long-horizon integrations.

The most expensive step in each integration cycle is the evaluation of accelerations $bold(a)_i$, which is addressed through hierarchical approximation in the following section.

== Hierarchical Force Evaluation

Rather than computing all $N(N-1)\/2$ pairwise interactions directly, the solver groups distant particles into tree nodes and approximates each group by a single equivalent mass. This section describes the monopole approximation used to represent these groups and the opening criterion that determines when a node is sufficiently distant to be treated as a single body.

Each internal node of the tree stores a total mass $M = sum_(i in "node") m_i$ and a center of mass $bold(R) = (sum_(i in "node") m_i bold(r)_i) \/ M$, computed by aggregating over all particles contained in that node's subtree. When a node is accepted as a monopole, its gravitational contribution to particle $i$ is
#math.equation(
  $
    bold(a)_(i,"node") = G M frac(bold(R) - bold(r)_i, (||bold(R) - bold(r)_i||^2 + epsilon^2)^(3/2))
  $,
)
The tree is implemented as a binary Bounding Volume Hierarchy (BVH) constructed and traversed entirely on the GPU.

An internal node is accepted as a monopole when it is sufficiently small relative to its distance from the target particle. The opening criterion tests whether the squared maximum extent of the node's axis-aligned bounding box (AABB) satisfies $"maxExtent"^2 \/ d^2 < theta^2$, where $"maxExtent" = max(Delta x, Delta y, Delta z)$ and $d^2 = ||bold(r)_i - bold(R)||^2$. This extent-based criterion reflects the non-cubic node shapes that arise in a BVH more accurately than a uniform half-width, and is expressed in squared form to avoid a per-node square root. Salmon and Warren provide rigorous error bounds for these opening criteria, showing that the conventional Barnes–Hut criterion can admit unbounded errors for $theta >= 1\/3$ in pathological configurations @skeletons_1994.

@fig:opening-criterion illustrates the geometry of both criteria. The default opening angle $theta = 0.75$ is used as a practical balance between accuracy and performance. For comparison, GADGET-2 uses $theta$ values in the range 0.5 to 0.7 for cosmological simulations where higher force accuracy is required @springel_2005, while the original Barnes and Hut paper used $theta = 1.0$ @barneshut. The parameter sweeps in the evaluation protocol (see @sec:evaluation-protocol) systematically characterize the accuracy–performance trade-off across $theta in {0.3, 0.5, 0.7, 1.0}$.

#figure(
  image("../graphics/fig_opening_criterion.png", width: 100%),
  caption: [Geometry of the opening criterion. A node is approximated as a monopole when its angular size, as measured by extent/$d$, falls below the threshold $theta$. Left: BVH variant using maximum AABB extent. Right: octree variant using cell half-width.],
) <fig:opening-criterion>

== Software Architecture and Execution Modes

The implementation is written in C++20 for host-side orchestration and physics, with WGSL for GPU compute and rendering shaders, using the WebGPU C API directly without wrapper libraries. The build system uses CMake with pinned dependency versions to ensure deterministic builds. Three build backends are supported: wgpu-native @wgpu-native (the Rust-based WebGPU implementation), Dawn @dawn (Google's WebGPU implementation), and Emscripten (which cross-compiles the C++ codebase to WebAssembly for browser deployment).

All physics operations (integration, tree construction, and force evaluation) are performed entirely on the GPU each step. The CPU is used only for diagnostic computation: at configurable intervals, positions and velocities are read back through staging buffers and energy and momentum are computed in double precision (64-bit). No per-step CPU physics overhead is incurred in the primary execution path.

The GPU-primary execution mode relies on a set of WebGPU compute shaders organized into a per-timestep pipeline, described in the following section.

== WebGPU Compute Methodology

This section describes the GPU-side data layout, the compute shader organisation, and the per-timestep execution pipeline that together form the core of the solver.

Simulation state is stored in WebGPU storage buffers using the packed `vec4<f32>` layout described in @fig:particle-layout: positions (with mass in the $w$ component), velocities, and accelerations. The BVH is stored as a flat array of $2N - 1$ nodes, each containing a centre of mass, total mass, and axis-aligned bounding box. A uniform parameters buffer shares simulation parameters between host and shader code. In-place updates are used throughout: there is no double buffering of positions, velocities, or accelerations. Correct ordering between compute passes relies on WebGPU's implicit storage-buffer synchronisation between dispatches within a single command buffer submission. Bind groups are cached and reused across frames to avoid per-frame recreation overhead.

The solver comprises WGSL compute shaders in two groups: integration and force evaluation (direct-summation baseline and BVH-traversal), and LBVH construction in seven passes @morton1966 @maximizeparallel. Workgroup sizes are tuned per kernel (128 for force evaluation, 256 for integration and tree building; the workgroup size selection is discussed in the optimisation section below).

=== Per-timestep execution sequence

Each timestep is recorded into a single command encoder and submitted as one command buffer. The six sequential passes, illustrated in @fig:timestep-pipeline, are: (1) a half-kick that advances velocities by $Delta t \/ 2$ using the current accelerations; (2) a drift that advances positions by $Delta t$ using the half-stepped velocities; (3) a full LBVH rebuild comprising seven sub-passes (global AABB reduction, Morton code generation, radix sort, Karras topology construction, leaf initialisation, and bottom-up aggregation); (4) BVH force evaluation, in which each particle traverses the tree iteratively using a fixed-depth explicit stack (depth 64, sufficient for all tested $N$); (5) a second half-kick that completes the velocity update; and (6) an optional diagnostics readback at configurable intervals, in which positions and velocities are copied to the CPU via staging buffers for double-precision energy and momentum computation.

#figure(
  image("../graphics/fig_timestep_pipeline.png", width: 50%),
  caption: [Per-timestep GPU execution pipeline for the leapfrog integrator. All six passes are recorded into a single command buffer. The LBVH build (pass 3) comprises seven sub-passes with implicit barrier synchronization between each.],
) <fig:timestep-pipeline>

=== GPU tree traversal

Because GPU compute shaders do not support recursion, tree traversal is implemented iteratively in the BVH force shader. One GPU thread is assigned per particle, and the thread maintains an explicit stack of node indices (maximum depth 64), beginning from the root. At each step, a node is either accepted as a monopole (if it is a leaf, or if the opening criterion is satisfied) and its gravitational contribution is accumulated, or it is expanded by pushing its two children onto the stack. This explicit-stack approach preserves the Barnes–Hut approximation structure while accommodating the lack of a call stack on GPU hardware and limiting branch divergence across threads within a workgroup @fastnbody @cudabarnes @maximizeparallel.

=== GPU LBVH construction

The Linear Bounding Volume Hierarchy is built fully on the GPU each timestep, following the parallel construction method of Karras @maximizeparallel. The construction proceeds through seven compute dispatches, illustrated in @fig:lbvh-pipeline:

+ *Global bounding box reduction.* A two-pass parallel reduction over all particle positions computes the axis-aligned bounding box of the entire system. This bounding box defines the coordinate range used to normalise positions in the next step.

+ *Morton code generation.* Each particle's position is normalised to a $[0, 1023]^3$ integer grid within the global bounding box, and the three 10-bit integer coordinates are interleaved to produce a single 30-bit Morton code @morton1966. The Morton code maps a three-dimensional position to a one-dimensional index along a Z-order (Morton) space-filling curve, so that particles that are spatially close in 3D tend to receive numerically similar codes.

+ *Radix sort.* The Morton codes and their associated particle indices are sorted into ascending order using a parallel radix sort. The radix sort processes the 30-bit keys in fixed-width digit passes (4 bits per pass), performing a prefix-sum histogram within each pass to determine output positions. This approach was chosen over the bitonic sort network @batcher1968 used in an earlier version of the implementation, because radix sort achieves $O(N)$ work complexity for fixed-width keys and scales more predictably on GPU hardware. An alternative is the onesweep radix sort, which is the most performant variant on native GPU APIs, but its reliance on fine-grained device-scope atomic operations makes it difficult to implement efficiently in WebGPU, where atomics are limited to workgroup and storage-buffer scope.

+ *Karras topology construction.* The sorted Morton codes define a binary radix tree whose internal structure is determined entirely by the codes themselves. For each internal node $i$, the Karras algorithm computes a direction and range by examining the _delta function_ $delta(i, j)$, defined as the number of leading zero bits in the bitwise XOR of Morton codes $k_i$ and $k_j$. Two codes that share a long common prefix (high $delta$) correspond to particles that are spatially close, because their Morton codes agree on the most significant bits of their interleaved coordinates. The algorithm determines each internal node's children by finding the split position within its range where the common prefix length changes. Duplicate Morton codes (which arise when two particles fall in the same grid cell) are handled by appending the particle index as a tie-breaker to ensure a unique ordering @maximizeparallel.

+ *Leaf initialisation.* Each leaf node is assigned the position, mass, and a point AABB corresponding to its sorted particle.

+ *Bottom-up aggregation.* Internal-node bounding boxes and centres of mass are computed in a bottom-up pass. An atomic counter per internal node tracks how many of its two children have been processed; the second thread to arrive at a node computes the merged AABB and mass-weighted centre of mass from both children, ensuring correctness without explicit synchronisation barriers.

The resulting BVH is immediately traversable without any CPU-side construction or data upload, eliminating what would otherwise be a per-step CPU–GPU transfer bottleneck.

#figure(
  image("../graphics/fig_lbvh_pipeline.png", width: 45%),
  caption: [LBVH construction pipeline. Seven compute dispatches build the tree entirely on-device. Each arrow represents an implicit storage-buffer barrier. The atomic-counter aggregation in pass 6 ensures correct bottom-up propagation of bounding boxes and centers of mass.],
) <fig:lbvh-pipeline>

== Force Traversal Optimisation

Profiling revealed that BVH force evaluation accounts for 95–99% of total step time across all tested $N$, with LBVH construction contributing less than 1% even at $N = 100000$. Optimisation efforts were therefore focused exclusively on the traversal shader. Four optimisations were applied, each benchmarked independently before combining.

The baseline traversal shader performs three operations per node visit: a full 64-byte struct read from global memory, an opening-criterion computation involving approximately 20 floating-point operations including transcendental functions, and a stack-based depth-first traversal with no spatial ordering. Each represents a different bottleneck class (memory bandwidth, ALU throughput, and cache efficiency respectively), and the optimisations target all three.

*Precomputed opening radius.* The opening criterion depends only on node-intrinsic properties (centre of mass, AABB bounds, total mass) that are invariant across particle interactions. In the baseline, these are recomputed for every particle–node pair. The optimised version precomputes a scalar opening radius per node during the bottom-up aggregation pass and stores it in an otherwise unused field. This eliminates redundant computation across all particle interactions, yielding a 1.74$times$ speedup at $N = 100000$.

*Compact traversal nodes.* The force shader reads a 64-byte BVH node per visit but uses only 28 bytes (centre of mass, opening radius, child indices). A compaction pass copies these fields into a 32-byte traversal buffer, reducing memory bandwidth per node visit. This provides an additional 3% improvement at large $N$.

*Workgroup size tuning.* Testing workgroup sizes of 64, 128, and 256 with otherwise identical code showed that 128 threads per workgroup (four SIMD groups on the Apple M2) provided the best balance between register pressure and occupancy for $N$ up to 50,000. This parameter is hardware-dependent and would require re-tuning on other GPUs.

*Morton-ordered particle access.* In the baseline, GPU thread $i$ processes particle $i$, so adjacent threads may handle spatially distant particles that traverse different parts of the tree, causing poor cache utilisation. The optimised version uses the Morton-code sort order already computed during LBVH construction: thread $i$ processes the particle at sorted index $i$, so adjacent threads handle spatially nearby particles that visit similar tree paths. This improves L1/L2 cache hit rates during traversal, yielding an additional 20% speedup at $N = 100000$.

Two additional approaches were investigated and rejected. Near-far child ordering (pushing the farther child first so the nearer subtree is processed first) caused cache thrashing from the extra node reads, making force computation 10–30% slower. Warp-coherent traversal using subgroup operations was not feasible because WGSL subgroup support is limited to experimental extensions on the Dawn backend.

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
  caption: [Combined effect of all four traversal optimisations. The overhead of the compaction pass and sort-index lookup causes a small regression at $N = 1000$; the crossover where optimisations break even is approximately $N = 3000$.],
) <tab:optimisation>

== Rendering and Interactive Operation

In interactive mode, particles are rendered as instanced billboard quads with additive blending. The vertex shader reads positions directly from the physics storage buffers, avoiding per-frame data upload. An ImGui overlay provides interactive control of simulation parameters and displays real-time diagnostics. In headless mode, rendering is skipped entirely for pure throughput measurement.

Having described the solver and its implementation, the following section specifies the benchmark scenarios used to evaluate it.

== Initial Conditions and Benchmark Scenarios <sec:initial-conditions>

No external astronomical datasets are used. All experiments are generated from synthetic initial conditions and produce derived outputs (trajectories, diagnostic scalars, and timing logs). This enables controlled, repeatable comparisons across parameter sweeps. Each experiment is fully specified by its simulation parameters: scenario type, seed, $N$, $Delta t$, $theta$, softening $epsilon$, and step count. Three benchmark scenarios are defined, with initial particle distributions shown in @fig:scenarios.

=== Scenario A: two-body circular orbit

Scenario A places two equal-mass particles ($m = 1000$ each, $N = 2$) separated by $d = 10$ units along the $x$-axis, with tangential velocities along the $z$-axis computed for a softened circular orbit:
#math.equation(
  $
    v = sqrt(frac(G m d^2, 2 (d^2 + epsilon^2)^(3/2)))
  $,
)
This configuration provides the simplest possible validation of integrator correctness: with the correct timestep and softening, the two particles should maintain a stable circular orbit indefinitely under the leapfrog scheme. Validation is quantitative rather than visual: the energy drift $Delta E \/ |E(0)|$ over the full integration is measured directly, and departures from circularity can be isolated without confounding effects from hierarchical force approximation at large $N$.

=== Scenario B: Plummer sphere

A Plummer sphere is a spherically symmetric, self-gravitating stellar system whose density falls off smoothly with distance from the centre. It was first introduced by Plummer @plummer1911 as an empirical fit to the light profiles of globular clusters, and its density profile is given by $rho(r) prop (1 + r^2 \/ a^2)^(-5\/2)$, where $a$ is a scale length that sets the size of the core. Because the Plummer model has known analytic properties — including closed-form expressions for the potential, escape velocity, and distribution function — it is widely used as a standard test case for $N$-body codes @galacticdynamics2nded @aarseth1974. Deviations from the expected equilibrium behaviour provide a direct diagnostic of force accuracy and integration stability.

Scenario B generates a Plummer sphere with $N in [10^3, 10^5]$ (depending on hardware) and scale length $a = 5$. Particle radii are sampled via the inverse cumulative distribution function
#math.equation(
  $
    r = frac(a, sqrt(u^(-2\/3) - 1))
  $,
)
with $u$ clamped to $[0.001, 0.999]$. Angular coordinates are isotropic: $cos(theta)$ is drawn uniformly and the azimuthal angle $phi.alt$ is drawn uniformly on $[0, 2 pi)$. Particle speeds are sampled via rejection sampling using
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
with isotropic velocity directions. This scenario tests tree accuracy and long-term stability in a compact three-dimensional distribution. The Plummer softening parameter $epsilon$ in the force model is conceptually related to the Plummer scale length $a$ in the initial conditions, though the two are independently configurable. The key sweep variables are $theta$, $epsilon$, and $Delta t$; the primary limitation is that the spherical geometry does not emphasize disk morphology such as spirals and bars.

=== Scenario C: rotating exponential disk (galaxy-like morphology test)

Scenario C generates a rotating disk with $N in [10^4, 10^5]$ to evaluate long-term evolution and visually interpretable galactic dynamics. The surface density profile follows an exponential distribution @freeman1970, with particle radii drawn from an exponential distribution (rate parameter 0.08) and clamped to a maximum of 50 units, and azimuthal angles drawn uniformly. Vertical height is drawn from a normal distribution $cal(N)(0, 0.3)$ scaled by $1 / (1 + 0.5 r)$ to produce a thinner disk at larger radii. Particle masses are drawn uniformly from $[0.5, 2.0]$.

Circular velocities are assigned using an approximate enclosed-mass estimate. For particles with $r > 0.1$, the tangential velocity is
#math.equation(
  $
    v = 0.5 sqrt(frac(M_"enclosed", r))
  $,
)
with the velocity directed tangentially. This simplified dynamical setup is not a full multi-component Milky Way model: the enclosed-mass estimate is approximate, and no bulge or halo component is included. Nevertheless, the disk geometry provides a morphologically rich test case in which the formation and persistence of spiral structure, bars, and other large-scale features serve as qualitative validation of the solver's long-term behavior. The key sweep variables are disk scale length, thickness, velocity dispersion, $theta$, and $Delta t$.

=== Sampling and robustness across seeds

Because initial conditions are stochastic, robustness is assessed by repeating runs with different random seeds and comparing diagnostics and timing. Runs are considered valid if they complete without NaN or overflow values and produce consistent parameter logs. Deliberately unstable configurations (such as excessively large $Delta t$) are retained as documented failures for robustness reporting rather than silently excluded.

#figure(
  grid(
    columns: 3,
    gutter: 12pt,
    figure(image("../graphics/fig_scenario_a.png", width: 100%), caption: [_(a) Two-body orbit_], numbering: none),
    figure(image("../graphics/fig_scenario_b.png", width: 100%), caption: [_(b) Plummer sphere_], numbering: none),
    figure(image("../graphics/fig_scenario_c.png", width: 100%), caption: [_(c) Exponential disk_], numbering: none),
  ),
  caption: [Initial particle distributions for the three benchmark scenarios. (a) Scenario A: two-body orbit. (b) Scenario B: Plummer sphere with $N = 10000$. (c) Scenario C: exponential disk with $N = 50000$.],
) <fig:scenarios>

== Evaluation Protocol <sec:evaluation-protocol>

The evaluation is designed to answer the three research questions by comparing the WebGPU solver against a native Metal baseline and across multiple WebGPU implementations, using a consistent benchmarking protocol throughout.

The primary baseline is UniSim @unisim, an open-source Barnes–Hut $N$-body solver written directly against the Metal API. Because UniSim runs on the same Apple M2 GPU using the same Metal driver as the WebGPU implementations, the performance difference isolates the overhead introduced by the WebGPU abstraction layer. A direct $O(N^2)$ summation path within the WebGPU solver serves as a secondary baseline for characterising the crossover point at which hierarchical force evaluation becomes beneficial.

The primary metric is runtime per timestep (milliseconds per step), decomposed into three components: tree build time (GPU LBVH construction), force evaluation time (BVH traversal), and integration time (kick and drift dispatches). This decomposition identifies which phase of the pipeline dominates at each particle count. For the cross-backend comparison, the abstraction overhead is quantified as the ratio of WebGPU ms/step to native Metal ms/step at matched $N$ and parameters. For the browser comparison, the browser wall-clock time minus the native GPU time yields the fixed per-step scheduling overhead.

Energy drift, defined as $Delta E(t) = |E(t) - E(0)| \/ |E(0)|$, is reported as a secondary observation for $N lt.eq 5000$ (where potential energy is computed via direct pair summation). Momentum conservation is monitored throughout. These numerical quality metrics characterise the 32-bit precision floor of WebGPU rather than serving as a primary research question.

Accurate GPU timing requires the CPU to wait for GPU work to complete before reading the clock. The synchronisation mechanism differs across backends: wgpu-native provides a blocking device poll, while Dawn and Emscripten use a buffer-map fence (a small staging buffer whose map callback fires only after all prior GPU work completes). Two timing modes are used: whole-step timing, in which a single command encoder records the entire timestep and the GPU is synchronised once at the end (used for total ms/step comparisons), and per-phase timing, in which separate command encoders and GPU synchronisations are issued per phase (used for the LBVH pass breakdown, at the cost of additional synchronisation overhead).

All measurements follow the benchmarking protocol described in the experiments section: 50 warmup steps discarded, 100 measured steps, with mean $plus.minus$ standard deviation, 95% confidence interval, and coefficient of variation reported for each configuration @maczan2026. All initial conditions are generated deterministically (default seed 42), and the execution environment is recorded alongside each run.
