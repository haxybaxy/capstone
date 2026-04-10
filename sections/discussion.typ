#pagebreak()
= Discussion
#set heading(numbering: "1.1")

== Interpretation of Results

=== Scalability in Context

The flatter-than-expected scaling (3.9$times$ over 1000$times$ in $N$) implies that GPU occupancy, not algorithmic complexity, is the binding factor at the particle counts tested. At small $N$ the GPU is underutilised and dispatch overhead dominates; as $N$ grows, the parallel hardware absorbs the $O(N log N)$ work increase. The implication for practitioners is that WebGPU tree-based solvers become cost-effective only above the crossover ($N approx 1500$ on this hardware), and that further gains require reducing the tree-build pipeline, which accounts for 74–79% of step time. The sort phase is the primary optimisation target within that pipeline.

=== Numerical Fidelity

The central finding is that 32-bit precision, not the integration scheme or opening angle, sets the floor on numerical fidelity. This means that investing in higher-order multipole expansions or smaller opening angles will not improve energy conservation until 64-bit GPU arithmetic becomes available in WebGPU. For practical use, the leapfrog integrator remains the correct choice: it conserves momentum and maintains orbit stability, and its energy drift is indistinguishable from that of forward Euler when both operate at the same 32-bit precision. The observed Plummer sphere expansion is physical rather than numerical, consistent with known behaviour of finite-$N$ systems with approximate forces @galacticdynamics2nded.

=== WebGPU as a Compute Platform

The browser deployment path adds a fixed 4.3 ms per-step overhead from asyncify event-loop scheduling, but this cost does not grow with $N$. The practical implication is that for scientifically meaningful particle counts ($N gt.eq 10000$), the browser platform approaches native throughput, with an overhead factor of 2.7$times$ at $N = 100000$ and numerically identical output. This positions WebGPU as viable for interactive, accessible $N$-body simulation without specialised hardware, subject to the 32-bit precision constraint @realitycheck.

== Comparison with Published Results

Direct comparison with CUDA-based Barnes–Hut implementations is limited by differences in hardware generation, floating-point precision (64-bit in CUDA studies versus 32-bit here), tree topology (octree versus BVH), and opening criteria. Nevertheless, several structural comparisons are informative.

Burtscher and Pingali report CUDA Barnes–Hut performance of approximately 10 billion body-body interactions per second on an NVIDIA GTX 280 @cudabarnes. At $N = 100000$ with $theta = 0.75$, this corresponds to roughly 10 ms per step on 2010-era hardware. The WebGPU implementation achieves 2.35 ms per step at the same $N$, which is faster in absolute terms but benefits from 16 years of hardware improvement (Apple M2 versus GTX 280). The comparison suggests that WebGPU achieves performance within the same order of magnitude as native CUDA when hardware generation is accounted for, consistent with the platform being computationally viable.

Gaburov, Bédorf, and Portegies Zwart report tree-construction overhead of approximately 15–25% of total step time in their CUDA octree implementation @bedorf2010, compared to 74–79% in this work. The substantially higher tree-build fraction here reflects the cost of the fully on-device LBVH construction via bitonic sort, which trades construction efficiency for the elimination of CPU-GPU transfer. CUDA implementations that build the octree on the CPU and upload it achieve lower build fractions but incur PCIe transfer costs not present in the LBVH approach.

Nyland, Harris, and Prins report direct $O(N^2)$ GPU throughput of approximately 10–30 GFLOP/s for $N$-body problems on contemporary NVIDIA hardware @fastnbody. The WebGPU direct-summation path in this work achieves approximately 5.0 ms per step at $N = 5000$ (equivalent to $N^2 / t approx 5 times 10^9$ interactions per second), which is competitive given the integrated GPU architecture of the M2 and the 32-bit precision.

== Limitations

The results should be interpreted in light of several limitations that bound their external validity.

The most significant constraint is that all experiments were conducted on a single Apple M2 system. Although the WebGPU specification is cross-platform, GPU performance characteristics vary substantially across vendors. The Apple M2 is an integrated GPU with unified memory, which eliminates CPU–GPU transfer costs that would be present on discrete GPU systems; conversely, its compute unit count is modest compared to dedicated NVIDIA or AMD GPUs. The timing results and scaling behaviour reported here may therefore not generalise to other hardware configurations.

A second fundamental constraint is the limitation of WebGPU to 32-bit floating-point arithmetic in compute shaders. As the results demonstrate, this single-precision ceiling is the dominant constraint on numerical fidelity, exceeding the effects of the opening angle and timestep size for the configurations tested. The effect is most pronounced at small $N$, where round-off error accumulates over many steps without the statistical averaging that occurs in large-$N$ systems. Relatedly, the force evaluation uses only the monopole term of the multipole expansion; quadrupole and higher-order terms, which are standard in production codes such as GADGET-2 @springel_2005, would reduce the force approximation error at a given $theta$ and potentially allow larger opening angles for the same accuracy target.

On the methodology side, all experiments use a global fixed timestep, whereas production codes commonly employ adaptive individual timestepping that assigns each particle a step proportional to its local dynamical timescale @springel_2005. The absence of adaptive timestepping means that the timestep must be chosen conservatively for the densest region of the simulation, which may be unnecessarily small for the majority of particles. Additionally, energy drift as a quantitative metric is available only for $N lt.eq 5000$, where direct pair summation for potential energy is computationally feasible; for larger $N$, numerical quality is assessed indirectly through kinetic energy trends and momentum conservation.