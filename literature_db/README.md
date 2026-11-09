# Literature database of carbonate denudation rates

A semi-automated pipeline to compile **independent** measurements of carbonate
denudation for validating the three CarboKitten denudation methods
(chemical dissolution, physical erosion, empirical ³⁶Cl regression).

Each record is tagged with the model component it can test (`rate_type`:
chemical / physical / total) and the timescale it integrates over, so that
proxies are compared only with what they can actually validate.

## Pipeline

| Step | Tool | Who | Output (`data/<group>/`) |
|---|---|---|---|
| 0. Seed from compilations | `scripts/ingest_octopus.py` · skill `octopus-seed` | script + you (GIS carbonate fraction) | `octopus/extractions/octopus_seed.json` |
| 1. Search | `scripts/search.py` · skill `lit-search` | script | `candidates.csv`, `search_log.csv` |
| 2a. Keyword prefilter | `scripts/prefilter.py` | script | `prefilter.csv`, `batches/*.jsonl` |
| 2b. Abstract screening | agent `lit-screener` · skill `lit-screen` | agents in parallel | `decisions/*.csv` |
| 2c. Merge + audit | `scripts/merge_screening.py` | script, **you review** `screening_audit.csv` | `screening_decisions.csv`, `included.csv` |
| 3. Full text | — | **you** (paywalled PDFs) | `pdfs/` |
| 4. Extraction | agent `denudation-extractor` · skill `extract-denudation` | agents in parallel | `extractions/*.json` |
| 5. Verification | — | **you**: check each record against `source_location`/`source_quote`, set `verified_by` | edited `extractions/*.json` |
| 6. Build | `scripts/build_db.py` | script | `database/denudation_db*.csv`, `database/summary.csv` |

Skills live in `.claude/skills/`, agents in `.claude/agents/` (repo root), so
Claude Code picks them up when started in this repository. Typical prompts:

- "Run the lit-search skill for the mem group."
- "Use the lit-screen skill to screen the open mem batches."
- "Extract `data/mem/pdfs/smith1999.pdf` with the denudation-extractor agent."
- "Run denudation-extractor agents on all PDFs in `data/mem/pdfs` that have no extraction yet, 4 at a time."

## Files

```
literature_db/
  schema/schema.json        field definitions (the database columns)
  schema/proxies.json       proxy vocabulary -> rate_type, timescale class
  schema/examples/          SYNTHETIC extraction example (format only)
  config/<group>.json       queries, keyword prefilter, batch size per proxy group
  config/screening_<group>.md  inclusion / exclusion criteria
  config/octopus_mapping.json  OCTOPUS column -> schema field
  scripts/                  pipeline scripts (Python >= 3.9, needs `requests`)
  data/<group>/             working files per proxy group (PDFs are git-ignored)
  database/                 built database
```

## Database fields (summary)

Full definitions in `schema/schema.json`.

- **Denudation rate**: `rate_value`, `rate_unit`, `rate_uncertainty`, auto-converted `rate_mm_kyr`, `rate_type`, `n_measurements`
- **Proxy**: `proxy`, `method_detail`, `integration_time_yr`, `measurement_period` (+ `timescale_class` in the build)
- **Geography**: `geographic_setting` (inland / coastal / island), `marine_zone` (subaerial / spray / intertidal / cave …), coordinates, elevation, `distance_to_coast_km`
- **Climate**: `precip_mm_yr`, `temp_mean_c` with `*_source` (reported vs gridded)
- **Slope**: `slope_deg`, `slope_scale` (point surface / hillslope / catchment mean), `slope_source`
- **Lithology**: `lithology`, `lithology_detail`, `carbonate_fraction`, `rock_density_g_cm3`
- **Literature source**: `citation`, `doi`, `year`, `source_location`, `source_quote`, `source_database`
- **QC**: `value_from_figure`, `confidence`, `extracted_by`, `verified_by`, `notes`, `qc_flags`

## Things to keep in mind

- **Circularity**: ³⁶Cl data used to fit the empirical regression must be tagged
  `calibration_set` in `notes` and held out of validation.
- **MEM coastal data**: many MEM studies are on intertidal shore platforms;
  they are kept but flagged (`marine_zone`, `qc_flags`) and should be excluded
  from subaerial validation.
- **OCTOPUS** rates are quartz-based catchment averages: only carbonate-dominated
  basins (carbonate fraction from a GIS overlay) are imported.
- **Gridded climate / DEM values** (WorldClim, CHELSA, SRTM) can fill gaps
  later, but must be marked `precip_source: gridded_dataset` etc. so they are
  never confused with reported values.
- **Network**: the search needs api.openalex.org and api.crossref.org.
  Run it on a machine with internet access if the environment blocks them.

## Quick start (MEM pilot)

```bash
pip install requests
python literature_db/scripts/search.py mem
python literature_db/scripts/prefilter.py mem
# screen with the lit-screener agent (lit-screen skill), then
python literature_db/scripts/merge_screening.py mem
# review data/mem/screening_audit.csv, put PDFs in data/mem/pdfs/, extract, verify
python literature_db/scripts/build_db.py
```
