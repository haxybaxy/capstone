#pagebreak()
= Future Work
#set heading(numbering: "1.1")

The limitations discussed above point to several concrete next steps, each tied to a specific performance or capability goal.

== Adaptive Individual Timestepping

Our fixed global timestep forces a conservative $Delta t$ that accommodates the densest region of the simulation. Adaptive individual timestepping, as implemented in GADGET-2 @springel_2005, assigns each particle a timestep proportional to its local dynamical timescale ($sqrt(epsilon / ( |a_i| ))$) and synchronises particles via block timestepping. Implementing this in WebGPU compute shaders would require per-particle step bookkeeping in storage buffers and more complex dispatch logic, but it would improve accuracy in dense cores (Plummer spheres, disk centres) without penalising particles in diffuse outer regions.

== Cross-Hardware and Cross-Browser Benchmarking

Our cross-backend comparison (Group 6) tested four WebGPU implementations on the same Apple M2 and found large cross-implementation variation, but all four use the same Metal driver. Extending the benchmarks to non-Apple hardware — discrete NVIDIA and AMD GPUs using the Vulkan backend, and Intel Arc using Direct3D 12 — would determine whether the scaling characteristics and relative implementation rankings observed here generalise across GPU architectures. Firefox (once WebGPU is enabled) represents another untested browser implementation. Mobile devices (smartphones and tablets), where GPU scheduling, thermal throttling, and memory bandwidth differ from desktop systems, are a further priority: the approximately 29 ms per-step asyncify overhead observed in browser execution may vary on devices with different event-loop scheduling characteristics. Such testing would extend the findings of Sengupta et al. @realitycheck to hierarchical $N$-body simulation across diverse consumer hardware.

== Higher-Order Multipole Expansion

Extending the monopole approximation to include quadrupole moments in the BVH nodes would reduce the force approximation error at a given $theta$, potentially allowing the use of larger opening angles (and correspondingly faster traversal) for the same accuracy target. The additional per-node storage (a symmetric $3 times 3$ tensor per node) fits within WebGPU storage buffer limits, and the extra arithmetic per interaction is modest. This extension would bring the force accuracy closer to production codes and enable more meaningful comparison with GADGET-2's multipole expansion @springel_2005.

== 64-Bit Precision When Available

Our results show that 32-bit GPU arithmetic is the dominant constraint on numerical quality. As the WebGPU specification evolves, optional 64-bit floating-point support in compute shaders (`f64`) may become available on supporting hardware. Benchmarking the precision-versus-performance trade-off with 64-bit force evaluation would determine whether the energy conservation improvement justifies the throughput reduction, and would enable direct integrator-quality comparisons (leapfrog vs Euler) that are currently confounded by the precision difference between GPU and CPU paths.

== Multi-Component Galaxy Models

Scenario C uses a simplified single-component disk. Adding a central bulge, an exponential disk, and a dark matter halo following standard multi-component galaxy models @galacticdynamics2nded would enable comparison with observational rotation curves and provide a more physically realistic testbed. The simulation architecture already supports heterogeneous particle masses, so accommodating multiple components would require changes mainly in the initial-condition generator.
