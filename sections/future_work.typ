#pagebreak()
= Future Work
#set heading(numbering: "1.1")

The limitations identified in the discussion suggest several concrete directions for extending this work, each tied to specific performance or capability goals.

== Adaptive Individual Timestepping

The fixed global timestep used in this implementation requires a conservative choice of $Delta t$ that accommodates the densest region of the simulation. Adaptive individual timestepping, as implemented in GADGET-2 @springel_2005, assigns each particle a timestep proportional to a local dynamical timescale (such as $sqrt(epsilon / |a_i|)$) and synchronises particles using block timestepping. Implementing this in WebGPU compute shaders would require per-particle step bookkeeping in storage buffers and more complex dispatch logic, but would significantly improve accuracy in the dense cores of Plummer spheres and disk centres without penalising the timestep for particles in diffuse outer regions.

== Cross-Browser and Cross-Device Benchmarking

The browser benchmarks in this work were conducted in a single Chromium instance on the Apple M2. Systematic benchmarking across Chrome and Firefox (once WebGPU is enabled in Firefox), and across integrated GPUs (Apple M2, Intel Arc), discrete GPUs (NVIDIA, AMD), and mobile devices, would extend the platform feasibility findings. Of particular interest is whether the fixed ~4.3 ms per-step event-loop overhead observed here is browser-specific or consistent across implementations, and whether the overhead varies on devices with different GPU scheduling characteristics. Such testing would extend the findings of Sengupta et al. @realitycheck to the specific case of hierarchical $N$-body simulation across diverse consumer hardware.

== Higher-Order Multipole Expansion

Extending the monopole approximation to include quadrupole moments in the BVH nodes would reduce the force approximation error at a given $theta$, potentially allowing the use of larger opening angles (and correspondingly faster traversal) for the same accuracy target. The additional per-node storage (a symmetric $3 times 3$ tensor per node) fits within WebGPU storage buffer limits, and the extra arithmetic per interaction is modest. This extension would bring the force accuracy closer to production codes and enable more meaningful comparison with GADGET-2's multipole expansion @springel_2005.

== 64-Bit Precision When Available

The results demonstrate that 32-bit GPU arithmetic is the dominant constraint on numerical quality. As the WebGPU specification evolves, optional 64-bit floating-point support in compute shaders (`f64`) may become available on supporting hardware. Benchmarking the precision-versus-performance trade-off with 64-bit force evaluation would determine whether the energy conservation improvement justifies the throughput reduction, and would enable direct integrator-quality comparisons (leapfrog vs Euler) that are currently confounded by the precision difference between GPU and CPU paths.

== Multi-Component Galaxy Models

The rotating disk scenario (Scenario C) uses a simplified single-component model. Extending the initial conditions to include a central bulge, an exponential disk, and a dark matter halo, following standard multi-component galaxy models @galacticdynamics2nded, would enable comparison with observational rotation curves and provide a more physically realistic testbed for the solver. The simulation architecture already supports heterogeneous particle masses and could accommodate multiple components with minimal code changes, primarily in the initial-condition generator.
