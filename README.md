# Intro to SQL

A 6-module SQL refresher built around interview-style questions for a
ride-sharing analytical role. Every module is concept → code → 3–6
interview questions you should be able to write from a cold start.

> **Live slides:** *(set up after enabling GitHub Pages on this repo)*

## Why this exists

Most SQL tutorials are general-purpose and slow. This one is targeted:
the goal is to walk into a 30-minute SQL portion of a tech-economics
interview and be able to write any of the canonical analytical queries
without thinking about syntax.

The questions are ride-sharing themed because that's the most common
domain for the interview slot it's preparing you for, but the patterns
generalize to any platform with a similar relational schema.

## How to use this repo

```bash
# 1. Build the synthetic SQLite database (once)
Rscript data/setup.R

# 2. Read the concepts file for each module
open module-01/concepts.md

# 3. Walk through the slide deck
open module-01/slides.html

# 4. Drill the queries
sqlite3 data/uber.sqlite < module-01/exercise.sql

# 5. Re-write each query from memory until you can do it in 2 minutes
```

The schema:

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

## Cheat sheet

One-page landscape reference card covering all five modules — execution-order palette, JOIN patterns, GROUP BY / aggregates, subqueries & CTEs, window functions, plus an all-modules capstone query: **[sql-cheatsheet.pdf](sql-cheatsheet.pdf)** ([LaTeX source](sql-cheatsheet.tex)).

## Modules

| # | Module | Topics | Sample interview questions |
|---|--------|--------|---|
| **1** | [SELECT, WHERE, Aggregates](module-01/) | Filter, sort, aggregate, CASE WHEN, dates | Top-10 longest trips, hourly avg fare, monthly conversion rate |
| **2** | [JOINs](module-02/) | INNER, LEFT, anti-join, multi-table chains | Unique drivers per rider, driver tenure attached to each ride |
| **3** | [GROUP BY, HAVING, Conversion Funnels](module-03/) | Per-group metrics, compare-to-global, funnels, cohort retention | City dashboards, funnel analysis, cohort tables |
| **4** | [Subqueries and CTEs](module-04/) | Scalar / table / correlated subqueries, multi-step CTEs | Each rider's first ride, multi-step funnel as CTE chain |
| **5** | [Window Functions](module-05/) | OVER, PARTITION BY, ranking, LAG/LEAD, gaps and islands | Top-N per group, rolling avg, longest streak |
| **6** | [SQL in a Real Replication](module-06/) | One step of a real pipeline: `CREATE TABLE AS`, override tables, a condition in `ON`, `UNION ALL` total rows, conditional sums, NULL semantics, checking against an answer key | Rebuild four tables of a real query on a synthetic billionaire panel; graded by `check.py` |

## Module 6: a different data set, and two new artifact types

Module 6 breaks the ride-sharing convention on purpose. It reproduces one real
pipeline step (`01_rtb_ca.sql` in
[fhoces/opa-prop40](https://github.com/fhoces/opa-prop40)) on a synthetic
billionaire panel in the shape of the real one, built by
`Rscript data/build_rtb_sample.R` (it writes `data/rtb_sample.sqlite` and the
reference results in `module-06/expected/`). Grade your answers with
`python module-06/check.py module-06/exercise.sql` (needs pandas).

It also introduces two artifact types that no earlier module has:

- **`module-06/lesson/`**: an audio lesson, `sql-in-a-real-replication.m4b`
  (chaptered, about 30 minutes, for Apple Books), narrated from the text
  sections in `lesson/text/`.
- **`module-06/quiz/`**: a walking quiz, read aloud and adaptive, published
  as a claude.ai Artifact: https://claude.ai/artifact/HRQfx89mVuNM8puPenTE8R (private; the rebuild steps are in
  [`module-06/quiz/README.md`](module-06/quiz/README.md)).

The scripts that build both live in `tools/quiz/` (copied from the
book-summaries project, adapted for code questions and PNG covers).

## Dependencies

To build the database and render slides locally:

```r
install.packages(c("DBI", "RSQLite", "tidyverse", "rmarkdown", "xaringan"))
```

The exercise files are pure SQL and only need the `sqlite3` CLI.

## Companion courses

This is part of a small set of refreshers for the same applied
policy-economist interview prep:

- [discrimination-econ-refresher](https://github.com/fhoces/discrimination-econ-refresher) — labor-econ literature on discrimination
- [ml-discrimination-refresher](https://github.com/fhoces/ml-discrimination-refresher) — ML fundamentals + algorithmic fairness
- [python-for-r-users](https://github.com/fhoces/python-for-r-users) — pandas + statsmodels for someone coming from R
