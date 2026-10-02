#!/usr/bin/env python3
"""Rebuild the committed v1 SQLite fixture from the frozen migration SQL.

Run from any directory:
    python3 Packages/DelveStore/Tools/regenerate_v1_fixture.py
Requires only Python's standard sqlite3 module. IDs, timestamps, and insert
order are fixed, so regeneration is byte-reproducible.
"""
import json
import os
import pathlib
import re
import sqlite3
import tempfile

PACKAGE = pathlib.Path(__file__).resolve().parents[1]
SOURCE = PACKAGE / "Sources/DelveStore/DelveStore.swift"
OUTPUT = PACKAGE / "Tests/DelveStoreTests/Fixtures/v1.sqlite"

RUN = "00000000-0000-0000-0000-000000000001"
WORLD = {
    "visitedRooms": ["entrance", "brazier-hall"],
    "flags": ["brazier-left"],
    "keys": ["bronze-key"],
}


def main():
    source = SOURCE.read_text(encoding="utf-8")
    match = re.search(r'registerMigration\("v1"\).*?db\.execute\(sql: """(.*?)"""', source, re.S)
    if not match:
        raise SystemExit("frozen v1 SQL not found")
    fd, temporary = tempfile.mkstemp(prefix="v1-", suffix=".sqlite", dir=OUTPUT.parent)
    os.close(fd)
    try:
        connection = sqlite3.connect(temporary)
        connection.execute("PRAGMA page_size=4096")
        connection.execute("PRAGMA foreign_keys=ON")
        connection.executescript(match.group(1))
        connection.execute("CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
        connection.execute("INSERT INTO grdb_migrations VALUES ('v1')")
        connection.execute(
            "INSERT INTO runs VALUES (?,?,?,?,?)",
            (
                RUN,
                "Delver",
                json.dumps(WORLD, sort_keys=True, separators=(",", ":")),
                100.0,
                101.0,
            ),
        )
        connection.executemany(
            "INSERT INTO ledger_events (run_id, kind, detail_json, occurred_at) VALUES (?,?,?,?)",
            [
                (RUN, "visit", json.dumps({"room": "entrance"}, sort_keys=True, separators=(",", ":")), 100.0),
                (RUN, "action", json.dumps({"room": "brazier-hall", "command": "toggle"}, sort_keys=True, separators=(",", ":")), 100.5),
                (RUN, "visit", json.dumps({"room": "brazier-hall"}, sort_keys=True, separators=(",", ":")), 101.0),
            ],
        )
        connection.commit()
        connection.execute("VACUUM")
        connection.close()
        os.replace(temporary, OUTPUT)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(OUTPUT)


if __name__ == "__main__":
    main()
