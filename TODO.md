# Capstone TODO

Everything you need to do, organized by priority. Check off as you go.

---

## 1. DATA / EXPERIMENTS (must run before writing)

### Investigate Suspicious Data

- [ ] **Fig 7**: The "NlogN" reference line has the wrong slope — need to regenerate with new data

### New Experiments (Cross-Backend, inspired by Maczan 2026)

- [x] **Group 6 — Four-way backend comparison**: wgpu-native, Dawn, Chrome, Safari at N={1000, 10000, 100000}
- [x] **Group 7 — Per-pass LBVH timing**: 7 sub-passes at N={1000, 5000, 10000, 50000, 100000}
- [ ] **WASM overhead decomposition**: Break down browser overhead into GPU kernel vs API vs asyncify
- [x] **Metal baseline (UniSim)**: Matched params at N={1000, 5000, 10000, 50000, 100000}
- [x] **N-scaling re-run**: Proper protocol (50 warmup, 100 measured) with new optimized code

### Fix Existing Figures — REGENERATE ALL WITH NEW DATA

- [ ] **fig_n_scaling_plummer.png** — log-log ms/step vs N (new data)
- [ ] **fig_crossover.png** — dual-axis: runtime + energy drift, direct vs tree (new framing: speed vs accuracy)
- [ ] **fig_web_native.png** — native vs Chrome ms/step (new data)
- [ ] **New: per-pass stacked bar chart** — LBVH breakdown at each N
- [ ] **New: cross-backend grouped bar chart** — wgpu vs Dawn vs Chrome vs Safari

---

## 2. PAPER TEXT EDITS

### Done — Content Additions

- [x] Explained what a Plummer sphere is
- [x] Rewrote LBVH construction with radix sort, elaborated Karras delta function
- [x] Added explicit M and center of mass formulas
- [x] Proper symbol introductions for leapfrog equations
- [x] Made all quantities vectorial (bold vectors)
- [x] Explained Emscripten flags (-sASYNCIFY, -sALLOW_MEMORY_GROWTH)
- [x] SoA vs AoS resolved (packed layout is optimal — force shader never reads particle mass)
- [x] Re-introduced RQ concept at start of results
- [x] Added benchmarking protocol section (warmup, mean±std, CI, CV)
- [x] Added Group 6 and Group 7 experiment descriptions
- [x] Added Maczan citation in lit review, results, and eval protocol
- [x] Added Force Traversal Optimisation section (4 optimisations + 2 rejected + combined table)
- [x] Added GPU synchronisation details (wgpuDevicePoll vs buffer-map fence vs emscripten_sleep)
- [x] Updated research questions to match new focus (scalability, abstraction overhead, browser feasibility)
- [x] Updated evaluation protocol (Metal baseline, not Euler/CPU)
- [x] Updated experimental platform table (16GB, Chrome/Safari versions, Dawn, UniSim)
- [x] Added UniSim citation (original + fork)
- [x] Added Maczan to lit review
- [x] Added supervisor's Morton code Z-curve figure with thesis citation
- [x] Wrote the abstract
- [x] Results section fully rewritten with new data

### Done — Content Removals

- [x] Removed internal variable names (cpuPositions\_ etc)
- [x] Removed CLI flags from body text
- [x] Removed "stage-map-readback" vague line
- [x] Removed verbose logging/dependency descriptions
- [x] Cut "Validation and Robustness" section
- [x] Cut "Reproducibility and Traceability" to one sentence
- [x] Cut "Comparative Positioning" from methodology
- [x] Cut Group 2d (Euler vs Leapfrog comparison)
- [x] Cut CPU tree and direct rows from old performance table
- [x] Removed seed robustness as a limitation
- [x] Removed all CPU octree references from methodology
- [x] Removed Euler integrator section
- [x] Removed CPU execution mode / mirror arrays
- [x] Removed system architecture figure (referenced CPU paths)

### Done — Structural

- [x] Merged sub-sections into flowing prose
- [x] Added intro paragraphs after section headings
- [x] Removed GPT-ism parenthetical headings
- [x] Rewrote limitations as flowing paragraphs
- [x] Tightened "Integrated Assessment" → "Summary of Findings"
- [x] Compressed rendering section
- [x] Compressed shader enumeration
- [x] Compressed two-body results
- [x] Merged softening + momentum into one subsection
- [x] Rewrote discussion to interpret rather than restate

### Done — Diagrams

- [x] Timestep pipeline diagram (fletcher, fig_pipeline.typ)
- [x] LBVH pipeline diagram (fletcher, fig_lbvh_pipeline.typ)
- [x] Morton code Z-curve figure (from supervisor's thesis)

### Still TODO — Content

- [ ] **BVH theory section**: Conceptual introduction to BVH trees BEFORE implementation section, with pseudocode
- [ ] **Add units to ALL quantities in results**: Define unit system explicitly
- [ ] **Fix energy drift equation rendering**: Check PDF for badly rendered equations
- [ ] **Rewrite conclusions**: Still references old RQ1/RQ2/RQ3 names and old data
- [ ] **Rewrite discussion**: Needs to match new data and new RQs
- [ ] **Update future work**: Some items are now done (radix sort, bind group caching)

### Still TODO — Supervisor's Specific Requests

- [ ] **"eliminates licensing and privacy concerns"**: Find and remove if still present
- [ ] **"Data Ethics, Security, and Integrity" section**: Remove if still present
- [ ] **"Build system" line in table**: Remove from platform table if still present
- [ ] **"octree-traversal fallback shader"**: Removed from code, verify removed from all text
- [ ] **Reference supervisor's PhD manuscript style**: Mimic his Morton/tree explanation approach

---

## 3. CODE CHANGES (simulation)

- [x] Removed CPU octree code
- [x] Implemented radix sort (replacing bitonic sort)
- [x] Implemented bind group caching
- [x] Implemented precomputed opening radius
- [x] Implemented compact traversal nodes
- [x] Workgroup size tuning (128)
- [x] Morton-ordered particle access
- [x] Forked and fixed UniSim for 100K benchmarking
- [ ] **Explore indirect dispatch**: Could reduce CPU-side overhead
- [ ] **Explore bundle encoders**: Pre-record compute bundles for reuse

---

## 4. FINAL PASS (after everything above)

- [ ] Compile with `typst compile main.typ` — zero warnings
- [ ] Read every section transition — does it flow?
- [ ] Check every figure/table is referenced in text
- [ ] Check every technology/method mentioned has a citation
- [ ] Verify no remaining CLI flags in body text
- [ ] Verify no remaining GPT-isms
- [ ] Uncomment abstract in main.typ
- [ ] Regenerate all figures with new data
- [ ] Uncomment figure references in results.typ once figures exist
