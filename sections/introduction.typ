#pagebreak()
= Literature Review

#set heading(numbering: none)

== Computational Constraints in Astrophysical Simulation
Over the past decades, progress in computational astrophysics has closely followed the performance improvements predicted by Moore’s Law, with central processing unit (CPU) speeds increasing at a near-exponential rate. Once an algorithm was implemented, substantial performance gains could often be achieved simply by running existing code on newer hardware, with minimal additional development effort. However, as single-core CPU performance has plateaued @freelunchover, this implicit scaling model has begun to break down.  As a result, continued advances in computational astrophysics increasingly depend on exploiting parallelism and adapting algorithms to emerging computing architectures @fluke2011.

One of the most significant architectural shifts has been the widespread adoption of graphics processing units (GPUs), which offer massive parallelism and high memory bandwidth. While GPUs provide the potential for orders-of-magnitude performance improvements @surveyofcomputation, realizing these gains typically requires substantial algorithmic reformulation. Algorithms that scale well on serial or modestly parallel CPUs may perform poorly on highly parallel architectures if they involve irregular control flow or memory access pattern  @cudabarnes. 
== Gravitational N-Body Simulations and Quadratic Scaling
Among the most computationally demanding problems in astrophysics are gravitational N-body simulations, which form the foundation of many studies in galactic dynamics and structure formation @galacticdynamics2nded. In such simulations, a galaxy is modeled as a system of particles (representing stars or dark matter) whose evolution is governed by their mutual gravitational interactions.

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
In Equation 1, $arrow(F)_(i j)$ denotes the gravitational force exerted on particle $i$ by particle $j$, and $G$ is the gravitational constant. The quantities $m_i$ and $m_j$ represent the masses of particles $i$ and $j$, respectively. The vectors $r_i$ and $r_j$ give the positions of particles $i$ and $j$ in three-dimensional space.

The vector difference $r_j$ − $r_i$ points from particle $i$ toward particle $j$, while $|r_j − r_i|$ denotes the Euclidean distance between the two particles. The cubic power of the distance in the denominator ensures that the magnitude of the force follows an inverse-square law while preserving the correct force direction.

The total gravitational force acting on particle $i$ is obtained by summing the pairwise force contributions from all other particles in the system, excluding self-interaction,
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

Evaluating this expression requires computing $N - 1$ pairwise interactions per particle. Consequently, a direct implementation of gravitational force evaluation scales as $O(N^2)$ per simulation timestep. This quadratic scaling rapidly becomes computationally prohibitive as the number of particles increases, particularly when long integration times are required to observe large-scale dynamical phenomena such as spiral structure or halo evolution.

== Hierarchical Approximation and the Barnes–Hut Algorithm
To address the computational limitations imposed by direct force evaluation, a variety of approximation techniques have been developed to reduce the cost of N-body simulations while preserving essential physical behavior. One of the most influential of these methods is the Barnes–Hut algorithm, which exploits the hierarchical spatial structure of particle distributions to approximate gravitational interactions @barneshut.

Originally introduced by Barnes and Hut in 1986, the algorithm organizes particles into a tree structure, typically a quadtree in two dimensions or an octree in three dimensions. During force evaluation, distant groups of particles are approximated as a single effective mass located at their center of mass, allowing subsets of the force summation to be replaced by a single interaction. An opening-angle parameter controls the accuracy of this approximation, providing a tunable tradeoff between computational efficiency and force accuracy.

By replacing many distant pairwise interactions with aggregate approximations, Barnes–Hut reduces the computational complexity of force evaluation from $O(N^2)$ to approximately $O(N log N)$. This reduction makes the algorithm particularly well-suited for simulating large, collisionless systems such as galaxies, where global dynamical behavior is often of greater interest than exact short-range interactions.

== Numerical Integration and Stability Considerations

In addition to force evaluation, the accuracy and long-term stability of N-body simulations depend critically on the choice of numerical integration scheme. Simple methods such as forward Euler integration are computationally inexpensive but suffer from poor energy conservation, leading to unphysical behavior over long time scales. As a result, symplectic integrators such as Verlet or leapfrog methods are commonly employed in astrophysical simulations due to their improved conservation properties @springel_2005.

In Barnes–Hut simulations, integration error interacts with approximation error introduced by hierarchical force evaluation @skeletons_1994. Prior studies have shown that, for many galactic-scale simulations, integration error can dominate approximation error if inappropriate time-stepping schemes are used @springel_2005. Consequently, careful selection of integration methods remains essential even when approximate force models are employed.

== GPU Acceleration of Hierarchical N-Body Methods

The computational demands of gravitational N-body simulations have made them a natural target for graphics processing units (GPUs), which provide massive data parallelism and high memory bandwidth. Modern GPUs are designed with thousands of small, efficient cores capable of executing the same operation on many data elements simultaneously @fluke2011. This architecture is particularly well-suited to the independent, particle-wise force computations inherent in N-body simulations @fastnbody.

To leverage GPUs effectively, computational tasks are expressed in terms of small programs that run on the GPU cores called shaders. Originally, shaders were designed to compute visual effects for rendering pipelines, including vertex transformations, fragment coloring, and texture operations. Early GPU-based scientific computing therefore relied on repurposing graphics shaders for numerical tasks, encoding computation as rendering operations and storing data in textures @owens2007. 

Over time, GPU programming languages such as CUDA and OpenCL have generalized this model to allow general-purpose computation, enabling the parallel execution of tasks that are not directly related to graphics, including N-body simulations @fastnbody @fluke2011.

Despite these advances, hierarchical algorithms such as Barnes–Hut present persistent challenges for GPU architectures. Tree construction and traversal introduce irregular memory access patterns and branch divergence, both of which reduce parallel efficiency on SIMD-style hardware @cudabarnes. To mitigate these issues, prior work has proposed optimizations including linearized tree representations, stackless traversal methods, and the use of space-filling curves to improve memory coherence @bedorf2010 @cudabarnes. While these techniques have enabled efficient native GPU implementations, they rely on low-level memory management and flexible data structures that have traditionally been inaccessible in browser-based computing environments.

== Web-Based Simulation and WebGL
WebGL has long served as the primary mechanism for accessing GPU acceleration within web browsers. Standardized by the Khronos Group as a JavaScript binding to OpenGL ES, WebGL was designed to provide portable and efficient access to GPU hardware for real-time graphics rendering across a wide range of devices @webgpu-spec. Its success has enabled a broad ecosystem of browser-based visualization tools, interactive simulations, and educational applications.

Although WebGL exposes programmable shaders, its computational model is fundamentally centered around the graphics rendering pipeline. All computation must be framed in terms of vertex and fragment processing stages, with data represented as textures and intermediate results captured via framebuffers @terascalewebviz. As a consequence, general-purpose computation in WebGL requires reformulating numerical algorithms as sequences of rendering passes, often involving non-intuitive data layouts and multiple shader invocations to emulate iteration and state updates.

This graphics-centric abstraction has enabled a class of data-parallel algorithms to be executed efficiently in the browser, particularly those that map naturally onto image-based representations. However, it imposes significant constraints on algorithms that require irregular memory access, dynamic data structures, or complex control flow @terascalewebviz . In the context of gravitational N-body simulations, these constraints complicate the implementation of adaptive time stepping, hierarchical spatial decomposition, and recursive tree traversal, all of which are central to physically accurate Barnes–Hut simulations @cudabarnes.

As a result, prior WebGL-based N-body implementations have typically prioritized real-time performance and visual plausibility over numerical rigor. Common approaches include limiting particle counts, employing softened or approximate force models, reducing integration accuracy, or relying on fixed spatial grids rather than fully adaptive hierarchical trees @realitycheck. While such methods are effective for interactive visualization and outreach, they are not well suited to large-scale galactic simulations where long-term energy conservation and accurate force evaluation are essential.

== WebGPU: General-Purpose GPU Programming in the Browser
WebGPU is a modern web standard designed to provide low-level, high-performance access to GPU hardware from within the browser. Unlike WebGL, which is built around a traditional graphics pipeline, WebGPU exposes explicit support for general-purpose GPU computation through compute shaders, storage buffers, and programmable pipelines @webgpu-gpuweb. Its design closely mirrors contemporary native graphics and compute APIs such as Vulkan, Metal, and Direct3D 12, enabling fine-grained control over memory layout, synchronization, and parallel execution @usta_webgpu_2024.

Central to WebGPU’s computational model is the compute shader: a general-purpose GPU program that executes independently of the rendering pipeline. Compute shaders allow developers to express parallel workloads directly in terms of data processing rather than image generation, making them well suited to scientific computing tasks such as particle simulation, spatial partitioning, and force evaluation @realtimeclothsimulation @usta_webgpu_2024. This model enables algorithms to be structured in a manner similar to native GPU implementations, without the need for graphics-specific workarounds @realitycheck.

The explicit memory model and flexible buffer abstractions provided by WebGPU make it possible to represent complex data structures, including hierarchical trees and linearized spatial indices, directly on the GPU @realtimeclothsimulation @usta_webgpu_2024. These features are particularly relevant for Barnes–Hut simulations, which rely on dynamic tree construction and traversal to achieve sub-quadratic scaling. While such patterns were previously impractical in web environments, WebGPU enables their implementation with performance characteristics comparable to native GPU code, subject to browser and hardware constraints @realitycheck.

== Positioning of This Work
While native GPU implementations of Barnes–Hut have been extensively studied @cudabarnes, prior web-based simulations have largely emphasized visualization and graphics rather than physics-accurate N-body computation @terascalewebviz. Existing WebGL approaches typically rely on approximations that simplify or bypass hierarchical force computation, limiting their scientific validity @realitycheck.

WebGPU presents a unique opportunity to bridge this gap: by enabling true general-purpose GPU computation in the browser @usta_webgpu_2024, it allows for hierarchical algorithms such as Barnes–Hut to be implemented without forcing the computation through the graphics pipeline. WebGPU provides the parallel performance necessary to handle large particle counts efficiently, making physically accurate simulations feasible in a lightweight, interactive environment.

This thesis investigates how Barnes–Hut hierarchical N-body simulations can be adapted to WebGPU, aiming to demonstrate that accurate galaxy simulations can be performed in-browser without compromising performance. By doing so, this work seeks to democratize astrophysical simulation, allowing users to explore large-scale galactic dynamics interactively without requiring high-end hardware, complex software setup, or native GPU access.
