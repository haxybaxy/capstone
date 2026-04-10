# Benchmarking Methodology

## Hardware

- Apple M2 (Apple Silicon, arm64)
- macOS 25.2.0 (Darwin)
- Metal GPU backend (via wgpu-native / Dawn / browser WebGPU)

## Simulation Parameters

All benchmarks use identical physics parameters unless explicitly stated:

| Parameter | Value |
|-----------|-------|
| Scenario | Plummer sphere |
| Integrator | Leapfrog (KDK) |
| Force method | Barnes-Hut tree |
| theta | 0.75 |
| softening | 0.5 |
| dt | 0.001 |
| seed | 42 |

## Timing Protocol

### Steps
- **150 total steps** per run
- **First 50 discarded** (warmup — GPU pipeline compilation, cache warming, driver JIT)
- **Last 100 measured** (steps 51-150)

### Why 50 warmup steps
GPU compute pipelines have first-run compilation overhead (shader compilation, memory allocation, driver optimization). The first few steps can be 10-100x slower than steady state. 50 steps is conservative — steady state is typically reached within 5-10 steps, but 50 ensures any lazy initialization or thermal throttling has stabilized.

### Statistics computed
Over the 100 measured steps:
- **mean**: average ms/step
- **std**: standard deviation
- **CI95**: 95% confidence interval (1.96 * std / sqrt(n))
- **CV**: coefficient of variation (std / mean) — values >0.3 suggest unstable measurements

### GPU synchronization
Timing requires the GPU to complete work before the CPU reads the clock. Without explicit synchronization, CPU-side timestamps only measure command submission time (~0ms), not actual GPU execution.

**Native (wgpu-native):** `wgpuDevicePoll(device, true, nullptr)` blocks until GPU work completes.

**Dawn:** Dawn's `wgpuQueueOnSubmittedWorkDone` callback fires on CPU submission, not GPU completion. A buffer-map fence is used instead — creating a tiny MapRead buffer and calling `wgpuBufferMapAsync`, which only completes after all prior GPU work finishes.

**Emscripten (browser):** Same buffer-map fence as Dawn, using `emscripten_sleep(0)` in the poll loop to yield to the browser event loop.

### Timing modes

**`--sync-timing`**: Single command encoder for the entire step. `flushGpuQueue` is called after submission. The `force_ms` column captures all GPU work (kick, drift, tree build, force, second kick) since everything is submitted together. Best for total ms/step comparison.

**`--benchmark-passes`**: Separate command encoder + GPU sync per phase (integrate, tree build, force). Gives accurate per-component timings but adds overhead from multiple GPU syncs per step. Use for analyzing where time is spent, not for total throughput comparison.

When comparing total ms/step across backends or optimizations, use `--sync-timing` (not `--benchmark-passes`) to avoid sync overhead inflating the numbers.

## Experiment Descriptions

### P1: Plummer N-scaling (wgpu-native)
N = {1000, 5000, 10000, 50000, 100000}. Measures how total step time scales with particle count. Establishes the baseline.

### P2: Per-pass LBVH breakdown
Same N values with `--benchmark-passes`. Breaks down tree build into 6 sub-passes (bbox, morton, radix_sort, karras, leaf_init, aggregate). Used to identify tree build bottlenecks.

### P3: Metal Barnes-Hut baseline
Separate Metal implementation with matched parameters (theta=0.75, softening=0.5). N = {1000, 5000, 10000, 50000}. N=100000 excluded due to anomalous results in the Metal implementation.

### P4: Cross-backend comparison
N = {1000, 10000, 100000} across wgpu-native, Dawn, Chrome, Safari. Same physics, same GPU. Measures backend/API overhead.

### P5: Native vs browser
Chrome data from P4 at N = {1000, 5000, 10000, 50000, 100000}. Compares Emscripten/WebGPU against native wgpu.

### P6: Optimized force shader
After applying optimizations (precomputed opening radius, compact traversal nodes, workgroup size 128, Morton-ordered particles).

## Considerations When Evaluating Speedups

### 1. Match the timing mode
Never compare `--benchmark-passes` results against `--sync-timing` results. The per-phase GPU sync overhead in benchmark-passes mode adds ~10-15ms of fixed cost per step. Always compare like-for-like.

### 2. Warmup matters
Discard the same number of warmup steps in both runs. The first step can be 100x slower due to shader compilation. If one run warms up faster than another, including warmup steps will bias the comparison.

### 3. Check the CV
A coefficient of variation (CV) above 0.3 suggests the measurement is noisy. Possible causes:
- Thermal throttling (GPU clock scaling under sustained load)
- Background processes competing for GPU
- Memory pressure causing page faults
- Timer resolution too coarse (browser timers round to 1ms)

If CV is high, run more steps or more trials. Do not trust mean comparisons when both CVs are >0.3.

### 4. Small N is dominated by fixed costs
At N=1000, total step time is ~5ms. Fixed per-step overhead (command submission, buffer mapping, GPU sync) can be 1-2ms. A 0.5ms optimization that adds 0.3ms of overhead looks like a regression at N=1000 but a clear win at N=100000 where force computation is 200+ms.

Always evaluate optimizations at multiple N values. The crossover point where optimization overhead is recovered tells you the effective range.

### 5. Energy drift as a correctness check
Energy drift should be comparable between baseline and optimized runs (same order of magnitude). A dramatic change in energy drift means the force computation changed — either a bug or a different traversal order.

Floating-point non-associativity from traversal reordering (e.g., Morton-ordered particles) causes small energy drift differences. This is expected and acceptable for a chaotic N-body system.

### 6. Isolate one variable at a time
When testing multiple optimizations, benchmark each independently before combining. An optimization that helps alone might hurt when combined with another (e.g., near-far traversal ordering + compact nodes: the extra memory reads for child COMs caused cache thrashing that negated the pruning benefit).

### 7. GPU memory bandwidth vs. compute
At small N, the GPU is compute-bound (not enough work to fill all cores). At large N, it becomes bandwidth-bound (too many memory reads per node visit). Optimizations that reduce ALU (precomputed radius) help at all N, but optimizations that reduce bandwidth (compact nodes, Morton ordering) only help when the working set exceeds cache size.

### 8. Browser-specific considerations
- Close all other tabs before benchmarking (GPU contention)
- Browser timers may have reduced resolution (1ms granularity vs. sub-ms native)
- Browser WebGPU adds JS overhead per API call (~5-30ms fixed cost per step at small N)
- WASM has additional overhead vs native (memory model, bounds checking)
- Keep conditions identical across Chrome/Safari runs for fair comparison

### 9. Backend-specific quirks
- **wgpu-native**: Most direct path to Metal. Lowest overhead at small N.
- **Dawn**: Google's WebGPU implementation. Comparable to wgpu at large N, slightly more overhead at small N.
- **Chrome**: Dawn + JS bindings + WASM. ~6x overhead at small N, competitive at large N.
- **Safari**: WebKit's WebGPU. Timer resolution appears to be 1ms (integer values in output). Similar overhead profile to Chrome.
- **Metal (native)**: Direct Metal API. Fastest at small N due to minimal abstraction.

### 10. Reproducibility
Always record:
- Exact command line used
- Git commit hash
- Hardware (chip, OS version)
- Other running processes
- Ambient temperature (if running sustained benchmarks — thermal throttling is real on laptops)

## Optimization Process

### Profiling-driven approach

Optimizations were selected by profiling where time was actually spent, not by intuition. The P1 and P2 benchmarks established that **force computation accounts for 95-99.8% of total step time** across all N values. Tree building (including radix sort, the most expensive sub-pass) was <1% even at N=100K. Kick and drift integration were negligible. This immediately ruled out optimizing anything other than the BVH force traversal shader.

### Identifying candidates

The force shader's hot loop visits hundreds of nodes per particle. For each node visit, the baseline implementation performed:

1. A full 64-byte struct read (BVHNode) from global memory
2. An opening criterion computation: `max(abs(...))`, `length(...)`, `log2(max(...))` — roughly 20 FLOPs including two transcendental functions
3. A stack-based DFS traversal with no spatial ordering

Each of these represents a different bottleneck class: memory bandwidth (#1), ALU throughput (#2), and cache efficiency (#3). We targeted all three.

### Optimization 1: Precomputed opening radius

**Observation:** The opening criterion depends only on node-intrinsic properties (center of mass, AABB bounds, total mass). These are computed once during the bottom-up aggregate pass but recalculated for every particle-node interaction in the force shader — billions of redundant computations per step.

**Change:** Compute `halfExtent = length(comToCorner) * (1 + 0.6 * log2(mass))` once per node in the aggregate pass, store in `boundsMax.w` (previously unused). Force shader reads the precomputed value instead of recomputing.

**Cost:** ~20 extra FLOPs per internal node (N-1 nodes, once per step). Negligible.

**Result:** 1.74x speedup at N=100K. The benefit scales with N because larger trees mean more node visits where the saved ALU accumulates. At small N the absolute savings are too small to overcome measurement noise.

### Optimization 2: Compact traversal nodes

**Observation:** The force shader reads a 64-byte BVHNode per node visit but only uses 28 bytes: `centerOfMass` (16B), `boundsMax.w` (4B), `left` (4B), `right` (4B). Fields `boundsMin`, `boundsMax.xyz`, `parent`, and `particleIdx` are never accessed. Every node read wastes 36 bytes of memory bandwidth.

**Change:** After the aggregate pass, a new compact pass copies the needed fields into a 32-byte `TraversalNode` buffer. The force shader reads from this compact buffer.

**Cost:** One extra compute pass per step (trivial — ~0.1ms even at N=100K). Extra 32B * nodeCount of GPU memory.

**Result:** Additional ~3% speedup on top of optimization 1 at large N. Modest because Apple M2's unified memory architecture has good cache behavior. Would likely help more on discrete GPUs with higher memory latency.

### Optimization 3: Workgroup size tuning

**Observation:** The force shader used workgroup size 64. GPU occupancy depends on the ratio of active threads to hardware capacity. Too few threads per workgroup can leave execution units idle.

**Change:** Tested workgroup sizes 64, 128, and 256 with identical physics. No code change beyond the `@workgroup_size()` directive and dispatch count. Each configuration was benchmarked at N=1000, 10000, 50000, 100000 with the standard protocol (150 steps, `--sync-timing`).

**Results (force_ms from last measured step):**

| N | WG=64 | WG=128 | WG=256 | Winner |
|---|-------|--------|--------|--------|
| 1K | 5.2ms | 3.9ms | 5.4ms | 128 |
| 10K | 15.3ms | 11.1ms | 11.5ms | 128 |
| 50K | 81.0ms | 76.2ms | 78.4ms | 128 |
| 100K | 220.7ms | 212.5ms | 210.1ms | 256 |

Workgroup 128 was consistently best across N=1K-50K. Workgroup 256 was marginally better only at N=100K. Selected 128 as the general-purpose best.

**Hardware dependence:** Optimal workgroup size is hardware-specific. It depends on the GPU's SIMD width, register file size, number of execution units, and how the driver schedules workgroups. The Apple M2 GPU has a SIMD width of 32 and benefits from moderate occupancy — 128 threads (4 SIMD groups) balances register pressure against parallelism. On discrete GPUs (NVIDIA, AMD) with larger register files and more compute units, 256 or higher may be optimal. This parameter should be re-tuned when targeting different hardware.

### Optimization 4: Morton-ordered particle access

**Observation:** Threads in a workgroup process particles with consecutive indices, but consecutive particles may be spatially distant (original insertion order). Spatially distant particles traverse different parts of the BVH tree, causing poor cache utilization — each thread loads different tree nodes, thrashing shared cache lines.

**Change:** The radix sort already produces a Morton-code ordering of particles (sortIndices buffer). Added this buffer as a binding in the force shader. Thread `i` processes particle `sortIndices[i]` instead of particle `i`, so adjacent threads in a workgroup handle spatially nearby particles that visit similar tree paths.

**Cost:** One extra u32 read per particle (sort index lookup). Write to `accelerations[particleIdx]` instead of `accelerations[i]` (scattered write, but writes are less frequent than reads).

**Result:** Additional ~20% speedup on top of previous optimizations at N=100K (224ms to 184ms). The benefit comes from improved L1/L2 cache hit rates during tree traversal.

### Theta tuning (parameter choice, not code change)

Increasing the Barnes-Hut opening angle theta reduces the number of node visits per particle at the cost of force accuracy. This is not a code optimization — it is a parameter tradeoff that should be documented alongside any performance claims.

At theta=0.75 (our benchmark default), the opening criterion is moderately conservative. Increasing to theta=1.0 would roughly halve the number of deep traversals, giving a significant speed improvement, but force errors grow as O(theta^2). For scientific accuracy, theta=0.5-0.75 is typical; for real-time visualization, theta=0.8-1.0 is acceptable.

All benchmark comparisons in this document use theta=0.75 on both baseline and optimized runs. When comparing against other implementations (e.g., the Metal baseline), matching theta is critical — a theta difference of 0.1 can change performance by 20-40% while appearing to be a code-level speedup.

### What we tried and rejected

**Near-far child traversal ordering:** Push the farther child first so the nearer child is processed first from the stack. The hypothesis was that nearer subtrees satisfy the opening criterion sooner, enabling more pruning. In practice, the two extra `bvhNodes[child].centerOfMass` reads per non-leaf node caused cache thrashing that outweighed the pruning benefit. At N=10K-50K, this optimization made force computation 10-30% *slower*.

**Warp-coherent traversal (subgroup operations):** The Karras & Aila technique where all threads in a warp collectively decide which nodes to expand. This was investigated but not implemented because: (a) WGSL subgroup operations are only available as experimental Chromium extensions on the Dawn backend, not on wgpu-native; (b) only `subgroupBallot` and `subgroupBroadcast` are implemented (no `subgroupAll`/`subgroupAny`); (c) the binary BVH has branching factor 2, limiting the coherence benefit compared to octrees (branching factor 8) where this technique originated.

**SoA particle layout (separating mass from position):** Investigated splitting the `vec4f` position buffer (xyz=position, w=mass) into separate `vec3f` positions and `f32` masses buffers. Analysis showed this would hurt performance: the BVH force shader (99% of step time) never reads particle masses — it uses aggregated node masses from the traversal buffer. The shaders that do read particle mass (leaf init, drift, direct force) always access position xyz and mass together, so separating them would double cache misses for no benefit. The only shaders that read position xyz without mass (bbox, morton, render) account for <1% of step time. The 4-byte-per-particle bandwidth saving (~3%) is negligible. Current packed layout (mass in position.w) is optimal.

### Combined result

| N | Baseline | Optimized | Speedup |
|---|----------|-----------|---------|
| 1,000 | 5.8 ms | 6.9 ms | 0.84x |
| 5,000 | 9.9 ms | 8.0 ms | 1.24x |
| 10,000 | 11.3 ms | 11.5 ms | ~1.0x |
| 50,000 | 109.5 ms | 67.2 ms | 1.63x |
| 100,000 | 396.2 ms | 183.9 ms | 2.15x |

The optimizations are most effective at large N where force computation dominates. At small N (1K), the per-step overhead of the compact pass and sort index lookup exceeds the savings. The crossover where optimizations break even is around N=3000-5000.

