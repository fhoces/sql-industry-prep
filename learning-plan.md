# Intro to SQL

A 6-module SQL refresher built around interview-style questions for an
applied policy economist role at a transportation network company. Every
module is concept → code → 3–6 interview questions you should be able to
write from a cold start in under two minutes each.

**Time budget: ~7 hours** (module 6 adds about 2 hours, including the 36-minute audio lesson)

| # | Module | Concepts | Sample interview questions |
|---|--------|----------|-----|
| 1 | SELECT, WHERE, Aggregates | Filtering, sorting, aggregates, dates, CASE WHEN | Top-10 longest trips, hourly avg fare, monthly conversion rate |
| 2 | JOINs | INNER, LEFT, anti-join, multi-table chains, common bugs | Unique drivers per rider, driver tenure attached to each ride, never-served-from-X |
| 3 | GROUP BY, HAVING, Conversion Funnels | Per-group dashboards, compare-to-global, funnels, cohort retention | City dashboards, funnel analysis, cohort tables, bottom-N per group |
| 4 | Subqueries and CTEs | Scalar / table / correlated subqueries, multi-step CTEs, first/last patterns | Each rider's first ride, multi-step funnel as CTE chain, active in each of last N weeks |
| 5 | Window Functions | OVER, PARTITION BY, ranking, LAG/LEAD, frames, gaps and islands | Top-N per group, time since previous event, rolling 7-day average, longest streak |
| 6 | SQL in a Real Replication | Reading and reproducing a real pipeline step: `DROP TABLE IF EXISTS` / `CREATE TABLE AS`, residency overrides via `IN (SELECT ...)` / `NOT IN (SELECT ...)`, one long table instead of seven, a condition in a `LEFT JOIN`'s `ON`, a `UNION ALL` total row, `SUM(CASE WHEN ...)`, NULL in `SUM` vs `COUNT`, no dot-commands, checking against an answer key and vintage gaps; part 2: `ROW_NUMBER() OVER (PARTITION BY ...)` to drop re-pasted rows, `NOT IN` in a CTE, yearly sums with `COALESCE` and `COUNT(*)`, `REPLACE` + `CASE` to pick rows by label | Rebuild the eight tables of `01_rtb_ca.sql`, `02_data_sec_agg.sql` and `03_ftb_b4a.sql` on synthetic data until `check.py` passes every block |

## How to use this repo

1. Build the SQLite database **once**: `Rscript data/setup.R`
2. Read each module's `concepts.md`
3. Walk through `slides.Rmd` (or the rendered `slides.html`)
4. Drill the questions in `exercise.sql` against the database with
   `sqlite3 data/uber.sqlite < module-XX/exercise.sql`
5. Re-write each query from memory until you can do it in under 2 minutes

The schema mirrors the kinds of tables you'd see at any rideshare:

```
cities         (city_id, name, country, lead_pm)
neighborhoods  (nbhd_id, city_id, name, pct_minority, median_income)
drivers        (driver_id, signup_date, gender, home_nbhd_id)
riders         (rider_id, signup_date, home_nbhd_id)
requests       (request_id, rider_id, pickup_nbhd_id, dropoff_nbhd_id,
                requested_at, accepted, accepted_by_driver_id)
rides          (ride_id, request_id, driver_id, started_at, ended_at,
                distance_mi, fare_usd, surge_mult, rider_rating)
```

## Dialect notes

The exercises run on **SQLite** (because it's a single file with no
server). The query patterns work in **PostgreSQL**, **MySQL**, and any
modern dialect with minor syntactic differences:

- Date functions: `strftime` vs `DATE_TRUNC` / `EXTRACT`
- Window function support: SQLite supports them since 3.25
- `BOOLEAN` vs `INTEGER`: SQLite uses 0/1
- `RANGE BETWEEN INTERVAL ...`: not in SQLite, use `ROWS BETWEEN`

If your interviewer uses a specific dialect, ask. The patterns are the
same; the syntax is slightly different.

Say **"start module 1"** to begin.
