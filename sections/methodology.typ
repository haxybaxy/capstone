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
  v = sqrt(frac(G m d^2,2 (d^2 + epsilon^2)^(3/2)))
$
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
  $
)
with $u$ clamped to $[0.001, 0.999]$. Angular coordinates are isotropic (uniform $cos(theta)$, uniform $phi.alt$). Speeds are sampled via rejection sampling using 
#math.equation(
$
  g(q) = q^2(1-q^2)^(7/2)
$
)
against the local escape velocity
#math.equation(
$
v_e = sqrt(frac(2 G M, sqrt(r^2 + a^2)))
$
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
  v = 0.5 sqrt(frac(M_"enclosed",r))
$
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
  a_i = G sum_(j eq.not i) m_j frac(r_j - r_i,(||r_j - r_i||^2 + epsilon^2)^(3/2))
$
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
  v_i^(n+1/2) =  v_i^(n) + (Delta t)/2 a_i^n
$
)
2. Drift
#math.equation(
$
  r_i^(n+1) =  r_i^(n) + Delta t v_i^(n+1/2)
$
)
3. Recompute acceleration $a_i^(n+1)$ using updated positions
4. Half kick
$
  v_i^(n+1) =  v_i^(n+1/2) + (Delta t)/2 a_i^(n+1)
$

This choice is motivated by the well-known long-term stability advantages of symplectic schemes in gravitational dynamics @springel_2005, particularly when combined with approximate force evaluation.

=== 2.4.2 Euler integrator (baseline/fallback)
A forward Euler method is retained as `--integrator euler` to provide a stability baseline. Its update sequence is: tree build $arrow.r$ force evaluation $arrow.r$

#math.equation(
$
  v arrow.l v + a Delta t,space r arrow.l r  + v Delta t
$
)

== Hierarchical force evaluation
=== Monopole approximation
Hierarchical evaluation approximates distant particle groups by a single monopole at the node center of mass. For a node with total mass $M$ and center of mass $R$,
#math.equation(
$
  a_(i,"node") = G M frac(R-r_i,(||R-r_i||^2+epsilon^2)^(3/2))
$
),
This monopole approximation is used consistently across both tree topologies implemented here: a binary BVH (GPU primary) and an 8-way octree (CPU fallback)  Only the tree representation and opening criterion differ.
=== Opening Criteria
An internal node is accepted if it is sufficiently small relative to its distance from the target particle.
- GPU BVH (tight AABB with maximum extent $"maxExtent"$): #math.equation(
$
  frac("maxExtent"^2,d^2) lt theta^2
$) where #math.equation(
$
  "maxExtent" = max(Delta x, Delta y, Delta z)
$
) derived from node AABB bounds. This criterion reflects non-cubic node shapes in a BVH more accurately than a uniform half-width.

- CPU octree (half-width $h$, distance squared $d^2 = ||r_i - R||^2$): #math.equation(
$
  frac(h^2,d^2) lt theta^2
$
) This squared form avoids a square root.

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

