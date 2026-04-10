#pagebreak()
= Literature Review
Simulating galactic dynamics means resolving gravitational interactions among large numbers of particles while keeping the numerics stable over long integration times. Historically, that has demanded serious computational resources and specialised software, putting high-fidelity N-body work out of reach for lightweight or widely accessible platforms. The relevant literature therefore spans four areas that converge on the gap this thesis addresses: N-body algorithms, numerical integration, GPU-accelerated computing, and browser-based GPU computation.
#set heading(numbering: none)

== Computational Constraints in Astrophysical Simulation
For decades, progress in computational astrophysics rode the performance curve predicted by Moore’s Law. Once an algorithm was implemented, running it on newer hardware often delivered large gains for free. That era is over. Single-core CPU speeds have plateaued @freelunchover, and continued progress now depends on exploiting parallelism and adapting algorithms to new computing architectures @fluke2011.

The most important shift has been the rise of graphics processing units (GPUs), which offer massive parallelism and high memory bandwidth. GPUs can deliver order-of-magnitude speedups @surveyofcomputation, but capturing those gains usually requires rethinking the algorithm itself. Code that scales well on serial or modestly parallel CPUs may perform poorly on highly parallel hardware if it involves irregular control flow or memory access patterns @cudabarnes.
== Gravitational N-Body Simulations and Quadratic Scaling
Gravitational N-body simulations are among the most computationally demanding problems in astrophysics, and they underpin much of the research on galactic dynamics and structure formation @galacticdynamics2nded. A galaxy is modelled as a system of particles — representing stars or dark matter — whose evolution is governed by mutual gravitational interactions @zwart_high-performance_2007.

According to Newton’s law of universal gravitation, the force exerted on a particle of mass $m_(i)$ by another particle of mass $m_(j)$ is given by

#math.equation(
  $
    arrow(F)_(i j) =
    G frac(
      m_i m_j (arrow(r)_j - arrow(r)_i)
      ,
      |arrow(r)_j - arrow(r)_i|^3
    )
  $,
)

Where $arrow(F)_(i j)$ denotes the gravitational force exerted on particle $i$ by particle $j$, and $G$ is the gravitational constant. The quantities $m_i$ and $m_j$ represent the masses of particles $i$ and $j$, respectively. The vectors $arrow(r)_i$ and $arrow(r)_j$ give the positions of particles $i$ and $j$ in three-dimensional space.

The vector difference $arrow(r)_j$ − $arrow(r)_i$ points from particle $i$ toward particle $j$, while $|arrow(r)_j − arrow(r)_i|$ denotes the Euclidean distance between the two particles. The cubic power of the distance in the denominator ensures that the magnitude of the force follows an inverse-square law while preserving the correct force direction.

To obtain the total force on particle $i$, we sum contributions from every other particle, excluding self-interaction:
#math.equation(
  $
    arrow(F)_i =
    sum_(j != i)^N
    G frac(
      m_i m_j (arrow(r)_j - arrow(r)_i),
      |arrow(r)_j - arrow(r)_i|^3
    )
  $,
)

Each particle requires $N - 1$ pairwise interactions, so a direct implementation scales as $O(N^2)$ per timestep. The cost becomes prohibitive quickly — especially when long integration times are needed to observe phenomena like spiral structure or halo evolution @zwart_high-performance_2007.

== Hierarchical Approximation and the Barnes–Hut Algorithm
A variety of approximation techniques have been developed to cut the cost of N-body force evaluation without sacrificing essential physics. The most influential is the Barnes–Hut algorithm, which exploits the hierarchical spatial structure of particle distributions @barneshut.

Introduced by Barnes and Hut in 1986, the algorithm organises particles into a tree — a quadtree in two dimensions, an octree in three. During force evaluation, distant groups of particles are replaced by a single effective mass at their centre of mass, collapsing many pairwise interactions into one. An opening-angle parameter $theta$ controls this approximation, trading force accuracy against speed.

The result is a reduction from $O(N^2)$ to roughly $O(N log N)$. That makes Barnes–Hut a natural fit for large, collisionless systems like galaxies, where global dynamics matter more than exact short-range interactions.

== Numerical Integration and Stability Considerations

Force evaluation is only half the problem. Accuracy and long-term stability also hinge on how the equations of motion are integrated. For each particle $i$, the total gravitational force from all other particles determines its acceleration:

#math.equation(
  $
    sum_(j)arrow(F)_(i j) = m_i arrow(a)_i
  $,
)

Where $arrow(a)_i$ is the acceleration of the particle $i$. The acceleration is related to the particle velocity and position through time derivatives,

#math.equation(
  $
    arrow(a)_i = frac(d arrow(v)_i, d t) ,#h(1cm) arrow(v)_i = frac(d arrow(r)_i, d t)
  $,
)

For systems of many interacting particles these equations have no closed-form solution, so their evolution must be approximated numerically. Integration methods advance positions and velocities forward in discrete timesteps of size $Delta t$.

The simplest scheme is forward Euler @Kreyszig2011, which updates positions using the current velocity:
#math.equation(
  $
    arrow(r)_(i)^(n+1) = arrow(r)_(i)^(n) + arrow(v)_(i)^(n) Delta t
  $,
)

Here the superscript $n$ denotes the discrete timestep, with $arrow(r)_(i)^(0)$ the initial position. Velocities are updated the same way using the current acceleration. Euler is cheap and easy to implement, but it does not conserve energy — errors accumulate and the simulation drifts into unphysical states over long runs.

Astrophysical N-body codes therefore use symplectic integrators such as Verlet or leapfrog, which preserve the Hamiltonian structure of the equations of motion. These schemes conserve energy far better over long timescales, making them the standard choice for galactic dynamics @springel_2005.

In Barnes–Hut simulations, integration error and force-approximation error interact @skeletons_1994. For many galactic-scale problems, integration error actually dominates when a poor timestepping scheme is used @springel_2005. Choosing the right integrator therefore matters just as much as choosing the right force model.
== GPU Acceleration of Hierarchical N-Body Methods

The computational demands of N-body simulations make them a natural target for GPUs, with their thousands of small cores executing the same operation across many data elements at once @fluke2011. The architecture maps well onto N-body force computation, where each particle's acceleration can be calculated independently @fastnbody.

GPU work is expressed as small programs — shaders — that run on the GPU cores. Shaders were originally designed for rendering: vertex transformations, fragment colouring, texture operations. Early GPU-based scientific computing repurposed these graphics shaders for numerical tasks, encoding computation as rendering passes and storing data in textures @owens2007. Languages like CUDA and OpenCL later generalised the model, allowing general-purpose parallel computation unrelated to graphics — including N-body simulations @fastnbody @fluke2011.

Hierarchical algorithms like Barnes–Hut remain difficult to map onto GPUs, however. Tree construction and traversal introduce irregular memory access and branch divergence, both of which hurt parallel efficiency on SIMD hardware @cudabarnes @maximizeparallel. Prior work has addressed this with linearised tree representations, stackless traversal, and space-filling curves to improve memory coherence @bedorf2010 @cudabarnes. These techniques work well on native GPU APIs, but they rely on low-level memory management that has historically been unavailable in browser environments.

Since 1986, many modifications to Barnes–Hut have been proposed — higher-order multipole expansions, the Fast Multipole Method (FMM), and hybrid approaches @wang_hybrid_2021 @fastalgo @fastnbody. They differ mainly in how distant interactions are approximated. Barnes–Hut persists because it is simple enough to implement well and accurate enough for most galactic-scale problems.
== General Purpose GPU Computation in the Web
Modern web applications increasingly lean on GPU acceleration for interactive, computation-heavy experiences delivered straight through the browser. With GPU access, browsers can run large-model inference, generate embeddings, process multimedia, and render complex visualisations — all without requiring users to install software or manage local hardware @terascalewebviz @realtimeclothsimulation @usta_webgpu_2024. For students, researchers, and enterprise teams working across devices, browser-based GPU access lowers friction and supports on-demand compute. 

WebGL has long been the primary way to access GPU acceleration in the browser. Standardised by the Khronos Group as a JavaScript binding to OpenGL ES, it was designed for real-time graphics rendering across a wide range of devices @webgpu-spec, and it has enabled a large ecosystem of browser-based visualisation tools and interactive simulations.

The problem is that WebGL's computational model revolves around the graphics pipeline. All computation must be framed as vertex and fragment processing, with data stored in textures and results captured via framebuffers @terascalewebviz. General-purpose computation therefore requires reformulating numerical algorithms as sequences of rendering passes — non-intuitive data layouts, multiple shader invocations to emulate iteration, and no direct way to write arbitrary memory locations.

The graphics-centric model works well enough for data-parallel algorithms that map onto image-based representations, but it breaks down for anything requiring irregular memory access, dynamic data structures, or complex control flow @terascalewebviz. For Barnes–Hut specifically, WebGL cannot easily express adaptive timestepping, hierarchical spatial decomposition, or recursive tree traversal @cudabarnes.

Prior WebGL-based N-body implementations have therefore prioritised visual plausibility over numerical rigour: limited particle counts, softened force models, reduced integration accuracy, or fixed spatial grids instead of adaptive trees @realitycheck. These trade-offs work for interactive outreach, but they are not adequate for galactic simulations where long-term energy conservation and accurate force evaluation matter.

WebGPU changes this picture. It is a modern web standard that gives browsers low-level, high-performance access to GPU hardware — not through a graphics pipeline, but through explicit compute shaders, storage buffers, and programmable pipelines @webgpu-gpuweb. The design mirrors native APIs like Vulkan @vulkan-spec, Metal @metal-spec, and Direct3D 12, giving developers fine-grained control over memory layout, synchronisation, and parallel execution @usta_webgpu_2024.

Central to WebGPU is the compute shader: a general-purpose GPU program that runs independently of the rendering pipeline. Compute shaders express parallel workloads as data processing rather than image generation, which makes them a direct fit for scientific tasks like particle simulation, spatial partitioning, and force evaluation @realtimeclothsimulation @usta_webgpu_2024. Algorithms can be structured much as they would be in a native CUDA or Metal implementation, without graphics-pipeline workarounds @realitycheck.

WebGPU's explicit memory model and flexible buffer abstractions also make it possible to represent complex data structures — hierarchical trees, linearised spatial indices — directly on the GPU @realtimeclothsimulation @usta_webgpu_2024. For Barnes–Hut, this is the key enabler: the algorithm relies on dynamic tree construction and traversal every timestep, patterns that were impractical under WebGL. With WebGPU, these patterns can run with performance close to native GPU code, subject to browser and hardware constraints @realitycheck.

There is a cost to this safety, however. WebGPU validates every operation and every command buffer submission, and that overhead compounds when many small dispatches are issued. Maczan @maczan2026 characterised this cost for LLM inference across four GPU vendors, three backends, and three browsers, measuring a true per-dispatch overhead of 24–36 µs on Vulkan and 32–71 µs on Metal — with up to 2.2$times$ variation between implementations on the same Metal backend. The takeaway from that work is that per-operation overhead, not kernel compute efficiency, is the bottleneck for dispatch-heavy GPU workloads at small batch sizes. We extend this characterisation from machine-learning inference to scientific simulation, where the dispatch pattern — a fixed pipeline of tree construction and force evaluation passes per timestep — differs fundamentally from the many small operations in a neural-network forward pass.
