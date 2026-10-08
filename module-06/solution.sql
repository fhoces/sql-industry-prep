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
-- Everything else, including the comments, is the real file. Part 2 at the
-- bottom (Q5 to Q8) adds the blocks of two more real files, 02_data_sec_agg.sql
-- and 03_ftb_b4a.sql; its own banner lists their inputs and outputs.
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


-- =============================================================================
-- Part 2: two files of the paper's second step (public workbook to tables)
-- =============================================================================
--
-- Q5 and Q6 are 02_data_sec_agg.sql, and Q7 and Q8 are 03_ftb_b4a.sql, from
-- the same folder of fhoces/opa-prop40. In the real files each one numbers
-- its own blocks Q1 and Q2; here they continue as Q5 to Q8. The code is the
-- real code; the comments are the real comments, shortened, with the
-- excluded person's id left out (the course's exclusion table holds an
-- invented id).
--
-- Inputs (in data/rtb_sample.sqlite, built by data/build_rtb_sample.R):
--   data_sec_all          one row per billionaire and year, in sheet order
--                         (row_num), money in $ million, blank cells NULL
--   data_sec_agg_exclude  forbes_id values left out of every aggregate
--   ftb_b4a               one row per income bracket and taxable year:
--                         sheet row (row_num), the year, the bracket label
--                         (agic), and four money columns in $
--
-- Outputs:
--   data_sec_all_kept     the rows that count (intermediate)
--   data_sec_agg          one row per year: the count n and 27 sums in $ billion
--   ftb_b4a_year          one row per taxable year: number of brackets and four sums
--   ftb_b4a_top           one row per taxable year and top bracket
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q5. The rows that count (intermediate table)  [02_data_sec_agg.sql, Q1]
--     Course: module 4 (CTE chain, NOT IN (SELECT ...)), module 5 (window
--     function ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...))
--     Beyond the course: DROP TABLE IF EXISTS, CREATE TABLE AS.
--
--     Two filters, in the order the R code applied them:
--       * kept: drop the ids on the exclusion table. NOT IN (SELECT ...)
--         would drop every row if the subquery returned a NULL id; the
--         loaders never write one.
--       * numbered / WHERE copy_num = 1: drop exact re-pastes. The sheet
--         repeats a four-row block of 2025 rows at its tail. A row counts as a
--         copy when an earlier row (lower row_num) has the same year,
--         forbes_id and forbes_worth. This is R's
--         !duplicated(df[c("year", "forbes_id", "forbes_worth")]), which
--         also keeps the first occurrence. Two rows with the same id and year
--         but a different worth (two separately tracked Forbes amounts) are
--         both kept. PARTITION BY puts NULL worths in one group, as
--         duplicated() treats two NAs as equal.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS data_sec_all_kept;
CREATE TABLE data_sec_all_kept AS
WITH kept AS (
  SELECT *
  FROM data_sec_all
  WHERE forbes_id NOT IN (SELECT forbes_id FROM data_sec_agg_exclude)
),
numbered AS (
  SELECT
    kept.*,
    ROW_NUMBER() OVER (
      PARTITION BY year, forbes_id, forbes_worth
      ORDER BY row_num
    ) AS copy_num
  FROM kept
)
SELECT *
FROM numbered
WHERE copy_num = 1;


-- -----------------------------------------------------------------------------
-- Q6. Yearly count and sums, in $ billion  [02_data_sec_agg.sql, Q2]
--     Course: module 3 (GROUP BY with COUNT and SUM), module 1 (COALESCE)
--
--     The R code was group_by(year) |> summarise(n = n(), across(cols,
--     \(x) sum(x, na.rm = TRUE) / 1000)). Here it is one GROUP BY with one
--     SUM per column, in the column order of the data_sec_agg sheet. Dividing
--     by 1000.0 (not 1000) keeps the division in floating point.
--
--     NULLs: SUM skips NULL, as R's sum(..., na.rm = TRUE) does. A year where
--     every value of a column is NULL would give NULL in SQL and 0 in R, so
--     each sum is wrapped in COALESCE(..., 0).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS data_sec_agg;
CREATE TABLE data_sec_agg AS
SELECT
  year,
  COUNT(*)                                          AS n,
  COALESCE(SUM(forbes_worth), 0) / 1000.0           AS forbes_worth,
  COALESCE(SUM(forbes_public_worth), 0) / 1000.0    AS forbes_public_worth,
  COALESCE(SUM(purchase), 0) / 1000.0               AS purchase,
  COALESCE(SUM(sale), 0) / 1000.0                   AS sale,
  COALESCE(SUM(kg), 0) / 1000.0                     AS kg,
  COALESCE(SUM(kg_long), 0) / 1000.0                AS kg_long,
  COALESCE(SUM(kg_short), 0) / 1000.0               AS kg_short,
  COALESCE(SUM(option_profit), 0) / 1000.0          AS option_profit,
  COALESCE(SUM(noneq_comp), 0) / 1000.0             AS noneq_comp,
  COALESCE(SUM(ordinary_income), 0) / 1000.0        AS ordinary_income,
  COALESCE(SUM(kg_taxable), 0) / 1000.0             AS kg_taxable,
  COALESCE(SUM(dividend), 0) / 1000.0               AS dividend,
  COALESCE(SUM(fiscal_income), 0) / 1000.0          AS fiscal_income,
  COALESCE(SUM(donation), 0) / 1000.0               AS donation,
  COALESCE(SUM(donation_deductible), 0) / 1000.0    AS donation_deductible,
  COALESCE(SUM(income_taxable), 0) / 1000.0         AS income_taxable,
  COALESCE(SUM(ca_income_tax), 0) / 1000.0          AS ca_income_tax,
  COALESCE(SUM(fed_ordinary_income_tax), 0) / 1000.0 AS fed_ordinary_income_tax,
  COALESCE(SUM(fed_preferential_tax), 0) / 1000.0   AS fed_preferential_tax,
  COALESCE(SUM(fed_income_tax), 0) / 1000.0         AS fed_income_tax,
  COALESCE(SUM(fiscal_income_tax), 0) / 1000.0      AS fiscal_income_tax,
  COALESCE(SUM(sales_tax), 0) / 1000.0              AS sales_tax,
  COALESCE(SUM(w_txt), 0) / 1000.0                  AS w_txt,
  COALESCE(SUM(w_tax_ppent), 0) / 1000.0            AS w_tax_ppent,
  COALESCE(SUM(w_pi), 0) / 1000.0                   AS w_pi,
  COALESCE(SUM(total_tax), 0) / 1000.0              AS total_tax,
  COALESCE(SUM(economic_income), 0) / 1000.0        AS economic_income
FROM data_sec_all_kept
GROUP BY year
ORDER BY year;


-- -----------------------------------------------------------------------------
-- Q7. Yearly totals over all AGI brackets  [03_ftb_b4a.sql, Q1]
--     Course: module 3 (GROUP BY with COUNT and SUM), module 1 (WHERE ...
--     IS NOT NULL, COALESCE)
--
--     Replaces sum(column[first_row:last_row], na.rm = TRUE), one call per
--     year and column. GROUP BY taxable_year does all years and all four
--     columns at once. n_brackets is there to check the grouping (in the
--     course table: 9 rows for 2021 and 2022, 8 for every earlier year).
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS ftb_b4a_year;
CREATE TABLE ftb_b4a_year AS
SELECT
  taxable_year,
  COUNT(*)                          AS n_brackets,
  COALESCE(SUM(all_returns), 0)     AS all_returns,
  COALESCE(SUM(ca_agi), 0)          AS ca_agi,
  COALESCE(SUM(taxable_income), 0)  AS taxable_income,
  COALESCE(SUM(total_tax), 0)       AS total_tax
FROM ftb_b4a
WHERE taxable_year IS NOT NULL
GROUP BY taxable_year
ORDER BY taxable_year;


-- -----------------------------------------------------------------------------
-- Q8. The top-bracket rows, with a short bracket key  [03_ftb_b4a.sql, Q2]
--     Course: module 4 (CTE), module 1 (CASE WHEN, IN (...) list, REPLACE)
--
--     The sheet's labels have two spaces around "to" and "and"
--     ('5,000,000  and  over'). The labelled CTE collapses double spaces
--     with REPLACE so the labels can be written normally below. A CASE then
--     maps each label to a short key:
--       5m_plus    $5,000,000 and over        (one row per year up to 2020)
--       5m_to_10m  $5,000,000 to $9,999,999   (2021 and 2022)
--       10m_plus   $10,000,000 and over       (2021 and 2022)
--     Every other bracket is dropped by the WHERE clause.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS ftb_b4a_top;
CREATE TABLE ftb_b4a_top AS
WITH labelled AS (
  SELECT
    row_num,
    taxable_year,
    REPLACE(agic, '  ', ' ') AS agic,
    all_returns,
    ca_agi,
    taxable_income,
    total_tax
  FROM ftb_b4a
  WHERE taxable_year IS NOT NULL
)
SELECT
  taxable_year,
  CASE agic
    WHEN '5,000,000 and over'       THEN '5m_plus'
    WHEN '5,000,000 to 9,999,999'   THEN '5m_to_10m'
    WHEN '10,000,000 and over'      THEN '10m_plus'
  END AS bracket,
  row_num,
  all_returns,
  ca_agi,
  taxable_income,
  total_tax
FROM labelled
WHERE agic IN ('5,000,000 and over', '5,000,000 to 9,999,999', '10,000,000 and over')
ORDER BY taxable_year, row_num;
