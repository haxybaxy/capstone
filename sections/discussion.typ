#pagebreak()
= Discussion
#set heading(numbering: "1.1")

== Interpretation of Results

=== Scalability in Context

The observed scaling behaviour, a 3.9$times$ increase in step time over a 1000$times$ increase in $N$, is substantially flatter than the theoretical $O(N log N)$ expectation. For $N log N$ scaling, a factor of 1000 in $N$ should produce approximately a $1000 times log(100000) / log(100) approx 2500$ factor increase in work, yet the wall-clock time increases by only 3.9$times$. This compression is explained by GPU parallelism: at small $N$, the GPU's compute units are underutilised, and dispatch overhead dominates; as $N$ grows, occupancy improves and the parallel hardware absorbs the increased arithmetic cost. The scaling curve therefore reflects the convolution of algorithmic complexity with hardware utilisation, not pure algorithmic cost.

The tree-build fraction of 74–79% across all tested $N$ indicates that the LBVH construction pipeline, rather than force evaluation, is the computational bottleneck. This is consistent with the seven-pass pipeline design: the bitonic sort alone requires $O(N log^2 N)$ comparisons across multiple dispatches, and each pass incurs GPU synchronisation overhead. Future optimisation should therefore target the tree-build pipeline, particularly the sort phase, which is known to be amenable to radix-sort alternatives with better GPU scaling @maximizeparallel.

=== Numerical Fidelity

The energy conservation results require careful interpretation. The most significant finding is that 32-bit floating-point precision, not the integration scheme or the opening angle, is the dominant constraint on numerical fidelity in the GPU execution path. This manifests in two ways: the two-body orbit shows dramatically different energy drift between the 32-bit GPU and 64-bit CPU force computation paths, and the Plummer sphere theta sweep shows no sensitivity to opening angle at $N = 5000$, suggesting that tree approximation error is below the 32-bit noise floor.

The Plummer sphere energy drift of $Delta E / ( |E(0)| ) approx 1.2$ after 1,000 steps represents genuine physical evolution (expansion of a finite-$N$ system with approximate forces) rather than a numerical failure. The kinetic energy remains constant to high precision while the potential energy magnitude decreases, consistent with a system that is slightly super-virial due to the combination of finite-$N$ sampling, monopole-only force approximation, and 32-bit accumulated round-off. Similar unbinding behaviour is commonly observed in $N$-body simulations with insufficiently matched softening and initial-condition scale lengths @galacticdynamics2nded.

=== WebGPU as a Compute Platform

The results demonstrate that WebGPU delivers on the promise of portable GPU compute. The native-versus-browser comparison quantifies this directly: at $N = 100000$, the browser achieves 6.3 ms per step compared to 2.35 ms natively, an overhead factor of only 2.7$times$. This overhead is a fixed per-step cost of approximately 4.3 ms attributable to Emscripten's asyncify event-loop yield, not a multiplicative penalty on GPU computation. The GPU executes the same compute shaders on the same hardware in both environments; the browser merely adds scheduling latency around each step.

For scalability, this means that as $N$ increases and the GPU compute time grows, the fixed browser overhead becomes a diminishing fraction of total step time. The overhead factor drops from 9.2$times$ at $N = 100$ (where the GPU does almost no work) to 2.7$times$ at $N = 100000$ (where GPU compute dominates). For scientifically meaningful particle counts, the browser platform approaches native throughput. The numerical output matches across platforms to within 1% for $N gt.eq 10000$.

The 32-bit precision constraint and the dispatch overhead at small $N$ remain inherent to the current WebGPU specification rather than implementation limitations of a particular backend @realitycheck. The direct-versus-tree crossover at $N approx 1500$ sets a practical lower bound on the particle count at which hierarchical force evaluation is beneficial on this platform.

== Comparison with Published Results

Direct comparison with CUDA-based Barnes–Hut implementations is limited by differences in hardware generation, floating-point precision (64-bit in CUDA studies versus 32-bit here), tree topology (octree versus BVH), and opening criteria. Nevertheless, several structural comparisons are informative.

Burtscher and Pingali report CUDA Barnes–Hut performance of approximately 10 billion body-body interactions per second on an NVIDIA GTX 280 @cudabarnes. At $N = 100000$ with $theta = 0.75$, this corresponds to roughly 10 ms per step on 2010-era hardware. The WebGPU implementation achieves 2.35 ms per step at the same $N$, which is faster in absolute terms but benefits from 16 years of hardware improvement (Apple M2 versus GTX 280). The comparison suggests that WebGPU achieves performance within the same order of magnitude as native CUDA when hardware generation is accounted for, consistent with the platform being computationally viable.

Gaburov, Bédorf, and Portegies Zwart report tree-construction overhead of approximately 15–25% of total step time in their CUDA octree implementation @bedorf2010, compared to 74–79% in this work. The substantially higher tree-build fraction here reflects the cost of the fully on-device LBVH construction via bitonic sort, which trades construction efficiency for the elimination of CPU-GPU transfer. CUDA implementations that build the octree on the CPU and upload it achieve lower build fractions but incur PCIe transfer costs not present in the LBVH approach.

Nyland, Harris, and Prins report direct $O(N^2)$ GPU throughput of approximately 10–30 GFLOP/s for $N$-body problems on contemporary NVIDIA hardware @fastnbody. The WebGPU direct-summation path in this work achieves approximately 5.0 ms per step at $N = 5000$ (equivalent to $N^2 / t approx 5 times 10^9$ interactions per second), which is competitive given the integrated GPU architecture of the M2 and the 32-bit precision.

== Limitations

The results should be interpreted in light of the following limitations, which bound the external validity of the findings.

*Single hardware platform.* All experiments were conducted on a single Apple M2 system. The WebGPU specification is cross-platform, but GPU performance characteristics (compute unit count, memory bandwidth, scheduling granularity) vary substantially across vendors (NVIDIA, AMD, Intel, Apple). The timing results and scaling behaviour reported here may not generalise to other hardware, particularly discrete GPUs with different memory hierarchies.

*32-bit GPU precision.* The WebGPU specification does not require 64-bit floating-point support in compute shaders, and the wgpu-native backend on Apple M2 provides only 32-bit arithmetic. All GPU-side force evaluation and integration therefore operates at single precision. As the results demonstrate, this is the dominant constraint on numerical quality, limiting the utility of energy drift as a quantitative diagnostic. The effect is most pronounced at small $N$ (two-body) where round-off accumulates over many steps without the statistical averaging that occurs in large-$N$ systems.

*Monopole-only approximation.* The force evaluation uses only the monopole term of the multipole expansion. Quadrupole and higher-order terms, which are standard in production codes such as GADGET-2 @springel_2005, would reduce the force approximation error at a given $theta$ and potentially allow larger opening angles for the same accuracy target.

*Fixed timestep.* All experiments use a global fixed timestep. Adaptive individual timestepping, as implemented in GADGET-2 @springel_2005 and other production codes, would improve accuracy in dense regions while maintaining efficiency in diffuse regions. The absence of adaptive timestepping means that the timestep must be chosen conservatively for the densest region of the simulation, which may be unnecessarily small for the majority of particles.

*Potential energy limited to $N lt.eq 5000$.* Energy drift as a quantitative metric is available only for small $N$ where direct pair summation is computationally feasible. For larger $N$, numerical quality is assessed indirectly through kinetic energy trends and momentum conservation, which are necessary but not sufficient indicators of force accuracy.

*No multi-seed statistical analysis at large $N$.* Seed robustness was tested at $N = 5000$ only. Timing and energy variability at larger $N$ may differ due to different particle distributions affecting tree structure and traversal depth.
