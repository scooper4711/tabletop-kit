#!/usr/bin/env python3
"""Adds sources to the source catalog (Sources/SourceAttribution/Resources/source-catalog.json).

    scripts/seed-source-catalog.py --licenses PF2E/static/licenses [--items ITEMS.json ...]
                                   [--scrollkeeper METADATA.json] [--alias "DATA TITLE=>NOTICE TITLE" ...]

- --licenses: every notice in pf2e's ORCLicense.md and OpenGameLicense.md becomes an entry that quotes it, under
  the license of the file it is in. A Tome of Horrors line in an OGL group goes into the `includes` of that group's
  Paizo books.
- --items: an app's bundled records (a JSON list with `source` and `game`). Each source not yet in the catalog is
  added as a gap, so it shows in docs/source-attribution-gaps.md.
- --scrollkeeper: Scrollkeeper's metadata.json (keyed by SKU, with `title`, `author` and `releaseDate`). It fills
  the year and authors of gap entries whose title it has, marked unverified. It is account data: keep it in tmp/.
- --alias: the data's title for a book whose notice is under another title, such as
  "Pathfinder Core Rulebook=>Pathfinder Core Rulebook (Second Edition)". Adventure Path volumes ("Pathfinder #145:")
  are paired with their notices by number without being asked.

Entries already complete are never changed, so hand edits survive. Run it again after a pf2e update.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Sources/SourceAttribution/Resources/source-catalog.json"
NOTICE = re.compile(r"^\s*\*\s+(?P<notice>(?P<title>.+?) © (?P<year>\d{4}), (?P<holder>.+?)(;.*)?)\s*$")
GROUP = re.compile(r"^\*\s+(?P<group>\S.*?)\s*$")
FIELDS = ["title", "aliases", "game", "license", "notice", "year", "publisher", "credits", "includes",
          "reference", "verified", "note"]


def key(title):
    folded = title.replace("&", " and ").casefold()
    return "".join(character for character in folded if character.isalnum())


def missing_facts(entry):
    if entry.get("license") is None:
        return True
    if entry.get("notice"):
        return False
    return entry.get("year") is None or not entry.get("publisher") or not entry.get("credits")


class Catalog:
    def __init__(self, entries):
        self.entries = entries
        self.by_key = {key(title): entry for entry in entries for title in [entry["title"], *entry.get("aliases", [])]}

    def add(self, entry):
        if key(entry["title"]) in self.by_key:
            return False
        self.entries.append(entry)
        self.by_key[key(entry["title"])] = entry
        return True

    def write(self):
        ordered = sorted(self.entries, key=lambda entry: natural_key(entry["title"]))
        rows = [{field: entry[field] for field in FIELDS if field in entry} for entry in ordered]
        CATALOG.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def natural_key(title):
    return [int(part) if part.isdigit() else part.casefold() for part in re.split(r"(\d+)", title.strip())]


def notices(path, license_name, reference):
    """Every Paizo notice in a pf2e license file, with the other publishers' notices of its group as includes."""
    entries, group_entries, upstream = [], [], []

    def close_group():
        for entry in group_entries:
            entry["includes"] = list(upstream) if license_name == "ogl" else []
        group_entries.clear()
        upstream.clear()

    for line in path.read_text(encoding="utf-8").splitlines():
        if GROUP.match(line):
            close_group()
            continue
        match = NOTICE.match(line)
        if not match:
            continue
        if not match["holder"].startswith("Paizo"):
            upstream.append(match["notice"])
            continue
        entry = {"title": match["title"].strip(), "license": license_name, "notice": match["notice"],
                 "year": int(match["year"]), "publisher": "Paizo Inc.", "reference": reference}
        entries.append(entry)
        group_entries.append(entry)
    close_group()
    return entries


def seed_licenses(catalog, folder):
    commit = subprocess.run(["git", "-C", str(folder), "rev-parse", "--short", "HEAD"],
                            capture_output=True, text=True).stdout.strip() or "unknown commit"
    added = 0
    for name, license_name in [("ORCLicense.md", "orc"), ("OpenGameLicense.md", "ogl")]:
        for entry in notices(folder / name, license_name, f"pf2e {commit}: static/licenses/{name}"):
            added += catalog.add(entry)
    print(f"Added {added} sources from pf2e's notices.")


def seed_items(catalog, path):
    added = 0
    for record in json.loads(path.read_text(encoding="utf-8")):
        title = (record.get("source") or "").strip()
        if title:
            added += catalog.add({"title": title, "game": record.get("game", ""), "license": None})
    print(f"Added {added} gap entries from {path.name}.")


def link_aliases(catalog, pairs):
    """Makes each gap title an alias of the complete entry it names, and drops the gap entry."""
    linked = 0
    for gap_title, title in pairs:
        gap, entry = catalog.by_key.get(key(gap_title)), catalog.by_key.get(key(title))
        if gap is None or entry is None or gap is entry or not missing_facts(gap) or missing_facts(entry):
            continue
        entry.setdefault("aliases", []).append(gap["title"])
        catalog.entries.remove(gap)
        catalog.by_key[key(gap["title"])] = entry
        linked += 1
    return linked


def link_adventure_path_volumes(catalog):
    """pf2e titles Adventure Path volumes "Pathfinder #145: Hellknight Hill"; their notices say
    "Pathfinder Adventure Path #145: Hellknight Hill". Pairs them by volume number."""
    volumes = {}
    for entry in catalog.entries:
        match = re.match(r"Pathfinder Adventure Path #(\d+):", entry["title"])
        if match and not missing_facts(entry):
            volumes[match.group(1)] = entry["title"]
    pairs = []
    for entry in list(catalog.entries):
        match = re.match(r"Pathfinder #(\d+):", entry["title"])
        if match and match.group(1) in volumes:
            pairs.append((entry["title"], volumes[match.group(1)]))
    print(f"Linked {link_aliases(catalog, pairs)} Adventure Path volumes to their notices.")


def fill_from_scrollkeeper(catalog, path):
    products = json.loads(path.read_text(encoding="utf-8"))
    by_title = {key(product.get("title", "")): (sku, product) for sku, product in products.items()}
    filled = 0
    for entry in catalog.entries:
        found = by_title.get(key(entry["title"]))
        if not missing_facts(entry) or entry.get("notice") or not found:
            continue
        sku, product = found
        filled += fill_entry(entry, sku, product)
    print(f"Filled {filled} entries from Scrollkeeper's metadata.")


def fill_entry(entry, sku, product):
    authors = [name.strip() for name in re.split(r",\s*(?:and\s+)?|\s+and\s+", product.get("author", "")) if name.strip()]
    year = re.match(r"\d{4}", str(product.get("releaseDate") or ""))
    if not authors and not year:
        return False
    entry.setdefault("publisher", "Paizo Inc.")
    if year and entry.get("year") is None:
        entry["year"] = int(year.group())
    if authors and not entry.get("credits"):
        entry["credits"] = [{"role": "Author" if len(authors) == 1 else "Authors", "names": authors}]
    if entry.get("license") is None and (entry.get("game") == "sf2e" or (entry.get("year") or 0) >= 2024):
        entry["license"] = "orc"  # Paizo's books are ORC from the Remaster on (Player Core, November 2023)
    entry["reference"] = f"Scrollkeeper metadata, SKU {sku}"
    entry["verified"] = False
    entry["note"] = "From Scrollkeeper's metadata; check against the book's notice."
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--licenses", type=pathlib.Path)
    parser.add_argument("--items", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--scrollkeeper", type=pathlib.Path)
    parser.add_argument("--alias", action="append", default=[])
    arguments = parser.parse_args()
    catalog = Catalog(json.loads(CATALOG.read_text(encoding="utf-8")))
    if arguments.licenses:
        seed_licenses(catalog, arguments.licenses)
    for items in arguments.items:
        seed_items(catalog, items)
    link_adventure_path_volumes(catalog)
    pairs = [tuple(alias.split("=>", 1)) for alias in arguments.alias]
    if pairs:
        print(f"Linked {link_aliases(catalog, pairs)} of {len(pairs)} aliases.")
    if arguments.scrollkeeper:
        fill_from_scrollkeeper(catalog, arguments.scrollkeeper)
    catalog.write()
    return 0


if __name__ == "__main__":
    sys.exit(main())
