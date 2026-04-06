#import "@preview/fletcher:0.5.8" as fletcher: diagram, node, edge

#let blob(pos, label, tint: white, ..args) = node(
  pos, align(center, label),
  width: 28mm,
  fill: tint.lighten(60%),
  stroke: 1pt + tint.darken(20%),
  corner-radius: 5pt,
  ..args,
)

#let lbvh-content = {
  set text(size: 7.5pt)
  let step(label) = box(
    width: 100%,
    inset: 4pt,
    fill: green.lighten(80%),
    stroke: 0.5pt + green.darken(10%),
    radius: 3pt,
    align(center, label),
  )
  stack(
    dir: ttb,
    spacing: 3pt,
    text(size: 9pt, weight: "bold")[LBVH Build],
    v(2pt),
    step[1. AABB Reduction],
    step[2. Morton Code Gen],
    step[3. Radix Sort],
    step[4. Karras Topology],
    step[5. Leaf Initialisation],
    step[6. Bottom-up Aggregation],
  )
}

#figure(
  diagram(
    spacing: 14pt,
    cell-size: (8mm, 6mm),
    edge-stroke: 1pt,
    edge-corner-radius: 5pt,
    mark-scale: 70%,

    // --- ½ Kick ---
    blob((0, 0), [*½ Kick*], tint: blue),
    edge((0, 0), (0, 1), "-"),
    node((0, 1), text(size: 8pt)[$bold(v) arrow.l bold(v) + frac(1,2) bold(a) Delta t$], stroke: none),
    edge((0, 1), (0, 2), "->"),

    // --- Drift ---
    blob((0, 2), [*Drift*], tint: blue),
    edge((0, 2), (0, 3), "-"),
    node((0, 3), text(size: 8pt)[$bold(r) arrow.l bold(r) + bold(v) Delta t$], stroke: none),
    edge((0, 3), (0, 4), "->"),

    // --- LBVH Build (single node with styled content) ---
    node(
      (0, 4),
      lbvh-content,
      fill: green.lighten(60%),
      stroke: 1pt + green.darken(20%),
      corner-radius: 5pt,
      width: 38mm,
      inset: 6pt,
    ),
    edge((0, 4), (0, 5), "->"),

    // --- BVH Force ---
    blob((0, 5), [*BVH Force*], tint: orange),
    edge((0, 5), (0, 6), "-"),
    node((0, 6), text(size: 8pt)[$bold(a) arrow.l F_"tree" \/ m$], stroke: none),
    edge((0, 6), (0, 7), "->"),

    // --- ½ Kick ---
    blob((0, 7), [*½ Kick*], tint: blue),
    edge((0, 7), (0, 8), "--"),
    node((0, 8), text(size: 8pt)[$bold(v) arrow.l bold(v) + frac(1,2) bold(a) Delta t$], stroke: none),
    edge((0, 8), (0, 9), "-->"),

    // --- Diagnostics ---
    blob((0, 9), text(size: 9pt)[_Diagnostics Readback_], tint: gray),
    node((1.5, 9), text(size: 8pt, fill: gray)[periodic], stroke: none),
  ),
  caption: [Per-timestep GPU execution pipeline for the leapfrog integrator. All passes are recorded into a single command buffer. The LBVH build comprises six sub-passes with implicit barrier synchronisation between each. Diagnostics readback occurs at configurable intervals.],
) <fig:timestep-pipeline>
