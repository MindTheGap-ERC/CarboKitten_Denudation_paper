# Screening criteria: micro-erosion meter (MEM / TMEM)

Decide on **title + abstract** (and keywords if present). When in doubt → `unsure`, never `exclude`.

## Include (all must plausibly hold)

- **I1 Method**: rates measured with a micro-erosion meter or traversing micro-erosion meter
  (or explicitly re-reports MEM measurements, e.g. a review table — mark `I1=review`).
- **I2 Lithology**: carbonate rock (limestone, marble, dolostone, chalk, calcarenite/aeolianite).
- **I3 Quantitative**: reports, or very likely reports, a numeric lowering/erosion rate
  (abstract gives a number, or says "rates were measured/quantified").
- **I4 Natural surface**: outcrop / karren / shore platform / cave / boulder in the field.
  Building stone and gravestones go to proxy `dated_structure` instead (decision `exclude`, reason `other_proxy:dated_structure`).

## Exclude

- **E1** Not MEM/TMEM (pins, tablets, laser scanning only) → `exclude`, reason `other_proxy:<id from schema/proxies.json>`
  — these are useful later, so always give the proxy id.
- **E2** Non-carbonate rock only (granite, sandstone, basalt…).
- **E3** Laboratory-only experiments.
- **E4** No new or re-reported quantitative rates (purely methodological / instrument design papers
  *without* field rates).
- **E5** Not about rock erosion (dentistry, materials, "MEM" = memory/membrane…).

## Do NOT exclude for

- Intertidal / shore-platform setting. Keep it (`include`) but set `marine_zone_hint=intertidal`;
  intertidal rates are filtered out at analysis time, not at screening, because some papers
  report subaerial and intertidal stations side by side.
- Old papers, non-English abstracts with an English summary, conference papers, theses.

## Output per record

`id, decision (include|exclude|unsure), reason (short), criteria (e.g. "I1;I2;I3;I4"), marine_zone_hint (subaerial|supratidal_spray|intertidal|cave|unknown), screener`
