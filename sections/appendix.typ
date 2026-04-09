#pagebreak()
= Appendix
#set heading(numbering: "A.1")

== Source Code Repositories

The source code for all software used in this work is publicly available:

#figure(
  table(
    columns: (auto, auto),
    align: (left, left),
    [*Repository*], [*URL*],
    [N-body solver (this work)], [`https://github.com/haxybaxy/webgpu-galaxy`],
    [UniSim fork (Metal baseline)], [`https://github.com/haxybaxy/unisim`],
    [Paper source (Typst)], [`https://github.com/haxybaxy/capstone`],
  ),
  caption: [Source code repositories.],
)

== Command-Line Interface Reference

The solver is invoked as a single binary with all parameters specified via command-line flags. @tab:cli lists the available options.

#figure(
  table(
    columns: (auto, auto, auto, auto),
    align: (left, left, left, left),
    [*Flag*], [*Type*], [*Default*], [*Description*],
    [`--scenario`], [`twobody` | `plummer` | `disk`], [`disk`], [Benchmark scenario],
    [`--N`], [integer], [`10000`], [Particle count (ignored for twobody)],
    [`--dt`], [float], [`0.001`], [Timestep $Delta t$],
    [`--theta`], [float], [`0.75`], [Opening angle $theta$],
    [`--softening`], [float], [`0.5`], [Plummer softening $epsilon$],
    [`--seed`], [integer], [`42`], [Random seed for initial conditions],
    [`--steps`], [integer], [0 (interactive)], [Step count; required for headless],
    [`--force-method`], [`tree` | `direct`], [`tree`], [Force evaluation method],
    [`--export`], [path], [(none)], [CSV output file path],
    [`--headless`], [flag], [off], [Batch mode with no window],
    [`--sync-timing`], [flag], [off], [GPU fence before each timestamp],
    [`--benchmark-passes`], [flag], [off], [Per-pass LBVH timing (implies sync)],
  ),
  caption: [Command-line flags. All flags are optional; unspecified parameters use the defaults shown.],
) <tab:cli>

== Experiment Invocations

Below are representative invocations for each experiment group. In all cases, the swept parameter is varied while other flags remain as shown. The benchmarking protocol (50 warmup steps discarded, 100 measured) is applied during post-processing of the CSV output; the `--steps` flag is set to 150 accordingly.

=== Group 1: Two-Body Validation

```
./build/src/galaxysim --headless --scenario twobody --N 2 \
  --steps 5000 --dt 0.001 --softening 0.5 --theta 0.75 \
  --seed 42 --force-method tree --sync-timing \
  --export results/benchmarks/dt_0.001_N2.csv
```
Swept: `--dt` over {0.0001, 0.0005, 0.001, 0.005}. Particle count is fixed at $N = 2$ by the scenario.

=== Group 2a: N-Scaling (Plummer)

```
./galaxysim --scenario plummer --N 1000 --dt 0.001 --theta 0.75 \
  --softening 0.5 --seed 42 --steps 150 --headless \
  --sync-timing --export results/B_scale_N1000.csv
```
Swept: `--N` over {1000, 5000, 10000, 50000, 100000}.

=== Groups 2b/2c/2e: Parameter Sweeps (Plummer, $N = 5000$)

```
./build/src/galaxysim --headless --scenario plummer --N 5000 \
  --steps 5000 --dt 0.001 --theta 0.3 --softening 0.5 \
  --seed 42 --force-method tree --sync-timing \
  --export results/B_theta03.csv
```
2b swept: `--theta` over {0.3, 0.5, 0.7, 1.0}. \
2c swept: `--dt` over {0.0001, 0.0005, 0.001, 0.005}. \
2e swept: `--softening` over {0.1, 0.25, 0.5, 1.0, 2.0}.

=== Group 3a: Disk N-Scaling

```
./build/src/galaxysim --headless --scenario disk \
  --N 10000 --steps 150 --dt 0.001 --softening 0.5 \
  --theta 0.75 --seed 42 --force-method tree \
  --sync-timing --export results/benchmarks/disk_sync_N10000.csv
```
Swept: `--N` over {1000, 5000, 10000, 50000, 100000}.

=== Group 4: Direct vs Tree Crossover

```
./galaxysim --scenario plummer --N 1000 --dt 0.001 --theta 0.75 \
  --softening 0.5 --seed 42 --steps 150 --headless \
  --sync-timing --force-method direct \
  --export results/D_direct_N1000.csv
```
Swept: `--N` over {1000, 5000, 10000, 50000, 100000}, each run twice with `--force-method tree` and `--force-method direct`.

=== Group 5: Native vs Browser

Native runs use the same invocation as Group 2a. Browser runs use the Emscripten-compiled WebAssembly build served to a Chrome instance, and timing is extracted from console-log timestamps.

=== Group 6: Cross-Backend Comparison

```
./galaxysim --scenario plummer --N 1000 --dt 0.001 --theta 0.75 \
  --softening 0.5 --seed 42 --steps 150 --headless \
  --sync-timing --export results/F_wgpu_N1000.csv
```
Swept: `--N` over {1000, 10000, 100000}. Repeated for four backends: wgpu-native, Dawn, Chrome (Emscripten), Safari (Emscripten). Positions are held frozen (forces computed but not applied) to isolate dispatch overhead.

=== Group 7: LBVH Pass Breakdown

```
./galaxysim --scenario plummer --N 1000 --dt 0.001 --theta 0.75 \
  --softening 0.5 --seed 42 --steps 150 --headless \
  --benchmark-passes --export results/G_lbvh_N1000.csv
```
Swept: `--N` over {1000, 5000, 10000, 50000, 100000}. The `--benchmark-passes` flag enables per-pass timing.

== Complete Experiment Parameter Table

@tab:all-experiments lists every distinct experiment configuration. All runs use leapfrog integration and seed 42 unless noted.

#figure(
  table(
    columns: (auto, auto, auto, auto, auto, auto, auto, auto),
    align: (left, left, right, right, right, right, left, right),
    [*Group*], [*Scenario*], [*$N$*], [*$Delta t$*], [*$theta$*], [*$epsilon$*], [*Force*], [*Steps*],
    [1], [twobody], [2], [0.0001–0.005], [0.75], [0.5], [tree], [5,000],
    [2a], [plummer], [1K–100K], [0.001], [0.75], [0.5], [tree], [150],
    [2b], [plummer], [5,000], [0.001], [0.3–1.0], [0.5], [tree], [5,000],
    [2c], [plummer], [5,000], [1e-4–5e-3], [0.75], [0.5], [tree], [5,000],
    [2e], [plummer], [5,000], [0.001], [0.75], [0.1–2.0], [tree], [5,000],
    [3a], [disk], [1K–100K], [0.001], [0.75], [0.5], [tree], [150],
    [4], [plummer], [1K–100K], [0.001], [0.75], [0.5], [both], [150],
    [5], [plummer], [1K–100K], [0.001], [0.75], [0.5], [tree], [150],
    [6], [plummer], [1K–100K], [0.001], [0.75], [0.5], [tree], [150],
    [7], [plummer], [1K–100K], [0.001], [0.75], [0.5], [tree], [150],
  ),
  caption: [Complete parameter table for all experiment groups. Ranges indicate swept variables, while all other parameters are held fixed. Group 4 runs both force methods at each $N$. Groups 5 and 6 repeat across execution platforms.],
) <tab:all-experiments>
