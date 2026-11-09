"""Seed the database from an OCTOPUS export (catchment-averaged cosmogenic rates).

OCTOPUS (Codilean et al. 2018, ESSD; v2 2022) compiles catchment-averaged
10Be/26Al denudation rates measured in river-sand QUARTZ. Pure carbonate
catchments yield little quartz, so OCTOPUS records only test carbonate
denudation where the carbonate fraction of the catchment is known and high.
OCTOPUS itself does not (to our knowledge) carry a carbonate fraction: compute
it per basin in GIS (e.g. basin polygons x GLiM lithology map) and pass it with
--lithology-csv.

Input: the attribute table of the OCTOPUS layer as .csv or .dbf (the .dbf
inside the downloaded shapefile zip works directly).

Usage:
    python literature_db/scripts/ingest_octopus.py octopus_crn.dbf --inspect
    python literature_db/scripts/ingest_octopus.py octopus_crn.dbf \\
        --lithology-csv basins_carbonate.csv --min-carbonate 0.5

--lithology-csv needs columns: sample_id, carbonate_fraction (0-1).

Outputs:
    data/octopus/octopus_all.csv                  every mapped OCTOPUS record
    data/octopus/extractions/octopus_seed.json    records passing the carbonate
                                                  filter, in extraction format
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import struct
from pathlib import Path

from common import CONFIG, group_dir, load_json, read_csv, write_csv


def read_dbf(path: Path) -> list[dict]:
    """Minimal dBase III reader (enough for shapefile attribute tables)."""
    with open(path, "rb") as f:
        _, _, _, _, n_rec, hdr_len, rec_len = struct.unpack("<BBBBIHH20x", f.read(32))
        fields = []
        while True:
            b = f.read(32)
            if b[0] == 0x0D:
                break
            name = b[:11].split(b"\x00")[0].decode("latin-1")
            fields.append((name, chr(b[11]), b[16]))
        f.seek(hdr_len)
        rows = []
        for _ in range(n_rec):
            rec = f.read(rec_len)
            if not rec or rec[0:1] == b"*":       # deleted
                continue
            pos, row = 1, {}
            for name, typ, size in fields:
                raw = rec[pos:pos + size].decode("utf-8", errors="replace").strip()
                pos += size
                row[name] = raw
            rows.append(row)
    return rows


def read_table(path: Path) -> list[dict]:
    if path.suffix.lower() == ".dbf":
        return read_dbf(path)
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def num(x):
    if x is None:
        return None
    x = str(x).strip()
    if x in ("", "NA", "NaN", "nan", "-9999", "-999", "None"):
        return None
    try:
        return float(x)
    except ValueError:
        return None


def resolve(columns: list[str], mapping: dict) -> dict:
    upper = {c.upper(): c for c in columns}
    return {field: next((upper[c.upper()] for c in cands if c.upper() in upper), None)
            for field, cands in mapping.items()}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("table", type=Path)
    ap.add_argument("--inspect", action="store_true", help="show columns and mapping, write nothing")
    ap.add_argument("--lithology-csv", type=Path)
    ap.add_argument("--min-carbonate", type=float, default=0.5)
    ap.add_argument("--mapping", type=Path, default=CONFIG / "octopus_mapping.json")
    args = ap.parse_args()

    cfg = load_json(args.mapping)
    rows = read_table(args.table)
    if not rows:
        raise SystemExit("empty table")
    colmap = resolve(list(rows[0]), cfg["columns"])

    if args.inspect:
        print(f"{len(rows)} rows; columns:\n  " + ", ".join(rows[0]))
        print("\nmapping (schema field <- column):")
        for k, v in colmap.items():
            print(f"  {k:20s} <- {v or '-- UNMAPPED --'}")
        print("\nfirst row:", json.dumps(rows[0], ensure_ascii=False)[:800])
        return
    for need in ("sample_id", "rate_value"):
        if not colmap[need]:
            raise SystemExit(f"Required column for '{need}' not found; run with --inspect and edit {args.mapping}")

    carb = {}
    if args.lithology_csv:
        carb = {r["sample_id"]: num(r["carbonate_fraction"]) for r in read_csv(args.lithology_csv)}

    def g(row, field):
        c = colmap.get(field)
        return row.get(c) if c else None

    all_rows, records = [], []
    n_noyear = 0
    for row in rows:
        sid = str(g(row, "sample_id")).strip()
        rate = num(g(row, "rate_value"))
        cf = carb.get(sid, num(g(row, "carbonate_fraction")))
        citation = (g(row, "citation") or "").strip() or None
        year = num(g(row, "year"))
        if year is None and citation:
            m = re.search(r"(19|20)\d{2}", citation)
            year = float(m.group(0)) if m else None
        all_rows.append({"sample_id": sid, "rate_mm_kyr": rate, "carbonate_fraction": cf,
                         "latitude": num(g(row, "latitude")), "longitude": num(g(row, "longitude")),
                         "citation": citation, "year": year})
        if rate is None or cf is None or cf < args.min_carbonate:
            continue
        if year is None:
            n_noyear += 1
            continue
        slope = num(g(row, "slope_deg"))
        precip, temp = num(g(row, "precip_mm_yr")), num(g(row, "temp_mean_c"))
        doi = (g(row, "doi") or "").strip().lower() or None
        records.append({
            "record_id": "octopus_" + re.sub(r"[^A-Za-z0-9_-]", "_", sid),
            "rate_value": rate, "rate_uncertainty": num(g(row, "rate_uncertainty")),
            "rate_uncertainty_type": "1sd" if num(g(row, "rate_uncertainty")) is not None else None,
            "rate_unit": cfg["rate_unit"], "rate_type": "total", "n_measurements": 1,
            "proxy": cfg["proxy"], "method_detail": "Catchment-averaged in-situ cosmogenic nuclide in river quartz (from OCTOPUS)",
            "integration_time_yr": num(g(row, "integration_time_yr")), "measurement_period": None,
            "site_name": (g(row, "site_name") or None), "country": (g(row, "country") or None),
            "latitude": num(g(row, "latitude")), "longitude": num(g(row, "longitude")),
            "coord_precision": "exact", "elevation_m": num(g(row, "elevation_m")),
            "geographic_setting": "unknown", "marine_zone": "subaerial", "distance_to_coast_km": None,
            "precip_mm_yr": precip, "precip_source": "reported" if precip is not None else None,
            "temp_mean_c": temp, "temp_source": "reported" if temp is not None else None,
            "slope_deg": slope, "slope_scale": "catchment_mean" if slope is not None else None,
            "slope_source": "dem_derived" if slope is not None else None,
            "lithology": "carbonate_dominated_mixed" if cf < 0.95 else "mixed_carbonate",
            "lithology_detail": f"carbonate fraction {cf:.2f} (from {'lithology overlay' if sid in carb else 'OCTOPUS'})",
            "carbonate_fraction": cf, "rock_density_g_cm3": None,
            "citation": citation or "unknown (see OCTOPUS)", "doi": doi, "year": int(year),
            "source_location": f"OCTOPUS sample {sid}", "source_quote": None,
            "source_database": cfg["source_database"],
            "value_from_figure": False, "confidence": "medium",
            "extracted_by": "script:ingest_octopus", "verified_by": None,
            "notes": "Uncertainty as given in OCTOPUS (assumed 1 sigma). Quartz-derived rate; check that quartz sources are representative of the carbonate part of the basin.",
        })

    d = group_dir("octopus")
    write_csv(d / "octopus_all.csv", all_rows)
    (d / "extractions").mkdir(exist_ok=True)
    out = {"paper": {"citation": "OCTOPUS compilation", "source_database": cfg["source_database"],
                     "extracted_by": "script:ingest_octopus"},
           "records": records,
           "skipped": [f"{n_noyear} carbonate records without a parseable publication year"] if n_noyear else []}
    (d / "extractions" / "octopus_seed.json").write_text(json.dumps(out, indent=1, ensure_ascii=False), encoding="utf-8")
    n_cf = sum(r["carbonate_fraction"] is not None for r in all_rows)
    print(f"{len(rows)} OCTOPUS rows; {n_cf} with carbonate fraction; "
          f"{len(records)} with carbonate fraction >= {args.min_carbonate} -> {d / 'extractions' / 'octopus_seed.json'}")
    if n_cf == 0:
        print("No carbonate fractions: supply --lithology-csv (basin x GLiM overlay) to select carbonate basins.")


if __name__ == "__main__":
    main()
