---
name: extract-denudation
description: Extract carbonate denudation / surface-lowering rates and site attributes (geography, precipitation, temperature, slope, lithology, proxy, source) from a scientific paper into the literature_db JSON schema. Use when asked to extract data from a paper/PDF for the denudation database, or when acting as the denudation-extractor agent.
---

# Extract denudation rates from a paper

Goal: turn one paper into `literature_db/data/<group>/extractions/<stem>.json`,
one record per **reported rate value per site/station/catchment**, with every
number traceable to its place in the paper.

## Before you start

1. Read `literature_db/schema/schema.json` (field definitions, enums) and
   `literature_db/schema/proxies.json` (allowed `proxy` ids and their default
   `rate_type`).
2. Read the worked example `literature_db/schema/examples/example_extraction.json`
   (synthetic — shows format only, the numbers are not real).
3. Get the full text: a PDF in `literature_db/data/<group>/pdfs/` (Read it with
   the `pages` parameter, ≤20 pages per call), or a text/HTML file. If you only
   have the abstract, extract only what the abstract states, set
   `confidence: "low"` and say `abstract only` in `notes`.

## Rules (non-negotiable)

- **Never invent or infer a number.** If precipitation, temperature, slope,
  coordinates or uncertainty are not stated in the paper, use `null`. Gridded
  climate/DEM values are filled later by a separate step, not by you.
- **Record units as reported** in `rate_value` + `rate_unit`. Do not convert;
  `validate.py` converts to `rate_mm_kyr`. If the unit is not in the enum,
  stop and report it in `skipped` rather than converting by hand.
- **Quote the source.** `source_location` (e.g. `Table 2, row "Site B3"`;
  `p. 214, para 2`) and `source_quote` (≤300 chars, verbatim, the sentence or
  table row holding the number). For values read off a plot:
  `value_from_figure: true`, `source_quote: null`, `confidence: "low"`.
- **One record per value.** If a table gives per-station rates *and* a site
  mean, extract the per-station values; add the mean only if stations are
  not given. Never mix both for the same site.
- **Re-reported data.** If the paper cites rates from an earlier study (a
  review table), extract them only if the original is not accessible, set
  `notes: "re-reported from <original citation>"`, and cite the original in
  `citation`/`doi` with `source_database` = this paper's citation.
- Set `verified_by: null` and `extracted_by: "agent:denudation-extractor"`
  (or your initials if a human). Only a human sets `verified_by`.

## Field guidance

| Field | How to decide |
|---|---|
| `proxy` | Measurement method, from `proxies.json`. MEM vs TMEM: TMEM if a traversing instrument is used. |
| `rate_type` | Use the proxy's `validates` default. Change only with a reason in `notes`. |
| `geographic_setting` | `coastal` if the site is described as coastal / within sea-spray reach / on a sea cliff or shore; `island` for small islands and exposed platforms (e.g. Bahamas, Bermuda); `inland` if clearly away from the coast; else `unknown`. |
| `marine_zone` | `intertidal` for shore platforms between tide marks, `supratidal_spray` for spray zone, `subaerial` for normal exposed rock, `cave` inside caves, `soil_covered` for rock under soil. **Critical for MEM**: many MEM studies are on intertidal shore platforms — their rates are marine erosion, not subaerial denudation. |
| `slope_deg` | For MEM: the dip of the measured rock surface if stated (horizontal = 0, vertical = 90). Convert % with atan(p/100) and say so in `notes`. `slope_scale`: `point_surface` for MEM. |
| `integration_time_yr` / `measurement_period` | MEM: years between first and last reading; e.g. 1978–1996 → 18 and `"1978-1996"`. |
| `n_measurements` | Number of MEM points / stations averaged into the value, if stated. |
| `lithology` | From the site description; put formation name, purity, facies in `lithology_detail`. |
| `latitude/longitude` | Decimal degrees. Convert DMS. If only a place name is given, `null` + `coord_precision: null` (do not geocode). If read from a location map: `approx_from_map`. |
| `confidence` | `high`: number + site attributes explicit in text/table. `medium`: number explicit, some attributes inferred from context. `low`: from figure, abstract only, or ambiguous. |

## Output format

```json
{
  "paper":   {"citation": "Author & Author 1999", "doi": "10.xxxx/yyyy", "year": 1999,
              "source_file": "pdfs/<file>.pdf", "extracted_by": "agent:denudation-extractor"},
  "records": [ { "record_id": "mem_author1999_1", ... all schema fields ... } ],
  "skipped": [ "Table 4: sandstone stations - not carbonate", "Fig. 7: rates by aspect, not per site" ]
}
```

- `record_id`: `<proxy>_<firstauthorsurname><year>_<n>`, lower case ASCII.
- File name: `<firstauthorsurname><year>[a|b].json` in the group's `extractions/` folder.
- Every schema field must be present (use `null` where allowed). Do not add
  fields that are not in the schema; put extra information in `notes`.
- List everything you deliberately did not extract in `skipped` with a reason,
  so the reviewer can see coverage.

## Finish

Run and fix until there are no errors:

```bash
python literature_db/scripts/validate.py literature_db/data/<group>/extractions/<file>.json
```

Then report: number of records, number skipped, and any value you were unsure about.
