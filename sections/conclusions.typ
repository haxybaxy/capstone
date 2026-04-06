#pagebreak()
= Conclusion
#set heading(numbering: "1.1")

We presented a hierarchical $N$-body solver for galactic dynamics, implemented entirely in WebGPU, with a fully GPU-resident Linear Bounding Volume Hierarchy (LBVH) constructed and traversed on-device each timestep. We evaluated it across three benchmark scenarios (two-body orbit, Plummer sphere, and rotating exponential disk) with systematic parameter sweeps targeting three research questions: scalability and pipeline bottlenecks, WebGPU abstraction overhead relative to native Metal, and browser feasibility. Numerical quality under 32-bit precision was characterised as a secondary observation throughout.

== Scalability and Pipeline Bottlenecks (RQ1)

Runtime grows from 5.86 ms per step at $N = 1000$ to 180.11 ms at $N = 100000$, with force evaluation accounting for 94–99% of step time. The LBVH construction pipeline stays below 0.35 ms even at $N = 100000$, with individual passes roughly constant in $N$ — the BVH traversal shader is clearly the primary optimisation target. Direct $O(N^2)$ summation is faster at every tested particle count, but it accumulates far more energy drift: $Delta E = 2.01$ vs $0.076$ for the tree path at $N = 100000$. The hierarchical approach trades throughput for the force accuracy needed to keep simulations physically meaningful.

== Abstraction Overhead (RQ2)

Against a native Metal Barnes–Hut baseline (UniSim @unisim) on the same Apple M2, the WebGPU layer costs 2.0$times$ at $N = 1000$, where per-dispatch overhead dominates. At $N gt.eq 5000$ the WebGPU solver is consistently faster — 2.9$times$ at $N = 100000$ (180.11 ms vs 516.78 ms) — because the fully GPU-resident LBVH pipeline eliminates CPU–GPU coordination, not because WebGPU is inherently faster than Metal. A four-way comparison across WebGPU implementations (wgpu-native, Dawn, Chrome, Safari) shows large cross-implementation variation, consistent with Maczan @maczan2026: Dawn has the lowest per-dispatch overhead at small $N$; wgpu-native scales best to large $N$.

== Browser Feasibility (RQ3)

Chrome's browser WebGPU implementation achieves lower per-dispatch overhead than wgpu-native at small $N$ (4.87 ms vs 5.86 ms at $N = 1000$, overhead 0.8$times$). As force evaluation dominates at larger particle counts, Chrome scales less efficiently: the overhead peaks at 2.0$times$ ($N = 5000$) and then gradually decreases to 1.4$times$ at $N = 100000$ (260.74 ms vs 180.11 ms). The overhead narrows with $N$ but does not vanish, indicating a scaling rather than a fixed-cost difference between platforms. Nevertheless, the browser sustains the same qualitative scaling behaviour as native execution, supporting WebGPU's viability for browser-based scientific simulation.

== Contribution

Taken together, the results show that WebGPU's compute shader model is sufficient for a complete scientific computing workload — parallel tree construction, hierarchical force evaluation, and symplectic integration — benchmarked across four implementations and compared against a native Metal baseline. The solver matches or exceeds native Metal performance at scientifically relevant particle counts, and browser execution remains within 1.4$times$ of native throughput at $N = 100000$. By building from a single C++/WGSL codebase targeting both desktop and browser, we show that accessible, interactive galactic dynamics simulation is achievable without specialised hardware or vendor-locked APIs. The performance data and identified precision limitations reported here should serve as a reference point for future GPU-accelerated scientific computing in WebGPU as the standard and its implementations mature.
