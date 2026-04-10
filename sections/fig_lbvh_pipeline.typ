#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#let step(pos, title, desc, tint: white, ..args) = node(
  pos,
  align(center)[
    #set par(leading: 0.4em)
    #text(weight: "bold", size: 9pt)[#title] \
    #text(size: 7pt, fill: gray.darken(30%))[#desc]
  ],
  width: 42mm,
  fill: tint.lighten(60%),
  stroke: 1pt + tint.darken(20%),
  corner-radius: 5pt,
  ..args,
)

#let barrier(row) = {
  // dashed horizontal line with "barrier" label
  edge((-0.6, row), (0.6, row), stroke: (dash: "dashed", paint: orange.darken(20%), thickness: 0.7pt))
  node((0.8, row), text(size: 6pt, fill: orange.darken(20%), style: "italic")[barrier], stroke: none)
}

#figure(
  diagram(
    spacing: 6pt,
    cell-size: (8mm, 6mm),
    edge-stroke: 1pt,
    edge-corner-radius: 5pt,
    mark-scale: 70%,

    step((0, 0), [Global AABB Reduction], [parallel min/max over all positions], tint: green),
    edge((0, 0), (0, 2), "->"),
    barrier(1),

    step((0, 2), [Morton Code Generation], [30-bit Z-order from normalised coords], tint: blue),
    edge((0, 2), (0, 4), "->"),
    barrier(3),

    step((0, 4), [Radix Sort], [O(N) GPU-friendly fixed-width sort], tint: yellow),
    edge((0, 4), (0, 6), "->"),
    barrier(5),

    step((0, 6), [Karras Topology], [internal node parent/child from sorted keys], tint: green),
    edge((0, 6), (0, 8), "->"),
    barrier(7),

    step((0, 8), [Leaf Initialisation], [leaf bounding boxes from particle positions], tint: blue),
    edge((0, 8), (0, 10), "->"),
    barrier(9),

    step((0, 10), [Bottom-up Aggregation], [propagate AABBs + COM to root], tint: purple),
    edge((0, 10), (0, 12), "->"),

    node(
      (0, 12),
      align(center, text(size: 9pt, weight: "bold")[Ready for Traversal]),
      width: 38mm,
      fill: gray.lighten(70%),
      stroke: 1pt + gray.darken(20%),
      corner-radius: 5pt,
    ),
  ),
  caption: [LBVH construction pipeline. Six compute dispatches build the tree entirely on-device. Dashed lines represent implicit storage-buffer barriers between passes. The atomic-counter aggregation in pass 6 ensures correct bottom-up propagation of bounding boxes and centres of mass.],
) <fig:lbvh-pipeline>
