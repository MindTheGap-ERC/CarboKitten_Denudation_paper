"""Step 6 - build the database.

Validates every data/*/extractions/*.json file and writes

    database/denudation_db.csv           all valid records (verified or not)
    database/denudation_db_verified.csv  only records with verified_by set
    database/summary.csv                 counts by proxy x rate_type x timescale

Records with errors are left out and reported; fix them and re-run.

Usage:
    python literature_db/scripts/build_db.py
"""
from __future__ import annotations

from collections import Counter

from common import DATA, DATABASE, PROXIES, SCHEMA, load_json, write_csv
from validate import validate_file


def main() -> None:
    schema, pcfg = load_json(SCHEMA), load_json(PROXIES)
    proxies = pcfg["proxies"]
    files = sorted(DATA.glob("*/extractions/*.json"))
    records, n_err, seen = [], 0, {}
    for f in files:
        recs, e = validate_file(f, schema, proxies, quiet=True)
        n_err += e
        for r in recs:
            rid = r["record_id"]
            if rid in seen:
                print(f"ERROR duplicate record_id {rid} in {f.name} and {seen[rid]} - second one dropped")
                n_err += 1
                continue
            seen[rid] = f.name
            r["timescale_class"] = proxies[r["proxy"]]["timescale"]
            r["proxy_group"] = f.parent.parent.name
            records.append(r)

    cols = list(schema["fields"]) + ["timescale_class", "proxy_group", "_extraction_file"]
    write_csv(DATABASE / "denudation_db.csv", records, cols)
    verified = [r for r in records if r.get("verified_by")]
    write_csv(DATABASE / "denudation_db_verified.csv", verified, cols)

    c = Counter((r["proxy"], r["rate_type"], r["timescale_class"], bool(r.get("verified_by"))) for r in records)
    summary = {}
    for (p, rt, ts, ver), n in c.items():
        s = summary.setdefault((p, rt, ts), {"proxy": p, "rate_type": rt, "timescale_class": ts,
                                             "n_records": 0, "n_verified": 0})
        s["n_records"] += n
        s["n_verified"] += n if ver else 0
    write_csv(DATABASE / "summary.csv", sorted(summary.values(), key=lambda s: (s["timescale_class"], s["proxy"])))

    print(f"{len(files)} extraction files -> {len(records)} valid records "
          f"({len(verified)} verified), {n_err} errors")
    for s in sorted(summary.values(), key=lambda s: s["proxy"]):
        print(f"  {s['proxy']:28s} {s['rate_type']:9s} {s['timescale_class']:12s} "
              f"{s['n_records']:5d} ({s['n_verified']} verified)")
    if n_err:
        print("Run `python literature_db/scripts/validate.py --group <group>` for details.")


if __name__ == "__main__":
    main()
