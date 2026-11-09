"""Step 4b - validate extraction files and normalise units.

An extraction file (data/<group>/extractions/<record-stem>.json) looks like:

    {
      "paper":   {"citation": "...", "doi": "...", "year": 1999,
                  "source_file": "pdfs/smith1999.pdf", "extracted_by": "agent:denudation-extractor"},
      "records": [ { ...fields from schema/schema.json... }, ... ],
      "skipped": [ "Table 3: rates for sandstone sites - not carbonate", ... ]
    }

Paper-level keys are copied into every record that does not set them.
Validation checks types, enums, required fields, the proxy vocabulary,
coordinate / value ranges, and converts rate_value to rate_mm_kyr.

Usage:
    python literature_db/scripts/validate.py path/to/file.json [more.json ...]
    python literature_db/scripts/validate.py --group mem        # all files of a group
Exit code 1 if any file has errors (warnings do not fail).
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

from common import PROXIES, SCHEMA, group_dir, load_json

DEFAULT_DENSITY = 2.7  # g/cm3 = t/m3

# factor to mm/kyr for length-per-time units
LENGTH_UNITS = {
    "mm/kyr": 1.0, "m/myr": 1.0, "mm/yr": 1000.0, "mm/a": 1000.0,
    "um/yr": 1.0, "cm/kyr": 10.0, "m/kyr": 1000.0, "m3/km2/yr": 1.0,
}
PY_TYPES = {"string": str, "number": (int, float), "integer": int, "boolean": bool}
PAPER_KEYS = ("citation", "doi", "year", "extracted_by", "source_database")


def to_mm_kyr(value: float, unit: str, density: float | None) -> tuple[float, list[str]]:
    u, flags = unit.lower(), []
    if u in LENGTH_UNITS:
        return value * LENGTH_UNITS[u], flags
    rho = density or DEFAULT_DENSITY
    if not density:
        flags.append(f"assumed_density_{DEFAULT_DENSITY}")
    if u == "t/km2/yr":                       # t km-2 yr-1 / (t m-3) = mm/kyr
        return value / rho, flags
    if u == "mg/cm2/yr":                      # 1 mg/cm2/yr = 10 t/km2/yr
        return value * 10.0 / rho, flags
    raise ValueError(f"unknown unit '{unit}'")


def validate_record(rec: dict, schema: dict, proxies: dict) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    fields = schema["fields"]
    for name in rec:
        if name not in fields:
            errors.append(f"unknown field '{name}'")
    for name, spec in fields.items():
        if name not in rec:
            if spec.get("required"):
                errors.append(f"missing required field '{name}'")
            continue
        v = rec[name]
        if v is None:
            if not spec.get("nullable"):
                errors.append(f"'{name}' must not be null")
            continue
        t = PY_TYPES[spec["type"]]
        if (spec["type"] != "boolean" and isinstance(v, bool)) or not isinstance(v, t):
            errors.append(f"'{name}' should be {spec['type']}, got {type(v).__name__} ({v!r})")
            continue
        if "enum" in spec and v not in spec["enum"]:
            errors.append(f"'{name}'={v!r} not in {[e for e in spec['enum'] if e is not None]}")

    if rec.get("proxy") and rec["proxy"] not in proxies:
        errors.append(f"proxy '{rec['proxy']}' not in schema/proxies.json")
    lat, lon = rec.get("latitude"), rec.get("longitude")
    if isinstance(lat, (int, float)) and not -90 <= lat <= 90:
        errors.append(f"latitude {lat} out of range")
    if isinstance(lon, (int, float)) and not -180 <= lon <= 180:
        errors.append(f"longitude {lon} out of range")
    if (lat is None) != (lon is None):
        warnings.append("only one of latitude/longitude given")
    if isinstance(rec.get("slope_deg"), (int, float)) and not 0 <= rec["slope_deg"] <= 90:
        errors.append(f"slope_deg {rec['slope_deg']} out of range 0-90")
    if isinstance(rec.get("precip_mm_yr"), (int, float)) and not 0 <= rec["precip_mm_yr"] <= 15000:
        errors.append(f"precip_mm_yr {rec['precip_mm_yr']} implausible")
    if isinstance(rec.get("temp_mean_c"), (int, float)) and not -40 <= rec["temp_mean_c"] <= 40:
        errors.append(f"temp_mean_c {rec['temp_mean_c']} implausible")
    if isinstance(rec.get("carbonate_fraction"), (int, float)) and not 0 <= rec["carbonate_fraction"] <= 1:
        errors.append("carbonate_fraction must be 0-1")
    if not rec.get("value_from_figure") and not rec.get("source_quote") and not rec.get("source_database"):
        warnings.append("no source_quote for a non-figure value")
    if rec.get("value_from_figure") and rec.get("confidence") == "high":
        warnings.append("figure-digitised value marked confidence=high")
    return errors, warnings


def normalise(rec: dict, proxies: dict) -> None:
    flags = []
    if isinstance(rec.get("rate_value"), (int, float)) and rec.get("rate_unit"):
        try:
            val, f = to_mm_kyr(rec["rate_value"], rec["rate_unit"], rec.get("rock_density_g_cm3"))
            rec["rate_mm_kyr"] = round(val, 6)
            flags += f
        except ValueError as e:
            flags.append(str(e))
    if isinstance(rec.get("rate_value"), (int, float)) and rec["rate_value"] < 0:
        flags.append("negative_rate(accretion/swelling?)")
    p = proxies.get(rec.get("proxy"), {})
    if p and rec.get("rate_type") and rec["rate_type"] != p.get("validates"):
        flags.append(f"rate_type_differs_from_proxy_default({p.get('validates')})")
    if rec.get("marine_zone") in ("intertidal", "subtidal"):
        flags.append("marine_zone_not_subaerial")
    if rec.get("proxy") == "cosmogenic_36cl":
        flags.append("check_calibration_overlap")
    if rec.get("verified_by") in (None, ""):
        flags.append("unverified")
    rec["qc_flags"] = ";".join(flags) or None


def validate_file(path: Path, schema: dict, proxies: dict, quiet: bool = False) -> tuple[list[dict], int]:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        print(f"ERROR {path}: invalid JSON ({e})")
        return [], 1
    paper = doc.get("paper", {})
    n_err, out, ids = 0, [], set()
    for i, rec in enumerate(doc.get("records", [])):
        rec = dict(rec)
        for k in PAPER_KEYS:
            if k not in rec and k in paper:
                rec[k] = paper[k]
        rec.pop("qc_flags", None)
        rec.pop("rate_mm_kyr", None)
        errs, warns = validate_record(rec, schema, proxies)
        if rec.get("record_id") in ids:
            errs.append(f"duplicate record_id {rec['record_id']}")
        ids.add(rec.get("record_id"))
        tag = f"{path.name}[{i}] {rec.get('record_id', '?')}"
        for e in errs:
            print(f"ERROR   {tag}: {e}")
        if not quiet:
            for w in warns:
                print(f"warning {tag}: {w}")
        n_err += len(errs)
        if not errs:
            normalise(rec, proxies)
            rec["_extraction_file"] = path.name
            out.append(rec)
    if not quiet:
        print(f"{path}: {len(doc.get('records', []))} records, {n_err} errors")
    return out, n_err


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", type=Path)
    ap.add_argument("--group")
    args = ap.parse_args()
    files = list(args.files)
    if args.group:
        files += sorted((group_dir(args.group) / "extractions").glob("*.json"))
    if not files:
        ap.error("give files or --group")
    schema, proxies = load_json(SCHEMA), load_json(PROXIES)["proxies"]
    total = 0
    for f in files:
        _, n = validate_file(f, schema, proxies)
        total += n
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
