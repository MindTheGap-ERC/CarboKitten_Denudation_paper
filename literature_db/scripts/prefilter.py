"""Step 2a - keyword prefilter and batching for agent screening.

Reads data/<group>/candidates.csv, applies the keyword rules in
config/<group>.json, writes data/<group>/prefilter.csv (every record with
pass/fail and the matched terms), and splits the passing records that have not
been screened yet into data/<group>/batches/batch_NNN.jsonl for the
lit-screener agent.

Usage:
    python literature_db/scripts/prefilter.py mem
"""
from __future__ import annotations

import argparse
import json

from common import group_dir, load_config, read_csv, write_csv


def match(text: str, cfg: dict) -> tuple[bool, str]:
    text = " " + text.lower() + " "
    hits = []
    for group in cfg["require_all_groups"]:
        g = [t for t in group if t.lower() in text]
        if not g:
            return False, "missing group: " + "/".join(group[:3]) + "..."
        hits += g
    bad = [t for t in cfg.get("exclude", []) if t.lower() in text]
    if bad:
        return False, "excluded term: " + ";".join(bad)
    return True, ";".join(dict.fromkeys(hits))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("group")
    args = ap.parse_args()
    cfg = load_config(args.group)
    d = group_dir(args.group)

    rows = read_csv(d / "candidates.csv")
    if not rows:
        raise SystemExit(f"No candidates in {d / 'candidates.csv'} - run search.py first.")

    for r in rows:
        if not (r.get("abstract") or "").strip():
            # title only: keep it if the title hits, otherwise still send to
            # the agent - abstracts are missing for many older papers
            ok, why = match(r["title"], cfg["keyword_prefilter"])
            r["prefilter"] = "pass"
            r["prefilter_note"] = "no_abstract" + ("" if ok else "; title_miss")
        else:
            ok, why = match(f"{r['title']} {r['abstract']}", cfg["keyword_prefilter"])
            r["prefilter"] = "pass" if ok else "fail"
            r["prefilter_note"] = why
    write_csv(d / "prefilter.csv", rows)

    screened = {r["id"] for r in read_csv(d / "screening_decisions.csv")}
    todo = [r for r in rows if r["prefilter"] == "pass" and r["id"] not in screened]

    bdir = d / "batches"
    bdir.mkdir(exist_ok=True)
    existing = sorted(bdir.glob("batch_*.jsonl"))
    queued = set()
    for p in existing:
        with open(p, encoding="utf-8") as f:
            queued |= {json.loads(line)["id"] for line in f if line.strip()}
    todo = [r for r in todo if r["id"] not in queued]

    n0, size = len(existing), int(cfg.get("batch_size", 25))
    keep = ["id", "doi", "title", "year", "authors", "journal", "abstract", "prefilter_note"]
    for i in range(0, len(todo), size):
        p = bdir / f"batch_{n0 + i // size + 1:03d}.jsonl"
        with open(p, "w", encoding="utf-8") as f:
            for r in todo[i:i + size]:
                f.write(json.dumps({k: r.get(k, "") for k in keep}, ensure_ascii=False) + "\n")

    n_pass = sum(r["prefilter"] == "pass" for r in rows)
    print(f"{len(rows)} candidates, {n_pass} pass prefilter, "
          f"{len(todo)} newly batched into {-(-len(todo) // size)} batch(es) in {bdir}")


if __name__ == "__main__":
    main()
