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
     exactly, NULL only where the reference has NULL). Q1 to Q4, Q7 and Q8
     need exactly the reference's columns; Q5 and Q6 need the columns the
     exercise names and accept more (see BLOCKS below).
  4. Prints one line per block: PASS, or the first difference it found.
  5. Runs your file once more on a copy where the tax table has one more
     year (a 2023 block at the top, so every other row moves down). Q7 and
     Q8 must still match; a query that picks rows by position fails here.

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

# (block, table, key columns, required columns)
# Required None: your table must have exactly the reference's columns.
# A list: your table must have these columns; other columns are allowed, and
# any of them that the reference also has are compared too. (Q5 may keep or
# drop the helper column copy_num; Q6 may sum all 27 money columns or only
# the ones the exercise asks for.)
Q6_REQUIRED = ["year", "n", "forbes_worth", "forbes_public_worth", "option_profit",
               "dividend", "ca_income_tax", "total_tax", "economic_income"]
BLOCKS = [
    ("Q1", "rtb_ca_all", ["date", "forbes_id"], None),
    ("Q2", "rtb_ca_eoy", ["date", "forbes_id"], None),
    ("Q3", "rtb_ca_2026_01_01_industry", ["industries"], None),
    ("Q4", "rtb_ca_aggregate", ["date"], None),
    ("Q5", "data_sec_all_kept", ["row_num"], "all but copy_num"),
    ("Q6", "data_sec_agg", ["year"], Q6_REQUIRED),
    ("Q7", "ftb_b4a_year", ["taxable_year"], None),
    ("Q8", "ftb_b4a_top", ["taxable_year", "bracket"], None),
]


def _missing(v):
    return v is None or (isinstance(v, float) and math.isnan(v))


def _key(row, cols):
    return tuple(str(row[c]) for c in cols)


def compare(con, table, keys, required=None, ref=None):
    """Return None if the table matches the reference, else a short message."""
    exists = con.execute(
        "SELECT 1 FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
        (table,)).fetchone()
    if not exists:
        return f"no table named {table}"
    ours = pd.read_sql(f"SELECT * FROM {table}", con)
    if ref is None:
        ref = pd.read_csv(EXPECTED / f"{table}.csv", keep_default_na=False, na_values=[""])

    if required is None:
        missing_cols = [c for c in ref.columns if c not in ours.columns]
        extra_cols = [c for c in ours.columns if c not in ref.columns]
        if missing_cols or extra_cols:
            return f"columns differ: missing {missing_cols}, unexpected {extra_cols}"
    else:
        if required == "all but copy_num":
            required = [c for c in ref.columns if c != "copy_num"]
        missing_cols = [c for c in required if c not in ours.columns]
        if missing_cols:
            return f"columns missing: {missing_cols}"
        # Compare the reference columns your table has; ignore the rest.
        ref = ref[[c for c in ref.columns if c in ours.columns]]
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


def shifted_sheet_check(sql, tmp):
    """Yield (block, message) for Q7 or Q8 if they break when a year is added.

    Only blocks that passed on the real sheet are re-checked here, so a
    failing block is reported once.
    """
    db = tmp / "shifted.sqlite"
    shutil.copy(DB, db)
    con = sqlite3.connect(db)
    n_new = con.execute("SELECT COUNT(*) FROM ftb_b4a WHERE taxable_year = 2022").fetchone()[0]
    first = con.execute("SELECT MIN(row_num) FROM ftb_b4a").fetchone()[0]
    con.executescript(f"""
        CREATE TEMP TABLE new_block AS
          SELECT row_num, 2023 AS taxable_year, agic, all_returns, ca_agi, taxable_income, total_tax
          FROM ftb_b4a WHERE taxable_year = 2022;
        UPDATE ftb_b4a SET row_num = row_num + {n_new};
        INSERT INTO ftb_b4a SELECT * FROM new_block;
        DROP TABLE new_block;
    """)
    con.commit()
    year_ref = pd.read_csv(EXPECTED / "ftb_b4a_year.csv")
    top_ref = pd.read_csv(EXPECTED / "ftb_b4a_top.csv")
    year_ref = pd.concat([year_ref, year_ref[year_ref.taxable_year == 2022].assign(taxable_year=2023)])
    new_top = top_ref[top_ref.taxable_year == 2022].assign(taxable_year=2023)
    top_ref = pd.concat([top_ref.assign(row_num=top_ref.row_num + n_new), new_top])
    assert new_top.row_num.min() >= first
    shifted = {"ftb_b4a_year": year_ref, "ftb_b4a_top": top_ref}
    ok_before = {}
    real = sqlite3.connect(tmp / "rtb_sample.sqlite")
    for block, table, keys, required in BLOCKS:
        if table in shifted:
            ok_before[table] = compare(real, table, keys, required) is None
    real.close()
    try:
        con.executescript(sql)
    except sqlite3.Error:
        pass
    for block, table, keys, required in BLOCKS:
        if table not in shifted or not ok_before[table]:
            continue
        msg = compare(con, table, keys, required, ref=shifted[table])
        if msg is not None:
            yield block, (f"{table} matches this sheet but not the same sheet with a 2023 "
                          f"block added at the top (pick rows by label, not position): {msg}")
    con.close()


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
        results = {}
        for block, table, keys, required in BLOCKS:
            msg = compare(con, table, keys, required)
            if msg is None:
                n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                results[block] = (True, f"{table} ({n} rows)")
            else:
                results[block] = (False, f"{table}: {msg}")
        con.close()
        # Q7 and Q8 again, on a sheet with one more year: a new 2023 block at
        # the top pushes every other row down, so a query that picks rows by
        # position stops matching while one that picks them by label holds.
        for block, msg in shifted_sheet_check(sql, Path(tmp)):
            results[block] = (False, msg)
    failures = 0
    for block, *_ in BLOCKS:
        ok, msg = results[block]
        failures += not ok
        print(f"{block}  {'PASS' if ok else 'FAIL'}  {msg}")
    print(f"{len(BLOCKS) - failures} of {len(BLOCKS)} blocks pass.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
