#pagebreak()
= Discussion
#set heading(numbering: "1.1")

== Interpretation of Results

=== Scalability and Pipeline Structure

Total runtime grows from 5.86 ms to 180.11 ms as $N$ increases 100-fold. Force evaluation is responsible for nearly all of it, accounting for 94–99% of step time. At small $N$ the GPU is underutilised and dispatch overhead dominates; but as $N$ grows, the parallel hardware absorbs the traversal workload. Tree construction, by contrast, stays below 0.35 ms at all tested particle counts, with individual passes roughly constant in $N$. The disk scenario confirms this pattern: force evaluation dominates to the same degree, with the disk slightly slower than the Plummer sphere at matched $N$ due to its non-uniform spatial distribution. This proves that the optimisation effort belongs in the BVH traversal shader, not the tree-build pipeline, and the direct-versus-tree comparison reinforces this. Direct summation is faster at every tested $N$, since its regular and branch-free access pattern maps well onto the GPU. It is also noted that the tree path produces 26$times$ lower energy drift at $N = 100000$, so for any simulation that needs to remain physically meaningful over many timesteps, the hierarchical approach is not optional.

=== Abstraction Overhead

The WebGPU solver outperforms the native Metal baseline (UniSim @unisim) at $N gt.eq 5000$, which deserves careful interpretation. We do not claim WebGPU is inherently faster than Metal. The advantage comes from the fully GPU-resident LBVH pipeline, which avoids the CPU–GPU coordination overhead in UniSim's tree construction. The gap widens steadily with $N$, confirming that the benefit is structural, not incidental. The cross-backend comparison tells a different story: implementation choice within the same Metal backend produces large performance variation. Dawn has the lowest per-dispatch overhead at small $N$ but scales the worst; wgpu-native is the opposite. This matches Maczan's finding that WebGPU implementation choice alone can produce substantial variation in per-dispatch cost @maczan2026. For compute-heavy workloads, wgpu-native is the better choice at large $N$; Dawn is preferable for low-latency small dispatches.

=== Browser Platform Viability

The browser overhead pattern is not a simple fixed cost. Chrome is actually faster than wgpu-native at the smallest particle count, suggesting lower per-dispatch overhead in the browser's WebGPU path. But as force evaluation takes over at larger $N$, Chrome scales less efficiently: the overhead peaks around 2$times$ at moderate workloads and then gradually narrows to roughly 1.4$times$ at the largest $N$ tested. The browser being faster at small $N$, but slower at large $N$ implies a scaling difference in how the browser's WebGPU implementation handles the irregular memory access patterns of BVH traversal, rather than a fixed event-loop penalty. The practical implication is that browser deployment is viable for interactive $N$-body simulation at moderate particle counts, with an overhead of roughly 1.4–1.5$times$ at scientifically meaningful $N$ ($gt.eq 50000$), subject to the precision constraints discussed below @realitycheck.

=== Numerical Quality

The theta-sweep results show a clear dependence of energy drift on opening angle, spanning about two orders of magnitude across the tested $theta$ range. This is the expected physical behaviour: larger $theta$ admits more distant nodes into the force approximation, introducing greater truncation error. The timestep and softening sweeps reinforce this picture: drift increases roughly tenfold across the tested $Delta t$ range and varies modestly with $epsilon$, confirming that multiple parameters interact with the 32-bit precision floor. Together, the three sweeps show that both the tree approximation and floating-point precision contribute to numerical error. For practical use, the leapfrog integrator remains the correct choice when compared to Euler, as it conserves momentum to within 0.1% over 5,000 steps and maintains stable orbits, consistent with its theoretical properties @springel_2005 @galacticdynamics2nded. We note that the observed Plummer sphere expansion is physical, not numerical. It is a known behaviour of finite-$N$ systems with approximate forces @galacticdynamics2nded.

== Comparison with Published Results

Direct comparison with CUDA-based Barnes–Hut implementations is complicated by differences in hardware generation, floating-point precision (64-bit in CUDA studies vs 32-bit here), tree topology (octree vs BVH), and opening criteria. Still, several structural comparisons are worth making.

Burtscher and Pingali report roughly 10 billion body-body interactions per second for CUDA Barnes–Hut on an NVIDIA GTX 280 @cudabarnes, roughly 10 ms per step at $N = 100000$ with $theta = 0.75$ on 2010-era hardware. Our WebGPU implementation needs 180.11 ms at the same $N$, reflecting the BVH traversal shader (99% of step time) and the irregular memory access patterns of LBVH vs octree traversal. A cross-generation, cross-topology comparison like this is not apples-to-apples, but it does confirm that the WebGPU compute shader model can support a complete solver pipeline at large $N$, with throughput limited by traversal efficiency rather than platform overhead.

Gaburov, Bédorf, and Portegies Zwart report tree-construction overhead of 15–25% of total step time in their CUDA octree implementation @bedorf2010. In our case, LBVH construction accounts for less than 0.2% (0.28 ms out of 180.11 ms at $N = 100000$). The difference comes down to where the tree is built: we construct the entire LBVH on the GPU (radix sort, topology, bottom-up aggregation) and never transfer tree data across the CPU–GPU boundary.

Nyland, Harris, and Prins report direct $O(N^2)$ GPU throughput of 10–30 GFLOP/s on contemporary NVIDIA hardware @fastnbody. Our WebGPU direct-summation path achieves 4.03 ms per step at $N = 5000$ ($approx 6.2 times 10^9$ interactions per second), which is competitive given the M2's integrated GPU and 32-bit precision.

== Limitations

Several limitations bound the external validity of these results.

The most significant is that all experiments ran on a single Apple M2 system. The cross-backend comparison (Group 6) shows that software-side variation across four WebGPU implementations is large, but all four use the same Metal driver on the same hardware. GPU performance varies across vendors. The M2 is an integrated GPU with unified memory, which avoids the CPU–GPU transfer costs of discrete systems, but its compute unit count is modest compared to dedicated NVIDIA or AMD GPUs. The timing results and scaling behaviour we report may not generalise to other hardware or GPU backends (Vulkan, Direct3D 12).

A second constraint is WebGPU's limitation to 32-bit floating-point arithmetic in compute shaders. Together with the tree approximation (controlled by $theta$), single-precision arithmetic constrains numerical fidelity. The theta sweep shows that both factors contribute: drift varies two orders of magnitude across $theta$ values, while 32-bit precision sets a floor visible in the direct-summation drift ($Delta E = 2.01$ at $N = 100000$ even without tree approximation). Relatedly, we use only the monopole term of the multipole expansion; quadrupole and higher-order terms, standard in production codes like GADGET-2 @springel_2005, would reduce force approximation error at a given $theta$ and potentially allow larger opening angles for the same accuracy.

The native Metal baseline (UniSim) required patching before it could produce correct results: the original tree serialisation placed a leaf rather than the root at index 0, causing the GPU traversal to skip most of the tree. Our comparison is therefore against a stabilised fork @unisim-fork, not the upstream codebase, and we cannot rule out that other latent issues in UniSim's pipeline affect the timing gap.

WebGPU's shader language (WGSL) does not yet include subgroup operations in the core specification; they are available only as an experimental Dawn extension. This limits both the BVH traversal shader (where warp-coherent techniques could reduce divergence) and the radix sort, which cannot use subgroup-level prefix scans and shuffles for its scatter phase. The current radix sort implementation works around this with per-workgroup local histograms and additional global passes, which is less efficient than a full subgroup-aware radix sort would be.

On the methodology side, we use a global fixed timestep, whereas production codes typically assign each particle an individual timestep proportional to its local dynamical timescale @springel_2005. Without adaptive timestepping, the global $Delta t$ must be conservative enough for the densest region, which wastes work on the majority of particles. Energy drift as a quantitative metric is also limited to $N lt.eq 5000$, where direct pair summation for potential energy is still feasible. At larger $N$ we need to rely on kinetic energy trends and momentum conservation as indirect quality indicators.

These limitations motivate several concrete extensions, discussed in the following section, before the overall conclusions are drawn.
