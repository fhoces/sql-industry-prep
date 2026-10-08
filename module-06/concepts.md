# Module 6: SQL in a Real Replication

## Why this module breaks the pattern

Modules 1 to 5 use the ride-sharing database. This one does not, on purpose. The skill here
is reading and reproducing one step of a real pipeline, and toy data cannot teach that,
because the shape of a real query comes from the data it was written for. So the data is a
synthetic billionaire panel in the exact shape of the real one (invented people, invented
ids, random-walk fortunes), and the real run lives in
[`fhoces/opa-prop40`](https://github.com/fhoces/opa-prop40) (`bsz-analysis/sql/01_rtb_ca.sql`).
The SQL you study here is that file, nearly verbatim: `module-06/solution.sql` differs only
in its banner and in four invented ids.

## The two-step reproduction idea

A published paper usually sits at the end of two steps. First, raw data (here, daily Forbes
snapshots of every billionaire's worth) are reduced to a small set of intermediate tables
(here, the California lists and a daily total), which the authors keep in a spreadsheet.
Second, those tables feed the paper's figures and estimates. Reproducing the second step
only needs the spreadsheet. Reproducing the first step means rewriting the reduction from
the raw data and then checking, cell by cell, that your tables match theirs. This module is
the first step for one pipeline: four SQL blocks, each building one table, each checked
against a reference.

## The data

`data/rtb_sample.sqlite` (built by `Rscript data/build_rtb_sample.R`, seed 2026):

```
rtb_all_combined        (date, forbes_id, forbes_name, state, country_citizenship,
                         source, industries, forbes_worth, forbes_public_worth,
                         forbes_private_worth)        16,089 rows, worth in $ million
rtb_ca_cik              (forbes_id, cik)              SEC id, NULL for non-filers
rtb_residency_overrides (forbes_id, rule, note)       rule is 'include' or 'exclude'
```

One row per person per snapshot date: 60 people, 293 dates from 2019-12-31 to 2026-03-30.
Missing values are stored as NULL, never as empty strings or zeros. That matters for every
aggregate below. The panel is built to exercise every rule: people who cross the $1 billion
line, people with no state on file, two non-US citizens, one person counted as Californian
only through the override table (their state says Nevada), one excluded by it, and one
industry (Sports) whose only member never has a public/private split.

## Block Q1: who counts as a California billionaire, on every date

**What it computes.** `rtb_ca_all`: every billionaire-day with worth of at least $1 billion
and California residence, where residence is the Forbes state field plus the override
table's includes, minus its excludes.

**The R idiom it replaces.** A chain of `filter()` calls: one for the threshold, one for
`state == "California" | forbes_id %in% include_ids`, one for `!forbes_id %in% exclude_ids`,
with the two id vectors typed into the script.

**The SQL idiom.** One `WHERE` clause with `AND` and a parenthesised `OR`, and the id lists
read from a table with `IN (SELECT ...)` and `NOT IN (SELECT ...)`:

```sql
WHERE forbes_worth >= 1000
  AND (state = 'California'
       OR forbes_id IN (SELECT forbes_id FROM rtb_residency_overrides WHERE rule = 'include'))
  AND forbes_id NOT IN (SELECT forbes_id FROM rtb_residency_overrides WHERE rule = 'exclude')
```

Order of the filters does not matter to the result (they are one boolean expression), but
the parentheses do. Without them `AND` binds tighter than `OR`, so every override include
would skip the threshold test and every Forbes Californian would skip the exclude test.

Moving the ids into a table is a design choice worth copying. The query stays public while
the list (which in the real project comes from confidential material) lives in a gitignored
file, and changing the list never touches the SQL.

**NULL in comparisons.** `NULL >= 1000` is neither true nor false, so `WHERE` drops the row.
A row with NULL `state` fails `state = 'California'` the same way and survives only through
the include list. That is also what R's `filter()` does with `NA`.

**The `NOT IN` trap.** If the subquery returns a single NULL id, `x NOT IN (...)` is NULL for
every `x` and the block returns zero rows. The real loader refuses an override row without an
id for exactly this reason. `NOT EXISTS` is the NULL-safe alternative.

**Course modules.** 1 (WHERE, AND / OR, NULL in comparisons) and 4 (subqueries).
**Beyond the course.** `DROP TABLE IF EXISTS`, `CREATE TABLE AS`, `CREATE INDEX`.

## Tables, not result sets

Every block in the real file has the same two-line opening:

```sql
DROP TABLE IF EXISTS rtb_ca_all;
CREATE TABLE rtb_ca_all AS
SELECT ...
```

`CREATE TABLE ... AS SELECT` stores the result as a table instead of printing it, so the next
block can read it, and R and Python can both read it back with the same `SELECT`. The
`DROP TABLE IF EXISTS` line makes the file idempotent: run it twice and you get the same
database, not an "already exists" error. `CREATE INDEX idx_rtb_ca_all_date ON rtb_ca_all (date)`
speeds up the later blocks, which all filter or group by date.

**No dot-commands in shared files.** Modules 1 to 5 start with `.headers on` and
`.mode column`. Those are commands of the `sqlite3` shell, not SQL. The real file is run by
Python's `sqlite3.Connection.executescript` and by R's `DBI::dbExecute`, statement by
statement, and neither understands them. A shared `.sql` file therefore holds SQL only.

## Block Q2: the seven year-end lists, in one long table

**What it computes.** `rtb_ca_eoy`: the California list on each of seven snapshot dates,
stacked, with the SEC id added to the 2026-01-01 list.

**The R idiom it replaces.** A loop or seven copies of `filter(date == d) |> arrange(desc(worth))`,
each written to its own spreadsheet sheet.

**The SQL idiom.** One table with a `date` column. Each old sheet is a `WHERE date = '...'`
slice, and a new year is one more value in the `IN` list, not another block of code:

```sql
FROM rtb_ca_all ca
LEFT JOIN rtb_ca_cik cik
  ON  cik.forbes_id = ca.forbes_id
  AND ca.date = '2026-01-01'
WHERE ca.date IN ('2019-12-31', '2020-12-31', ..., '2026-01-01')
ORDER BY ca.date, ca.forbes_worth DESC, ca.forbes_id;
```

**Why 2026-01-01.** The data have no 2025-12-31 snapshot (2025-12-30 is followed by
2026-01-01), so 2026-01-01 stands in for the 2025 list.

**The condition in the `ON` clause.** Only the 2026-01-01 list gets `sec_cik`. With the date
test in `ON`, the join simply finds no match for the other six dates, and a `LEFT JOIN` keeps
those rows with `sec_cik` NULL. Move the same test to `WHERE` and those six lists disappear,
because `WHERE` filters after the join. In R terms: `left_join()` followed by
`mutate(sec_cik = if_else(date == "2026-01-01", cik, NA))`, not a `filter()`.

**What a NULL `sec_cik` means.** Two different things: on the six earlier lists, "not
looked up"; on the 2026-01-01 list, "this person has no CIK" (the crosswalk row has a NULL
`cik`, or there is no crosswalk row). The table cannot tell you which without the date.

**The tie-breaker.** `ORDER BY ... forbes_worth DESC, forbes_id` sorts like the authors'
sheets and adds `forbes_id` so equal worths always come out in the same order. A
reproduction that compares files needs deterministic order.

**Course modules.** 1 (WHERE) and 2 (LEFT JOIN). **Beyond the course.** `IN (...)` with a
literal list; an extra condition in the `ON` clause of a `LEFT JOIN`.

## Block Q3: wealth by industry on 2026-01-01, with a Total row

**What it computes.** `rtb_ca_2026_01_01_industry`: per industry, the count, public worth and
total worth in $ billion, the public share, and the industry's share of all California
wealth, plus a `Total` row at the bottom.

**The R idiom it replaces.** `group_by(industries) |> summarise(...)`, then an ungrouped
`mutate(share = worth / sum(worth))`, then a one-row `summarise()` for the total, then
`bind_rows()`.

**The SQL idiom.** A chain of CTEs (module 4), one per R step:

- `list_2026`: the 2026-01-01 rows.
- `by_industry`: `GROUP BY industries` with `COUNT(*)` and `COALESCE(SUM(...), 0) / 1000.0`.
- `with_share`: `forbes_worth / SUM(forbes_worth) OVER ()`. An empty `OVER ()` is a window
  over all rows of the CTE, which is the SQL form of an ungrouped `mutate()` after
  `summarise()` (module 5 used `OVER (PARTITION BY ...)`; with nothing inside, the partition
  is the whole table).
- `total_row`: the same sums over the whole list, labelled `'Total'`.
- `stacked`: `UNION ALL` puts the Total row under the industry rows. `UNION ALL` keeps every
  row; plain `UNION` would also remove duplicates, which is never what you want here.

**`COALESCE` in the sums.** In the synthetic panel the Sports owner has no public/private
split, so `SUM(forbes_public_worth)` over that one-person group is NULL. `COALESCE(..., 0)`
turns it into 0, which is what R's `sum(x, na.rm = TRUE)` returns for an all-`NA` vector.

**Sorting the Total row last.** SQLite only lets you sort a `UNION` by its output columns, so
the final `SELECT` reads the `stacked` CTE and sorts by `(industries = 'Total')`, a true/false
expression that is 0 for industry rows and 1 for the Total row.

**`NULLIF`, and why the file does not need it.** Module 5 guarded a division with
`NULLIF(x, 0)`, which turns a zero denominator into NULL so the ratio is NULL instead of an
error. Here every group has worth of at least $1 billion (Q1 guarantees it), so
`forbes_public_worth / forbes_worth` can never divide by zero. The file says so in a comment
instead of adding a guard that cannot fire.

**Course modules.** 3 (GROUP BY), 4 (CTE chain, UNION ALL), 5 (window SUM), 1 (COALESCE).
**Beyond the course.** An empty `OVER ()` as a grand total; `ORDER BY` on a true/false
expression.

## Block Q4: daily count and wealth

**What it computes.** `rtb_ca_aggregate`: per date, the number of California billionaires,
their total worth, the worth of the four largest fortunes (the paper's "top 4") and private
worth, all in $ billion, leaving out three snapshot dates.

**The R idiom it replaces.** `group_by(date) |> summarise(top4 = sum(worth[id %in% top4_ids]))`:
subsetting a vector inside the sum.

**The SQL idiom.** A conditional sum (module 1's `SUM(CASE WHEN ...)`):

```sql
COALESCE(SUM(CASE WHEN forbes_id IN ('marlo-zanderfell', ...) THEN forbes_worth END), 0) / 1000.0
```

The `CASE` returns the worth for the four ids and NULL for everyone else (no `ELSE` means
`ELSE NULL`), and `SUM` skips the NULLs. Writing `ELSE 0` gives the same sum; leaving it out
makes the intent (only these rows count) explicit.

**Excluding dates.** `WHERE date NOT IN ('2022-07-18', '2026-03-29', '2026-03-30')` drops three
snapshot dates, as the authors' code does. A literal list cannot contain NULL, so the
`NOT IN` trap from Q1 does not apply.

**Column order.** The authors' sheet has the first four value columns. `forbes_private_worth`
comes last because their current code computes it but their sheet does not have it, which is
itself a hint that the code and the sheet are different vintages (see below).

**Course modules.** 3 (GROUP BY) and 1 (`SUM(CASE WHEN ...)`). **Beyond the course.**
`IN (...)` and `NOT IN (...)` with literal lists.

## Part 2: the paper's second step, in SQL

The two-step idea above has a second step: the authors' spreadsheet to the paper's tables.
The real project reproduces that step from the **public** workbook, and two of its inputs
go through shared SQL files, run unchanged from R and from Python:
`02_data_sec_agg.sql` (a yearly SEC panel to yearly sums) and `03_ftb_b4a.sql` (a
tax-statistics table to yearly totals and top-bracket rows). Before the SQL, both were R
code. The course versions are Q5 to Q8, on three more synthetic tables in
`data/rtb_sample.sqlite`:

```
data_sec_all          (row_num, year, forbes_id, 29 money columns)   235 rows, $ million
data_sec_agg_exclude  (forbes_id)                                    1 invented id
ftb_b4a               (row_num, taxable_year, agic, all_returns,     59 rows, $
                       ca_agi, taxable_income, total_tax)
```

`row_num` is the row's position in the sheet it was loaded from. Both files need it, for
opposite reasons: Q5 uses it to decide which copy of a row came first, and Q8 is about
not using it to pick rows.

## Block Q5: drop the excluded ids, then the re-pasted rows

**What it computes.** `data_sec_all_kept`: the rows of the yearly panel that count, after
two filters.

**The R idiom it replaces.** `filter(!forbes_id %in% exclude_ids)` and then
`filter(!duplicated(df[c("year", "forbes_id", "forbes_worth")]))`. `duplicated()` marks
every row that repeats an earlier row on those columns, so `!duplicated()` keeps the first
copy.

**The SQL idiom.** Two CTEs. `kept` is the exclusion as `NOT IN (SELECT ...)`, the same
pattern as Q1's exclude list, now in a CTE. `numbered` gives every row a copy number:

```sql
ROW_NUMBER() OVER (PARTITION BY year, forbes_id, forbes_worth ORDER BY row_num) AS copy_num
```

The window splits the rows into groups with the same year, id and worth, sorts each group
by sheet position, and numbers it 1, 2, 3. `WHERE copy_num = 1` keeps the first row of
each group, which is `!duplicated()`. Module 5 used the same function for "top N per
group"; here N is 1 and the group is "the same row".

**Why this key.** The real sheet has a four-row block pasted twice at its tail. Some
copies are byte-identical, some are not (a re-typed cell outside the key). The key is
what makes two rows the same observation: same person, same year, same worth. It also
leaves alone two rows with the same person and year but a **different** worth, which in
the real data are two separately tracked fortunes. The synthetic panel has all three
cases: identical copies, a copy with a different `dividend`, and a 2022 pair with worths
8,000 and 5,256.

**Why not `DISTINCT`.** `SELECT DISTINCT *` compares every column, and `row_num` differs
on every row, so it removes nothing. `DISTINCT` on the key columns alone would lose the
other columns. A self-join (`NOT EXISTS` an earlier row with `b.forbes_worth =
a.forbes_worth`) is closer, but `=` is never true for two NULLs, so a re-pasted row with
no worth survives. `PARTITION BY` (like `GROUP BY`) puts all NULLs in one group, which
is what `duplicated()` does with two `NA`s. The synthetic tail has one such row.

**Does the order of the two filters matter?** Not here. The partition includes
`forbes_id`, so an excluded person's rows never share a group with anyone else's, and
removing them first or last changes no copy number. The file follows the order of the
R code anyway, which makes the side-by-side reading easier.

**Course modules.** 4 (CTE chain, `NOT IN (SELECT ...)`) and 5 (`ROW_NUMBER() OVER
(PARTITION BY ... ORDER BY ...)`).

## Block Q6: yearly sums with COALESCE

**What it computes.** `data_sec_agg`: per year, the count `n` and 27 sums in $ billion.

**The R idiom it replaces.** `group_by(year) |> summarise(n = n(), across(cols, \(x)
sum(x, na.rm = TRUE) / 1000))`.

**The SQL idiom.** One `GROUP BY year` and one line per column,
`COALESCE(SUM(col), 0) / 1000.0 AS col`, in the sheet's column order. Three details:

- **`COUNT(*)`, not `COUNT(forbes_worth)`.** `n` counts people, and a kept row can have
  no worth (the synthetic 2025 has one). `COUNT(col)` skips NULLs and would give 29
  instead of 30.
- **`COALESCE(..., 0)`.** In the synthetic panel `option_profit` is NULL for every 2019
  row. `SUM` over nothing but NULLs is NULL; R's `sum(na.rm = TRUE)` is 0. Same rule as
  Q3 and Q4, now on 27 columns.
- **`1000.0`, not `1000`.** In SQLite, integer divided by integer is integer division
  (`7 / 2` is 3). The money columns here are REAL, so `/ 1000` would happen to work, but
  a column of whole numbers loaded as INTEGER would be truncated. `1000.0` makes the
  division floating point whatever the input type.

The real file's header also notes a numerical detail: SQLite (3.43 and later) adds doubles
with a compensated sum, R adds them one by one, so the two can differ around 1e-13 of the
value. That is noise; the checks allow it.

**Course modules.** 3 (GROUP BY, COUNT, SUM) and 1 (COALESCE).

## Block Q7: yearly totals over all brackets

**What it computes.** `ftb_b4a_year`: per taxable year, the number of brackets and the
four sums (returns, AGI, taxable income, tax), in dollars.

**The R idiom it replaces.** One `sum(column[first_row:last_row], na.rm = TRUE)` per year
and column, with the row ranges typed in (rows 242 to 300 for one year in the real code).

**The SQL idiom.** `GROUP BY taxable_year`, with `WHERE taxable_year IS NOT NULL` first.
The loaded table ends with a footnote row that has no year; without the `WHERE`, `GROUP
BY` would put it in a group of its own, with a NULL year. `n_brackets` (`COUNT(*)`) is a
built-in check on the grouping: 9 for 2021 and 2022, 8 before (59 and 60 in the real
sheet).

## Block Q8: pick rows by label, not by position

**What it computes.** `ftb_b4a_top`: the rows of the top income brackets, one per year up
to 2020 and two from 2021 (when the source split the top bracket), with a short key.

**The R idiom it replaces.** Row numbers again: "the top bracket of 2018 is sheet row
300". That is correct for one version of the sheet and silently wrong for the next. In the
synthetic table the year blocks have different lengths (8 or 9 rows), and the grader re-runs
your file on a copy with a 2023 block added at the top, which moves every other row down by
nine.

**The SQL idiom.** Select by what the row **is**, its year and its label:

- **`REPLACE(agic, '  ', ' ')`** in a CTE. The sheet writes labels with two spaces around
  "to" and "and" (`'5,000,000  and  over'`), but not consistently (one synthetic 2019
  label has a single space, as one real label does). Collapsing double spaces first lets
  the rest of the query use normal labels. Note what `REPLACE` does: it replaces
  non-overlapping pairs left to right, so three spaces become two, not one. It works here
  because the sheet never has more than two.
- **`CASE agic WHEN ... THEN ... END`**, the "simple" form of `CASE` (compare one
  expression with several values), maps each label to `5m_plus`, `5m_to_10m` or
  `10m_plus`. A label not listed gives NULL.
- **`WHERE agic IN (...)`** keeps only those three labels. Because the `WHERE` uses the
  same list as the `CASE`, no row with a NULL bracket can get through.

`row_num` stays in the output, as information (which sheet row each value came from),
and to sort; it is never used to choose.

**Course modules.** 4 (CTE) and 1 (`CASE`, `IN`). **Beyond the course.** `REPLACE`, and
the simple form of `CASE`.

## Beyond the course, in one place

| Idiom | Where | What it does |
|---|---|---|
| `DROP TABLE IF EXISTS x;` | every block | makes the file safe to re-run |
| `CREATE TABLE x AS SELECT ...` | every block | stores a result for the next block and for R / Python |
| `CREATE INDEX ... ON t (date)` | Q1 | speeds up later filters and groups by date |
| `IN (SELECT ...)`, `NOT IN (SELECT ...)` | Q1 | id lists read from a table |
| condition in a `LEFT JOIN`'s `ON` | Q2 | joins some rows, keeps all rows |
| `IN (...)`, `NOT IN (...)` literal lists | Q2, Q4 | pick or drop a handful of dates |
| `SUM(x) OVER ()` | Q3 | grand total on every row |
| `UNION ALL` | Q3 | stacks a total row under the groups |
| `ORDER BY (col = 'Total')` | Q3 | puts one labelled row last |
| `NULLIF(x, 0)` | not used | the zero-denominator guard, unnecessary here |
| no dot-commands | the whole file | the file runs from Python and R, not only the CLI |
| `ROW_NUMBER() OVER (PARTITION BY key ORDER BY row_num)` | Q5 | keeps the first copy of each row, R's `!duplicated()` |
| `NOT IN (SELECT ...)` inside a CTE | Q5 | an exclusion list as one step of a chain |
| `/ 1000.0` | Q6 | floating-point division whatever the column type |
| `WHERE col IS NOT NULL` before `GROUP BY` | Q7 | no stray NULL group from a footnote row |
| `REPLACE(text, '  ', ' ')` | Q8 | normalises labels before matching them |
| `CASE col WHEN 'a' THEN ... END` | Q8 | maps labels to short keys |

## NULL semantics, all in one place

| Expression | Over values 5, NULL, 7 | Over an all-NULL group |
|---|---|---|
| `SUM(x)` | 12 (skips NULL) | NULL |
| `COALESCE(SUM(x), 0)` | 12 | 0 (R's `sum(na.rm = TRUE)`) |
| `COUNT(*)` | 3 (counts rows) | number of rows |
| `COUNT(x)` | 2 (counts non-NULL values) | 0 |
| `AVG(x)` | 6 (12 / 2, not 12 / 3) | NULL |
| `x >= 1000` in `WHERE` | NULL rows dropped | all dropped |
| `x NOT IN (SELECT ...)` with a NULL in the list | false or NULL for every row | zero rows kept |
| `PARTITION BY x` or `GROUP BY x` | NULLs form one group | one group |
| `a.x = b.x` in a join | never true when either side is NULL | no matches |

The real file uses `COUNT(*)` for `n_billionaires`, which is right because Q1 already
dropped rows with NULL worth. `COUNT(forbes_public_worth)` would count only people with a
split, a different number.

## Checking against the authors' sheet, and vintage gaps

The real check (`py/check_rtb_ca.py` in `opa-prop40`) never compares files line by line. It
aligns both sides on a key (`forbes_id` within each date for the lists, `industries` for the
industry table, `date` for the daily table), then reports four things: rows only in ours,
rows only in theirs, the largest absolute difference in each numeric column (pass if below
`1e-6`), and text cells that differ. Counts must match exactly. `module-06/check.py` does the
same for your answers, against `module-06/expected/`.

**What matched.** In the final run, every target: the seven year-end lists (same ids, same
text, worths within about 1e-12), the industry table, the daily aggregate on every date the
authors' sheet has, the year-end totals in the public workbook to their 2-decimal rounding,
and the R and Python exports of the same SQL to exactly zero difference.

**What did not, and why.** Two things, and neither was a logic error.

1. An earlier version of the check was off by one person on the 2026-01-01 list. The
   authors' saved sheet included one id that the override list in their shared script did
   not. The sheet and the script were different versions (vintages) of the same work. The
   fix was to follow the list behind the published workbook, after which every target
   matched.
2. The SQL output has 25 dates that the authors' daily sheet does not. The check reports
   them and does not count them as failures, because a reproduction has to agree on the
   dates both sides have. Extra dates mean the data file and the sheet were saved at
   different times.

**The lesson.** A reproduction compares your output with a snapshot of someone else's work.
When the numbers disagree, first ask whether the inputs or the code version differ. Call it a
vintage gap only when you can name the version difference (one id, a set of dates, a column
the sheet does not have). If you cannot, call it unexplained and keep looking. Never widen a
tolerance to make a mismatch go away.

## The drill

1. `Rscript data/build_rtb_sample.R` (once; it also writes `module-06/expected/`).
2. Write the eight blocks in `module-06/exercise.sql` (or a copy): Q1 to Q4 for part 1,
   Q5 to Q8 for part 2.
3. `python module-06/check.py module-06/exercise.sql` prints one line per block. A blank file
   fails all eight; `module-06/solution.sql` passes all eight. Q7 and Q8 are graded twice,
   the second time on a sheet with one more year at the top.
4. Listen to `module-06/lesson/sql-in-a-real-replication.m4b`, and take the walking quiz
   (link in `module-06/quiz/README.md`).
5. Then read the real files (`01_rtb_ca.sql`, `02_data_sec_agg.sql`, `03_ftb_b4a.sql`) and the README in
   [`opa-prop40/bsz-analysis/sql/`](https://github.com/fhoces/opa-prop40/tree/main/bsz-analysis/sql),
   which also documents how it was checked against the authors' sheets.
