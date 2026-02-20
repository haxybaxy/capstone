#pagebreak()
= Methodology
#set heading(numbering: "1.1")
== Research Design and Objectives
This project follows a computational-methods research design: we implement and evaluate a GPU-accelerated gravitational N-body solver for galactic dynamics, built with C++20 and the WebGPU API. The application compiles to both native desktop (via wgpu-native or Dawn backends) and browser (via Emscripten), enabling interactive visualization and headless batch evaluation from the same codebase.

The methodology is structured to ensure the implementation is (i) reproducible, (ii) numerically stable over long integrations, and (iii) computationally scalable beyond the quadratic cost of direct summation.


The central methodological choices follow directly from the Literature Review:
- *Force Model*: Newtonian gravity with softening to avoid singularities and reduce two-body relaxation (collisionless approximation).
- *Acceleration strategy*: a hierarchical tree method in the Barnes-Hut family to reduce per-step complexity from $O(N^2)$ to approximately $O(N log N)$. @barneshut
- *Time Integration*: a symplectic scheme (leapfrog / velocity Verlet) to improve long-term energy behavior compared to Euler.
- *Compute platform*: WebGPU compute shaders to enable general-purpose parallel computation on the GPU. The WebGPU C API is used throughout (raw `WGPUDevice`, `WGPUBuffer`, etc.), supporting native execution and browser deployment from a single build system.

The research questions operationalized by this methodology are:

1. *Scalability*: How does runtime per timestep scale with $N$ for a WebGPU Barnes-Hut implementation compared to a direct $O(N^2)$ baseline at small $N$?
2. *Numerical quality*: For fixed $N$, how do timestep size $(d t)$ and opening angle $(theta)$ affect $(a)$ force accuracy relative to a direct reference, and $(b)$ long-term conservation metrics (energy drift, momentum drift)?
3. *Platform feasibility*: What particle counts and timestep rates are practical within WebGPU constraints (32-bit precision, memory limits, scheduling, device variability)?

== Simulation data generation and benchmark scenarios
=== Initial-condition scenarios


