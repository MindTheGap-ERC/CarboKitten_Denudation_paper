---
name: octopus-seed
description: Seed the carbonate denudation database from the OCTOPUS compilation of catchment-averaged cosmogenic (10Be/26Al) denudation rates, selecting carbonate-dominated basins. Use when asked to import OCTOPUS or another existing compilation.
---

# Seeding from OCTOPUS

OCTOPUS compiles catchment-averaged cosmogenic denudation rates from river-sand
**quartz** (Codilean et al. 2018, ESSD; v2 2022). Download the cosmogenic
layer from the OCTOPUS website (octopusdata.org) as a shapefile or CSV. This
step is manual: the download needs a browser, and this cloud session's network
may block the host.

## Caveats to tell the user

- Quartz-based rates only describe carbonate denudation where the basin is
  mostly carbonate and the quartz comes from that carbonate (chert, sand
  impurities) or is otherwise representative. Treat these as a **total-rate,
  geomorphic-timescale** check with `confidence: medium`.
- OCTOPUS records are **not** ³⁶Cl, so they are independent of the empirical
  ³⁶Cl regression. Any ³⁶Cl compilation (e.g. the one behind the regression)
  must be tagged `calibration_set` in `notes` and held out of validation.
- Basin carbonate fraction is not (to our knowledge) an OCTOPUS attribute: it
  has to be computed in GIS (OCTOPUS basin polygons × GLiM lithology classes
  `sc` carbonate sedimentary rocks), exported as `sample_id,carbonate_fraction`.

## Steps

1. Inspect the export and fix the column mapping if needed:
   ```bash
   python literature_db/scripts/ingest_octopus.py <export.dbf|csv> --inspect
   ```
   Edit candidate column names in `literature_db/config/octopus_mapping.json`
   for any field reported `UNMAPPED` (rate and sample id are required).
2. Ingest with the carbonate fractions:
   ```bash
   python literature_db/scripts/ingest_octopus.py <export> --lithology-csv <basins_carbonate.csv> --min-carbonate 0.5
   ```
3. Validate and build:
   ```bash
   python literature_db/scripts/validate.py --group octopus
   python literature_db/scripts/build_db.py
   ```
4. Seed papers: the original publications of the selected basins are a good
   list of `seed_dois` for citation chaining in other proxy groups.

The same pattern (mapping JSON + ingest script writing an extraction-format
JSON with `source_database` set) applies to other compilations.
