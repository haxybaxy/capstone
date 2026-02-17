# Hierarchical N-Body Simulation of Galactic Dynamics in WebGPU

**Bachelor's Capstone Thesis** — IE University, School of Science & Technology

**Author:** Zaid Alsaheb
**Supervisor:** Professor Raul Perez Pelaez


You can check out the simulation on your web browser [here!](https://haxybaxy.github.io/webgpu-galaxy/) (Only compatible with chrome)

The paper is also available [here](https://github.com/haxybaxy/capstone) if you don't want to download it.


---

## Overview

This thesis presents a GPU-accelerated Barnes-Hut N-body gravitational solver built entirely on WebGPU. A single C++20 codebase compiles to both native desktop (via wgpu-native or Dawn) and web browsers (via Emscripten), enabling interactive simulations of galactic dynamics without specialized software installation.

The core contribution is bringing hierarchical O(N log N) force evaluation to the browser through WebGPU compute shaders, bridging the gap between high-fidelity astrophysical simulation and web accessibility.

## Key Features

- **Barnes-Hut Algorithm**: Hierarchical approximation reducing force evaluation from O(N²) to O(N log N)
- **Fully GPU-resident**: Linear BVH construction and traversal implemented across 12 WGSL compute shaders
- **Dual-target compilation**: Native desktop and browser from a single codebase
- **Symplectic integration**: Kick-drift-kick leapfrog for long-term energy conservation
- **Interactive visualization**: Real-time rendering with ImGui overlay for parameter control

## Benchmark Scenarios

| Scenario | Description | Particle Count |
|----------|-------------|----------------|
| A | Two-body circular orbit | 2 |
| B | Plummer sphere equilibrium | 10³ – 10⁵ |
| C | Rotating exponential disk | 10⁴ – 10⁵ |

## Tech Stack

- **Language:** C++20
- **GPU API:** WebGPU C API (no wrapper libraries)
- **Shaders:** WGSL (WebGPU Shading Language)
- **Build:** CMake with FetchContent (all dependencies pinned)
- **Document:** [Typst](https://typst.app/)

### Dependencies (auto-fetched by CMake)

- WebGPU-distribution v0.2.0
- GLFW 3.4
- glfw3webgpu v1.2.0
- spdlog v1.16.0
- Dear ImGui v1.90.9
- GLM 1.0.2

### Backends

| Target | Backend |
|--------|---------|
| Native | wgpu-native or Dawn |
| Browser | Emscripten (with Asyncify) |

## Project Structure

```
capstone/
├── main.typ              # Main Typst document
├── main.pdf              # Compiled thesis PDF
├── references.bib        # Bibliography
├── graphics/             # Figures and logos
├── sections/             # Thesis sections (Typst)
│   ├── title_page.typ
│   ├── abstract.typ
│   ├── introduction.typ
│   ├── methodology.typ
│   ├── experiments.typ
│   ├── results.typ
│   ├── discussion.typ
│   ├── conclusions.typ
│   ├── future_work.typ
│   └── appendix.typ
└── .github/
    └── workflows/
        └── deploy-pdf.yml  # Auto-deploy PDF to GitHub Pages
```

## Building the PDF

Requires the [Typst CLI](https://github.com/typst/typst):

```bash
typst compile main.typ
```

The PDF is also automatically compiled and deployed to GitHub Pages on every push to `main`.

## GPU Pipeline Overview

Each simulation timestep executes the following compute shader passes:

1. **AABB Reduction** — Compute scene bounding box
2. **Morton Code Generation** — Assign spatial keys to particles
3. **Bitonic Sort** — Sort particles by Morton code
4. **Karras Topology** — Build binary radix tree (Karras 2012)
5. **Leaf Initialization** — Populate leaf nodes
6. **Bottom-up Aggregation** — Compute internal node bounding boxes and centers of mass
7. **Tree Traversal** — Evaluate gravitational forces via monopole approximation
8. **Integration** — Symplectic leapfrog (kick-drift-kick)

## License

Academic work — IE University, 2026.
