#!/usr/bin/env python3
"""Adds sources to the source catalog (Sources/SourceAttribution/Resources/source-catalog.json).

    scripts/seed-source-catalog.py [--licenses PF2E/static/licenses] [--items ITEMS.json ...]
                                   [--alias "DATA TITLE=>NOTICE TITLE" ...] [--books FOLDER]
                                   [--scrollkeeper METADATA.json]

- --licenses: every notice in pf2e's ORCLicense.md and OpenGameLicense.md becomes an entry that quotes it, under
  the license of the file it is in. A Tome of Horrors line in an OGL group goes into the `includes` of that group's
  Paizo books.
- --items: an app's bundled records (a JSON list with `source` and `game`). Each source not yet in the catalog is
  added as a gap, so it shows in docs/source-attribution-gaps.md.
- --alias: the data's title for a book whose notice is under another title, such as
  "Pathfinder Core Rulebook=>Pathfinder Core Rulebook (Second Edition)". Adventure Path volumes ("Pathfinder #145:")
  are paired with their notices by number without being asked.
- --books: a folder of book PDFs, one subfolder per product named by its title, as Scrollkeeper downloads them.
  A gap whose book is there gets the notice the book asks to be credited with ("please credit us in your product
  as follows: ..."), under the ORC License.
- --scrollkeeper: Scrollkeeper's metadata.json (keyed by SKU, with `name`, `author`, `releaseDate` and
  `storePath`). It fills the year and authors of the gaps left, marked unverified.

Entries already complete are never changed, so hand edits survive. Run it again after a pf2e update.

Requirements: source-attribution 2.1, 2.3, 2.4, 3.2
"""

import argparse
import datetime
import json
import pathlib
import re
import subprocess
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "Sources/SourceAttribution/Resources/source-catalog.json"
NOTICE = re.compile(r"^\s*\*\s+(?P<notice>(?P<title>.+?) © (?P<year>\d{4}), (?P<holder>.+?)(;.*)?)\s*$")
GROUP = re.compile(r"^\*\s+(?P<group>\S.*?)\s*$")
CREDIT_REQUEST = re.compile(r"as follows:\s*(?P<notice>[^\n].+?©.+?)(?=\n\s*\n|$)", re.S)
NOTICE_END = re.compile(
    r"\s+(Reserved Material|Expressly Designated|Paizo, the Paizo golem|All rights reserved|Produced using|Printed in)"
    r"\b.*",
    re.S,
)
APPLE_EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.UTC)
FIELDS = [
    "title",
    "aliases",
    "game",
    "license",
    "notice",
    "year",
    "publisher",
    "credits",
    "includes",
    "reference",
    "verified",
    "note",
]

Entry = dict[str, object]


def key(title: str) -> str:
    """Returns the title as the catalog compares it: lowercase letters and digits only, "&" read as "and"."""
    folded = title.replace("&", " and ").casefold()
    return "".join(character for character in folded if character.isalnum())


def title_keys(title: str) -> set[str]:
    """Returns the keys a book with this data title may be found under in other sources."""
    keys = {key(title), key(re.sub(r"^Pathfinder Adventures:", "Pathfinder Adventure:", title))}
    volume = re.match(r"Pathfinder #(\d+):(.*)", title)
    if volume:
        keys.add(key(f"Pathfinder Adventure Path #{volume[1]}:{volume[2]}"))
    return keys


def product_key(name: str) -> str:
    """Returns the key of a product or folder name, without " PDF" and a trailing "(… 1 of 3)"."""
    name = re.sub(r"\s*\(?\bPDF\b\)?\s*$", "", name, flags=re.I)
    return key(re.sub(r"\s*\([^)]*\bof \d+\)\s*$", "", name))


def missing_facts(entry: Entry) -> bool:
    """Returns whether the entry still lacks a license, or the notice facts to attribute it."""
    if entry.get("license") is None:
        return True
    if entry.get("notice"):
        return False
    return entry.get("year") is None or not entry.get("publisher") or not entry.get("credits")


def natural_key(title: str) -> list[int | str]:
    """Returns a sort key that orders "#9" before "#10"."""
    return [int(part) if part.isdigit() else part.casefold() for part in re.split(r"(\d+)", title.strip())]


class Catalog:
    """The catalog's entries, found by the key of their titles and aliases."""

    def __init__(self, entries: list[Entry]) -> None:
        self.entries = entries
        self.by_key = {key(title): entry for entry in entries for title in [entry["title"], *entry.get("aliases", [])]}

    def add(self, entry: Entry) -> bool:
        """Adds the entry unless its title is already in the catalog; returns whether it was added."""
        if key(entry["title"]) in self.by_key:
            return False
        self.entries.append(entry)
        self.by_key[key(entry["title"])] = entry
        return True

    def gaps(self) -> list[Entry]:
        """Returns the entries that still lack facts."""
        return [entry for entry in self.entries if missing_facts(entry)]

    def write(self) -> None:
        """Writes the catalog sorted by title, two-space indented, with the fields in a fixed order."""
        ordered = sorted(self.entries, key=lambda entry: natural_key(entry["title"]))
        rows = [{field: entry[field] for field in FIELDS if field in entry} for entry in ordered]
        CATALOG.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def notices(path: pathlib.Path, license_name: str, reference: str) -> list[Entry]:
    """Returns every Paizo notice in a pf2e license file, with its group's other publishers' notices as includes."""
    entries: list[Entry] = []
    group_entries: list[Entry] = []
    upstream: list[str] = []

    def close_group() -> None:
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
        entry = {
            "title": match["title"].strip(),
            "license": license_name,
            "notice": match["notice"],
            "year": int(match["year"]),
            "publisher": "Paizo Inc.",
            "reference": reference,
        }
        entries.append(entry)
        group_entries.append(entry)
    close_group()
    return entries


def seed_licenses(catalog: Catalog, folder: pathlib.Path) -> None:
    """Adds every notice in pf2e's ORC and OGL files, quoted."""
    commit = (
        subprocess.run(
            ["git", "-C", str(folder), "rev-parse", "--short", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
        or "unknown commit"
    )
    added = 0
    for name, license_name in [("ORCLicense.md", "orc"), ("OpenGameLicense.md", "ogl")]:
        for entry in notices(folder / name, license_name, f"pf2e {commit}: static/licenses/{name}"):
            added += catalog.add(entry)
    print(f"Added {added} sources from pf2e's notices.")


def seed_items(catalog: Catalog, path: pathlib.Path) -> None:
    """Adds each source of an app's records that the catalog lacks, as a gap."""
    added = 0
    for record in json.loads(path.read_text(encoding="utf-8")):
        title = (record.get("source") or "").strip()
        if title:
            added += catalog.add({"title": title, "game": record.get("game", ""), "license": None})
    print(f"Added {added} gap entries from {path.name}.")


def link_aliases(catalog: Catalog, pairs: list[tuple[str, str]]) -> int:
    """Makes each gap title an alias of the complete entry it names, and drops the gap entry.

    Returns:
        How many pairs were linked.
    """
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


def link_adventure_path_volumes(catalog: Catalog) -> None:
    """Pairs pf2e's "Pathfinder #145: …" volumes with their "Pathfinder Adventure Path #145: …" notices."""
    volumes = {}
    for entry in catalog.entries:
        match = re.match(r"Pathfinder Adventure Path #(\d+):", entry["title"])
        if match and not missing_facts(entry):
            volumes[match[1]] = entry["title"]
    pairs = [
        (entry["title"], volumes[match[1]])
        for entry in list(catalog.entries)
        if (match := re.match(r"Pathfinder #(\d+):", entry["title"])) and match[1] in volumes
    ]
    print(f"Linked {link_aliases(catalog, pairs)} Adventure Path volumes to their notices.")


def fill_from_books(catalog: Catalog, folder: pathlib.Path) -> None:
    """Fills each gap whose book is in the folder with the notice the book asks to be credited with."""
    products = {product_key(product.name): product for product in folder.iterdir() if product.is_dir()}
    filled = 0
    for entry in catalog.gaps():
        product = next((products[found] for found in title_keys(entry["title"]) if found in products), None)
        pdf = largest_pdf(product) if product else None
        notice = credit_request(pdf) if pdf else None
        if notice:
            year = re.search(r"© (\d{4})", notice)
            entry.update(
                license="orc",
                notice=notice,
                publisher="Paizo Inc.",
                reference=pdf.name,
                verified=True,
                year=int(year[1]) if year else None,
            )
            filled += 1
    print(f"Filled {filled} entries from the books' own notices.")


def largest_pdf(folder: pathlib.Path) -> pathlib.Path | None:
    """Returns the product's largest PDF, which is the book rather than a sheet or a map."""
    pdfs = sorted(folder.rglob("*.pdf"), key=lambda pdf: pdf.stat().st_size, reverse=True)
    return pdfs[0] if pdfs else None


def credit_request(pdf: pathlib.Path) -> str | None:
    """Returns the notice an ORC book asks to be credited with, from its last or first pages.

    A notice that runs into a column or page break (it ends without a period and before the book's next section)
    comes out cut short, so it isn't returned: that book is filled in by hand.
    """
    info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True).stdout
    pages = int(match[1]) if (match := re.search(r"Pages:\s+(\d+)", info)) else 0
    for first, last in [(max(1, pages - 5), pages), (1, min(pages, 6))]:
        text = subprocess.run(
            ["pdftotext", "-f", str(first), "-l", str(last), str(pdf), "-"], capture_output=True, text=True
        ).stdout
        if match := CREDIT_REQUEST.search(text):
            flat = re.sub(r"-\n(?=[a-z])", "", match["notice"]).replace("\n", " ")
            notice = re.sub(r"\s+", " ", NOTICE_END.sub("", flat)).strip()
            following = " " + text[match.end() :].lstrip()
            complete = NOTICE_END.search(flat) or NOTICE_END.match(following) or notice.endswith(".")
            return notice if complete else None
    return None


def fill_from_scrollkeeper(catalog: Catalog, path: pathlib.Path) -> None:
    """Fills the year and authors of the gaps left from Scrollkeeper's metadata, marked unverified."""
    metadata = json.loads(path.read_text(encoding="utf-8"))
    products = {product_key(product["name"]): product for product in metadata.values()}
    filled = 0
    for entry in catalog.gaps():
        product = next((products[found] for found in title_keys(entry["title"]) if found in products), None)
        if product and not entry.get("notice") and fill_entry(entry, product):
            filled += 1
    print(f"Filled {filled} entries from Scrollkeeper's metadata.")


def fill_entry(entry: Entry, product: dict[str, str]) -> bool:
    """Fills the entry's year, authors and license from a product; returns whether it had authors to fill."""
    authors = [
        name.strip() for name in re.split(r",\s*(?:and\s+)?|\s+and\s+", product.get("author", "")) if name.strip()
    ]
    if not authors:
        return False
    released = product.get("releaseDate")
    entry.update(
        publisher="Paizo Inc.",
        verified=False,
        credits=[{"role": "Author" if len(authors) == 1 else "Authors", "names": authors}],
        reference=f"https://paizo.com{product.get('storePath', '/')}",
        note="From Scrollkeeper's metadata; check against the book's notice.",
    )
    if released and entry.get("year") is None:
        entry["year"] = (APPLE_EPOCH + datetime.timedelta(seconds=float(released))).year
    if entry.get("license") is None and (entry.get("game") == "sf2e" or (entry.get("year") or 0) >= 2024):
        entry["license"] = "orc"  # Paizo's books are ORC from the Remaster on (Player Core, November 2023)
    return True


def main() -> int:
    """Runs the steps the arguments ask for, in order, and writes the catalog."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--licenses", type=pathlib.Path)
    parser.add_argument("--items", type=pathlib.Path, action="append", default=[])
    parser.add_argument("--alias", action="append", default=[])
    parser.add_argument("--books", type=pathlib.Path)
    parser.add_argument("--scrollkeeper", type=pathlib.Path)
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
    if arguments.books:
        fill_from_books(catalog, arguments.books)
    if arguments.scrollkeeper:
        fill_from_scrollkeeper(catalog, arguments.scrollkeeper)
    catalog.write()
    print(f"{len(catalog.gaps())} gaps left.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
