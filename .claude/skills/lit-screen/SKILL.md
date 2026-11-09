---
name: lit-screen
description: Screen literature candidates (title + abstract) for the carbonate denudation database against a proxy group's inclusion criteria, using lit-screener agents on prepared batches, then merge decisions and prepare the human audit. Use when asked to screen papers, run the screening round, or continue screening.
---

# Screening round

Inputs (from the `lit-search` skill): `literature_db/data/<group>/batches/batch_NNN.jsonl`
and criteria `literature_db/config/screening_<group>.md`.

## Steps

1. List batches without a decision file:
   `batches/batch_NNN.jsonl` that has no `decisions/batch_NNN.csv`.
2. Screen them with the **lit-screener** agent, one batch per agent, several
   in parallel (≈ 4 at a time is a good default). Prompt each with:
   > Screen `literature_db/data/<group>/batches/batch_NNN.jsonl` using the
   > criteria in `literature_db/config/screening_<group>.md`. Write
   > `literature_db/data/<group>/decisions/batch_NNN.csv`.
   If agents are not available, screen the batch yourself following
   `.claude/agents/lit-screener.md` exactly.
3. Merge and summarise:
   ```bash
   python literature_db/scripts/merge_screening.py <group>
   ```
4. Tell the user:
   - the PRISMA-style counts printed by the script,
   - that `data/<group>/screening_audit.csv` (all `unsure` + ~10 % random
     `exclude`) needs their review; their corrections go in
     `data/<group>/screening_overrides.csv` (`id,decision,reason,reviewer`),
     then re-run the merge,
   - papers excluded as `other_proxy:<id>` — they are candidates for other
     proxy groups later,
   - `data/<group>/included.csv` is the reading list: open-access links are
     in `oa_url`; paywalled PDFs must be downloaded by the user into
     `data/<group>/pdfs/` and the file name entered in the `pdf_file` column.

## Quality check

If the human audit finds wrongly excluded papers, report the false-exclusion
rate (wrong / audited) and tighten `screening_<group>.md` before screening
more batches. Never delete decision files; overrides are the audit trail.
