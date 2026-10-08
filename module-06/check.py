"""Grade a module 6 answer file against the reference results.

Usage, from the repo root:

    python module-06/check.py my_answers.sql
    python module-06/check.py module-06/solution.sql     # must pass every block

What it does:
  1. Copies data/rtb_sample.sqlite to a temporary file, so your answers never
     change the shared database.
  2. Runs your whole file with sqlite3.Connection.executescript, the same call
     the real pipeline uses. (So: no sqlite3 dot-commands like .headers.)
  3. For each block, reads the table your file should have created and
     compares it with module-06/expected/<table>.csv: the columns, the row
     count, the set of keys, then every cell (numbers within 1e-6, text
     exactly, NULL only where the reference has NULL).
  4. Prints one line per block: PASS, or the first difference it found.

Exit code 0 if every block passes, 1 otherwise. Needs pandas.
"""
import math
import shutil
import sqlite3
import sys
import tempfile
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
DB = HERE.parent / "data" / "rtb_sample.sqlite"
EXPECTED = HERE / "expected"
TOL = 1e-6

# (block, table, key columns)
BLOCKS = [
    ("Q1", "rtb_ca_all", ["date", "forbes_id"]),
    ("Q2", "rtb_ca_eoy", ["date", "forbes_id"]),
    ("Q3", "rtb_ca_2026_01_01_industry", ["industries"]),
    ("Q4", "rtb_ca_aggregate", ["date"]),
]


def _missing(v):
    return v is None or (isinstance(v, float) and math.isnan(v))


def _key(row, cols):
    return tuple(str(row[c]) for c in cols)


def compare(con, table, keys):
    """Return None if the table matches the reference, else a short message."""
    exists = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
        (table,)).fetchone()
    if not exists:
        return f"no table named {table}"
    ours = pd.read_sql(f"SELECT * FROM {table}", con)
    ref = pd.read_csv(EXPECTED / f"{table}.csv", keep_default_na=False, na_values=[""])

    missing_cols = [c for c in ref.columns if c not in ours.columns]
    extra_cols = [c for c in ours.columns if c not in ref.columns]
    if missing_cols or extra_cols:
        return f"columns differ: missing {missing_cols}, unexpected {extra_cols}"
    if len(ours) != len(ref):
        return f"{len(ours)} rows, expected {len(ref)}"

    ours_rows = {_key(r, keys): r for r in ours.to_dict("records")}
    ref_rows = {_key(r, keys): r for r in ref.to_dict("records")}
    if len(ours_rows) != len(ours):
        return f"the key ({', '.join(keys)}) is not unique in your table"
    only_ours = sorted(set(ours_rows) - set(ref_rows))
    only_ref = sorted(set(ref_rows) - set(ours_rows))
    if only_ours or only_ref:
        ex = only_ours[:1] or only_ref[:1]
        return (f"keys differ: {len(only_ours)} only in yours, {len(only_ref)} only in the "
                f"reference (for example {ex[0]})")

    numeric = [c for c in ref.columns if pd.api.types.is_numeric_dtype(ref[c])]
    for k in sorted(ref_rows):
        a_row, b_row = ours_rows[k], ref_rows[k]
        for c in ref.columns:
            a, b = a_row[c], b_row[c]
            if _missing(a) or _missing(b):
                if _missing(a) != _missing(b):
                    return f"{k} {c}: yours {a!r}, expected {b!r}"
                continue
            if c in numeric:
                try:
                    if abs(float(a) - float(b)) > TOL:
                        return f"{k} {c}: yours {a!r}, expected {b!r}"
                except (TypeError, ValueError):
                    return f"{k} {c}: yours {a!r} is not a number, expected {b!r}"
            elif str(a) != str(b):
                return f"{k} {c}: yours {a!r}, expected {b!r}"
    return None


def main(argv):
    if len(argv) != 1:
        sys.exit("usage: python module-06/check.py ANSWERS.sql")
    sql = Path(argv[0]).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "rtb_sample.sqlite"
        shutil.copy(DB, db)
        con = sqlite3.connect(db)
        try:
            con.executescript(sql)
        except sqlite3.Error as e:
            # executescript stops at the first error; blocks before it still count.
            print(f"SQL error (blocks after it did not run): {e}")
        failures = 0
        for block, table, keys in BLOCKS:
            msg = compare(con, table, keys)
            if msg is None:
                n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                print(f"{block}  PASS  {table} ({n} rows)")
            else:
                failures += 1
                print(f"{block}  FAIL  {table}: {msg}")
        con.close()
    print(f"{len(BLOCKS) - failures} of {len(BLOCKS)} blocks pass.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
