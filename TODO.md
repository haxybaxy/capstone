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

### Still Needs Doing — Content Additions

- [ ] **BVH theory section**: Add a conceptual introduction to BVH trees BEFORE the implementation section. Include a diagram and pseudocode. Supervisor: "introduce the algorithm and theory behind it before this section"
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
