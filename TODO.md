# Capstone TODO

Everything you need to do, organized by priority. Check off as you go.

---

## 1. DATA / EXPERIMENTS (must run before writing)

### Investigate Suspicious Data
- [ ] **Fig 11**: Verlet 32-bit shows no energy drift — something is wrong. Re-run and check the data/plot
- [ ] **Table 10**: Values jump from ~0.1 to ~1 to ~1e-10. Investigate whether this is a bug or a precision artifact
- [ ] **Table 5**: Missing values — figure out why and either fill them or explain the gap
- [ ] **Fig 7**: The "NlogN" reference line has the wrong slope. Supervisor thinks it's actually N^2. Fix the label/line

### New Experiments (Cross-Backend, inspired by Maczan 2026)
- [ ] **Group 6 — Four-way backend comparison**: Run Plummer sphere at N={1000, 10000, 100000} on:
  - [ ] wgpu-native/Metal (your current default)
  - [ ] Dawn/Metal (you confirmed this builds)
  - [ ] Chrome/Metal (Emscripten → browser)
  - [ ] Safari/Metal (Emscripten → browser)
  - Use frozen-state protocol: 50 warmup steps, 100 measured steps, positions held constant
  - Report mean ± std, 95% CI, CV for each
- [ ] **Group 7 — Per-pass LBVH timing**: Instrument each of the 7 LBVH passes individually at N={1000, 5000, 10000, 50000, 100000}. Export per-pass ms (AABB reduction, Morton codes, radix sort, Karras topology, leaf init, bottom-up aggregation, force eval)
- [ ] **WASM overhead decomposition**: At N=10000, break down browser overhead into GPU kernel time vs WebGPU API overhead vs asyncify event-loop cost vs WASM compilation overhead
- [ ] **Ablation study (single-variable changes)**:
  - [ ] Leapfrog 32-bit GPU vs Leapfrog 32-bit CPU (same precision — fixes Table 8)
  - [ ] Radix sort vs bitonic sort (if old code still exists)
  - [ ] Bind groups cached vs recreated each frame (measure before/after)

### Fix Timing Methodology
- [ ] Re-run key configurations with proper protocol: 50 warmup steps (no measurement), then 100 measured steps, report mean ± std, 95% CI, CV
- [ ] Consider frozen-state runs (no position updates) for pure overhead measurement

### Fix Existing Figures
- [ ] **Fig 5a,b**: Plot in negative color, make pixels much larger (currently invisible)
- [ ] **Fig 6**: Add time units to axes (even natural units have a unit: $t_0 = \sqrt{r_0^3 / (GM_0)}$)
- [ ] **Fig 7**: Fix the NlogN reference line label (likely N^2)
- [ ] **Fig 10**: Missing entirely — create it
- [ ] **Fig 11**: Fix after investigating the data
- [ ] **Page 20**: Rotated 90 degrees — fix the orientation

---

## 2. PAPER TEXT EDITS (can do in parallel with experiments)

### Already Done (by Claude)
- [x] Merged sub-sections into flowing prose (Physical Model, Time Integration, Evaluation Protocol)
- [x] Added intro paragraphs after every section heading (no more title→subtitle without text)
- [x] Removed GPT-ism parenthetical headings: "(iterative, no recursion)", "(fallback paths)", "(pinned dependency versions)"
- [x] Rewrote limitations as flowing paragraphs instead of bullet list
- [x] Tightened "Integrated Assessment" → brief "Summary of Findings"
- [x] Defined natural unit system ($G=1$, $M_0$, $r_0$, $t_0$)
- [x] Explained what a Plummer sphere is
- [x] Rewrote LBVH construction with radix sort, sub-items, elaborated Karras delta function
- [x] Added explicit $M = \sum m_i$ and center of mass formula
- [x] Proper symbol introductions for leapfrog equations ($n$, $\mathbf{r}$, $\mathbf{v}$, $\mathbf{a}$)
- [x] Made all quantities vectorial (bold vectors)
- [x] Fixed Euler notation inconsistency
- [x] Explained Emscripten flags (-sASYNCIFY, -sALLOW_MEMORY_GROWTH)
- [x] Added SoA vs AoS discussion
- [x] Re-introduced RQ concept at start of results
- [x] Removed internal variable names (cpuPositions_ etc)
- [x] Removed CLI flags from body text
- [x] Removed "stage-map-readback" vague line
- [x] Removed verbose logging/dependency descriptions
- [x] Clarified CPU/GPU dual-path (separate run mode, not simultaneous)
- [x] Fixed "consistent timing" wording (6.9–11.2 is NOT consistent)
- [x] All figures/tables now referenced in text (was 10 unreferenced, now 0)
- [x] Added citations: wgpu-native, Dawn, Vulkan, Metal, Emscripten, Maczan
- [x] Added benchmarking protocol section
- [x] Added Group 6 and Group 7 experiment descriptions
- [x] Cut "Validation and Robustness" section (circular — restated what experiments show)
- [x] Cut "Reproducibility and Traceability" to one sentence
- [x] Cut "Comparative Positioning" from methodology (moved to discussion only)
- [x] Compressed CPU octree subsection to one sentence
- [x] Compressed rendering section (fixed too-little/too-much pattern)
- [x] Compressed BVH data layout (cut indexing formulas)
- [x] Compressed shader enumeration (count + split, not every name)
- [x] Cut micro-optimisation details from GPU traversal (inverseSqrt, self-interaction guard)
- [x] Cut Group 2d (Euler vs Leapfrog) from experiment matrix — confounded by precision
- [x] Compressed Group 2e/2f descriptions
- [x] Cut CPU tree and direct rows from performance summary table
- [x] Compressed two-body results to one paragraph + trimmed table (3 rows not 5)
- [x] Compressed Plummer energy drift prose (cut raw numbers from prose)
- [x] Merged softening + momentum into one "Softening and Momentum" subsection (2 sentences)
- [x] Merged seed robustness + practical limits into one subsection
- [x] Cut browser timing implementation details (emscripten_sleep(0), JS-to-WASM context switching)
- [x] Rewrote discussion to interpret rather than restate results
- [x] Fixed stale "bitonic sort" reference in discussion

### Still Needs Doing — Content Additions
- [ ] **BVH theory section**: Add a conceptual introduction to BVH trees BEFORE the implementation section. Include a diagram and pseudocode. Supervisor: "introduce the algorithm and theory behind it before this section"
- [ ] **Quantized LBVH**: Supervisor mentioned "quantized version of LBVH you could try to improve perf" — at minimum discuss it even if not implemented
- [ ] **Reference supervisor's PhD manuscript**: Look at his Morton/tree/sort explanation style in section 11.2, consider using his figure with attribution
- [ ] **Add units to ALL quantities in results**: Even natural units need definition (e.g., $K = 123112 \, t_0^{-2}$ where $t_0 = \sqrt{r_0^3/(GM_0)}$)
- [ ] **Fix energy drift equation rendering**: Noted as "badly rendered" in both experiments and results sections
- [ ] **Write the abstract**: Still a placeholder

### Still Needs Doing — Content Removals
- [ ] **"eliminates licensing and privacy concerns"**: Find and remove (supervisor: "idk what you mean")
- [ ] **"Data Ethics, Security, and Integrity" section**: Remove if it exists anywhere
- [ ] **"Build system" line in table**: Remove from platform table
- [ ] **Remove duplicate dependency pinning mentions**: Check for any remaining duplicates

### Still Needs Doing — Structural
- [ ] **Reduce remaining subtitle count**: Audit methodology for any remaining unnecessary `===` sub-headings
- [ ] **Add transition text**: Check every section boundary — end of each section should bridge to the next
- [ ] **Audit for the too-little/too-much pattern**: Supervisor example: "rendered as instanced billboard quads" (too vague) immediately followed by "@builtin(instance_index)" (too specific). Find and fix throughout
- [ ] **"octree-traversal fallback shader" — what is this?**: Supervisor asked. Explain or remove the term

### Still Needs Doing — Tables & Figures
- [ ] **Table 8**: Fix to compare same-precision configs (Verlet 32-bit GPU vs Euler 32-bit GPU, not mixed precision)
- [ ] **"RQ" in Table 4**: Make sure the abbreviation is defined before its first appearance in tables
- [ ] **Add new results tables** for Group 6 (cross-backend) and Group 7 (per-pass LBVH) once experiments are done
- [ ] **Create stacked bar chart** for per-pass LBVH timing breakdown

### Still Needs Doing — Discussion Section
- [ ] **Reference Maczan's dispatch overhead findings**: Compare your ~4.3ms browser overhead to his per-dispatch costs (24-36µs Vulkan, 32-71µs Metal)
- [ ] **Discuss Metal-specific behavior**: Maczan found fusion helps Vulkan but NOT Metal. Discuss implications for your M2 results
- [ ] **Comparison with existing work**: Supervisor wishes you could "run some of these yourself on current hardware." The cross-backend comparison partially addresses this

---

## 3. CODE CHANGES (simulation)

- [ ] **Explore indirect dispatch**: Could reduce CPU-side overhead for LBVH pipeline
- [ ] **Explore bundle encoders**: Pre-record render/compute bundles for reuse
- [ ] **Add frozen-state mode**: Flag to skip position updates but still run full pipeline (for overhead measurement)
- [ ] **Per-pass timing export**: Make sure each LBVH sub-pass timing is exported to CSV or logged separately
- [ ] **Research asyncify alternatives**: Supervisor is personally interested in reducing the ~4.3ms event-loop overhead. Report findings even if no solution found

---

## 4. FINAL PASS (after everything above)

- [ ] Compile with `typst compile main.typ` — zero warnings
- [ ] Read every section transition aloud — does it flow?
- [ ] Check every figure/table is referenced in text
- [ ] Check every technology/method mentioned has a citation
- [ ] Verify no remaining CLI flags in body text (delay to appendix)
- [ ] Verify no remaining GPT-isms: parenthetical headings, "blazingly fast", trailing summaries
- [ ] Write the abstract (last — it summarizes the final paper)
