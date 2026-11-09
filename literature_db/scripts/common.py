"""Shared paths and helpers for the literature database pipeline."""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # literature_db/
SCHEMA = ROOT / "schema" / "schema.json"
PROXIES = ROOT / "schema" / "proxies.json"
CONFIG = ROOT / "config"
DATA = ROOT / "data"
DATABASE = ROOT / "database"


def load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_config(group: str) -> dict:
    path = CONFIG / f"{group}.json"
    if not path.exists():
        raise SystemExit(f"No config for proxy group '{group}': expected {path}")
    return load_json(path)


def group_dir(group: str) -> Path:
    d = DATA / group
    d.mkdir(parents=True, exist_ok=True)
    return d


def norm_doi(doi: str | None) -> str | None:
    if not doi:
        return None
    doi = doi.strip().lower()
    doi = re.sub(r"^(https?://(dx\.)?doi\.org/|doi:)", "", doi)
    return doi or None


def norm_title(title: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())


def read_csv(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: list[dict], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if fields is None:
        fields = []
        for r in rows:
            for k in r:
                if k not in fields:
                    fields.append(k)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
