-- =============================================================================
-- Module 6: SQL in a real replication (reference solution)
-- =============================================================================
--
-- This is 01_rtb_ca.sql from github.com/fhoces/opa-prop40
-- (bsz-analysis/sql/), the query that turns daily Forbes real-time
-- billionaire snapshots into the California lists of a published paper.
-- The code below is the real file with two changes for the course:
--   1. The banner is shorter.
--   2. The four "top 4" ids in Q4 are the invented ids of the synthetic
--      panel's four largest California fortunes.
-- Everything else, including the comments, is the real file.
--
-- Inputs (in data/rtb_sample.sqlite, built by data/build_rtb_sample.R):
--   rtb_all_combined         one row per (date, forbes_id), worth in $ million,
--                            missing values stored as NULL
--   rtb_ca_cik               forbes_id to SEC CIK, for the 2026-01-01 list
--   rtb_residency_overrides  ids counted as California residents whatever the
--                            state field says (rule = 'include') or never
--                            counted (rule = 'exclude')
--
-- Outputs (tables in the same database):
--   rtb_ca_all                  intermediate: every CA billionaire-day
--   rtb_ca_eoy                  the seven year-end lists, stacked
--   rtb_ca_2026_01_01_industry  wealth by industry on 2026-01-01
--   rtb_ca_aggregate            count and wealth totals per date
--
-- Grade it (it must pass every block):
--   python module-06/check.py module-06/solution.sql
--
-- Two deliberate differences from the house style of modules 1 to 5:
--   1. No sqlite3 dot-commands (.headers, .mode). Python runs this file with
--      sqlite3.Connection.executescript and R runs it statement by statement
--      with DBI::dbExecute; dot-commands only work in the sqlite3 CLI.
--   2. Each block creates a table instead of printing a result set
--      (DROP TABLE IF EXISTS x; CREATE TABLE x AS ...;). Both languages then
--      read the result back with the same SELECT.
--
-- Money: the input is in $ million. The industry and daily tables report
-- $ billion, so this file divides by 1000.
--
-- NULLs: SUM skips NULL, which is what R's sum(..., na.rm = TRUE) does. The
-- one difference is a group where every value is NULL: SQL returns NULL and
-- R returns 0. COALESCE(SUM(x), 0) reproduces R there.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1. California billionaires on every date (intermediate table)
--     Course: module 1 (WHERE, AND / OR, NULL in comparisons), module 4
--     (subqueries: IN (SELECT ...) and NOT IN (SELECT ...))
--     Beyond the course: DROP TABLE IF EXISTS, CREATE TABLE AS, CREATE INDEX.
--
--     Replaces a chain of filters in the authors' code: worth of at least
--     $1 billion; then Forbes state "California" or an id on the override
--     table's include list; then not an id on its exclude list. Here they are
--     one WHERE clause.
--
--     NULL behaviour matches R's filter(): a row with NULL forbes_worth fails
--     the first test, and a row with NULL state passes only through the
--     include list. Both are dropped in R too. NOT IN (SELECT ...) would drop
--     every row if the subquery returned a NULL id, so the loader refuses an
--     override row without an id.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS rtb_ca_all;
CREATE TABLE rtb_ca_all AS
SELECT
  date,
  forbes_id,
  forbes_name,
  state,
  country_citizenship,
  source,
  industries,
  forbes_worth,
  forbes_public_worth,
  forbes_private_worth
FROM rtb_all_combined
WHERE forbes_worth >= 1000
  AND (
        state = 'California'
        OR forbes_id IN (SELECT forbes_id
                         FROM rtb_residency_overrides
                         WHERE rule = 'include')
      )
  AND forbes_id NOT IN (SELECT forbes_id
                        FROM rtb_residency_overrides
                        WHERE rule = 'exclude');

CREATE INDEX idx_rtb_ca_all_date ON rtb_ca_all (date);


-- -----------------------------------------------------------------------------
-- Q2. The seven year-end lists, in one long table
--     Course: module 1 (WHERE), module 2 (LEFT JOIN)
--     Beyond the course: IN (...) with a literal list; an extra condition in
--     the ON clause of a LEFT JOIN.
--
--     The authors' code filters one date at a time, sorts by worth
--     descending, and writes seven data frames to seven sheets. A database
--     keeps one table with a date column instead. The seven sheets are then
--     just WHERE date = '...' slices, and a new year is a new value in the IN
--     list rather than a new block of code.
--
--     The 2026-01-01 snapshot is the "2025" list (the data have no
--     2025-12-31 snapshot; 2025-12-30 is followed by 2026-01-01). Only that
--     list gets sec_cik. Putting the date test in the ON clause, not in
--     WHERE, keeps every row of the other six lists and leaves their sec_cik
--     NULL. A WHERE test would drop them.
--
--     ORDER BY reproduces the sheets' row order (worth descending); forbes_id
--     breaks ties so the order is deterministic.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS rtb_ca_eoy;
CREATE TABLE rtb_ca_eoy AS
SELECT
  ca.date,
  ca.forbes_id,
  ca.forbes_name,
  ca.state,
  ca.country_citizenship,
  ca.source,
  ca.industries,
  ca.forbes_worth,
  ca.forbes_public_worth,
  ca.forbes_private_worth,
  cik.cik AS sec_cik
FROM rtb_ca_all ca
LEFT JOIN rtb_ca_cik cik
  ON  cik.forbes_id = ca.forbes_id
  AND ca.date = '2026-01-01'
WHERE ca.date IN (
        '2019-12-31', '2020-12-31', '2021-12-31', '2022-12-31',
        '2023-12-31', '2024-12-31', '2026-01-01'
      )
ORDER BY ca.date, ca.forbes_worth DESC, ca.forbes_id;


-- -----------------------------------------------------------------------------
-- Q3. Wealth by industry on 2026-01-01, with a Total row
--     Course: module 3 (GROUP BY), module 4 (CTE chain, UNION ALL to stack
--     rows), module 5 (a window function, SUM(...) OVER ()), module 1
--     (COALESCE)
--     Beyond the course: an empty OVER () as a grand total; ORDER BY on a
--     true/false expression to put the Total row last.
--
--     The authors' code summarises per industry, adds the share of the grand
--     total in a second step, builds the Total row as a separate one-row
--     summary, and binds the two by rows.
--       * by_industry: the per-industry sums ($ billion). The share of public
--         wealth is a ratio of the two sums.
--       * with_share: SUM(forbes_worth) OVER () is the total over all rows of
--         by_industry, the SQL form of an ungrouped mutate() after
--         summarise() in dplyr.
--       * total_row: the same sums over the whole list, labelled 'Total'.
--       * stacked: UNION ALL puts the Total row under the industry rows.
--     SQLite only lets a UNION be sorted by its output columns, so the final
--     SELECT sorts the stacked CTE instead: (industries = 'Total') is 0 for
--     industry rows and 1 for the Total row, so the Total sorts last.
--
--     No division by zero is possible: every group has worth >= $1 billion
--     because Q1 kept only rows with forbes_worth >= 1000.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS rtb_ca_2026_01_01_industry;
CREATE TABLE rtb_ca_2026_01_01_industry AS
WITH list_2026 AS (
  SELECT industries, forbes_worth, forbes_public_worth
  FROM rtb_ca_eoy
  WHERE date = '2026-01-01'
),
by_industry AS (
  SELECT
    industries,
    COUNT(*)                                       AS n_billionaires,
    COALESCE(SUM(forbes_public_worth), 0) / 1000.0 AS forbes_public_worth,
    COALESCE(SUM(forbes_worth), 0) / 1000.0        AS forbes_worth
  FROM list_2026
  GROUP BY industries
),
with_share AS (
  SELECT
    industries,
    n_billionaires,
    forbes_public_worth,
    forbes_worth,
    forbes_public_worth / forbes_worth          AS fraction_public_worth,
    forbes_worth / SUM(forbes_worth) OVER ()    AS fraction_forbes_worth
  FROM by_industry
),
total_row AS (
  SELECT
    'Total'                                        AS industries,
    COUNT(*)                                       AS n_billionaires,
    COALESCE(SUM(forbes_public_worth), 0) / 1000.0 AS forbes_public_worth,
    COALESCE(SUM(forbes_worth), 0) / 1000.0        AS forbes_worth
  FROM list_2026
),
stacked AS (
  SELECT * FROM with_share
  UNION ALL
  SELECT
    industries,
    n_billionaires,
    forbes_public_worth,
    forbes_worth,
    forbes_public_worth / forbes_worth          AS fraction_public_worth,
    forbes_worth / forbes_worth                 AS fraction_forbes_worth
  FROM total_row
)
SELECT *
FROM stacked
ORDER BY (industries = 'Total'), fraction_forbes_worth DESC, industries;


-- -----------------------------------------------------------------------------
-- Q4. Daily count and wealth of California billionaires
--     Course: module 3 (GROUP BY), module 1 (SUM(CASE WHEN ...) filtered
--     aggregate)
--     Beyond the course: NOT IN (...) and IN (...) with a literal list.
--
--     Per date: the number of CA billionaires, total worth, the worth of the
--     four people the paper calls the top 4 (here, invented ids), and
--     private worth, all in $ billion. The authors' code picks the top 4 by subsetting the worth
--     vector inside the sum; the CASE expression here returns their worth and
--     NULL for everyone else, and SUM skips the NULLs.
--
--     Three snapshot dates are left out, as in the authors' code.
--
--     Column order: the four columns of the authors' sheet first, then
--     forbes_private_worth, which the authors' current code computes but
--     their sheet does not have.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS rtb_ca_aggregate;
CREATE TABLE rtb_ca_aggregate AS
SELECT
  date,
  COUNT(*)                                        AS n_billionaires,
  COALESCE(SUM(forbes_worth), 0) / 1000.0         AS forbes_worth_total,
  COALESCE(SUM(CASE
                 WHEN forbes_id IN ('marlo-zanderfell', 'calla-vantongeren',
                                    'xavi-juniper', 'quill-silverbrook')
                 THEN forbes_worth
               END), 0) / 1000.0                  AS forbes_worth_top4,
  COALESCE(SUM(forbes_private_worth), 0) / 1000.0 AS forbes_private_worth
FROM rtb_ca_all
WHERE date NOT IN ('2022-07-18', '2026-03-29', '2026-03-30')
GROUP BY date
ORDER BY date;
