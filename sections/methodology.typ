#pagebreak()
= Methodology
#set heading(numbering: "1.1")
== Research Design and Objectives
This project follows a computational-methods research design: we implement and evaluate a GPU-accelerated gravitational N-body solver for galactic dynamics, built with C++20 and the WebGPU API. The application compiles to both native desktop (via wgpu-native or Dawn backends) and browser (via Emscripten), enabling interactive visualization and headless batch evaluation from the same codebase.

The methodology is structured to ensure the implementation is (i) reproducible, (ii) numerically stable over long integrations, and (iii) computationally scalable beyond the quadratic cost of direct summation.


The central methodological choices follow directly from the Literature Review:
- *Force Model*: Newtonian gravity with softening to avoid singularities and reduce two-body relaxation (collisionless approximation).
- *Acceleration strategy*: a hierarchical tree method in the Barnes-Hut family to reduce per-step complexity from $O(N^2)$ to approximately $O(N log N)$. @barneshut
- *Time Integration*: a symplectic scheme (leapfrog / velocity Verlet) to improve long-term energy behavior compared to Euler.
- *Compute platform*: WebGPU compute shaders to enable general-purpose parallel computation on the GPU. The WebGPU C API is used throughout (raw `WGPUDevice`, `WGPUBuffer`, etc.), supporting native execution and browser deployment from a single build system.

The research questions operationalized by this methodology are:

1. *Scalability*: How does runtime per timestep scale with $N$ for a WebGPU Barnes-Hut implementation compared to a direct $O(N^2)$ baseline at small $N$?
2. *Numerical quality*: For fixed $N$, how do timestep size $(d t)$ and opening angle $(theta)$ affect $(a)$ force accuracy relative to a direct reference, and $(b)$ long-term conservation metrics (energy drift, momentum drift)?
3. *Platform feasibility*: What particle counts and timestep rates are practical within WebGPU constraints (32-bit precision, memory limits, scheduling, device variability)?

== Simulation data generation and benchmark scenarios
=== Initial-condition scenarios

To satisfy traceability and enable controlled evaluation, we define three standardized benchmark scenarios. Each scenario is fully described by a set of command-line parameters: scenario type, seed, $N$, $d t$, $theta$, softening, and step count.
#set heading(numbering: none)
==== Scenario A -- Two-body orbit (sanity check)

- *Scope*: N = 2 (enforced regardless of the `--N` parameter)
- *Purpose*: verifies integrator correctness (closed orbit behavior; stability vs dt)
- *Setup*: two equal-mass particles (m = 1000 each) separated by 10 units along the X-axis, with tangential velocities along the Z-axis computed for a softened circular orbit: $v = sqrt(G * m * d^2 / (2 * (d^2 + epsilon^2)^(3/2)))$

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

*Bounding-box computation for tree construction*: the global axis-aligned bounding box (AABB) is computed each step. On the GPU path, this is performed via a two-pass parallel reduction (workgroup-level reduction followed by a single-workgroup final reduction). On the CPU mirror path, a sequential iteration over all particle positions determines the AABB, and the octree root cell is centered on this box with a half-width equal to half the maximum extent (plus a small padding of 1.0 unit).

 *Justification*: the GPU-computed AABB feeds directly into Morton code generation (normalizing positions into a [0,1023]^3 grid), avoiding a CPU→GPU upload step. The CPU AABB serves the mirror octree construction.

*Gravitational softening (epsilon)*: the force law is modified to avoid singularities and large accelerations at very small separations. The softened potential replaces $|r|^2 "with" |r|^2 + epsilon^2$

*Justification*: improves stability and better matches collisionless assumptions in galactic dynamics.

*Precision management*: the simulation uses 32-bit floating point on the GPU. State is maintained in natural (dimensionless) units with $G = 1$. Diagnostics (energy, momentum) are computed in 64-bit double precision on the CPU to reduce accumulation errors.

*Justification*: 32-bit GPU computation maximizes throughput; 64-bit CPU diagnostics provide more reliable conservation metrics.

=== Derived metrics

These are computed on the CPU from the mirror arrays for evaluation and do not affect dynamics:

- *Total kinetic energy:* $K = sum(0.5 * m_i * |v_i|^2)$ (double precision)
- *Total potential energy*: $U = -sum_{i<j} m_i * m_j / sqrt(|r_i - r_j|^2 + epsilon^2)$ (*computed only when N <= 5000* due to O(N^2) cost; for larger N, potential energy is not tracked)
- *Total energy*: $E = K + U$
- *Energy drift*: $delta_E(t) = |E(t) - E(0)| / |E(0)|$
- *Linear momentum*: $P = sum(m_i * v_i)$ (3D vector, double precision) and its magnitude $|P|$
- *Runtime per pass*: tree build, force computation, and integration timings via `std::chrono::high_resolution_clock`

