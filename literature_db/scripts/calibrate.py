"""Calibrate agent screening against human labels.

    make:  python literature_db/scripts/calibrate.py make <group> <labels.csv> [--skip-ids id1,id2]
           labels.csv needs columns id, your_decision (yes/no/include/exclude);
           records are looked up in data/*/candidates.csv. Writes
           data/<group>/calibration/batch_cNN.jsonl (labels hidden from the agent).
    score: python literature_db/scripts/calibrate.py score <group>
           compares data/<group>/calibration/decisions/batch_cNN.csv with the labels and
           prints agreement, a confusion table and every disagreement.

Agent 'unsure' counts as 'include' for recall (it goes to human review).
"""
from __future__ import annotations

import argparse
import json
from collections import Counter

from common import DATA, group_dir, read_csv, write_csv

YES = {"yes", "include", "y", "1"}
NO = {"no", "exclude", "n", "0"}
KEEP = ["id", "doi", "title", "year", "authors", "journal", "abstract"]


def make(group: str, labels_path: str, skip: set[str], size: int) -> None:
    cand = {}
    for p in DATA.glob("*/candidates.csv"):
        for r in read_csv(p):
            cand.setdefault(r["id"], r)
    labels = []
    for r in read_csv(__import__("pathlib").Path(labels_path)):
        lab = (r.get("your_decision") or "").strip().lower()
        if r["id"] in skip or not lab or r["id"] not in cand:
            continue
        labels.append({"id": r["id"], "label": "include" if lab in YES else "exclude" if lab in NO else lab,
                       "note": r.get("your_note", ""), "title": cand[r["id"]]["title"]})
    d = group_dir(group) / "calibration"
    (d / "decisions").mkdir(parents=True, exist_ok=True)
    write_csv(d / "labels.csv", labels)
    for i in range(0, len(labels), size):
        with open(d / f"batch_c{i // size + 1:02d}.jsonl", "w", encoding="utf-8") as f:
            for lab in labels[i:i + size]:
                f.write(json.dumps({k: cand[lab["id"]].get(k, "") for k in KEEP}, ensure_ascii=False) + "\n")
    print(f"{len(labels)} labelled records -> {-(-len(labels) // size)} calibration batch(es) in {d}")


def score(group: str) -> None:
    d = group_dir(group) / "calibration"
    labels = {r["id"]: r for r in read_csv(d / "labels.csv")}
    dec = {}
    for p in sorted((d / "decisions").glob("*.csv")):
        dec.update({r["id"]: r for r in read_csv(p)})
    pairs = [(labels[i]["label"], dec[i]["decision"].strip().lower(), i) for i in labels if i in dec]
    conf = Counter((h, a) for h, a, _ in pairs)
    n = len(pairs)
    hum_inc = [p for p in pairs if p[0] == "include"]
    hum_exc = [p for p in pairs if p[0] == "exclude"]
    recall = sum(a in ("include", "unsure") for _, a, _ in hum_inc) / max(1, len(hum_inc))
    strict = sum(a == "include" for _, a, _ in hum_inc) / max(1, len(hum_inc))
    spec = sum(a == "exclude" for _, a, _ in hum_exc) / max(1, len(hum_exc))
    print(f"{n} records scored ({len(labels) - n} without agent decision)")
    print("confusion (human -> agent):", dict(conf))
    print(f"recall (agent include|unsure on human-include): {recall:.0%}   strict include: {strict:.0%}")
    print(f"correct exclusion of human-exclude:              {spec:.0%}")
    print(f"agent-unsure share:                              {sum(a == 'unsure' for _, a, _ in pairs) / max(1, n):.0%}")
    print("\nDisagreements:")
    rows = []
    for h, a, i in pairs:
        if (h == "include" and a == "exclude") or (h == "exclude" and a != "exclude"):
            print(f"  human={h:7s} agent={a:7s} | {labels[i]['title'][:70]} | agent: {dec[i].get('reason', '')[:60]}")
            rows.append({"id": i, "human": h, "agent": a, "title": labels[i]["title"],
                         "human_note": labels[i].get("note", ""), "agent_reason": dec[i].get("reason", "")})
    write_csv(d / "disagreements.csv", rows)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("action", choices=["make", "score"])
    ap.add_argument("group")
    ap.add_argument("labels", nargs="?")
    ap.add_argument("--skip-ids", default="")
    ap.add_argument("--batch-size", type=int, default=20)
    a = ap.parse_args()
    if a.action == "make":
        make(a.group, a.labels, set(filter(None, a.skip_ids.split(","))), a.batch_size)
    else:
        score(a.group)


if __name__ == "__main__":
    main()
