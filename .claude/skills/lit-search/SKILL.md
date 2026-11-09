---
name: lit-search
description: Run or extend the reproducible literature search for a proxy group of the carbonate denudation database (OpenAlex/Crossref queries, citation chaining, keyword prefilter, batching). Use when asked to search the literature, add search terms, add a new proxy group, or refresh candidates.
---

# Literature search for the denudation database

All configuration lives in `literature_db/config/<group>.json` (see `mem.json`).
Never search ad hoc without recording it there: the search must be reproducible
for the methods section.

## Run a search

```bash
python literature_db/scripts/search.py <group>              # OpenAlex + Crossref
python literature_db/scripts/search.py <group> --seed-doi <doi>   # + references and citing works
python literature_db/scripts/prefilter.py <group>           # keyword filter + agent batches
```

Outputs in `literature_db/data/<group>/`: `candidates.csv` (deduplicated),
`search_log.csv` (date, query, hit counts), `prefilter.csv`, `batches/`.
Re-running only adds new candidates; already-screened records are never re-batched.

If the APIs are unreachable (HTTP 403 from a proxy / no network), say so and
stop: the search must then be run on a machine with internet access. Do not
replace the API search with web-search results, as that is not reproducible.

## Improve the search

- **Citation chaining** usually adds more than extra keywords: put the DOIs of
  key reviews / compilations / highly relevant papers in `search.seed_dois`.
- After the first screening round, look at included papers that were found by
  only one query (`found_by` column) — they show which terms matter — and at
  the human audit of excluded records for missed vocabulary.
- Keep `keyword_prefilter` permissive: it is a cost filter, not the screen.
  Check `prefilter.csv` for `fail` records whose title looks relevant and widen
  the term groups if any are found.

## Add a new proxy group

1. Make sure the proxy ids exist in `literature_db/schema/proxies.json`.
2. Copy `config/mem.json` → `config/<group>.json`; set `proxy_group`,
   `proxies`, `search.queries`, `keyword_prefilter`, `screening_criteria`.
3. Write `config/screening_<group>.md` following `screening_mem.md`
   (include/exclude criteria with codes, "do not exclude for" list, output columns).
4. Run the search and prefilter, then use the `lit-screen` skill.
