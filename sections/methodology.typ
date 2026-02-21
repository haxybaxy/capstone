#pagebreak()
= Methodology
#set heading(numbering: "1.1")
== Research Design and Objectives
This work adopts a computational-methods design in which a gravitational $N$-body solver is implemented and evaluated with a focus on reproducibility, long-term numerical stability, and computational scalibility beyond the $O(N^2)$ cost of direct summation. The solver is implemented in C++20 using the WebGPU C API and is built from a single codebase targetting both:
- Native desktop execution, using WebGPU backends such as wgpu-native and Dawn.
- Browser execution, compiled via Emscripten.
This dual-target approach enables interactive visualizaiton as well as headless batch runs, allowing performance and numerical behavior to be evaluated under comparable conditions across platforms.

The methodological choices follwo directly from the literature foundations on hierarchical $N$-body simulation and GPU parallelism:
- *Force Model*: Newtonian gravity with Plummer-type softening to avoid the $1/r^2$ singularity and reduce spurious two-body relaxation in collisionless regimes.
- *Acceleration strategy*: a Barnes-Hut style hierarchical approximation that reduces force-evaluation from $O(N^2)$ to approximately $O(N log N)$ @barneshut. In the primary path, both tree construction and force evaluation are executed on the GPU: a Linear Bounding Volume Hierarchy (LBVH) is constructed fully on-device using the parallel method of @maximizeparallel, removing the per-step CPU to GPU tree upload bottleneck.
- *Time Integration*: a second order symplectic leapfrog integrator (kick–drift–kick; also known as velocity Verlet in an equivalent form) selected for improved long-term energy behavior relative to forward Euler in gravitational systems @springel_2005.
- *Compute platform*: WebGPU compute shaders for general-purpose parallel kernels, enabling both native and browser deployment through the same low-level API surface.

The evaluation is structured around three operational research questions:

1. *Scalability*: How does runtime per timestep scale with $N$ for a WebGPU Barnes-Hut implementation compared to a direct $O(N^2)$ baseline at small $N$?
2. *Numerical quality*: For fixed $N$, how do timestep size $Delta t$ and opening angle $theta$ affect (a) long-term conservation behavior (energy and momentum drift where measurable) and (b) stability under long integrations?
3. *Platform feasibility*: what particle counts and timestep rates are practical under WebGPU constraints (32-bit GPU arithmetic, buffer/memory limits, scheduling overhead, and device variability)?

== Initial conditions and benchmark scenarios
No external astronomical datasets are used. All experiments are generated from synthetic initial conditions and produce derived outputs (trajectories, diagnostic scalars, and timing logs). This design eliminates licensing and privacy concerns and enables controlled, repeatable comparisons across parameter sweeps.

Each experiment is fully specified by command-line parameters: scenario type, seed, $N$, $Delta t$, $theta$, softening $epsilon$, and step count. Initial condition generation uses `std::mt19937` seeded by `--seed` (default seed = 42), ensuring deterministic reproduction of particle distributions and velocities.

=== Scenario A -- Two-body orbit (sanity check)

- *Scope*: $N = 2$ (enforced regardless of the `--N` parameter)
- *Purpose*: verifies integrator correctness and sensitivity to $Delta t$ and $epsilon$.
- *Setup*: two equal-mass particles ($m = 1000$ each) separated by $d = 10$ units along the $x$-axis, with tangential velocities along the $z$-axis computed for a softened circular orbit:
#math.equation(
  $
    v = sqrt(frac(G m d^2, 2 (d^2 + epsilon^2)^(3/2)))
  $,
)
- *Key variables*: $Delta t$, $epsilon$
- *Limitations*: not representative of large-N hierarchical behavior
=== Scenario B -- Plummer sphere (spherical equilibrium test)
- *Scope*: $N in [10^3, 10^5]$ (depending on hardware).
- *Purpose*: tests tree accuracy and stability in a compact 3D distribution with known analytic properties.
- *Setup*: a Plummer model @aarseth1974 with scale length $a = 5$. Radii sampled via inverse CDF:
#math.equation(
  $
    r = frac(a, sqrt(u^(-2/3)-1))
  $,
)
with $u$ clamped to $[0.001, 0.999]$. Angular coordinates are isotropic (uniform $cos(theta)$, uniform $phi.alt$). Speeds are sampled via rejection sampling using
#math.equation(
  $
    g(q) = q^2(1-q^2)^(7/2)
  $,
)
against the local escape velocity
#math.equation(
  $
    v_e = sqrt(frac(2 G M, sqrt(r^2 + a^2)))
  $,
)
with isotropic velocity directions.

- *Key variables*: $theta$, $epsilon$, $Delta t$
- *Limitations*: does not emphasize disk morphology (spirals/bars)

=== Scenario C -- Rotating exponential disk (galaxy-like morphology test)
- *Scope*: $N in [10^4, 10^5]$
- *Purpose*: evaluates long-term evolution and visually interpretable galactic dynamics
- *Setup*: radii drawn from an exponential distribution (rate 0.08) and  clamped to 50, uniform azimuth. Vertical height is drawn from $N(0, 0.3)$ scaled by $1/(1 + 0.5r)$. Masses are uniform in $[0.5, 2.0]$. Circular velocities are assigned with an approximate enclosed-mass estimate, using (for $r>0.1$)
#math.equation(
  $
    v = 0.5 sqrt(frac(M_"enclosed", r))
  $,
)
with tangential direction.
- *Key variables*: disk scale length, thickness, velocity dispersion, $theta$, $Delta t$
- *Limitations*: simplified dynamical setup (not a full multi-component Milky Way model); enclosed-mass estimate is approximate.

=== Sampling and robustness across seeds
Because these scenarios are stochastic, robustness is assessed by repeating runs with different seeds (`--seed 1`, `--seed 2`, …) and comparing diagnostics and timing. Runs are considered valid if they complete without NaNs/overflow and produce consistent parameter logs. Deliberately unstable settings (e.g., excessively large $Delta t$) are retained as documented failures for robustness reporting rather than silently excluded.

== Physical model and state representation

=== Softened gravitational acceleration
Each particle represents a mass element evolving under self-gravity in an isolated (open) domain. Using dimensionless units with
$G=1$, the softened acceleration of particle $i$ is
#math.equation(
  $
    a_i = G sum_(j eq.not i) m_j frac(r_j - r_i, (||r_j - r_i||^2 + epsilon^2)^(3/2))
  $,
)
Softening parameter $epsilon$ defaults to 0.5 and is configurable.

=== GPU-friendly mass packing
To reduce memory bandwidth, each particle mass is stored in the w component of its position vector (`vec4: x,y,z,m`), avoiding a dedicated mass buffer.

=== Precision strategy
GPU kernels operate in 32-bit floating point to maximize throughput and match typical WebGPU availability. Diagnostic quantities (energy and momentum) are computed on the CPU in double precision to reduce accumulation error. This split reflects the practical precision/performance trade-off in WebGPU environments.

== Time Integration

=== Primary integrator: symplectic leapfrog (KDK)
The primary integration scheme is a fixed-timestep, second-order symplectic leapfrog (kick-drift-kick). With timestep $Delta t$ (default (0.0001) the update is:
1. Half-kick
#math.equation(
  $
    v_i^(n+1/2) = v_i^(n) + (Delta t)/2 a_i^n
  $,
)
2. Drift
#math.equation(
  $
    r_i^(n+1) = r_i^(n) + Delta t v_i^(n+1/2)
  $,
)
3. Recompute acceleration $a_i^(n+1)$ using updated positions
4. Half kick
$
  v_i^(n+1) = v_i^(n+1/2) + (Delta t)/2 a_i^(n+1)
$

This choice is motivated by the well-known long-term stability advantages of symplectic schemes in gravitational dynamics @springel_2005, particularly when combined with approximate force evaluation.

=== 2.4.2 Euler integrator (baseline/fallback)
A forward Euler method is retained as `--integrator euler` to provide a stability baseline. Its update sequence is: tree build $arrow.r$ force evaluation $arrow.r$

#math.equation(
  $
    v arrow.l v + a Delta t,space r arrow.l r + v Delta t
  $,
)

== Hierarchical force evaluation
=== Monopole approximation
Hierarchical evaluation approximates distant particle groups by a single monopole at the node center of mass. For a node with total mass $M$ and center of mass $R$,
#math.equation($ a_(i,"node") = G M frac(R-r_i, (||R-r_i||^2+epsilon^2)^(3/2)) $),
This monopole approximation is used consistently across both tree topologies implemented here: a binary BVH (GPU primary) and an 8-way octree (CPU fallback)  Only the tree representation and opening criterion differ.
=== Opening Criteria
An internal node is accepted if it is sufficiently small relative to its distance from the target particle.
- GPU BVH (tight AABB with maximum extent $"maxExtent"$): #math.equation($ frac("maxExtent"^2, d^2) lt theta^2 $) where #math.equation($ "maxExtent" = max(Delta x, Delta y, Delta z) $) derived from node AABB bounds. This criterion reflects non-cubic node shapes in a BVH more accurately than a uniform half-width.

- CPU octree (half-width $h$, distance squared $d^2 = ||r_i - R||^2$): #math.equation($ frac(h^2, d^2) lt theta^2 $) This squared form avoids a square root.

Default $theta=0.75$ is used as a practical balance between accuracy and performance.

== Software architecture and execution modes
=== GPU-primary stepping with on-demand diagnostics
The primary execution mode is GPU-primary: all physics operations (integration, tree construction, and force evaluation) are performed on the GPU each step. Diagnostic quantities are computed on the CPU only at configurable intervals through staging-buffer readback of positions and velocities. Diagnostic frequency is set to every 60 frames in interactive mode, and every step or every 50 steps in headless mode depending on $N$.

To support cross-checking and fallback behavior, CPU mirror arrays (`cpuPositions_`, `cpuVelocities_`, `cpuAccelerations_`) are retained and used by non-primary modes (Euler and CPU-tree leapfrog), where scalar CPU loops and a CPU octree are executed in parallel with the GPU path.

This design yields two methodological advantages:
1. No per-step CPU physics overhead in the primary mode: the tree is built directly from GPU-resident particle state.
2. Cross-validation potential across runs: selecting CPU octree vs GPU BVH paths provides two independent hierarchical implementations for comparative diagnostics, aiding debugging and sensitivity analysis.

=== Tools and build system
- Language: C++20 (orchestration, physics, UI); WGSL (compute and rendering).
- API: WebGPU C API only (no wrapper libraries).
- Build system: CMake + FetchContent with pinned versions (deterministic builds).
- Dependencies (fetched automatically): WebGPU-distribution (v0.2.0), GLFW (3.4), glfw3webgpu (v1.2.0), spdlog (v1.16.0), Dear ImGui (v1.90.9), GLM (1.0.2).
- Backends: `WGPU` (wgpu-native), `DAWN` (Dawn), `EMSCRIPTEN` (browser build with `-sASYNCIFY`, `-sALLOW_MEMORY_GROWTH=1`, `-sUSE_GLFW=3`).
- Deterministic PRNG: `std::mt19937` seeded by `--seed` (default 42).

== WebGPU Compute Methodology

=== GPU Data Layout
Simulation state is stored in WebGPU storage buffers:
- `positions: array<vec4f>` - $(x,y,z,m)$
- `velocities: array<vec4f>` - $(v_x,v_y,v_z,0)$
- `accelerations: array<vec4f>` - $(a_x,a_y,a_z,0)$
- `bvhNodes: array<BVHNode>` - GPU-built LBVH nodes (force traversal)
- `octreeBuffer: array<Node>` - flattened CPU octree nodes (fallback only)
- `paramsBuffer: Params` - uniform parameters shared between C++ and WGSL (layout-matched)

The BVH uses a binary representation with $2N-1$ nodes: internal nodes indexed $0 ... N-2$, leaves indexed $N-1 ... 2N-2$. Each BVH node stores center of mass and a tight AABB. The CPU octree node layout uses explicit child fields `c0..c7` to avoid dynamic indexing limitations in WGSL implementations.

In-place updates are used: there is no double buffering of positions/velocities/accelerations. Correct ordering between compute passes relies on WebGPU’s implicit storage-buffer synchronization between passes within a single command buffer submission. Bind groups are recreated each frame.

=== Compute Shaders

The implementation comprises 12 WGSL compute shaders:

- Integration and force: direct summation (baseline), octree traversal (fallback), BVH traversal (primary), plus kick/drift and Euler integration shaders.

- LBVH construction (7 passes): two-pass bounding box reduction, Morton code generation, bitonic sort (multiple sub-passes), Karras (2012) topology construction, leaf initialization, and bottom-up aggregation via atomic counters.

Workgroup sizes are fixed per kernel (e.g., 64 for force evaluation, 256 for integration and tree building) and are reported as part of the implementation configuration.

=== Per-timestep execution sequence (GPU-primary leapfrog)

Each timestep is recorded into a single command encoder and submitted as one command buffer:
1. Half-kick: $v arrow.l v + (a Delta t)/ 2$
2. Drift: $r arrow.l r + (v Delta r)$
3. LBVH build (7 passes): global AABB $arrow.r$ Morton codes $arrow.r$ bitonic sort $arrow.r$ Karras build $arrow.r$ leaf init $arrow.r$ bottom-up aggregation
4. BVH force evaluation: iterative traversal with fixed-depth explicit stack (depth 64; sufficient for all tested $N$)
5. Half-kick:  $v arrow.l v + (a Delta t)/ 2$
6. Diagnostics readback (periodic): stage-map-readback $arrow.r$ CPU double-precision diagnostics

=== GPU traversal (iterative, no recursion)
Tree traversal is implemented iteratively in the BVH force shader. One GPU thread is assigned per particle. The thread maintains an explicit stack of node indices, beginning from the root. A node is either accepted (leaf or opening-criterion satisfied) and accumulated via the monopole approximation, or expanded by pushing its children. Fast inverse square root (`inverseSqrt`) is used for inverse-distance evaluation. A self-interaction guard avoids adding contributions for degenerate near-zero distances.

This approach preserves the Barnes–Hut approximation structure while accommodating GPU execution constraints and limiting branch divergence where possible @fastnbody @cudabarnes @maximizeparallel .

=== GPU LBVH construction (Karras 2012)


The LBVH is built fully on-device in seven conceptual steps:

1. Two-pass parallel reduction to compute global AABB.
2. Morton code generation by normalizing positions to a $[0,1023]^3$ integer grid and interleaving bits (30-bit code).
3. Bitonic sort of Morton codes and particle indices (key–value), using multiple $(k,j)$ sub-passes with dynamic uniform offsets; padded-to-power-of-two arrays are used, with sentinel codes for padding elements.
4. Parallel binary tree topology construction using the Karras (2012) delta function (leading zeros of XOR of adjacent codes, with tie-breaking for duplicates).
5. Leaf initialization mapping sorted indices to particle positions/masses and point AABBs.
6. Bottom-up aggregation of internal-node AABBs and centers of mass using atomic counters to ensure both children are ready before parent evaluation.

The resulting BVH is immediately traversable without CPU-side construction or upload, eliminating a per-step CPU bottleneck in the primary mode.

=== CPU octree construction (fallback paths)

The CPU octree is used only by Euler and CPU-tree leapfrog modes. It is built from CPU mirror arrays by computing a bounding box, inserting particles via octant selection, propagating centers of mass bottom-up, and optionally flattening to a GPU-friendly node array when GPU evaluation is used. GPU buffers auto-resize during uploads when needed.

== Rendering and interactive operation (visualization mode)

For visualization, particles are rendered as instanced billboard quads with additive blending. Positions and colors are read directly from storage buffers via `@builtin(instance_index)` (no vertex buffer). Depth testing is enabled with depth writes disabled; fragments are masked to a circular footprint with a soft alpha falloff. An ImGui overlay provides interactive control of parameters and displays diagnostics and timing breakdowns. Rendering is a presentation layer and does not alter the simulation state.

== Evaluation protocol: baselines, metrics, and parameter sweeps

=== Baselines

Two baselines are used:

1. Direct summation: $O(N^2)$ for small $N$, used as a reference computation path. Additionally, potential energy is computed by direct pair summation only when $N lt.eq 5000$ due to its $O(N^2)$ cost.
2. Forward Euler: (`--integrator euler`) as a numerical stability baseline relative to leapfrog.

=== Primary metrics

- *Runtime per timestep* (ms/step), broken down into:
  - tree build time (GPU LBVH or CPU octree + upload),
  - force evaluation time (GPU BVH traversal or CPU Barnes–Hut),
  - integration time (kick/drift dispatches and any CPU mirror loops on fallback paths).
    Timing is measured using `std::chrono::high_resolution_clock`.
- *Scaling with particle count*: empirical scaling trends across (N) for hierarchical vs direct modes.
- *Long-term stability* (where measurable): energy drift #math.equation($ Delta E(t) = frac(|E(t)-E(0)|, E(0)) $) reported only for $ N lt.eq 5000 $ where potential energy is computed.

=== Secondary Metrics

- *Linear momentum magnitude* #math.equation($ ||P(t)|| = ||sum_i m_i v_i || $) double precision), expected to remain near zero for symmetric initial conditions.
- *Qualitative morphology (disk runs)*: persistence and evolution of large-scale structure, reported descriptively rather than as a ground-truth numerical metric.

=== Parameter sweeps (ablation-style sensitivity analysis)

To characterize accuracy–performance trade-offs and stability regimes, controlled sweeps are performed via CLI:

- $theta in {0.3,0.5,0.7,1.0}$
- $Delta t$ across a stable range (scenario dependent)
- $epsilon$ across representative values
- Euler vs leapfrog
- CPU octree vs GPU LBVH construction paths
Results are compared using exported CSV logs.


=== Error analysis procedure
When instability or anomalous drift occurs, runs are inspected for correlations with: dense regions vs diffuse regions, large $theta$, large $Delta t$, small $epsilon$, and platform/backend differences. Failures (NaNs, overflow, extreme velocities) are detected explicitly and logged.

== Validation and Robustness

=== Theoretical Grounding
- Barnes–Hut hierarchical approximation and tunable opening angle $theta$ follow Barnes & Hut (1986).
- Leapfrog integration is a standard choice for long-horizon gravitational dynamics due to symplectic stability properties @springel_2005
- The GPU hierarchy construction follows Karras (2012), a widely used parallel LBVH method.
- GPU traversal methodology follows established considerations for irregular tree algorithms on SIMD-style hardware @cudabarnes @maximizeparallel

=== Empirical validation

- Scenario A (two-body) provides a controlled sanity check for orbit stability and integrator correctness.
- Deterministic seeds and complete parameter logging allow exact repetition.
- Fixed step counts (`--steps`) provide consistent comparison across runs; instability events are recorded rather than filtered.

=== Practical constraints
Interactive runs couple stepping to the render loop; headless mode prioritizes throughput. Particle count is adjustable (2 to 100,000). Potential energy tracking is intentionally limited to $N lt.eq 5000$ to avoid prohibitive overhead; for larger $N$, stability is assessed through kinetic energy and momentum diagnostics plus qualitative behavior.


== Data ethics, security, and integrity
No personal or sensitive data are collected. All computation runs locally (native) or within the user’s browser sandbox (Emscripten). Diagnostic logs and trajectories are exported only when explicitly requested (`--export`). Each CSV export is linked to the complete set of runtime parameters (scenario, $N$, $Delta t$, $theta$, $epsilon$, seed, integrator, steps). The primary practical risk is high GPU load; mitigation is provided through adjustable $N$ and configurable step limits.





