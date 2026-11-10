# Screening criteria: terrestrial carbonate / karst denudation rates (any method)

Scope: studies that **measure or derive a denudation, erosion, surface-lowering or
dissolution rate of carbonate rock (or a carbonate-dominated catchment) on land**.
English-language papers only. Decide on title + abstract (+ journal, year).
When in doubt → `unsure`, never `exclude`.

## Include (all must plausibly hold)

- **I1 Carbonate**: limestone, dolostone/dolomite, marble, chalk, calcarenite, or a
  carbonate-dominated catchment / karst area.
- **I2 Terrestrial setting**: subaerial bare rock, rock under soil/vegetation,
  hillslopes, karst plateaus, catchments, river basins on land.
  Papers that compare coastal and inland sites → include if there are inland sites
  (`marine_zone_hint=subaerial`, mention "mixed coastal/inland" in reason).
- **I3 Quantitative rate**: reports (or very likely reports) a numeric rate of
  denudation / erosion / lowering / dissolution from **field data**, by ANY method,
  for example: MEM/TMEM, limestone or rock tablets, profile gauges, erosion pins,
  catchment solute flux / hydrochemical denudation, sediment yield, cosmogenic
  nuclides (36Cl, 10Be, 26Al), erratic-boulder pedestals, dated surfaces,
  residual-soil mass balance, uplifted dated terraces (subaerial lowering).
- **I3r Reviews / compilations** that tabulate such rates also count (reason starts with `review:`).

## Exclude

- **E1 Marine or cave setting only**: intertidal, shore platforms, tidal/marine notches,
  spray (supratidal) zone, subtidal, sea cliffs; rates measured only inside caves.
  Exclude ONLY when the abstract makes clear that all sites are coastal/marine/cave.
  Coastal studies often also report inland rates in the main text: a coastal TITLE with
  no abstract, or an abstract that does not rule out inland sites → `unsure`
  (reason starts with `coastal-title:`).
- **E2 Non-carbonate** rock only (granite, sandstone, basalt, gypsum, salt...).
- **E3 Laboratory-only** dissolution kinetics or experiments without field rates.
- **E4 No rate**: qualitative geomorphology, karst morphology/mapping, hydrogeology,
  speleogenesis, landform description, paleoclimate/speleothem records, papers on
  method design without field rates.
- **E5 Soil erosion only**: soil loss / RUSLE / runoff plots / rocky desertification
  studies that quantify **soil** loss, not bedrock or catchment denudation.
- **E6 Not about rock denudation**: engineering, materials, cement, petroleum
  reservoirs, CO2 storage, marine carbonate chemistry, biology, etc.
- **E7 Built stone only**: buildings, monuments, gravestones (reason `other_proxy:dated_structure`;
  kept for possible later use).
- **E8 Not English** (full text clearly in another language, e.g. title and journal
  are non-English; an English abstract alone does not exclude).
- **E9 Model only**: denudation from a model without new or compiled measured rates.
- **E10 Mass wasting**: rockfall, landslides, cliff collapse (gravitational, not denudation of the surface).
- **E11 Biological-control studies**: the focus is how vegetation, lichens, fungi, cyanobacteria,
  enzymes or plant communities change dissolution/erosion (treatment comparisons), rather than
  representative denudation rates of a site or region.
- **E12 Fluvial channel incision**: bedrock river incision / channel erosion / coarse sediment transport.
- **E13 Soil or regolith erosion**: erosion pins or plots in residual soil / regolith, not rock or catchment denudation.

## Notes from the human calibration (MEM round)

- Catchment / basin solute denudation (e.g. "autogenic and allogenic denudation", "erosion rate of a karst basin") → **include** (`proxy_hint=solute_flux`).
- In-situ 36Cl / cosmogenic denudation of carbonates, and comments/replies discussing them → **include** (`proxy_hint=cosmogenic_36cl`). These may overlap with the empirical-model calibration data; that is handled later, not at screening.
- Reviews of karst denudation rates (e.g. Gunn 2013, methods reviews) → **include** as `review:`.
- General textbook chapters on "denudation and weathering" without a rate table → exclude (E4).

## Do NOT exclude for

- Old papers, conference abstracts, theses, book chapters (they may hold data).
- A method other than MEM — every method in I3 is in scope.
- Missing abstract with a relevant title → `unsure`.

## Output per record

Columns (header exactly):
`id,decision,reason,criteria,proxy_hint,marine_zone_hint,screener`

- `decision`: include | exclude | unsure
- `reason`: ≤ 15 words
- `criteria`: codes met/violated, e.g. `I1;I2;I3` or `E1`
- `proxy_hint`: the most likely proxy id(s) from `literature_db/schema/proxies.json`,
  `;`-separated (e.g. `limestone_tablet;mem`), or `unknown`
- `marine_zone_hint`: subaerial | soil_covered | supratidal_spray | intertidal | cave | unknown
- `screener`: `agent:lit-screener`
