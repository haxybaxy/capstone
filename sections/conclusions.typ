#pagebreak()
= Conclusion
#set heading(numbering: "1.1")

We presented a hierarchical $N$-body solver for galactic dynamics, implemented entirely in WebGPU, with a fully GPU-resident Linear Bounding Volume Hierarchy (LBVH) constructed and traversed on-device each timestep. We evaluated it across three benchmark scenarios (two-body orbit, Plummer sphere, and rotating exponential disk) with systematic parameter sweeps targeting three research questions: scalability and pipeline bottlenecks, WebGPU abstraction overhead relative to native Metal, and browser feasibility. Numerical quality under 32-bit precision was characterised as a secondary observation throughout.

== Scalability and Pipeline Bottlenecks (RQ1)

Runtime grows from 7.04 ms per step at $N = 1000$ to 182.85 ms at $N = 100000$, with force evaluation accounting for 94–99% of step time. The LBVH construction pipeline stays below 1 ms even at $N = 100000$, with individual passes roughly constant in $N$ — the BVH traversal shader is clearly the primary optimisation target. Direct $O(N^2)$ summation is faster at every tested particle count, but it accumulates far more energy drift: $Delta E = 2.01$ vs $0.079$ for the tree path at $N = 100000$. The hierarchical approach trades throughput for the force accuracy needed to keep simulations physically meaningful.

== Abstraction Overhead (RQ2)

Against a native Metal Barnes–Hut baseline (UniSim @unisim) on the same Apple M2, the WebGPU layer costs 2.4$times$ at $N = 1000$, where per-dispatch overhead dominates. At $N gt.eq 5000$ the WebGPU solver is consistently faster — 2.8$times$ at $N = 100000$ (182.85 ms vs 516.78 ms) — because the fully GPU-resident LBVH pipeline eliminates CPU–GPU coordination, not because WebGPU is inherently faster than Metal. A four-way comparison across WebGPU implementations (wgpu-native, Dawn, Chrome, Safari) shows large cross-implementation variation, consistent with Maczan @maczan2026: Dawn has the lowest per-dispatch overhead at small $N$; wgpu-native scales best to large $N$.

== Browser Feasibility (RQ3)

Browser execution via Emscripten adds a fixed ~29 ms per step from asyncify scheduling. At small $N$ this dominates (5.1$times$ at $N = 1000$), but it is additive, not multiplicative — it does not grow with $N$. By $N = 50000$ the browser matches native throughput (67.77 ms vs 67.53 ms), and at $N = 100000$ the overhead drops to 1.2$times$ (219.96 ms vs 182.85 ms). The native scaling behaviour is preserved in the browser, supporting WebGPU's viability for browser-based scientific simulation within the 32-bit precision constraint @realitycheck.

== Contribution

Taken together, the results show that WebGPU's compute shader model is sufficient for a complete scientific computing workload — parallel tree construction, hierarchical force evaluation, and symplectic integration — benchmarked across four implementations and compared against a native Metal baseline. The solver matches or exceeds native Metal performance at scientifically relevant particle counts, and browser execution converges to native throughput as GPU compute dominates. By building from a single C++/WGSL codebase targeting both desktop and browser, we show that accessible, interactive galactic dynamics simulation is achievable without specialised hardware or vendor-locked APIs. The performance data and 32-bit precision limitations reported here should serve as a reference point for future GPU-accelerated scientific computing in WebGPU as the standard and its implementations mature.
