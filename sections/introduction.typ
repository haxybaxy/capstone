#pagebreak()
= Literature Review
Galaxy simulation boils down to computing gravitational forces among many particles and stepping them forward in time without the numerics falling apart. GPU-accelerated N-body solvers are well established on platforms like CUDA, but whether the newer, cross-platform WebGPU standard can handle the same workload and what it would cost in practice, is largely untested. This review covers the four areas that bear on that question: N-body force algorithms, numerical integration, GPU-accelerated computing, and browser-based GPU computation.
#set heading(numbering: "1.1")

== Computational Constraints in Astrophysical Simulation
For most of the field’s history, computational astrophysics could rely on Moore’s Law: implement an algorithm once and wait for faster hardware. Sutter documented the end of that era in 2005, noting that single-core clock speeds had hit a wall @freelunchover. Since then, progress has meant finding parallelism by writing code that can split work across hundreds or thousands of execution units rather than waiting for any single one to get faster @fluke2011.

GPUs are the clearest beneficiary of that shift. Their thousands of lightweight cores and high memory bandwidth can accelerate suitable workloads by an order of magnitude or more @surveyofcomputation. But "suitable" is doing real work in that sentence, as an algorithm that runs well on a CPU, with its deep caches and branch predictors, will most likely perform terribly on a GPU if it involves irregular memory access or divergent control flow. Burtscher and Pingali showed this concretely for Barnes–Hut tree traversal, where thread divergence within warps became the primary bottleneck @cudabarnes.
== Gravitational N-Body Simulations and Quadratic Scaling
The gravitational N-body problem is central to galactic dynamics: model a galaxy as a collection of particles (stars, dark matter) interacting through gravity, and simulate their evolution over time @galacticdynamics2nded @zwart_high-performance_2007. The physics is straightforward. The gravitational force on particle $i$ due to particle $j$ is

#math.equation(
  $
    bold(F)_(i j) =
    G frac(
      m_i m_j (bold(r)_j - bold(r)_i)
      ,
      |bold(r)_j - bold(r)_i|^3
    )
  $,
)

where $G$ is the gravitational constant, $m_i$ and $m_j$ are the particle masses, and $bold(r)_i$ and $bold(r)_j$ are their positions. The cube of the distance in the denominator combines the inverse-square magnitude with a unit direction vector. Summing over all other particles gives the total force on particle $i$:

#math.equation(
  $
    bold(F)_i =
    sum_(j != i)^N
    G frac(
      m_i m_j (bold(r)_j - bold(r)_i),
      |bold(r)_j - bold(r)_i|^3
    )
  $,
)

Every particle interacts with every other particle in the simulation, so the cost scales as $O(N^2)$ per timestep. At $N = 100000$ that is roughly $10^(10)$ interactions per step, which is feasible on modern GPUs, but far too expensive for the million-step integrations needed to observe phenomena such as spiral arm formation or halo relaxation @zwart_high-performance_2007.

== Hierarchical Approximation and the Barnes–Hut Algorithm
A variety of approximation techniques have been developed to reduce the computational cost of N-body force evaluation without sacrificing essential physics. The most prevalent "entry level" algorithm is the Barnes–Hut algorithm, which exploits the hierarchical spatial structure of particle distributions @barneshut.

Introduced by Barnes and Hut in 1986, this algorithm organises particles into a tree: a quadtree in two dimensions, or an octree in three. During force evaluation, distant groups of particles are replaced by a single effective mass at their centre of mass, collapsing many pairwise interactions into one. An opening-angle parameter $theta$ controls this approximation, trading force accuracy against speed.

The result is a reduction from $O(N^2)$ complexity to roughly $O(N log N)$. That makes Barnes–Hut a natural fit for large, collisionless systems like galaxies, where global dynamics matter more than exact short-range interactions.

== Numerical Integration and Stability Considerations

In scientific galaxy simulations, force evaluation is only half the problem. Accuracy and long term stability also depend on how the equations of motion are integrated. For each particle $i$, the total gravitational force from all other particles determines its acceleration:

#math.equation(
  $
    sum_(j)bold(F)_(i j) = m_i bold(a)_i
  $,
)

Where $bold(a)_i$ is the acceleration of the particle $i$. The acceleration is related to the particle velocity and position through time derivatives,

#math.equation(
  $
    bold(a)_i = frac(d bold(v)_i, d t) ,#h(1cm) bold(v)_i = frac(d bold(r)_i, d t)
  $,
)

For systems of many interacting particles these equations have no closed-form solution, so their evolution must be approximated numerically. Integration methods advance positions and velocities forward in discrete timesteps of size $Delta t$.

The simplest scheme is the forward Euler integrator @Kreyszig2011, which updates the positions of the particles using the current velocity:
#math.equation(
  $
    bold(r)_(i)^(n+1) = bold(r)_(i)^(n) + bold(v)_(i)^(n) Delta t
  $,
)

Here the superscript $n$ denotes the discrete timestep, with $bold(r)_(i)^(0)$ the initial position. Velocities are updated the same way using the current acceleration. Euler is cheap and easy to implement, but it does not conserve energy, as errors accumulate and the simulation drifts into unphysical states over long runs.

Astrophysical N-body codes therefore use symplectic integrators such as Verlet or leapfrog, which preserve the Hamiltonian structure of the equations of motion. These schemes conserve energy far better over long timescales, making them the standard choice for galactic dynamics @springel_2005.

In Barnes–Hut simulations, integration error and force-approximation error interact @skeletons_1994. For many galactic-scale problems, integration error actually dominates when a poor timestepping scheme is used @springel_2005. Choosing the right integrator is just as detrimental as choosing the right force model.
== GPU Acceleration of Hierarchical N-Body Methods

The computational demands of N-body simulations make them a natural target for GPUs, with their thousands of small cores executing the same operation across many data elements at once @fluke2011. The architecture maps well onto N-body force computation, where each particle's acceleration can be calculated independently @fastnbody.

GPU work is expressed as small programs, called shaders, which run on the GPU cores. Shaders were originally designed for rendering: vertex transformations, fragment colouring, texture operations. Early GPU-based scientific computing repurposed these graphics shaders for numerical tasks, encoding computation as rendering passes and storing data in textures @owens2007. Languages like CUDA and OpenCL later generalised the model, allowing general-purpose parallel computation unrelated to graphics, including N-body simulations @fastnbody @fluke2011.

Hierarchical algorithms like Barnes–Hut remain difficult to map onto GPUs, however. Tree construction and traversal introduce irregular memory access and branch divergence, both of which hurt parallel efficiency on SIMD hardware @cudabarnes @maximizeparallel. Prior work has addressed this with linearised tree representations, stackless traversal, and space-filling curves to improve memory coherence @bedorf2010 @cudabarnes. These techniques work well on native GPU APIs, but they rely on low-level memory management that has historically been unavailable in browser environments.

Since 1986, many modifications to the Barnes–Hut algorithm have been proposed, such as higher-order multipole expansions, the Fast Multipole Method (FMM), and hybrid approaches @wang_hybrid_2021 @fastalgo @fastnbody. They differ mainly in how distant interactions are approximated. Barnes–Hut persists because it is simple enough to implement well and accurate enough for most galactic-scale problems.
== General Purpose GPU Computation in the Web
Modern web applications increasingly lean on GPU acceleration for interactive, computation-heavy experiences delivered straight through the browser. With GPU access, browsers can run large-model inference, generate embeddings, process multimedia, and render complex visualisations, without requiring users to install any software or manage local hardware @terascalewebviz @realtimeclothsimulation @usta_webgpu_2024. For students, researchers, and enterprise teams working across devices, browser-based GPU access lowers friction and supports on-demand compute.

WebGL has long been the primary way to access GPU acceleration in the browser. Standardised by the Khronos Group as a JavaScript binding to OpenGL ES, it was designed for real-time graphics rendering across a wide range of devices @webgpu-spec, and it has enabled a large ecosystem of browser-based visualisation tools and interactive simulations.

The problem is that WebGL's computational model revolves around the graphics pipeline. All computation must be framed as vertex and fragment processing, with data stored in textures and results captured via framebuffers @terascalewebviz. General-purpose computation therefore requires working against the API, by reformulating numerical algorithms as sequences of rendering passes, creating non-intuitive data layouts, and requiring multiple shader invocations to emulate iteration, and no direct way to write arbitrary memory locations.

The graphics-centric model works well enough for data-parallel algorithms that map onto image-based representations, but it breaks down for anything requiring irregular memory access, dynamic data structures, or complex control flow @terascalewebviz. For Barnes–Hut specifically, WebGL cannot easily express adaptive the fundamentals needed to run it, such as timestepping, hierarchical spatial decomposition, or recursive tree traversal @cudabarnes.

For that reason, prior WebGL-based N-body implementations have prioritised visual plausibility over numerical rigour: limited particle counts, softened force models, reduced integration accuracy, or fixed spatial grids instead of adaptive trees @realitycheck. These trade-offs don't matter if the aim of a project is interactive outreach, but they are not adequate for scientific galactic simulations where long-term energy conservation and accurate force evaluation matter.

WebGPU changes this picture, as it is a modern web standard that gives browsers low-level, high-performance access to GPU hardware. Unlike WebGL, it does not force the user to construct programs in terms of a graphics pipeline, but instead through explicit compute shaders, storage buffers, and programmable pipelines @webgpu-gpuweb. The design mirrors native APIs like Vulkan @vulkan-spec, Metal @metal-spec, and Direct3D 12, giving developers fine-grained control over memory layout, synchronisation, and parallel execution @usta_webgpu_2024.

Compute shaders are the central element of WebGPU, as they are general-purpose GPU programs that run independently of the rendering pipeline. Compute shaders express parallel workloads as data processing rather than image generation, which makes them a direct fit for scientific tasks like particle simulation, spatial partitioning, and force evaluation @realtimeclothsimulation @usta_webgpu_2024. Algorithms can be structured just as they would be in a native CUDA or Metal implementation, without any graphics-pipeline workarounds @realitycheck.

WebGPU's explicit memory model and flexible buffer abstractions also make it possible to represent complex data structures, such as hierarchical trees and linearised spatial indices directly on the GPU @realtimeclothsimulation @usta_webgpu_2024. The data structures are the key to implementing Barnes–Hut in a performant manner, as the algorithm relies on dynamic tree construction and traversal at every timestep, which was entirely impractical under WebGL. With WebGPU, these patterns can run with performance close to native GPU code, subject to browser and hardware constraints @realitycheck.

However, this safety does come at a cost. WebGPU validates every operation and every command buffer submission, and that overhead compounds when many small dispatches are issued. Maczan @maczan2026 characterised this cost for LLM inference across four GPU vendors, three backends, and three browsers, measuring a true per-dispatch overhead of 24–36 µs on Vulkan and 32–71 µs on Metal, with up to 2.2$times$ variation between implementations on the same Metal backend. The takeaway from that work is that per-operation overhead, not kernel compute efficiency, is the bottleneck for dispatch-heavy GPU workloads at small batch sizes. We extend this characterisation from machine-learning inference to scientific simulation, where the dispatch pattern — a fixed pipeline of tree construction and force evaluation passes per timestep — differs fundamentally from the many small operations in a neural-network's forward pass.

== Research Gap and Contribution

GPU-accelerated Barnes–Hut solvers are well established on native platforms — CUDA implementations have been benchmarked extensively @cudabarnes @bedorf2010 @fastnbody, and native Metal solvers exist for Apple hardware @unisim. WebGPU's compute shader model has been characterised for machine-learning inference @maczan2026 and demonstrated for cloth simulation @realtimeclothsimulation and general GPU workloads @usta_webgpu_2024 @realitycheck. However, no prior work has implemented a hierarchical N-body solver in WebGPU, and no systematic benchmark exists comparing WebGPU's performance against a native GPU baseline for a scientific simulation workload of this kind. The question of whether WebGPU's abstraction layer permits a complete solver pipeline — parallel tree construction, hierarchical force evaluation, and symplectic integration — to run at scientifically relevant particle counts, and what that abstraction costs, remains unanswered.

This thesis addresses that gap. We present a complete Barnes–Hut gravitational N-body solver implemented in WebGPU, with a fully GPU-resident LBVH constructed and traversed on-device each timestep, targeting both native desktop and browser execution from a single C++/WGSL codebase. We benchmark it across four WebGPU implementations and compare against a native Metal baseline to quantify the abstraction overhead. The results establish a performance reference point for GPU-accelerated scientific computing in WebGPU and demonstrate that browser-based deployment of computationally demanding physics simulations is now practical. The following section describes the methodology in detail: the physical model, integration scheme, LBVH construction pipeline, and evaluation protocol.
