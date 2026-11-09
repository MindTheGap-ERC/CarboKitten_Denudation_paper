"""Step 2b - merge agent screening decisions.

Collects data/<group>/decisions/batch_NNN.csv written by the lit-screener
agent into data/<group>/screening_decisions.csv, creates an audit sample of
excluded records for human review, and prints PRISMA-style counts.

A human can override any decision by adding a row to
data/<group>/screening_overrides.csv with columns: id, decision, reason, reviewer.

Usage:
    python literature_db/scripts/merge_screening.py mem [--audit-fraction 0.1]
"""
from __future__ import annotations

import argparse
import random
from collections import Counter

from common import group_dir, read_csv, write_csv

VALID = {"include", "exclude", "unsure"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("group")
    ap.add_argument("--audit-fraction", type=float, default=0.1)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    d = group_dir(args.group)

    decisions: dict[str, dict] = {}
    for p in sorted((d / "decisions").glob("batch_*.csv")):
        for r in read_csv(p):
            r["decision"] = (r.get("decision") or "").strip().lower()
            if r["decision"] not in VALID:
                print(f"WARNING {p.name}: invalid decision '{r['decision']}' for {r.get('id')} -> unsure")
                r["decision"] = "unsure"
            r["batch"] = p.stem
            decisions[r["id"]] = r

    for o in read_csv(d / "screening_overrides.csv"):
        if o["id"] in decisions:
            decisions[o["id"]].update(decision=o["decision"], reason=f"OVERRIDE ({o.get('reviewer', '')}): {o.get('reason', '')}")

    rows = list(decisions.values())
    write_csv(d / "screening_decisions.csv", rows)

    # human audit: all 'unsure' + a random sample of 'exclude'
    excl = [r for r in rows if r["decision"] == "exclude"]
    random.Random(args.seed).shuffle(excl)
    n_audit = max(1, round(len(excl) * args.audit_fraction)) if excl else 0
    meta = {r["id"]: r for r in read_csv(d / "candidates.csv")}
    audit = [r for r in rows if r["decision"] == "unsure"] + excl[:n_audit]
    audit = [{"id": r["id"], "decision": r["decision"], "reason": r.get("reason", ""),
              "year": meta.get(r["id"], {}).get("year", ""), "title": meta.get(r["id"], {}).get("title", ""),
              "doi": meta.get(r["id"], {}).get("doi", ""), "your_decision": "", "your_note": ""} for r in audit]
    write_csv(d / "screening_audit.csv", audit)

    # include list = the reading list for full text
    inc = [{**meta.get(r["id"], {}), **r} for r in rows if r["decision"] == "include"]
    write_csv(d / "included.csv", inc,
              ["id", "doi", "title", "year", "authors", "journal", "oa_url", "reason", "marine_zone_hint", "pdf_file"])

    pre = read_csv(d / "prefilter.csv")
    c = Counter(r["decision"] for r in rows)
    print("PRISMA-style counts")
    print(f"  records identified (unique)   {len(meta)}")
    print(f"  excluded by keyword prefilter {sum(r['prefilter'] == 'fail' for r in pre)}")
    print(f"  screened by agent             {len(rows)}")
    for k in ("include", "unsure", "exclude"):
        print(f"    {k:8s} {c.get(k, 0)}")
    other = Counter((r["reason"].split(":", 1)[1].split() or ["?"])[0].strip(";,")
                    for r in rows if (r.get("reason") or "").startswith("other_proxy:"))
    if other:
        print("  excluded as other proxies (re-usable later):", dict(other))
    print(f"\nHuman audit list ({len(audit)} rows): {d / 'screening_audit.csv'}")
    print(f"Reading list ({len(inc)} rows): {d / 'included.csv'}")


if __name__ == "__main__":
    main()
