"""Step 1 - literature search.

Runs every query in config/<group>.json against OpenAlex (primary) and
Crossref (secondary), optionally expands from seed DOIs (references + citing
works), de-duplicates, and writes data/<group>/candidates.csv plus a search
log (queries, date, hit counts) for the methods section.

Usage:
    python literature_db/scripts/search.py mem
    python literature_db/scripts/search.py mem --no-crossref
    python literature_db/scripts/search.py mem --seed-doi 10.xxxx/yyyy

OpenAlex needs a free API key (https://openalex.org): set OPENALEX_API_KEY.
Without it, use --no-openalex (Crossref only; fewer abstracts).
Optionally set CROSSREF_MAILTO to a contact address for Crossref's polite pool.
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import sys
import time

import requests

from common import group_dir, load_config, norm_doi, norm_title, read_csv, write_csv

OPENALEX = "https://api.openalex.org/works"
CROSSREF = "https://api.crossref.org/works"
FIELDS = ["id", "doi", "title", "year", "authors", "journal", "abstract",
          "oa_url", "type", "found_by"]
SESSION = requests.Session()
SESSION.headers["User-Agent"] = "carbokitten-literature-db/0.1"


def _get(url: str, params: dict, tries: int = 4) -> dict:
    for i in range(tries):
        try:
            r = SESSION.get(url, params=params, timeout=60)
            if r.status_code == 429 or r.status_code >= 500:
                raise requests.HTTPError(f"HTTP {r.status_code}")
            r.raise_for_status()
            return r.json()
        except (requests.RequestException, ValueError) as e:
            if i == tries - 1:
                raise
            wait = 2 ** (i + 1)
            print(f"  retry in {wait}s ({e})", file=sys.stderr)
            time.sleep(wait)
    return {}


def _abstract_from_index(inv: dict | None) -> str:
    if not inv:
        return ""
    pos = [(p, w) for w, ps in inv.items() for p in ps]
    return " ".join(w for _, w in sorted(pos))


def _openalex_record(w: dict, found_by: str) -> dict:
    loc = w.get("primary_location") or {}
    src = loc.get("source") or {}
    oa = w.get("open_access") or {}
    return {
        "id": (w.get("id") or "").rsplit("/", 1)[-1],
        "doi": norm_doi(w.get("doi")),
        "title": w.get("display_name") or "",
        "year": w.get("publication_year"),
        "authors": "; ".join(a["author"]["display_name"]
                             for a in w.get("authorships", [])[:20] if a.get("author")),
        "journal": src.get("display_name") or "",
        "abstract": _abstract_from_index(w.get("abstract_inverted_index")),
        "oa_url": oa.get("oa_url") or "",
        "type": w.get("type") or "",
        "found_by": found_by,
    }


def openalex_search(query: str, from_year: int, limit: int) -> list[dict]:
    out, cursor = [], "*"
    params = {"search": query, "per-page": 200,
              "filter": f"from_publication_date:{from_year}-01-01"}
    if os.environ.get("OPENALEX_API_KEY"):
        params["api_key"] = os.environ["OPENALEX_API_KEY"]
    while cursor and len(out) < limit:
        data = _get(OPENALEX, {**params, "cursor": cursor})
        out += [_openalex_record(w, f"openalex:{query}") for w in data.get("results", [])]
        cursor = (data.get("meta") or {}).get("next_cursor")
        if not data.get("results"):
            break
    return out[:limit]


def openalex_by_ids(ids: list[str], found_by: str) -> list[dict]:
    out = []
    for i in range(0, len(ids), 50):
        chunk = "|".join(x.rsplit("/", 1)[-1] for x in ids[i:i + 50])
        data = _get(OPENALEX, {"filter": f"openalex:{chunk}", "per-page": 50})
        out += [_openalex_record(w, found_by) for w in data.get("results", [])]
    return out


def expand_seed(doi: str) -> list[dict]:
    """References of and works citing a seed paper (citation chaining)."""
    seed = _get(f"{OPENALEX}/doi:{doi}", {})
    refs = [_openalex_record(seed, f"seed:{doi}")]
    refs += openalex_by_ids(seed.get("referenced_works", []), f"refs_of:{doi}")
    cited, cursor = [], "*"
    while cursor:
        data = _get(OPENALEX, {"filter": f"cites:{seed['id'].rsplit('/', 1)[-1]}",
                               "per-page": 200, "cursor": cursor})
        cited += [_openalex_record(w, f"cites:{doi}") for w in data.get("results", [])]
        cursor = (data.get("meta") or {}).get("next_cursor")
        if not data.get("results"):
            break
    return refs + cited


def crossref_search(query: str, from_year: int, limit: int) -> list[dict]:
    params = {"query.bibliographic": query, "rows": min(limit, 200),
              "filter": f"from-pub-date:{from_year}"}
    if os.environ.get("CROSSREF_MAILTO"):
        params["mailto"] = os.environ["CROSSREF_MAILTO"]
    items = _get(CROSSREF, params).get("message", {}).get("items", [])
    out = []
    for it in items:
        year = (it.get("issued", {}).get("date-parts") or [[None]])[0][0]
        out.append({
            "id": "crossref:" + (it.get("DOI") or ""),
            "doi": norm_doi(it.get("DOI")),
            "title": (it.get("title") or [""])[0],
            "year": year,
            "authors": "; ".join(f"{a.get('given', '')} {a.get('family', '')}".strip()
                                 for a in it.get("author", [])[:20]),
            "journal": (it.get("container-title") or [""])[0],
            "abstract": re.sub(r"<[^>]+>", " ", it.get("abstract", "")).strip(),
            "oa_url": "",
            "type": it.get("type", ""),
            "found_by": f"crossref:{query}",
        })
    return out


def dedupe(records: list[dict]) -> list[dict]:
    """Merge on DOI, then on normalised title; keep the richest record and
    concatenate the 'found_by' provenance."""
    merged: dict[str, dict] = {}
    for r in records:
        key = r["doi"] or "t:" + norm_title(r["title"])
        if key == "t:":
            continue
        if key not in merged:
            merged[key] = dict(r)
            continue
        m = merged[key]
        for k in FIELDS:
            if not m.get(k) and r.get(k):
                m[k] = r[k]
        if len(r.get("abstract") or "") > len(m.get("abstract") or ""):
            m["abstract"] = r["abstract"]
        found = set(m["found_by"].split(" | ")) | {r["found_by"]}
        m["found_by"] = " | ".join(sorted(found))
    return list(merged.values())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("group")
    ap.add_argument("--no-crossref", action="store_true")
    ap.add_argument("--no-openalex", action="store_true")
    ap.add_argument("--chain-only", action="store_true", help="skip queries; only citation chaining from seeds")
    ap.add_argument("--add-doi", action="append", default=[], help="add a known paper by DOI (no chaining); implies --chain-only unless seeds are given")
    ap.add_argument("--max-per-query", type=int, help="override config max_results_per_query (e.g. small pilot)")
    ap.add_argument("--seed-doi", action="append", default=[])
    args = ap.parse_args()

    cfg = load_config(args.group)["search"]
    out_dir = group_dir(args.group)
    log_rows, records = [], []
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    limit = args.max_per_query or cfg["max_results_per_query"]
    for q in ([] if args.chain_only else cfg["queries"]):
        if not args.no_openalex:
            hits = openalex_search(q, cfg["from_year"], limit)
            print(f"openalex  {len(hits):5d}  {q}")
            log_rows.append({"date_utc": now, "source": "openalex", "query": q, "hits": len(hits)})
            records += hits
        if not args.no_crossref:
            hits = crossref_search(q, cfg["from_year"], limit)
            print(f"crossref  {len(hits):5d}  {q}")
            log_rows.append({"date_utc": now, "source": "crossref", "query": q, "hits": len(hits)})
            records += hits

    for doi in args.add_doi:
        w = _get(f"{OPENALEX}/doi:{norm_doi(doi)}", {})
        records.append(_openalex_record(w, "manual"))
        print(f"added     {norm_doi(doi)}  {w.get('display_name', '')[:70]}")
        log_rows.append({"date_utc": now, "source": "manual_doi", "query": doi, "hits": 1})

    seeds = [] if (args.add_doi and not args.seed_doi and args.chain_only) else cfg.get("seed_dois", []) + args.seed_doi
    for doi in seeds:
        hits = expand_seed(norm_doi(doi))
        print(f"chaining  {len(hits):5d}  {doi}")
        log_rows.append({"date_utc": now, "source": "openalex_chaining", "query": doi, "hits": len(hits)})
        records += hits

    # keep previously found records (re-runs only add)
    previous = read_csv(out_dir / "candidates.csv")
    unique = dedupe(previous + records)
    write_csv(out_dir / "candidates.csv", unique, FIELDS)
    old_log = read_csv(out_dir / "search_log.csv")
    write_csv(out_dir / "search_log.csv", old_log + log_rows)
    print(f"\n{len(records)} raw hits -> {len(unique)} unique candidates "
          f"({len(unique) - len(previous)} new) -> {out_dir / 'candidates.csv'}")


if __name__ == "__main__":
    main()
