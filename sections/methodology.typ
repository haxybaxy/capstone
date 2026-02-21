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
- *Setup*: two equal-mass particles ($m = 1000$ each) separated by $d = 10$ units along the X-axis, with tangential velocities along the $z$-axis computed for a softened circular orbit: $v = sqrt(G * m * d^2 / (2 * (d^2 + epsilon^2)^(3/2)))$

- *Key variables*: $d t$, softening
- *Limitations*: not representative of large-N hierarchical behavior
==== Scenario B -- Plummer sphere (spherical equilibrium test)
- *Scope*: $N$ in $[10^3, 10^5]$ (depending on hardware)
- *Purpose*: tests tree accuracy and stability in a compact 3D distribution with known analytic properties
- *Setup*: Plummer model with scale length $a = 5$. Radii sampled via inverse CDF: $r = a / sqrt(u^(-2/3) - 1)$, with u clamped to $[0.001, 0.999]$. Positions are isotropic (uniform $cos(theta)$, uniform $phi$). Speeds are sampled via rejection sampling of $g(q) = q^2 * (1 - q^2)^(7/2)$ against the local escape velocity $v_e = sqrt(2 * G * M / sqrt(r^2 + a^2))$, with isotropic velocity directions.
- *Key variables*: $theta$, softening, $d t$
- *Limitations*: does not emphasize disk structures (spirals/bars)
==== Scenario C -- Rotating exponential disk (galaxy-like morphology test)
- *Scope*: $N$ in $[10^4, 10^5]$
- *Purpose*: evaluates long-term evolution and visually interpretable galactic dynamics (e.g., spiral-like patterns)
- *Setup*: radii drawn from an exponential distribution (rate 0.08, clamped to 50), uniform azimuthal angle, vertical height from $N(0, 0.3)$ scaled by $1/(1 + r * 0.5)$. Masses are uniform in $[0.5, 2.0]$. Circular orbit velocities computed as $v = sqrt(M_("enclosed") / r)$  0.5 for $r$ > 0.1, with tangential direction.
- *Key variables*: disk scale length, thickness, velocity dispersion, $theta$, $d t$
- *Limitations*: simplified dynamical setup (not a full multi-component Milky Way model); enclosed-mass estimate is approximate.

The project provides the exact generator code plus seed (default seed = 42) to reproduce any run. All initial-condition generation uses `std::mt19937` seeded by the user-specified `--seed` parameter.

#set heading(numbering: "1.1")

=== Core preprocessing and transformations

These transformations are applied every timestep (or during initialization) and are justified by GPU efficiency and the Barnes-Hut method.

- *Bounding-box computation for tree construction*: the global axis-aligned bounding box (AABB) is computed each step as part of the tree build. On the GPU tree path, this is performed entirely on-device via a two-pass parallel reduction (workgroup-level reduction followed by a single-workgroup final reduction); no CPU AABB is computed per step. On the CPU tree fallback paths (Euler integrator, CPU-tree leapfrog), a sequential iteration over all CPU mirror particle positions determines the AABB, and the octree root cell is centered on this box with a half-width equal to half the maximum extent (plus a small padding of 1.0 unit).
- *Justification*: the GPU-computed AABB feeds directly into Morton code generation (normalizing positions into a [0,1023]^3 grid), avoiding a CPU→GPU upload step. The CPU AABB computation is used only by the CPU tree fallback paths for octree construction.

- *Gravitational softening (epsilon)*: the force law is modified to avoid singularities and large accelerations at very small separations. The softened potential replaces $|r|^2$ with $|r|^2 + epsilon^2$.

-  *Justification*: improves stability and better matches collisionless assumptions in galactic dynamics.

- *Precision management*: the simulation uses 32-bit floating point on the GPU. State is maintained in natural (dimensionless) units with G = 1. Diagnostics (energy, momentum) are computed in 64-bit double precision on the CPU to reduce accumulation errors.

- *Justification*: 32-bit GPU computation maximizes throughput; 64-bit CPU diagnostics provide more reliable conservation metrics.

=== Derived metrics

These are computed on the CPU from the mirror arrays for evaluation and do not affect dynamics:
.
- Total kinetic energy: K = sum(0.5 * m_i * |v_i|^2) (double precision)
- Total potential energy: $U = -sum_{i<j} m_i * m_j / sqrt(|r_i - r_j|^2 + epsilon^2)$ (*computed only when $N <= 5000$* due to O(N^2) cost; for larger N, potential energy is not tracked)
- Total energy: $E = K + U$
- Energy drift: $Delta_E(t) = |E(t) - E(0)| / |E(0)|$
- Linear momentum: $P = sum(m_i * v_i)$ (3D vector, double precision) and its magnitude $|P|$
- Runtime per pass: tree build, force computation, and integration timings via `std::chrono::high_resolution_clock`

=== Simulation
```
Config (CLI args: seed, N, dt, theta, epsilon, steps, scenario, integrator)
        |
        v
Initial condition generator  --->  CPU arrays (positions, velocities) + GPU buffers
        |
        v
Compute initial forces (GPU LBVH build + BVH force evaluation)
        |
        v
For each timestep (KDK leapfrog — GPU only):
  (1) Half-kick:  GPU kick shader                     v += a * dt/2
  (2) Drift:      GPU drift shader                    x += v * dt
  (3) Tree build: GPU LBVH pipeline (bbox → Morton → sort → Karras → leafInit → aggregate)
  (4) Force:      GPU BVH force shader                a = tree traversal
  (5) Half-kick:  GPU kick shader                     v += a * dt/2
  (6) Periodic:   GPU readback via staging buffers → CPU diagnostics
  (7) Optional:   render (GPU)
        |
        v
Logs: timing breakdown, energy/momentum (CSV export via --export)
```

== Physical model and governing equations

Each particle represents a mass element (star/dark matter tracer) evolving under self-gravity. The acceleration of particle i is:

$a_i = G * sum_{j != i} m_j * (r_j - r_i) / (|r_j - r_i|^2 + epsilon^2)^(3/2)$

where $G$ is the gravitational constant (set to 1 in dimensionless units), and epsilon is the softening length default: 0.5).

*Mass storage*: each particle's mass is packed into the w-component of its position vector (`vec4: x, y, z, mass`), avoiding a separate mass buffer and reducing memory bandwidth.

*Boundary conditions*: an isolated (open) system is assumed. No periodic boundary conditions are applied, consistent with an isolated-galaxy demonstration.

== Numerical Integration

To avoid the instability and energy drift typical of forward Euler in gravitational systems, the simulation uses a *second-order symplectic leapfrog* scheme (kick-drift-kick), with fixed timestep dt (default: 0.001):

1. *Half-kick*:
   $v_i^{n+1/2} = v_i^n + (d t/2) * a_i^n$
2. *Drift*:
   $r_i^{n+1} = r_i^n + d t * v_i^{n+1/2}$
3. *Recompute acceleration* $a_i^{n+1}$ from updated positions. On the GPU, this involves building the LBVH via 7 compute passes (see Section 2.8.5) followed by BVH force traversal.
4. *Half-kick*:
   $v_i^{n+1} = v_i^{n+1/2} + (d t/2) * a_i^{n+1}$
Only the GPU executes physics every step; diagnostics use on-demand readback via staging buffers at configurable intervals.
*Justification:* symplectic methods better preserve Hamiltonian structure and long-term qualitative behavior in collisionless galactic simulations @springel_2005.

== Hierarchical force evaluation (Barnes-Hut family)

=== Node approximation

Particles are grouped into a spatial hierarchy. For a node with total mass M and center of mass R, the contribution to particle i is approximated as:

$a_{i,"node"} = G * M * (R - r_i) / (|R - r_i|^2 + epsilon^2)^(3/2)$

This is a monopole approximation (center-of-mass only), matching the classic Barnes-Hut approach. The approximation applies identically to both the 8-way octree (CPU path) and the binary BVH (GPU path); only the tree topology and opening criterion differ.

=== Opening criterion

A node is accepted (treated as a single body) if it is sufficiently far from the target particle.

*GPU BVH*: using the maximum extent of the node's axis-aligned bounding box (AABB) and squared distance $d^2 = |r_i - R|^2$:
where maxExtent = max(AABB_max.x - AABB_min.x, AABB_max.y - AABB_min.y, AABB_max.z - AABB_min.z). This replaces the octree half-width with the largest dimension of the node's tight AABB, providing a more accurate size estimate for non-cubic bounding regions in the binary tree.

The default opening angle theta = 0.75 balances accuracy and performance for both tree types.

== Architecture
