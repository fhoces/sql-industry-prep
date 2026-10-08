# Quiz questions: SQL in a Real Replication

Generated from `quiz.json` by `tools/quiz/make_clips.py`; do not edit by hand. Each concept has three levels: Warm-up (1), Core (2) and Deep (3). Questions marked (code) show a code block on the quiz page; the audio says "Look at the code on the screen" instead of reading it. The answer key is at the bottom.

## 1. Filter order and the threshold
**Warm-up.** (code) Look at the code on the screen. Worth is stored in millions of dollars. What does the number one thousand in the first line stand for?

```sql
WHERE forbes_worth >= 1000
  AND (state = 'California'
       OR forbes_id IN (
            SELECT forbes_id
            FROM rtb_residency_overrides
            WHERE rule = 'include'))
```

- A) One billion dollars, the line a person must reach to count as a billionaire
- B) One thousand dollars, a floor that removes rows with placeholder worth values
- C) The top one thousand people by worth on each snapshot date
- D) One trillion dollars, since the later tables report their totals in billions

**Core.** Block one joins the threshold, the state test and the exclude test with AND. If you reorder the three, what happens to the result?
- A) Rows are filtered in sequence, so putting the cheapest test first changes which rows survive
- B) The exclude test must come last, or excluded people slip back in through the state test
- C) Nothing changes. They form one true or false test per row, so their order does not matter
- D) The threshold must come first, or people below one billion pass through the include list

**Deep.** (code) Look at the code on the screen. The parentheses around the OR are gone. Which rows does this version wrongly keep?

```sql
WHERE forbes_worth >= 1000
  AND state = 'California'
  OR forbes_id IN (
       SELECT forbes_id
       FROM rtb_residency_overrides
       WHERE rule = 'include')
```

- A) Californians worth less than one billion, because OR is evaluated before AND
- B) Override includes worth less than one billion dollars, because AND binds before OR
- C) None. AND and OR have equal precedence, so SQL reads the conditions left to right
- D) Rows with a null state, because removing the parentheses makes the state test unknown

## 2. Residency overrides
**Warm-up.** What does a row with the rule include in the residency override table do?
- A) It adds that person to the panel on dates when Forbes left them out
- B) It keeps that person even when their worth falls below one billion dollars
- C) It marks that person's state field as checked, so the query trusts it
- D) It counts that person as Californian, whatever their state field says

**Core.** (code) Look at the code on the screen. Suppose the override file gains a row with a blank id, loaded as null, and the rule exclude. What happens to block one's result?

```sql
AND forbes_id NOT IN (
      SELECT forbes_id
      FROM rtb_residency_overrides
      WHERE rule = 'exclude')
```

- A) It keeps no rows at all, because NOT IN with a null in its list is never true
- B) Nothing changes, because NOT IN skips null values in its list the way SUM does
- C) It keeps every row, because a null in the list makes the whole condition true
- D) It drops only people whose own id is null, and the panel has none of those

**Deep.** Why does the real project keep the override ids in a separate table instead of typing them into the SQL?
- A) A subquery on a table runs faster than a typed list once the list has more than a few ids
- B) SQLite limits how many literal values an IN list may hold
- C) The ids come from confidential material, so the list stays private and the query public
- D) R and Python read typed lists differently, so a table keeps the two languages in step

## 3. Snapshot selection by exact date
**Warm-up.** (code) Look at the code on the screen. Why is the last date January 1, 2026, rather than December 31, 2025?

```sql
WHERE ca.date IN (
  '2019-12-31', '2020-12-31', '2021-12-31',
  '2022-12-31', '2023-12-31', '2024-12-31',
  '2026-01-01'
)
```

- A) The paper's 2025 list is dated at the start of the tax year, which begins on January 1
- B) The data have no December 31, 2025 snapshot, so January 1 stands in for the 2025 list
- C) December 31, 2025 is one of the three dates the query leaves out of the daily series
- D) Forbes publishes its year-end list on the first day of the following year

**Core.** Dates are stored as text, like 2019 dash 12 dash 31. Why does that format make comparing and sorting the text safe?
- A) SQLite turns any text that looks like a date into a date before it compares
- B) The dashes tell SQLite to compare each part as a separate number
- C) Text sorts like dates in any format, as long as the separator stays the same
- D) Year, month, day order with zero padding makes text order the same as date order

**Deep.** (code) Look at the code on the screen. A colleague wants to pick each year's last snapshot like this, instead of typing the dates. What would it pick for 2025?

```sql
SELECT MAX(date) AS snapshot
FROM rtb_ca_all
GROUP BY substr(date, 1, 4);
```

- A) December 30, 2025, a day earlier than the date the authors' 2025 list uses
- B) January 1, 2026, the same date that the typed list uses
- C) December 31, 2025, because MAX fills in the missing year-end date
- D) Nothing for 2025, because GROUP BY drops a year that has no December 31 row

## 4. One long table versus seven
**Warm-up.** Block two puts seven year-end lists into one table. What tells the lists apart?
- A) A list number column that block two adds to every row
- B) The sec cik column, which is filled in only on the 2026 list
- C) The date column. Each list is the set of rows with one of the seven dates
- D) The row order. Each list starts where the previous date's rows end

**Core.** (code) Look at the code on the screen. In the authors' workflow, what did a query like this one replace?

```sql
SELECT forbes_id, forbes_name, forbes_worth
FROM rtb_ca_eoy
WHERE date = '2022-12-31'
ORDER BY forbes_worth DESC;
```

- A) The R code that computed the 2022 row of the daily aggregate table, one date at a time
- B) One of seven spreadsheet sheets, each written from a filtered, sorted data frame
- C) A join between the 2022 list and the C I K table
- D) The step that removed people below one billion dollars in 2022

**Deep.** Next year the paper adds a 2026 year-end list. Given the long-table design, what changes in the SQL?
- A) A new create table block for the 2026 list, copied from the others
- B) A new column in the year-end table that holds the 2026 worth
- C) Nothing at all, because block two picks every December 31 by itself
- D) One more date in block two's IN list, and no new block of code

## 5. CREATE TABLE AS and DROP TABLE IF EXISTS
**Warm-up.** (code) Look at the code on the screen. What does the first line buy you?

```sql
DROP TABLE IF EXISTS rtb_ca_all;
CREATE TABLE rtb_ca_all AS
SELECT date, forbes_id, forbes_worth
FROM rtb_all_combined
WHERE forbes_worth >= 1000;
```

- A) The file can run twice. Each run removes the old table before rebuilding it
- B) It deletes the rows of rtb all combined that failed the threshold on the last run
- C) It stops the block if the table already exists, so old results stay safe
- D) It frees memory before the create statement, which matters for large tables

**Core.** What is the difference between a plain select and create table as select, with the same query?
- A) The second runs faster, because SQLite can skip formatting the output for the screen
- B) The first can use group by and joins, while create table as cannot
- C) The second keeps the order by, while a plain select may ignore it
- D) It stores the result as a table, so later blocks and other languages can read it

**Deep.** (code) Look at the code on the screen. Someone runs this file a second time on the same database. What happens?

```sql
CREATE TABLE rtb_ca_all AS
SELECT * FROM rtb_all_combined
WHERE forbes_worth >= 1000;

CREATE INDEX idx_rtb_ca_all_date
  ON rtb_ca_all (date);
```

- A) It replaces the old table silently, because create table as overwrites by default
- B) It appends a second copy of every row, so the table doubles in size
- C) It stops with an error, because the table rtb ca all already exists
- D) It runs, but the index is built twice, which slows down later queries

## 6. A total row with UNION ALL
**Warm-up.** In block three, what does UNION ALL do?
- A) It joins the Total row to each industry row, so every row carries the grand total
- B) It stacks the one-row Total summary under the per-industry rows
- C) It removes duplicate industry rows before the Total row is added
- D) It adds a Total column to the right of the industry columns

**Core.** (code) Look at the code on the screen. What does the empty OVER clause make this sum add up?

```sql
SELECT
  industries,
  forbes_worth,
  forbes_worth / SUM(forbes_worth) OVER ()
    AS fraction_forbes_worth
FROM by_industry;
```

- A) The grand total over every row of the C T E, the same on each row
- B) Worth within the current industry, so every fraction comes out as one
- C) Worth over the rows above the current one, which gives a running total
- D) Worth over every date in the panel, not only January 1, 2026

**Deep.** Why does the final select of block three sort first by the comparison industries equals Total?
- A) It filters the Total row out before sorting and adds it back at the end
- B) It sorts alphabetically, and Total comes after every industry name
- C) It makes SQLite sort the two halves of the union separately
- D) It is zero for industry rows and one for Total, so Total sorts after every industry

## 7. Conditional sums
**Warm-up.** (code) Look at the code on the screen. The CASE has no ELSE. What does it return for everyone outside the four ids?

```sql
SUM(CASE
      WHEN forbes_id IN ('marlo-zanderfell',
                         'calla-vantongeren',
                         'xavi-juniper',
                         'quill-silverbrook')
      THEN forbes_worth
    END)
```

- A) Zero, because a CASE with no ELSE defaults to zero inside a sum
- B) An error, because every CASE expression needs an ELSE branch
- C) Null, which SUM then skips, so only the four worths are added
- D) The person's worth, because an unmatched CASE falls through to the THEN value

**Core.** What R idiom does block four's top four column replace?
- A) Filtering to the four people first, summarising, then joining back by date
- B) Subsetting the worth vector inside the sum, by whether the id is one of the four
- C) An if else over the whole data frame, before grouping by date
- D) Ranking people by worth each day and keeping the first four

**Deep.** (code) Look at the code on the screen. On a date when none of the four ids appears, what would this column be without COALESCE?

```sql
COALESCE(SUM(CASE
  WHEN forbes_id IN ('marlo-zanderfell',
                     'calla-vantongeren',
                     'xavi-juniper',
                     'quill-silverbrook')
  THEN forbes_worth
END), 0) / 1000.0 AS forbes_worth_top4
```

- A) Null, because the sum of nothing but nulls is null
- B) Zero, because SUM over no matching rows is always zero in SQLite
- C) The date would be missing, because its group would have no rows
- D) Zero, because dividing by one thousand point zero forces a number

## 8. LEFT JOIN and a null sec_cik
**Warm-up.** On the year-end list for December 31, 2021, every sec cik is null. Why?
- A) Nobody on the 2021 list had filed with the S E C by then
- B) The C I K table has no rows for the people on the 2021 list
- C) Block one drops the C I K column for every date before 2026
- D) The join only looks up C I Ks on the January 1, 2026 rows

**Core.** (code) Look at the code on the screen. The date test moved from the ON clause into WHERE. What happens to the year-end table?

```sql
FROM rtb_ca_all ca
LEFT JOIN rtb_ca_cik cik
  ON cik.forbes_id = ca.forbes_id
WHERE ca.date IN ('2019-12-31', ...,
                  '2026-01-01')
  AND ca.date = '2026-01-01'
```

- A) Nothing changes, because ON and WHERE conditions are interchangeable in a join
- B) All seven lists survive, but every sec cik becomes null
- C) Only the 2026 list survives, because WHERE removes the other six lists after the join
- D) All seven lists survive, and every row gets a C I K, not just the 2026 list

**Deep.** On the 2026 list, one person's sec cik is null. What can you conclude?
- A) They are not American citizens, because only citizens are given a C I K
- B) They have no C I K, from a null crosswalk value or a missing crosswalk row
- C) They are on the list only through the override table, which skips the lookup
- D) Their worth fell below one billion dollars on that date

## 9. Null in SUM versus COUNT
**Warm-up.** (code) Look at the code on the screen. The column holds five, null and seven. What are the three results?

```sql
SELECT COUNT(*),
       COUNT(forbes_public_worth),
       SUM(forbes_public_worth)
FROM t;
-- forbes_public_worth holds 5, NULL, 7
```

- A) Three, two and twelve
- B) Three, three and twelve
- C) Two, two and twelve
- D) Three, two and null, because one of the values is missing

**Core.** Why does block four count billionaires with count star rather than count of public worth?
- A) Count star is faster, and the two give the same number after block one
- B) Count of a column counts distinct values, which would merge people with equal worth
- C) Count star skips rows with a null worth, which block four needs
- D) Only count star counts every billionaire. The other counts only people with a split

**Deep.** (code) Look at the code on the screen. This version drops COALESCE. What does the Sports row show, and how does that compare with R?

```sql
SELECT industries,
       SUM(forbes_public_worth) / 1000.0
         AS forbes_public_worth
FROM list_2026
GROUP BY industries;
```

- A) Zero, the same as R, because SUM skips the nulls
- B) Null, the same as R, because R's sum also returns N A for an all-missing group
- C) Null, while R's sum with N A removed would give zero for the all-missing group
- D) The Sports row disappears, because GROUP BY drops groups whose values are all null

## 10. Excluding dates with NOT IN
**Warm-up.** What does block four's where clause do with July 18, 2022, and March 29 and 30, 2026?
- A) It keeps only those three dates, which are the paper's event dates
- B) It leaves those three snapshot dates out of the daily table
- C) It sets the totals on those dates to zero, so the series has no gaps
- D) It moves those snapshots to the nearest neighbouring date

**Core.** (code) Look at the code on the screen. Block one warned that NOT IN can empty a result. Why is it safe here?

```sql
SELECT date, COUNT(*) AS n_billionaires
FROM rtb_ca_all
WHERE date NOT IN ('2022-07-18',
                   '2026-03-29',
                   '2026-03-30')
GROUP BY date
ORDER BY date;
```

- A) The list is typed into the query, so it cannot pick up a null by accident
- B) NOT IN is only dangerous on text columns, and these are dates
- C) GROUP BY runs first, so a null cannot reach the where clause
- D) SQLite removes nulls from a NOT IN list when the list is typed in

**Deep.** A learner replaces the not in list with three not-equal tests joined by OR. What does that version keep?
- A) Every date except the three, exactly like the not in list
- B) No dates at all, because no date can differ from all three at once
- C) Only the three dates, because OR reverses the meaning of not equal
- D) Every date, because any date differs from at least one of the three

## 11. Why no dot-commands
**Warm-up.** (code) Look at the code on the screen. Why is this fine at the sqlite3 prompt but not in the shared SQL file?

```sql
.headers on
.mode column

SELECT * FROM rtb_ca_aggregate LIMIT 5;
```

- A) LIMIT is not allowed in a file that Python runs with execute script
- B) Dot-commands work everywhere, but they slow down a file run from a script
- C) They are sqlite3 shell commands, which Python and R cannot run
- D) Select star is banned in shared files, because column order can change

**Core.** How does R run the shared SQL file, and why does that matter for dot-commands?
- A) It hands the whole file to the sqlite3 program, so dot-commands would work
- B) It sends each statement through D B I, which only understands SQL
- C) It translates the SQL into dplyr code first, and dot-commands have no dplyr version
- D) It calls Python's execute script, so Python's rules apply

**Deep.** (code) Look at the code on the screen. Python runs this file with execute script. What happens?

```sql
DROP TABLE IF EXISTS rtb_ca_all;
.timer on
CREATE TABLE rtb_ca_all AS
SELECT * FROM rtb_all_combined
WHERE forbes_worth >= 1000;
```

- A) The drop runs, then execute script stops with a syntax error at the dot-command
- B) Execute script skips the unknown line and builds the table as usual
- C) Nothing runs, because execute script checks the whole file before running any of it
- D) The table is built, and the timer prints how long each statement took

## 12. Checking and vintage gaps
**Warm-up.** How does the checker compare your year-end lists with the authors' sheets?
- A) It compares the two files line by line, after sorting both of them by worth descending
- B) It compares the total worth of each list, within one in a million
- C) It hashes each file and checks that the two hashes are equal
- D) It aligns rows on forbes id within each date, then compares keys and cells

**Core.** (code) Look at the code on the screen. Why compare the numbers within a tolerance rather than exactly?

```python
TOL = 1e-6
maxd = 0.0
for c in num_cols:
    diff = abs(float(ours[c]) - float(key[c]))
    maxd = max(maxd, diff)
ok = maxd <= TOL and n_ours == n_key
```

- A) The authors' sheet rounds every value to six decimal places
- B) Floating-point numbers cannot be compared with an equals sign at all
- C) Sums can differ in their last digits when programs add in a different order
- D) The tolerance absorbs small vintage gaps, such as one missing person

**Deep.** Your daily table has twenty-five dates the authors' sheet lacks, and every shared date matches. How should you report it?
- A) As a failure, because a reproduction must have exactly the same rows
- B) As a vintage gap: the data and the sheet were saved at different times, and shared dates agree
- C) As a logic error in the date filter, since the authors' code skips those dates
- D) As unexplained, because a vintage gap needs a different code version, not a different data file

## Answer key

- 1.1 Filter order and the threshold, Warm-up: **A**. Worth is in millions, so one thousand million is one billion dollars. The later tables divide by one thousand to report billions.
- 1.2 Filter order and the threshold, Core: **C**. A where clause is a single boolean expression evaluated per row. Order among AND terms changes nothing. Parentheses around the OR are what matter.
- 1.3 Filter order and the threshold, Deep: **B**. AND binds more tightly than OR, so the clause splits into worth and California, or the include list. Anyone on the include list now skips the threshold.
- 2.1 Residency overrides, Warm-up: **D**. Include means count as Californian regardless of the state on file. The threshold still applies, and no rows are added to the panel.
- 2.2 Residency overrides, Core: **A**. For a listed id NOT IN is false, and for every other id it is unknown, because the null might be that id. The where clause keeps nothing. That is why the loader refuses rows without an id.
- 2.3 Residency overrides, Deep: **C**. The query is public code, but the override list comes from the authors' confidential material. With the ids in a gitignored table, changing the list never touches the SQL.
- 3.1 Snapshot selection by exact date, Warm-up: **B**. The snapshots jump from December 30, 2025 to January 1, 2026. So the January 1 list plays the role of the 2025 year end.
- 3.2 Snapshot selection by exact date, Core: **D**. With the year first and two-digit months and days, comparing the text character by character gives the same order as the calendar. SQLite has no separate date type.
- 3.3 Snapshot selection by exact date, Deep: **A**. Grouping by the first four characters puts January 1, 2026 in the year 2026. The latest 2025 date is December 30, so the lists would no longer match the authors'.
- 4.1 One long table versus seven, Warm-up: **C**. The long table keeps a date column instead of seven separate tables. Each old sheet is a where date equals slice.
- 4.2 One long table versus seven, Core: **B**. The authors filtered one date at a time, sorted by worth, and wrote seven sheets. With one long table, each sheet is just this slice.
- 4.3 One long table versus seven, Deep: **D**. The seven lists differ only in their date, so a new list is a new value in the IN list. Block two does not find dates by itself, it reads the typed list.
- 5.1 CREATE TABLE AS and DROP TABLE IF EXISTS, Warm-up: **A**. Drop table if exists makes the file idempotent. Without it, a second run fails because the table already exists.
- 5.2 CREATE TABLE AS and DROP TABLE IF EXISTS, Core: **D**. Create table as runs the same select and saves the result. Later blocks read it, and R and Python read it back with one shared select.
- 5.3 CREATE TABLE AS and DROP TABLE IF EXISTS, Deep: **C**. Create table fails if the name is taken. That is what the drop table if exists line in the real file prevents.
- 6.1 A total row with UNION ALL, Warm-up: **B**. Union all stacks two results with the same columns, keeping every row. Plain union would also remove duplicates.
- 6.2 A total row with UNION ALL, Core: **A**. With nothing inside the over clause, the window is the whole result. It is the SQL form of an ungrouped mutate after summarise.
- 6.3 A total row with UNION ALL, Deep: **D**. A comparison is zero or one. Without it, Total, whose share is one, would sort first under the share-descending key.
- 7.1 Conditional sums, Warm-up: **C**. A case with no else returns null when nothing matches. Sum skips nulls, so the result is the four people's total.
- 7.2 Conditional sums, Core: **B**. The authors wrote sum of worth where the id is in the top four ids. A conditional sum does the same thing inside one group by.
- 7.3 Conditional sums, Deep: **A**. The date's group still has other billionaires, but the case gives null for all of them. Coalesce turns that null into zero, as R would.
- 8.1 LEFT JOIN and a null sec_cik, Warm-up: **D**. The date test sits in the on clause, so earlier rows never match, and the left join keeps them with a null. Many of those people do have C I K rows.
- 8.2 LEFT JOIN and a null sec_cik, Core: **C**. Where filters after the join, so it drops every row not dated January 1, 2026. On and where are only interchangeable for an inner join.
- 8.3 LEFT JOIN and a null sec_cik, Deep: **B**. On the 2026 rows the lookup does happen, so null means no C I K was found. The table alone cannot tell a null crosswalk value from a missing row.
- 9.1 Null in SUM versus COUNT, Warm-up: **A**. Count star counts rows, count of a column counts non-null values, and sum skips the null.
- 9.2 Null in SUM versus COUNT, Core: **D**. Count of a column skips nulls. Block one already dropped null worths, so every remaining row is a billionaire, and count star counts them all.
- 9.3 Null in SUM versus COUNT, Deep: **C**. Every public worth in Sports is null, so the SQL sum is null. R's sum with n a dot r m equals true returns zero, which is why the file wraps sums in coalesce.
- 10.1 Excluding dates with NOT IN, Warm-up: **B**. Not in with a typed list drops exactly those three dates. The reproduction follows the authors' choice.
- 10.2 Excluding dates with NOT IN, Core: **A**. The danger comes from a subquery that returns a null. Three typed dates contain no null. Dates are text here anyway, and where runs before group by.
- 10.3 Excluding dates with NOT IN, Deep: **D**. A date equal to one of the three still differs from the other two, so at least one test is true. The correct rewrite joins the three tests with AND.
- 11.1 Why no dot-commands, Warm-up: **C**. Dot headers and dot mode belong to the sqlite3 program, not to SQL. Execute script and D B I only accept SQL.
- 11.2 Why no dot-commands, Core: **B**. The R runner splits the text at each semicolon that is real code and calls D B I db execute on each statement. A dot-command would be sent to SQLite as SQL and fail.
- 11.3 Why no dot-commands, Deep: **A**. Execute script runs statements in order and stops at the first error. The drop has already run, so the table is gone and not rebuilt.
- 12.1 Checking and vintage gaps, Warm-up: **D**. Aligning on a key makes the check immune to row order and number formatting. Then rows on one side only, counts, and each cell are compared.
- 12.2 Checking and vintage gaps, Core: **C**. The real differences were about one in a trillion, from the order of addition. A missing person changes counts and fails no matter what the tolerance is.
- 12.3 Checking and vintage gaps, Deep: **B**. You can name the difference, extra dates from a later data file, and everything shared agrees. That is a vintage gap. Unexplained is for differences you cannot name.
