#pagebreak()
= Methodology
#set heading(numbering: "1.1")

== Research Design and Objectives

This work adopts a computational-methods design in which a gravitational $N$-body solver is implemented and evaluated with a focus on reproducibility, long-term numerical stability, and computational scalability beyond the $O(N^2)$ cost of direct summation. The solver is implemented in C++20 using the WebGPU C API and built from a single codebase targeting both native desktop execution (via backends such as wgpu-native and Dawn) and browser execution (compiled via Emscripten) @webgpu-spec. This dual-target approach enables interactive visualization as well as headless batch runs, allowing performance and numerical behavior to be evaluated under comparable conditions across platforms.

The physical and numerical foundations of the implementation draw directly from the literature on hierarchical $N$-body simulation and GPU parallelism. The gravitational force model adopts Newtonian gravity with Plummer-type softening to avoid the $1/r^2$ singularity and reduce spurious two-body relaxation in collisionless regimes @galacticdynamics2nded. Accelerations are computed using a Barnes–Hut-style hierarchical approximation that reduces force evaluation from $O(N^2)$ to approximately $O(N log N)$ @barneshut, with the primary code path constructing and traversing a Linear Bounding Volume Hierarchy (LBVH) entirely on the GPU using the parallel method of Karras @maximizeparallel. Time integration employs a second-order symplectic leapfrog scheme (kick–drift–kick), selected for its improved long-term energy behavior relative to forward Euler in gravitational systems @springel_2005. The compute platform, WebGPU, provides general-purpose parallel compute shaders that enable both native and browser deployment through the same low-level API surface.

The evaluation is structured around three operational research questions:

1. *Scalability*: How does runtime per timestep scale with $N$ for a WebGPU Barnes–Hut implementation compared to a direct $O(N^2)$ baseline at small $N$?
2. *Numerical quality*: For fixed $N$, how do timestep size $Delta t$ and opening angle $theta$ affect (a) long-term conservation behavior (energy and momentum drift where measurable) and (b) stability under long integrations?
3. *Platform feasibility*: What particle counts and timestep rates are practical under WebGPU constraints (32-bit GPU arithmetic, buffer and memory limits, scheduling overhead, and device variability)?

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

On the GPU, particle state is stored as packed four-component vectors (`vec4<f32>`), with each particle's mass occupying the $w$ component of its position vector to yield a layout of $(x, y, z, m)$. This packing reduces the number of buffer reads required during force evaluation compared to maintaining separate position and mass buffers. However, it also means the mass is fetched during phases that do not require it (such as tree construction), which represents a trade-off between force-evaluation bandwidth and overall memory traffic. The question of whether a Structure-of-Arrays (SoA) layout, which stores positions and masses in separate contiguous arrays, would reduce unnecessary bandwidth consumption during non-force phases remains an open question for future optimisation. @fig:particle-layout summarises the storage layout for all three state arrays.

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

The solver supports two integration schemes: a symplectic leapfrog as the primary integrator and a forward Euler method as a baseline for comparison. Both operate with a fixed global timestep $Delta t$.

The primary scheme is the second-order symplectic leapfrog integrator in kick–drift–kick (KDK) form @verlet1967. In the following equations, the superscript $n$ denotes the discrete timestep index, and $bold(r)_i^n$, $bold(v)_i^n$, $bold(a)_i^n$ are the position, velocity, and acceleration vectors of particle $i$ at step $n$ respectively. With timestep $Delta t$ (default $10^(-4)$), the update proceeds in three stages. First, a half-kick advances velocities by half a step using the current accelerations:
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

A forward Euler method is also implemented as a stability baseline. Its update sequence is
#math.equation(
  $
    bold(v)_i^(n+1) = bold(v)_i^(n) + bold(a)_i^n Delta t, quad bold(r)_i^(n+1) = bold(r)_i^(n) + bold(v)_i^(n+1) Delta t
  $,
)
The Euler integrator serves as a lower bound on numerical quality against which the leapfrog scheme is compared. The energy conservation behaviour of both integrators is quantified in the evaluation protocol (see @sec:evaluation-protocol).

The most expensive step in each integration cycle is the evaluation of accelerations $bold(a)_i$, which is addressed through hierarchical approximation in the following section.

== Hierarchical Force Evaluation

Rather than computing all $N(N-1)\/2$ pairwise interactions directly, the solver groups distant particles into tree nodes and approximates each group by a single equivalent mass. This section describes the monopole approximation used to represent these groups and the opening criterion that determines when a node is sufficiently distant to be treated as a single body.

Each internal node of the tree stores a total mass $M = sum_(i in "node") m_i$ and a center of mass $bold(R) = (sum_(i in "node") m_i bold(r)_i) \/ M$, computed by aggregating over all particles contained in that node's subtree. When a node is accepted as a monopole, its gravitational contribution to particle $i$ is
#math.equation(
  $
    bold(a)_(i,"node") = G M frac(bold(R) - bold(r)_i, (||bold(R) - bold(r)_i||^2 + epsilon^2)^(3/2))
  $,
)
This monopole approximation is used consistently across both tree topologies implemented in this work: a binary Bounding Volume Hierarchy (BVH) on the GPU and an eight-way octree on the CPU. Only the tree representation and the geometry of the opening criterion differ between the two paths.

An internal node is accepted as a monopole when it is sufficiently small relative to its distance from the target particle. The GPU BVH path uses a tight axis-aligned bounding box (AABB) and tests whether the squared maximum extent of the node satisfies $"maxExtent"^2 \/ d^2 < theta^2$, where $"maxExtent" = max(Delta x, Delta y, Delta z)$ is derived from the node's AABB bounds. This extent-based criterion reflects the non-cubic node shapes that arise in a BVH more accurately than a uniform half-width. The CPU octree path uses the conventional half-width criterion $h^2 \/ d^2 < theta^2$, where $h$ is the half-width of the cubic octree cell and $d^2 = ||bold(r)_i - bold(R)||^2$. Both formulations are expressed in squared form to avoid a per-node square root. Salmon and Warren provide rigorous error bounds for these opening criteria, showing that the conventional Barnes–Hut criterion can admit unbounded errors for $theta >= 1\/3$ in pathological configurations @skeletons_1994.

@fig:opening-criterion illustrates the geometry of both criteria. The default opening angle $theta = 0.75$ is used as a practical balance between accuracy and performance. For comparison, GADGET-2 uses $theta$ values in the range 0.5 to 0.7 for cosmological simulations where higher force accuracy is required @springel_2005, while the original Barnes and Hut paper used $theta = 1.0$ @barneshut. The parameter sweeps in the evaluation protocol (see @sec:evaluation-protocol) systematically characterize the accuracy–performance trade-off across $theta in {0.3, 0.5, 0.7, 1.0}$.

#figure(
  image("../graphics/fig_opening_criterion.png", width: 100%),
  caption: [Geometry of the opening criterion. A node is approximated as a monopole when its angular size, as measured by extent/$d$, falls below the threshold $theta$. Left: BVH variant using maximum AABB extent. Right: octree variant using cell half-width.],
) <fig:opening-criterion>

== Software Architecture and Execution Modes

The implementation is written in C++20 for host-side orchestration and physics, with WGSL for GPU compute and rendering shaders, using the WebGPU C API directly without wrapper libraries. The build system uses CMake with pinned dependency versions to ensure deterministic builds. Three build backends are supported: wgpu-native @wgpu-native (the Rust-based WebGPU implementation), Dawn @dawn (Google's WebGPU implementation), and Emscripten (which cross-compiles the C++ codebase to WebAssembly for browser deployment).

The primary execution mode is GPU-primary: all physics operations (integration, tree construction, and force evaluation) are performed entirely on the GPU each step. Diagnostic quantities (total energy and momentum) are computed on the CPU at configurable intervals by reading back positions and velocities through staging buffers. In this mode, no per-step CPU physics overhead is incurred, since the tree is built and traversed directly from GPU-resident particle state. A secondary execution mode provides an independent CPU code path: a conventional octree is built from CPU-side copies of the particle state, and forces are evaluated via scalar tree traversal in double precision. This CPU path is invoked as a separate run configuration rather than running simultaneously with the GPU, providing cross-validation by allowing the same initial conditions to be evaluated through two independent hierarchical implementations. @fig:system-architecture provides an overview of both execution paths.

#figure(
  image("../graphics/fig_system_architecture.png", width: 80%),
  caption: [System architecture overview. The GPU-primary path (solid arrows) performs all physics on-device. CPU mirror arrays (dashed arrows) support fallback execution modes and cross-validation. Diagnostic readback occurs at configurable intervals via staging buffers.],
) <fig:system-architecture>

The GPU-primary execution mode relies on a set of WebGPU compute shaders organized into a per-timestep pipeline, described in the following section.

== WebGPU Compute Methodology

This section describes the GPU-side data layout, the compute shader organisation, and the per-timestep execution pipeline that together form the core of the solver.

Simulation state is stored in WebGPU storage buffers using the packed `vec4<f32>` layout described in @fig:particle-layout: positions (with mass in the $w$ component), velocities, and accelerations. The BVH is stored as a flat array of $2N - 1$ nodes, each containing a centre of mass, total mass, and axis-aligned bounding box. A uniform parameters buffer shares simulation parameters between host and shader code. In-place updates are used throughout: there is no double buffering of positions, velocities, or accelerations. Correct ordering between compute passes relies on WebGPU's implicit storage-buffer synchronisation between dispatches within a single command buffer submission. Bind groups are cached and reused across frames to avoid per-frame recreation overhead.

Twelve WGSL compute shaders implement the solver: five for integration and force evaluation (including direct-summation and tree-traversal variants), and seven for LBVH construction @morton1966 @maximizeparallel. Workgroup sizes are fixed per kernel (64 for force evaluation, 256 for integration and tree building).

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

A CPU octree path is also available as a separate run configuration, providing cross-validation of force evaluation in double precision against the GPU BVH path.

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

== Evaluation Protocol: Baselines, Metrics, and Parameter Sweeps <sec:evaluation-protocol>

Two baselines are used. The first is a direct $O(N^2)$ summation, which serves as a reference computation path for small $N$. Potential energy is computed by direct pair summation only when $N lt.eq 5000$ due to its $O(N^2)$ cost. The second baseline is the forward Euler integrator, which provides a numerical stability reference against which the leapfrog scheme is compared.

=== Metrics

Runtime per timestep (measured in milliseconds per step using `std::chrono::high_resolution_clock`) is decomposed into three components: tree build time (GPU LBVH construction or CPU octree construction plus upload), force evaluation time (GPU BVH traversal or CPU Barnes–Hut walk), and integration time (kick and drift dispatches, including any CPU mirror loops on fallback paths). This decomposition identifies which phase dominates at each particle count and reveals the tree-build fraction, which is a key indicator of the overhead introduced by per-step hierarchy construction.

Scaling with particle count is characterized by measuring total and per-component runtimes across a range of $N$ values for both hierarchical and direct modes, producing empirical scaling curves that are compared against the expected $O(N log N)$ and $O(N^2)$ asymptotic behavior. Long-term stability is assessed through energy drift, defined as $Delta E(t) = ( |E(t) - E(0)| ) / ( |E(0)| )$, reported only for $N lt.eq 5000$ where potential energy is computed via direct pair summation. For larger $N$, stability is assessed through kinetic energy trends and momentum diagnostics.

Linear momentum magnitude $||bold(P)(t)|| = ||sum_i m_i bold(v)_i||$ is computed in double precision and is expected to remain near zero for symmetric initial conditions (Plummer sphere) while reflecting the net angular momentum of the disk scenario. Qualitative morphology in disk runs (persistence of spiral arms, bar formation, and overall structural evolution) is reported descriptively as a complement to quantitative diagnostics.

To characterise accuracy–performance trade-offs and stability regimes, controlled parameter sweeps are performed. The opening angle $theta$ is swept over ${0.3, 0.5, 0.7, 1.0}$, the timestep $Delta t$ is varied across a scenario-dependent stable range, and the softening parameter $epsilon$ is tested across representative values. Each sweep also compares the Euler and leapfrog integrators and the CPU octree versus GPU LBVH construction paths. When instability or anomalous drift occurs, runs are inspected for correlations with dense versus diffuse particle regions, large $theta$, large $Delta t$, small $epsilon$, and platform or backend differences. Failures (NaN values, overflow, and extreme velocities) are detected explicitly and logged rather than silently suppressed.

All initial conditions are generated deterministically using a seeded pseudo-random number generator (default seed 42), ensuring that any run can be exactly reproduced. The execution environment and all simulation parameters are recorded alongside each run. Potential energy is computed via direct pair summation only for $N lt.eq 5000$ due to its $O(N^2)$ cost; for larger $N$, numerical quality is assessed through kinetic energy trends and momentum conservation.
