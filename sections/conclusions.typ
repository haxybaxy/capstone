#pagebreak()
= Conclusion
#set heading(numbering: "1.1")

This work presented a hierarchical $N$-body solver for galactic dynamics implemented entirely in WebGPU, featuring a fully GPU-resident Linear Bounding Volume Hierarchy (LBVH) constructed and traversed on-device each timestep. The implementation was evaluated across three benchmark scenarios (two-body orbit, Plummer sphere, and rotating exponential disk) with systematic parameter sweeps targeting three research questions: scalability and pipeline bottlenecks, WebGPU abstraction overhead relative to native Metal, and browser feasibility. Numerical quality under 32-bit floating-point precision was characterised as a cross-cutting secondary observation.

== Scalability and Pipeline Bottlenecks (RQ1)

Total runtime increases from 7.04 ms per step at $N = 1000$ to 182.85 ms at $N = 100000$, with force evaluation accounting for 94–99% of step time across all particle counts. The six-pass LBVH construction pipeline remains below 1 ms even at $N = 100000$, with individual construction passes approximately constant in $N$, confirming that the parallel construction method scales efficiently and that the BVH traversal shader is the primary optimisation target. Direct $O(N^2)$ summation is faster than tree-based evaluation at all tested particle counts, but accumulates substantially more energy drift: at $N = 100000$, direct summation yields $Delta E = 2.01$ compared to $0.079$ for the tree path, demonstrating that the hierarchical approach trades throughput for the force accuracy required to keep simulations physically meaningful over long integrations.

== Abstraction Overhead (RQ2)

Comparison against a native Metal Barnes–Hut baseline (UniSim @unisim) on the same Apple M2 hardware shows that the WebGPU abstraction layer imposes a 2.4$times$ overhead at $N = 1000$, where per-dispatch cost dominates. At $N gt.eq 5000$ the WebGPU implementation is consistently faster, reaching 2.8$times$ faster at $N = 100000$ (182.85 ms vs 516.78 ms), reflecting the efficiency of the fully GPU-resident LBVH pipeline rather than an inherent speed advantage of WebGPU over Metal. A four-way comparison across WebGPU implementations (wgpu-native, Dawn, Chrome, and Safari) reveals substantial cross-implementation variation consistent with Maczan @maczan2026: Dawn achieves the lowest per-dispatch overhead (1.47 ms at $N = 1000$) while wgpu-native scales best to large $N$.

== Browser Feasibility (RQ3)

Browser execution via Emscripten WebAssembly adds a fixed overhead of approximately 29 ms per step from asyncify event-loop scheduling. This cost dominates at small $N$ (5.1$times$ overhead at $N = 1000$) but diminishes as GPU compute time grows: at $N = 50000$ the browser matches native throughput (67.77 ms vs 67.53 ms), and at $N = 100000$ the overhead is 1.2$times$ (219.96 ms vs 182.85 ms). The overhead is additive and constant, not multiplicative: the scaling behaviour observed in native execution is preserved in the browser, supporting WebGPU's viability as a platform for browser-based scientific simulation subject to the 32-bit precision constraint @realitycheck.

== Contribution

The results demonstrate that WebGPU's compute shader model is sufficient for a complete scientific computing workload: parallel tree construction, hierarchical force evaluation, and symplectic integration, benchmarked across four WebGPU implementations and compared against a native Metal baseline. The WebGPU solver matches or exceeds native Metal performance at scientifically relevant particle counts, and browser execution converges to native throughput as GPU compute dominates. By building from a single C++/WGSL codebase that targets both native desktop and browser environments, this work shows that accessible, interactive galactic dynamics simulation is achievable without specialised hardware or vendor-locked APIs. The performance characteristics reported here, together with the identified 32-bit precision limitations, provide a reference point for future work on GPU-accelerated scientific computing in WebGPU as the specification and its implementations continue to mature.
