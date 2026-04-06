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

### Fix Existing Figures — REGENERATE ALL WITH NEW DATA

- [ ] **fig_n_scaling_plummer.png** — log-log ms/step vs N (new data)
- [ ] **fig_crossover.png** — dual-axis: runtime + energy drift, direct vs tree (new framing: speed vs accuracy)
- [ ] **fig_web_native.png** — native vs Chrome ms/step (new data)
- [ ] **New: per-pass stacked bar chart** — LBVH breakdown at each N
- [ ] **New: cross-backend grouped bar chart** — wgpu vs Dawn vs Chrome vs Safari

---

## 2. PAPER TEXT EDITS

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
