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

The specific choice of WebGPU over established GPU APIs such as CUDA and OpenCL is motivated by three factors. First, WebGPU is a cross-platform compute and rendering API that exposes general-purpose compute shaders and storage buffers through a unified interface, running natively on Vulkan, Metal, and Direct3D 12 backends while also being deployable in web browsers @webgpu-spec @webgpu-gpuweb. This portability is central to the research objective of evaluating $N$-body simulation across diverse execution environments, from native desktop applications to browser-based deployments. Second, WebGPU's compute shader model provides the primitives required for tree-based algorithms: random-access storage buffer reads and writes, atomic operations for bottom-up aggregation, and flexible workgroup dispatch @usta_webgpu_2024 @realtimeclothsimulation. Third, WebGPU is an emerging W3C standard with active implementation across major browsers and native runtimes, positioning it as the successor to WebGL for GPU-accelerated web applications @realitycheck.

These advantages are accompanied by constraints that inform the implementation design. GPU-side computation in WebGPU is limited to 32-bit floating-point arithmetic, imposing a precision ceiling on force evaluation and integration. Buffer size limits and memory allocation patterns vary across devices and backends. Scheduling overhead for compute dispatches can be significant relative to kernel execution time at small $N$, and device variability across integrated and discrete GPUs affects both performance and available features @realitycheck. These constraints are explicitly tested through the platform-feasibility research question.

A comparative assessment of available GPU APIs clarifies the positioning of WebGPU. CUDA provides mature tooling and high performance for tree-based $N$-body codes @cudabarnes @bedorf2010, but is locked to NVIDIA hardware and has no browser deployment path. OpenCL offers cross-vendor support on desktop but lacks browser integration and has seen declining adoption in favour of vendor-specific APIs. WebGL provides broad browser reach but was designed for rendering, not general-purpose computation: it lacks compute shaders, storage buffers, and atomic operations, limiting it to fragment-shader workarounds for GPGPU tasks @terascalewebviz. WebGPU is uniquely positioned as both browser-deployable and compute-capable, making it the only viable API for evaluating an $N$-body solver across native and web environments from a single codebase.

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

=== Softened gravitational acceleration

Each particle represents a mass element evolving under self-gravity in an isolated (open) domain. Using dimensionless units with $G = 1$, the softened acceleration of particle $i$ is
#math.equation(
  $
    a_i = G sum_(j eq.not i) m_j frac(r_j - r_i, (||r_j - r_i||^2 + epsilon^2)^(3/2))
  $,
)
The softening parameter $epsilon$ (default 0.5, configurable) introduces a Plummer-type potential that suppresses the $1/r^2$ singularity at short range @galacticdynamics2nded. This formulation is equivalent to treating each particle as a Plummer sphere rather than a point mass, and the same softening kernel appears in the Plummer-model initial conditions used in Scenario B (see @sec:initial-conditions).

=== GPU-friendly mass packing

To reduce memory bandwidth on the GPU, each particle's mass is stored in the $w$ component of its position vector, yielding a packed `vec4<f32>` layout of $(x, y, z, m)$ that avoids a dedicated mass buffer. Because GPU compute throughput is frequently limited by memory bandwidth rather than arithmetic capacity, this packing halves the number of buffer reads required during force evaluation compared to a separate position and mass layout.

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

=== Precision strategy

GPU kernels operate in 32-bit floating point to maximize throughput and match typical WebGPU device capabilities. Diagnostic quantities (total energy and momentum) are computed on the CPU in double precision to reduce accumulation error in long-running integrations. This split reflects the practical precision-versus-performance trade-off inherent in WebGPU environments, where 64-bit GPU arithmetic is not available @realitycheck.

== Time Integration

=== Primary integrator: symplectic leapfrog (KDK)

The primary integration scheme is a fixed-timestep, second-order symplectic leapfrog (kick–drift–kick) @verlet1967. With timestep $Delta t$ (default 0.0001), the update sequence is:
1. Half-kick:
#math.equation(
  $
    v_i^(n+1\/2) = v_i^(n) + frac(Delta t, 2) a_i^n
  $,
)
2. Drift:
#math.equation(
  $
    r_i^(n+1) = r_i^(n) + Delta t v_i^(n+1\/2)
  $,
)
3. Recompute acceleration $a_i^(n+1)$ using updated positions.
4. Half-kick:
#math.equation(
  $
    v_i^(n+1) = v_i^(n+1\/2) + frac(Delta t, 2) a_i^(n+1)
  $,
)

This choice is motivated by the well-known long-term stability advantages of symplectic schemes in gravitational dynamics @springel_2005. Unlike forward Euler, which introduces secular energy drift proportional to $Delta t$, the leapfrog scheme is time-reversible and exhibits bounded energy oscillation rather than monotonic growth, making it substantially more suitable for long-horizon integrations in Hamiltonian systems @galacticdynamics2nded. The energy conservation behavior of leapfrog relative to Euler is quantified in the evaluation protocol (see @sec:evaluation-protocol).

=== Euler integrator (baseline and fallback)

A forward Euler method is retained as `--integrator euler` to provide a stability baseline. Its update sequence is: tree build, force evaluation, then
#math.equation(
  $
    v arrow.l v + a Delta t, space r arrow.l r + v Delta t
  $,
)
The Euler integrator serves as a lower bound on numerical quality against which the leapfrog scheme is compared.

The most expensive step in each integration cycle is the evaluation of accelerations, addressed through hierarchical approximation in the following section.

== Hierarchical Force Evaluation

=== Monopole approximation

Hierarchical evaluation approximates distant particle groups by a single monopole at the node's center of mass. For a node with total mass $M$ and center of mass $R$,
#math.equation(
  $
    a_(i,"node") = G M frac(R - r_i, (||R - r_i||^2 + epsilon^2)^(3/2))
  $,
)
This monopole approximation is used consistently across both tree topologies implemented in this work: a binary Bounding Volume Hierarchy (BVH) on the GPU and an eight-way octree on the CPU. Only the tree representation and the geometry of the opening criterion differ between the two paths.

=== Opening criteria

An internal node is accepted as a monopole approximation when it is sufficiently small relative to its distance from the target particle. The GPU BVH path uses a tight axis-aligned bounding box (AABB) and tests whether the squared maximum extent of the node satisfies $"maxExtent"^2 / d^2 < theta^2$, where $"maxExtent" = max(Delta x, Delta y, Delta z)$ is derived from the node's AABB bounds. This extent-based criterion reflects the non-cubic node shapes that arise in a BVH more accurately than a uniform half-width. The CPU octree path uses the conventional half-width criterion $h^2 / d^2 < theta^2$, where $h$ is the half-width of the cubic octree cell and $d^2 = ||r_i - R||^2$. Both formulations are expressed in squared form to avoid a per-node square root. Salmon and Warren provide rigorous error bounds for these opening criteria, showing that the conventional Barnes–Hut criterion can admit unbounded errors for $theta >= 1\/3$ in pathological configurations @skeletons_1994.

The default opening angle $theta = 0.75$ is used as a practical balance between accuracy and performance. For comparison, GADGET-2 uses $theta$ values in the range 0.5 to 0.7 for cosmological simulations where higher force accuracy is required @springel_2005, while the original Barnes and Hut paper used $theta = 1.0$ @barneshut. The parameter sweeps in the evaluation protocol (see @sec:evaluation-protocol) systematically characterize the accuracy–performance trade-off across $theta in {0.3, 0.5, 0.7, 1.0}$.

#figure(
  rect(width: 100%, height: 6cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Tree opening criterion geometry showing a target particle, a distant tree node, the distance $d$, the node extent, and the $theta$ threshold for both BVH (maximum AABB extent) and octree (half-width) variants._]
  ],
  caption: [Geometry of the opening criterion. A node is approximated as a monopole when its angular size, as measured by extent/$d$, falls below the threshold $theta$. Left: BVH variant using maximum AABB extent. Right: octree variant using cell half-width.],
) <fig:opening-criterion>

== Software Architecture and Execution Modes

The implementation is written in C++20 for host-side orchestration and physics, with WGSL for compute and rendering shaders, using the WebGPU C API directly without wrapper libraries. The build system uses CMake with FetchContent and pinned dependency versions to ensure deterministic builds. Dependencies fetched automatically include WebGPU-distribution (v0.2.0), GLFW (3.4), glfw3webgpu (v1.2.0), spdlog (v1.16.0), Dear ImGui (v1.90.9), and GLM (1.0.2). Three build backends are supported: `WGPU` (wgpu-native), `DAWN` (Dawn), and `EMSCRIPTEN` (browser build with `-sASYNCIFY`, `-sALLOW_MEMORY_GROWTH=1`, `-sUSE_GLFW=3`).

The primary execution mode is GPU-primary: all physics operations (integration, tree construction, and force evaluation) are performed on the GPU each step. Diagnostic quantities are computed on the CPU only at configurable intervals through staging-buffer readback of positions and velocities, with the diagnostic frequency set to every 60 frames in interactive mode and every step or every 50 steps in headless mode depending on $N$. To support cross-checking and fallback behavior, CPU mirror arrays (`cpuPositions_`, `cpuVelocities_`, `cpuAccelerations_`) are retained and used by non-primary modes (Euler and CPU-tree leapfrog), where scalar CPU loops and a CPU octree are executed in parallel with the GPU path. This design yields two methodological advantages: first, no per-step CPU physics overhead in the primary mode, since the tree is built directly from GPU-resident particle state; second, cross-validation potential across runs, since selecting the CPU octree versus GPU BVH path provides two independent hierarchical implementations for comparative diagnostics.

#figure(
  rect(width: 100%, height: 7cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: System architecture block diagram showing C++ host orchestration, WebGPU compute shader dispatch, GPU storage buffers (positions, velocities, accelerations, BVH nodes), staging buffer readback for diagnostics, CPU mirror arrays for fallback paths, and the rendering pipeline reading directly from storage buffers._]
  ],
  caption: [System architecture overview. The GPU-primary path (solid arrows) performs all physics on-device. CPU mirror arrays (dashed arrows) support fallback execution modes and cross-validation. Diagnostic readback occurs at configurable intervals via staging buffers.],
) <fig:system-architecture>

The GPU-primary execution mode relies on a set of WebGPU compute shaders organized into a per-timestep pipeline, described in the following section.

== WebGPU Compute Methodology

=== GPU data layout

Simulation state is stored in WebGPU storage buffers using the packed `vec4<f32>` layout described in @fig:particle-layout: positions (with mass in the $w$ component), velocities, and accelerations. The BVH is stored as an array of `BVHNode` structures with $2N - 1$ entries (internal nodes indexed $0$ to $N - 2$, leaves indexed $N - 1$ to $2N - 2$), where each node stores a center of mass and a tight AABB. A flattened CPU octree buffer is maintained for fallback paths, using explicit child fields (`c0` through `c7`) to avoid dynamic indexing limitations in WGSL. A uniform parameters buffer shares layout-matched simulation parameters between C++ and WGSL. In-place updates are used throughout: there is no double buffering of positions, velocities, or accelerations. Correct ordering between compute passes relies on WebGPU's implicit storage-buffer synchronization between dispatches within a single command buffer submission, with bind groups recreated each frame.

=== Compute shaders

The implementation comprises twelve WGSL compute shaders organized into two functional groups. The first group handles integration and force evaluation: a direct-summation baseline shader, an octree-traversal fallback shader, the primary BVH-traversal force shader, and kick/drift and Euler integration shaders. The second group implements LBVH construction in seven passes: two-pass bounding-box reduction, Morton code generation @morton1966, bitonic sort with multiple sub-passes @batcher1968, Karras topology construction @maximizeparallel, leaf initialization, and bottom-up aggregation via atomic counters. Workgroup sizes are fixed per kernel (64 for force evaluation, 256 for integration and tree building) and are reported as part of the implementation configuration.

=== Per-timestep execution sequence (GPU-primary leapfrog)

Each timestep is recorded into a single command encoder and submitted as one command buffer. The six sequential passes are:
1. Half-kick: $v arrow.l v + (a Delta t) / 2$
2. Drift: $r arrow.l r + v Delta t$
3. LBVH build (7 sub-passes): global AABB reduction $arrow.r$ Morton code generation $arrow.r$ bitonic sort $arrow.r$ Karras topology construction $arrow.r$ leaf initialization $arrow.r$ bottom-up aggregation
4. BVH force evaluation: iterative traversal with fixed-depth explicit stack (depth 64, sufficient for all tested $N$)
5. Half-kick: $v arrow.l v + (a Delta t) / 2$
6. Diagnostics readback (periodic): stage-map-readback $arrow.r$ CPU double-precision energy and momentum computation

#figure(
  rect(width: 60%, height: 8cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Vertical flow diagram showing the six per-timestep passes: half-kick, drift, LBVH build (with 7 sub-passes expanded), BVH force evaluation, half-kick, and periodic diagnostics readback._]
  ],
  caption: [Per-timestep GPU execution pipeline for the leapfrog integrator. All six passes are recorded into a single command buffer. The LBVH build (pass 3) comprises seven sub-passes with implicit barrier synchronization between each.],
) <fig:timestep-pipeline>

=== GPU traversal (iterative, no recursion)

Tree traversal is implemented iteratively in the BVH force shader. One GPU thread is assigned per particle. The thread maintains an explicit stack of node indices, beginning from the root. A node is either accepted (leaf or opening criterion satisfied) and accumulated via the monopole approximation, or expanded by pushing its children onto the stack. Fast inverse square root (`inverseSqrt`) is used for inverse-distance evaluation, and a self-interaction guard avoids contributions from degenerate near-zero distances. This approach preserves the Barnes–Hut approximation structure while accommodating GPU execution constraints and limiting branch divergence where possible @fastnbody @cudabarnes @maximizeparallel.

=== GPU LBVH construction (Karras 2012)

The LBVH is built fully on-device in seven conceptual steps. First, a two-pass parallel reduction computes the global axis-aligned bounding box. Second, particle positions are normalized to a $[0, 1023]^3$ integer grid and their bits interleaved to produce 30-bit Morton codes @morton1966, which impose a spatial ordering along a space-filling Z-curve. Third, Morton codes and associated particle indices are sorted using a bitonic sort network @batcher1968 with multiple $(k, j)$ sub-passes and dynamic uniform offsets; arrays are padded to the next power of two, with sentinel codes assigned to padding elements. Fourth, the parallel binary tree topology is constructed using the Karras delta function (leading zeros of the XOR of adjacent codes, with tie-breaking for duplicates) @maximizeparallel. Fifth, leaves are initialized by mapping sorted indices to particle positions, masses, and point AABBs. Sixth, internal-node AABBs and centers of mass are aggregated bottom-up using atomic counters to ensure both children are processed before their parent. The resulting BVH is immediately traversable without CPU-side construction or upload, eliminating a per-step CPU bottleneck in the primary execution mode.

#figure(
  rect(width: 70%, height: 8cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Vertical flow diagram showing the seven LBVH construction sub-passes with data dependencies: (1) global AABB reduction, (2) Morton code generation, (3) bitonic sort, (4) Karras topology, (5) leaf initialization, (6) bottom-up aggregation. Arrows indicate barrier synchronization points between passes._]
  ],
  caption: [LBVH construction pipeline. Seven compute dispatches build the tree entirely on-device. Each arrow represents an implicit storage-buffer barrier. The atomic-counter aggregation in pass 6 ensures correct bottom-up propagation of bounding boxes and centers of mass.],
) <fig:lbvh-pipeline>

=== CPU octree construction (fallback paths)

The CPU octree is used only by Euler and CPU-tree leapfrog modes. It is built from CPU mirror arrays by computing a bounding box, inserting particles via octant selection, propagating centers of mass bottom-up, and optionally flattening to a GPU-friendly node array when GPU evaluation is used. GPU buffers auto-resize during uploads when needed.

== Rendering and Interactive Operation

For visualization, particles are rendered as instanced billboard quads with additive blending. Positions and colors are read directly from storage buffers via `@builtin(instance_index)`, requiring no separate vertex buffer. Depth testing is enabled with depth writes disabled; fragments are masked to a circular footprint with a soft alpha falloff. An ImGui overlay provides interactive control of simulation parameters ($theta$, $Delta t$, $epsilon$, and integrator selection) and displays real-time diagnostics including energy, momentum, and per-component timing breakdowns. In headless mode, the rendering pipeline is skipped entirely and the simulation loop runs without any presentation overhead, enabling pure throughput measurement. Rendering is a presentation layer and does not alter the simulation state.

Having described the solver and its implementation, the following section specifies the benchmark scenarios used to evaluate it.

== Initial Conditions and Benchmark Scenarios <sec:initial-conditions>

No external astronomical datasets are used. All experiments are generated from synthetic initial conditions and produce derived outputs (trajectories, diagnostic scalars, and timing logs). This design eliminates licensing and privacy concerns and enables controlled, repeatable comparisons across parameter sweeps. Each experiment is fully specified by command-line parameters: scenario type, seed, $N$, $Delta t$, $theta$, softening $epsilon$, and step count.

=== Scenario A: two-body orbit (sanity check)

Scenario A places two equal-mass particles ($m = 1000$ each, $N = 2$ enforced regardless of the `--N` parameter) separated by $d = 10$ units along the $x$-axis, with tangential velocities along the $z$-axis computed for a softened circular orbit:
#math.equation(
  $
    v = sqrt(frac(G m d^2, 2 (d^2 + epsilon^2)^(3/2)))
  $,
)
This configuration provides the simplest possible validation of integrator correctness. With the correct timestep and softening, the two particles should maintain a stable circular orbit indefinitely under the leapfrog scheme. Departures from circularity provide a direct diagnostic for integration error, and the sensitivity to $Delta t$ and $epsilon$ can be isolated without confounding effects from hierarchical force approximation. The scenario is not representative of large-$N$ hierarchical behavior, but it is an essential sanity check that must pass before more complex scenarios are credible.

=== Scenario B: Plummer sphere (spherical equilibrium test)

Scenario B generates a Plummer sphere @plummer1911 @aarseth1974 with $N in [10^3, 10^5]$ (depending on hardware) and scale length $a = 5$. The Plummer model is a classical self-gravitating equilibrium configuration in which the density profile follows $rho(r) prop (1 + r^2 / a^2)^(-5/2)$, and it is widely used as a test case for $N$-body codes because of its known analytic properties @galacticdynamics2nded. Particle radii are sampled via the inverse cumulative distribution function
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

Because initial conditions are stochastic, robustness is assessed by repeating runs with different seeds (`--seed 1`, `--seed 2`, and so on) and comparing diagnostics and timing. Initial condition generation uses `std::mt19937` seeded by the `--seed` parameter (default 42), ensuring deterministic reproduction of particle distributions and velocities. Runs are considered valid if they complete without NaN or overflow values and produce consistent parameter logs. Deliberately unstable configurations (such as excessively large $Delta t$) are retained as documented failures for robustness reporting rather than silently excluded.

#figure(
  rect(width: 100%, height: 6cm, stroke: 0.5pt + gray, inset: 1em)[
    #align(center + horizon)[_Placeholder: Three-panel figure showing initial particle distributions. Left: Scenario A (two-body orbit, two particles with velocity vectors). Center: Scenario B (Plummer sphere, spherically symmetric particle cloud). Right: Scenario C (exponential disk, face-on view showing disk structure)._]
  ],
  caption: [Initial particle distributions for the three benchmark scenarios. (a) Scenario A: two-body orbit. (b) Scenario B: Plummer sphere with $N = 10000$. (c) Scenario C: exponential disk with $N = 50000$.],
) <fig:scenarios>

== Evaluation Protocol: Baselines, Metrics, and Parameter Sweeps <sec:evaluation-protocol>

=== Baselines

Two baselines are used. The first is a direct $O(N^2)$ summation, which serves as a reference computation path for small $N$. Potential energy is computed by direct pair summation only when $N lt.eq 5000$ due to its $O(N^2)$ cost. The second baseline is the forward Euler integrator (`--integrator euler`), which provides a numerical stability reference against which the leapfrog scheme is compared.

=== Primary metrics

Runtime per timestep (measured in milliseconds per step using `std::chrono::high_resolution_clock`) is decomposed into three components: tree build time (GPU LBVH construction or CPU octree construction plus upload), force evaluation time (GPU BVH traversal or CPU Barnes–Hut walk), and integration time (kick and drift dispatches, including any CPU mirror loops on fallback paths). This decomposition identifies which phase dominates at each particle count and reveals the tree-build fraction, which is a key indicator of the overhead introduced by per-step hierarchy construction.

Scaling with particle count is characterized by measuring total and per-component runtimes across a range of $N$ values for both hierarchical and direct modes, producing empirical scaling curves that are compared against the expected $O(N log N)$ and $O(N^2)$ asymptotic behavior. Long-term stability is assessed through energy drift, defined as $Delta E(t) = |E(t) - E(0)| / |E(0)|$, reported only for $N lt.eq 5000$ where potential energy is computed via direct pair summation. For larger $N$, stability is assessed through kinetic energy trends and momentum diagnostics.

=== Secondary metrics

Linear momentum magnitude $||P(t)|| = ||sum_i m_i v_i||$ is computed in double precision and is expected to remain near zero for symmetric initial conditions (Plummer sphere) while reflecting the net angular momentum of the disk scenario. Qualitative morphology in disk runs (persistence of spiral arms, bar formation, and overall structural evolution) is reported descriptively as a complement to quantitative diagnostics, providing a visual sanity check on solver behavior over long integration times.

=== Parameter sweeps

To characterize accuracy–performance trade-offs and stability regimes, controlled parameter sweeps are performed via the command-line interface. The opening angle $theta$ is swept over ${0.3, 0.5, 0.7, 1.0}$, the timestep $Delta t$ is varied across a scenario-dependent stable range, and the softening parameter $epsilon$ is tested across representative values. Each sweep also compares the Euler and leapfrog integrators and the CPU octree versus GPU LBVH construction paths. Results are compared using exported CSV logs containing per-step diagnostics and timing.

=== Error analysis procedure

When instability or anomalous drift occurs, runs are inspected for correlations with dense versus diffuse particle regions, large $theta$, large $Delta t$, small $epsilon$, and platform or backend differences. Failures (NaN values, overflow, and extreme velocities) are detected explicitly and logged rather than silently suppressed.

=== Comparative positioning

To situate the performance of this implementation within the broader landscape of GPU $N$-body codes, key metrics are mapped to those reported in existing literature. Burtscher and Pingali report throughput for a CUDA Barnes–Hut implementation on NVIDIA hardware @cudabarnes, and Gaburov, Bédorf, and Portegies Zwart report CUDA tree-code performance including tree-build fractions at varying $N$ @bedorf2010. Nyland, Harris, and Prins provide reference throughput figures for GPU $N$-body methods in the CUDA ecosystem @fastnbody. While direct comparison is limited by differences in hardware generation, precision (64-bit versus 32-bit), tree topology (octree versus BVH), and opening criteria, the metrics collected in this work (throughput at given $N$, tree-build fraction of total step time, and crossover $N$ between direct and hierarchical methods) are chosen to enable meaningful comparison with these published results.

Beyond the quantitative metrics, the methodology incorporates several validation strategies to ensure correctness and robustness.

== Validation and Robustness

The validation strategy rests on three pillars: theoretical grounding, empirical checks, and explicit acknowledgment of practical constraints. On the theoretical side, the Barnes–Hut hierarchical approximation with tunable opening angle $theta$ follows Barnes and Hut @barneshut, the leapfrog integration scheme is a standard choice for long-horizon gravitational dynamics due to its symplectic stability properties @springel_2005, the GPU hierarchy construction follows the widely used parallel LBVH method of Karras @maximizeparallel, and the GPU traversal methodology follows established considerations for irregular tree algorithms on SIMD-style hardware @cudabarnes @fastnbody.

Empirical validation is provided at multiple levels. Scenario A (two-body orbit) offers a controlled sanity check for orbit stability and integrator correctness, where deviations from the analytic circular orbit can be directly measured. Deterministic seeds and complete parameter logging ensure that any run can be exactly reproduced. Fixed step counts (`--steps`) provide consistent comparison across runs, and instability events are recorded rather than filtered. The availability of both CPU octree and GPU BVH execution paths allows cross-validation of force evaluation results for the same initial conditions.

Practical constraints are explicitly acknowledged. Interactive runs couple stepping to the render loop, while headless mode prioritizes throughput. Particle count is adjustable from 2 to 100,000. Potential energy tracking is intentionally limited to $N lt.eq 5000$ to avoid prohibitive $O(N^2)$ overhead; for larger $N$, stability is assessed through kinetic energy and momentum diagnostics combined with qualitative morphological assessment. These precision and buffer constraints connect directly to the WebGPU platform limitations described in the platform justification section, where 32-bit arithmetic and device variability were identified as fundamental characteristics of the target environment.

== Data Ethics, Security, and Integrity

No personal or sensitive data are collected. All computation runs locally (native) or within the user's browser sandbox (Emscripten). Diagnostic logs and trajectories are exported only when explicitly requested (`--export`). Each CSV export is linked to the complete set of runtime parameters (scenario, $N$, $Delta t$, $theta$, $epsilon$, seed, integrator, steps). The primary practical risk is high GPU load; mitigation is provided through adjustable $N$ and configurable step limits.

== Reproducibility and Traceability

Reproducibility of build and configuration is ensured through several mechanisms. Initial condition generation uses `std::mt19937` with the seed recorded at startup (default 42), producing deterministic particle distributions and velocities for any given parameter set. All third-party dependency versions are pinned through CMake FetchContent, and the complete set of CLI parameters is logged at startup via spdlog alongside the GPU adapter name and selected WebGPU backend, creating a full record of the execution environment for each run.

Output reproducibility and cross-environment comparison are supported by the CSV export format, which records per-step diagnostics and timing: step number, simulation time, kinetic energy, potential energy (when $N lt.eq 5000$), total energy, energy drift, momentum components ($p_x$, $p_y$, $p_z$), tree-build time, force-evaluation time, and integration time. The dual build targets (native and browser) are produced from the same source code, enabling direct cross-environment comparison of both numerical results and performance characteristics under identical simulation parameters.
