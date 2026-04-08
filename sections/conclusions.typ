#pagebreak()
= Conclusion
#set heading(numbering: "1.1")

We presented a hierarchical $N$-body solver for galactic dynamics implemented entirely in WebGPU, evaluated across three benchmark scenarios with systematic parameter sweeps targeting scalability, abstraction overhead relative to native Metal, and browser feasibility.

== Scalability and Pipeline Bottlenecks (RQ1)

Force evaluation accounts for 94–99% of step time across all tested particle counts, while LBVH construction remains negligible. The BVH traversal shader is therefore the primary optimisation target. Direct $O(N^2)$ summation is faster but accumulates far more energy drift, confirming that the hierarchical approach is necessary to keep simulations physically meaningful over many timesteps.

== Abstraction Overhead (RQ2)

The WebGPU solver matches or exceeds a native Metal Barnes–Hut baseline (UniSim @unisim) at $N gt.eq 5000$ on the same Apple M2, with the advantage widening at larger particle counts. This reflects implementation differences between the two solvers rather than an inherent platform advantage. A four-way comparison across WebGPU implementations confirms that backend choice alone produces substantial performance variation, consistent with Maczan @maczan2026.

== Browser Feasibility (RQ3)

Browser overhead converges to roughly 1.4$times$ at large particle counts, with the browser sustaining the same qualitative scaling behaviour as native execution. This supports WebGPU's viability for browser-based scientific simulation at scientifically relevant particle counts.

== Contribution

Taken together, the results show that WebGPU's compute shader model is sufficient for a complete scientific computing workload (parallel tree construction, hierarchical force evaluation, and symplectic integration) benchmarked across four implementations and compared against a native Metal baseline. The solver matches or exceeds native Metal performance at scientifically relevant particle counts, and browser execution remains within 1.4$times$ of native throughput at $N = 100000$. By building from a single C++/WGSL codebase targeting both desktop and browser, we show that accessible, interactive galactic dynamics simulation is achievable without specialised hardware or vendor-locked APIs. The performance data and identified precision limitations reported here should serve as a reference point for future GPU-accelerated scientific computing in WebGPU as the standard and its implementations mature.

The practical implications extend beyond the benchmark results themselves. Browser deployment eliminates the installation, driver management, and vendor lock-in that currently limit access to GPU-accelerated simulation. An astrophysics course could distribute an interactive N-body lab as a URL rather than requiring students to configure CUDA toolchains or purchase specific hardware. Research groups could share reproducible simulation environments without containerisation or cloud GPU provisioning. Outreach projects could embed galactic dynamics simulations directly in web pages, reaching audiences that would never install standalone software. As WebGPU matures (with broader hardware support, potential 64-bit precision extensions, and growing adoption across browsers) these applications become increasingly viable, positioning browser-based scientific computing as a practical complement to traditional HPC workflows rather than a concession.
