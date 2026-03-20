#pagebreak()
= Conclusion
#set heading(numbering: "1.1")

This work presented a hierarchical $N$-body solver for galactic dynamics implemented entirely in WebGPU, featuring a fully GPU-resident Linear Bounding Volume Hierarchy (LBVH) constructed and traversed on-device each timestep. The implementation was evaluated across three benchmark scenarios (two-body orbit, Plummer sphere, and rotating exponential disk) with systematic parameter sweeps targeting three research questions: scalability, numerical quality, and platform feasibility.
== Scalability (RQ1)

The GPU LBVH Barnes–Hut implementation demonstrated sub-linear scaling with particle count, increasing from 0.61 ms per step at $N = 100$ to 2.35 ms per step at $N = 100000$, a 3.9$times$ increase in runtime over a 1000$times$ increase in $N$. This scaling, substantially flatter than the theoretical $O(N log N)$ due to GPU parallelism, shows that hierarchical force evaluation on WebGPU is effective at the particle counts relevant to interactive galactic dynamics simulation. The tree-based approach outperformed direct $O(N^2)$ summation for $N gt.eq 2000$, with tree construction accounting for 74–79% of total step time and force evaluation for 18–20%.

== Numerical Quality (RQ2)

Energy conservation analysis revealed that 32-bit GPU floating-point precision is the dominant constraint on numerical fidelity in the current implementation, exceeding the effects of opening angle $theta$ and timestep $Delta t$ for the configurations tested. The symplectic leapfrog integrator maintained stable orbits and conserved momentum to high precision, consistent with its theoretical properties @springel_2005 @galacticdynamics2nded. However, quantitative energy drift comparisons between integrators were confounded by the different precision of their force computation paths (32-bit GPU BVH versus 64-bit CPU octree), indicating that a fair comparison would require either 64-bit GPU arithmetic or a 32-bit CPU reference path.

== Platform Feasibility (RQ3)

WebGPU proved capable of sustaining interactive frame rates (above 60 FPS) for up to at least $N = 50000$ particles on an Apple M2 GPU, with headless throughput of 425 timesteps per second at $N = 100000$. Browser execution via Emscripten WebAssembly adds a fixed overhead of approximately 4.3 ms per step from event-loop scheduling, yielding an overhead factor of 2.7$times$ at $N = 100000$ that diminishes as GPU compute time grows with $N$. Drift values match between platforms to within 1% at $N gt.eq 10000$. The overhead is additive and constant, not multiplicative: the sub-linear scaling behaviour observed in native execution is preserved in the browser, which supports WebGPU's viability as a platform for browser-based scientific simulation. The primary platform constraints are 32-bit arithmetic precision and the fixed per-step browser scheduling cost at small $N$, rather than buffer size limits or compute throughput.

== Contribution

The results show that WebGPU's compute shader model is sufficient for a complete scientific computing workload: a complete Barnes–Hut $N$-body solver with parallel tree construction, hierarchical force evaluation, and symplectic integration. By building from a single codebase that targets both native desktop and browser environments, the implementation shows that accessible, interactive galactic dynamics simulation is achievable without specialised hardware or vendor-locked APIs. The performance characteristics reported here, together with the identified precision limitations, provide a reference point for future work on GPU-accelerated scientific computing in WebGPU as the specification and its implementations continue to mature.
