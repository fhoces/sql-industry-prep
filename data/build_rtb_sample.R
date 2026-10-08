# =============================================================================
# Build the synthetic billionaire panel used by module 6
# =============================================================================
#
# Module 6 reads and reproduces one step of a real replication: the SQL file
# 01_rtb_ca.sql in github.com/fhoces/opa-prop40 (bsz-analysis/sql/), which
# turns daily Forbes real-time billionaire snapshots into the California lists
# of a published paper. The real snapshots are confidential, so this script
# invents a panel in exactly the same shape. Every person, id and number here
# is made up.
#
# Tables written to data/rtb_sample.sqlite:
#   rtb_all_combined        one row per (date, forbes_id), worth in $ million
#                           (date, forbes_id, forbes_name, state,
#                            country_citizenship, source, industries,
#                            forbes_worth, forbes_public_worth,
#                            forbes_private_worth)
#   rtb_ca_cik              forbes_id to SEC CIK for the 2026-01-01 list
#                           (forbes_id, cik)
#   rtb_residency_overrides ids counted as California residents whatever the
#                           state field says (rule = 'include') or never
#                           counted (rule = 'exclude')
#                           (forbes_id, rule, note)
#   data_sec_all            one row per California billionaire and year, in
#                           sheet order: (row_num, year, forbes_id, then 29
#                           money columns in $ million), with a re-pasted
#                           block of four rows at the tail
#   data_sec_agg_exclude    ids left out of the yearly sums (forbes_id)
#   ftb_b4a                 a tax-statistics table, one row per income
#                           bracket and taxable year: (row_num, taxable_year,
#                           agic, all_returns, ca_agi, taxable_income,
#                           total_tax), money in $
#
# It then runs module-06/solution.sql on a copy of the database with the
# sqlite3 CLI and writes the reference results to module-06/expected/*.csv,
# which module-06/check.py compares your answers against.
#
# Run from the repo root with: Rscript data/build_rtb_sample.R

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(tidyverse)
})
set.seed(2026)

db_path <- "data/rtb_sample.sqlite"
if (file.exists(db_path)) invisible(file.remove(db_path))

# =============================================================================
# Dates: about 300 snapshots between 2019-12-31 and 2026-03-30
# =============================================================================
# The real data are daily with gaps. Here: every 8th day, plus the seven
# year-end snapshot dates the query keeps, plus the three dates its daily
# aggregate leaves out. As in the real data there is no 2025-12-31 snapshot:
# 2025-12-30 is followed by 2026-01-01, which is why the query treats
# 2026-01-01 as the "2025" year-end list.

eoy_dates  <- as.Date(c("2019-12-31", "2020-12-31", "2021-12-31", "2022-12-31",
                        "2023-12-31", "2024-12-31", "2026-01-01"))
skip_dates <- as.Date(c("2022-07-18", "2026-03-29", "2026-03-30"))

dates <- sort(unique(c(
  seq(as.Date("2019-12-31"), as.Date("2026-03-30"), by = 8),
  eoy_dates, skip_dates, as.Date("2025-12-30")
)))
dates <- dates[dates != as.Date("2025-12-31")]
n_dates <- length(dates)

# =============================================================================
# People: 60 invented billionaires
# =============================================================================

first <- c("Avery", "Bram", "Calla", "Dorian", "Ember", "Faro", "Gideon", "Halle",
           "Ines", "Jory", "Kestrel", "Lumen", "Marlo", "Nell", "Orrin", "Pia",
           "Quill", "Rhea", "Soren", "Tamsin", "Ulla", "Vance", "Wren", "Xavi",
           "Yara", "Zeno", "Adair", "Bexley", "Cyrus", "Delphine")
last  <- c("Ashgrove", "Brightwater", "Coldharbor", "Dunmore", "Elderfield",
           "Fairweather", "Glenrock", "Hollowell", "Ironwood", "Juniper",
           "Kettleby", "Larkspur", "Merriweather", "Northcott", "Oakhurst",
           "Pennyroyal", "Quarrington", "Ravensworth", "Silverbrook", "Thistlewood",
           "Underhill", "Vantongeren", "Whitlock", "Yarrowby", "Zanderfell",
           "Amberly", "Blackthorn", "Copperfield", "Driftwood", "Emberton")

n_people <- 60
all_names <- as.vector(outer(first, last, paste))
people <- tibble(forbes_name = sample(all_names, n_people)) |>
  mutate(forbes_id = str_replace_all(str_to_lower(forbes_name), " ", "-"))
stopifnot(nrow(people) == n_people)

industry_sources <- tribble(
  ~industries,              ~source,
  "Technology",             "software",
  "Technology",             "semiconductors",
  "Technology",             "online marketplace",
  "Finance & Investments",  "hedge funds",
  "Finance & Investments",  "private equity",
  "Media & Entertainment",  "streaming",
  "Real Estate",            "real estate",
  "Healthcare",             "medical devices",
  "Food & Beverage",        "coffee chains",
  "Fashion & Retail",       "athletic apparel",
  "Diversified",            "investments",
  "Sports",                 "sports team"
)

# States: about half California. A few people have no state on file (NULL),
# and a few are not US citizens (no state either).
people <- people |>
  mutate(
    state = sample(c("California", "New York", "Texas", "Washington", "Florida",
                     "Nevada", "Massachusetts"),
                   n_people, replace = TRUE,
                   prob = c(0.50, 0.12, 0.10, 0.08, 0.08, 0.06, 0.06)),
    country_citizenship = "United States",
    ind = sample(nrow(industry_sources), n_people, replace = TRUE,
                 prob = c(4, 3, 2, 3, 2, 2, 2, 2, 1, 1, 1, 0.4))
  )
people$industries <- industry_sources$industries[people$ind]
people$source     <- industry_sources$source[people$ind]

# Hand-placed cases, so every rule in the query has something to bite on.
# Positions 1-4: the "top 4" (the four largest California fortunes).
# 5: California by override only (state on file is Nevada).
# 6: California by override only (no state on file).
# 7: state says California, but the override table excludes them.
# 8, 9: no state on file and no override (dropped by the query).
# 10, 11: not US citizens (no state).
# 12: the only person in Sports, with no public/private split on file.
people$state[1:4] <- "California"
people$industries[1:4] <- "Technology"
people$source[1:4] <- c("software", "semiconductors", "online marketplace", "software")
people$state[5] <- "Nevada"
people$state[6] <- NA
people$state[7] <- "California"
people$state[8:9] <- NA
people$state[10:11] <- NA
people$country_citizenship[10:11] <- c("Canada", "Brazil")
people$state[12] <- "California"
people$industries[people$industries == "Sports"] <- "Diversified"
people$source[people$source == "sports team"] <- "investments"
people$industries[12] <- "Sports"
people$source[12] <- "sports team"

# Starting worth in $ million, log-uniform from $0.6 billion to $40 billion;
# the top 4 start far above everyone else. Some people start below the
# $1 billion threshold and cross it later (or never).
people <- people |>
  mutate(
    w0 = exp(runif(n_people, log(600), log(40000))),
    public_share = round(runif(n_people, 0, 0.95), 3),
    first_day = 1L,
    last_day  = n_dates
  )
people$w0[1:4] <- c(160000, 120000, 95000, 90000)
people$w0[c(5, 6, 7, 12)] <- c(4000, 2500, 6000, 1800)
# Ten people enter the data later, two drop out early.
late <- sample(13:n_people, 10)
people$first_day[late] <- sample(30:250, 10)
gone <- sample(setdiff(13:n_people, late), 2)
people$last_day[gone] <- sample(150:280, 2)

# =============================================================================
# The panel: one random walk in log worth per person
# =============================================================================

panel <- map_dfr(seq_len(n_people), function(i) {
  p <- people[i, ]
  days <- p$first_day:p$last_day
  steps <- rnorm(length(days), mean = 0.003, sd = 0.04)
  worth <- p$w0 * exp(cumsum(steps) - steps[1])
  tibble(
    date = as.character(dates[days]),
    forbes_id = p$forbes_id,
    forbes_name = p$forbes_name,
    state = p$state,
    country_citizenship = p$country_citizenship,
    source = p$source,
    industries = p$industries,
    forbes_worth = round(worth, 1)
  ) |>
    mutate(
      forbes_public_worth = round(forbes_worth * p$public_share, 1),
      forbes_private_worth = round(forbes_worth - forbes_public_worth, 1)
    )
})

# Missing values, as the real snapshots have them:
#  * the Sports owner never has a public/private split;
#  * about 3% of other rows lose the split;
#  * about 0.5% of rows have no worth at all (so they fail the threshold).
sports <- panel$forbes_id == people$forbes_id[12]
panel$forbes_public_worth[sports] <- NA
panel$forbes_private_worth[sports] <- NA
no_split <- runif(nrow(panel)) < 0.03
panel$forbes_public_worth[no_split] <- NA
panel$forbes_private_worth[no_split] <- NA
no_worth <- runif(nrow(panel)) < 0.005
panel$forbes_worth[no_worth] <- NA

panel <- arrange(panel, date, forbes_id)

# =============================================================================
# Residency overrides (invented ids, invented reasons)
# =============================================================================

overrides <- tibble(
  forbes_id = people$forbes_id[c(5, 6, 7)],
  rule = c("include", "include", "exclude"),
  note = c("course example: state on file is Nevada, counted as California",
           "course example: no state on file, counted as California",
           "course example: state on file is California, never counted")
)

# =============================================================================
# SEC CIK crosswalk for the 2026-01-01 list
# =============================================================================
# Everyone who could be on a California list gets a row; about a quarter
# have no CIK (not an SEC filer), stored as NULL.

ca_ids <- people$forbes_id[(people$state %in% "California" |
                             people$forbes_id %in% overrides$forbes_id[overrides$rule == "include"])]
cik <- tibble(
  forbes_id = ca_ids,
  cik = as.integer(sample(1000000:1999999, length(ca_ids)))
)
cik$cik[runif(nrow(cik)) < 0.25] <- NA

# =============================================================================
# Step 2 inputs: the yearly SEC panel and a tax-statistics table
# =============================================================================
# Module 6's second part (Q5 to Q8) reproduces two more real files,
# 02_data_sec_agg.sql and 03_ftb_b4a.sql, which read two sheets of the
# paper's public workbook after they are loaded into SQLite. These tables
# copy the shape of those loaded sheets. A separate seed keeps every table
# above unchanged when this section is edited.
set.seed(4026)

# data_sec_all: one row per California billionaire and year, money in
# $ million, in sheet order (row_num). The 29 money columns are the sheet's.
dsa_money <- c("forbes_worth", "forbes_public_worth", "purchase", "sale", "kg",
               "kg_long", "kg_short", "option_profit", "noneq_comp",
               "ordinary_income", "kg_taxable", "dividend", "fiscal_income",
               "donation", "donation_deductible", "income_taxable",
               "ca_income_tax", "fed_ordinary_income_tax", "fed_preferential_tax",
               "fed_income_tax", "fiscal_income_tax", "sales_tax", "w_txt",
               "w_tax_ppent", "w_pi", "public_worth", "public_worth_avg",
               "total_tax", "economic_income")

dsa_people <- tibble(forbes_id = ca_ids) |>
  mutate(w0 = exp(runif(n(), log(1100), log(30000))))
dsa_people$w0[match(people$forbes_id[1:4], dsa_people$forbes_id)] <- c(150000, 110000, 90000, 85000)

dsa <- map_dfr(2019:2025, function(yr) {
  keep <- runif(nrow(dsa_people)) < 0.85 | dsa_people$forbes_id %in% people$forbes_id[1:4]
  p <- dsa_people[keep, ]
  w <- round(p$w0 * exp(rnorm(nrow(p), 0.06 * (yr - 2019), 0.15)), 3)
  pub <- round(w * runif(nrow(p), 0.3, 0.95), 3)
  inc <- function(scale, p_null = 0.15) {
    v <- round(w * scale * runif(nrow(p), 0.2, 1.8), 4)
    v[runif(nrow(p)) < p_null] <- NA
    v
  }
  out <- tibble(year = yr, forbes_id = p$forbes_id, forbes_worth = w, forbes_public_worth = pub,
                purchase = inc(0.004), sale = inc(0.010), kg = inc(0.008),
                kg_long = inc(0.007), kg_short = inc(0.001), option_profit = inc(0.002, 0.5),
                noneq_comp = inc(0.0005), ordinary_income = inc(0.001), kg_taxable = inc(0.008),
                dividend = inc(0.003), fiscal_income = inc(0.012), donation = inc(0.002),
                donation_deductible = inc(0.001), income_taxable = inc(0.010),
                ca_income_tax = inc(0.0012), fed_ordinary_income_tax = inc(0.0004),
                fed_preferential_tax = inc(0.0015), fed_income_tax = inc(0.0019),
                fiscal_income_tax = inc(0.003), sales_tax = inc(0.0002), w_txt = inc(0.004, 0),
                w_tax_ppent = inc(0.0003, 0), w_pi = inc(0.03, 0),
                public_worth = round(pub * runif(nrow(p), 0.95, 1.05), 3),
                public_worth_avg = round(pub * runif(nrow(p), 0.85, 1.0), 3),
                total_tax = inc(0.008, 0), economic_income = inc(0.04, 0))
  arrange(out, desc(forbes_worth))
})

# Hand-placed cases for Q5 and Q6:
#  * one id is on the exclusion table (in the real file, a person counted as
#    a California resident only for part of the panel);
#  * in 2022 one id has two rows with different worths (two separately
#    tracked fortunes): both are real and both count;
#  * option_profit is empty for every 2019 row, so its 2019 sum is NULL in
#    SQL and must come out as 0;
#  * the last four 2025 rows are pasted a second time at the tail of the
#    sheet. One copy differs in a column outside the key (a re-typed
#    dividend), and one row has no worth, so its copy can only be matched
#    by treating two NULLs as equal.
excluded_id <- dsa_people$forbes_id[!dsa_people$forbes_id %in% people$forbes_id[1:12]][1]
twin_id <- dsa_people$forbes_id[!dsa_people$forbes_id %in% c(people$forbes_id[1:12], excluded_id)][1]
dsa <- dsa |> filter(!(forbes_id == twin_id & year == 2022))
twin_rows <- tibble(year = 2022L, forbes_id = twin_id, forbes_worth = c(8000, 5256)) |>
  mutate(forbes_public_worth = round(forbes_worth * 0.6, 3))
for (col in setdiff(dsa_money, names(twin_rows))) {
  twin_rows[[col]] <- round(twin_rows$forbes_worth * runif(2, 0.001, 0.01), 4)
}
dsa <- bind_rows(dsa, twin_rows) |>
  mutate(year = as.integer(year)) |>
  arrange(year, desc(forbes_worth))
dsa$option_profit[dsa$year == 2019] <- NA
n_2025 <- sum(dsa$year == 2025)
last4 <- which(dsa$year == 2025)[(n_2025 - 3):n_2025]
dsa$forbes_worth[last4[4]] <- NA
repaste <- dsa[last4, ]
repaste$dividend[2] <- repaste$dividend[2] + 0.5
dsa <- bind_rows(dsa, repaste)
data_sec_all <- bind_cols(row_num = seq_len(nrow(dsa)), dsa[c("year", "forbes_id", dsa_money)])
data_sec_agg_exclude <- tibble(forbes_id = excluded_id)

# ftb_b4a: a tax-statistics table by income bracket, one block per taxable
# year, newest year first, as the source sheet lists it. row_num is the sheet
# row (the title and header rows 1 to 3 are not loaded). The blocks differ in
# length: from 2021 the top bracket is split in two, so any rule that picks
# rows by position breaks when a year is added. Labels carry two spaces
# around "to" and "and"; one 2019 label has a single space, as such
# hand-made sheets often do. The last loaded row is a footnote with no year.
ftb_labels <- function(yr) {
  base <- c("Negative", "Zero", "1  to  49,999", "50,000  to  99,999",
            "100,000  to  499,999", "500,000  to  999,999", "1,000,000  to  4,999,999")
  top <- if (yr >= 2021) c("5,000,000  to  9,999,999", "10,000,000  and  over")
         else if (yr == 2019) "5,000,000  and over"
         else "5,000,000  and  over"
  c(base, top)
}
ftb <- map_dfr(2022:2016, function(yr) {
  lab <- ftb_labels(yr)
  k <- length(lab)
  returns <- round(c(150000, 60000, 9e6, 4e6, 4.5e6, 3e5, 1e5, rep(9000, k - 7)) *
                     runif(k, 0.9, 1.1) * (1 + 0.02 * (yr - 2016)))
  if (k == 9) returns[9] <- round(returns[8] * 0.6)
  avg_agi <- c(-60000, 0, 25000, 72000, 190000, 690000, 1.9e6, 7e6, 3.1e7)[seq_len(k)]
  if (k == 8) avg_agi[8] <- 1.6e7
  agi <- round(returns * avg_agi * runif(k, 0.95, 1.05), -3)
  taxable <- round(pmax(agi, 0) * runif(k, 0.75, 0.95), -3)
  tax <- round(taxable * c(0.001, 0, 0.01, 0.03, 0.06, 0.09, 0.105, 0.12, 0.125)[seq_len(k)], -3)
  tibble(taxable_year = as.integer(yr), agic = lab, all_returns = returns,
         ca_agi = agi, taxable_income = taxable, total_tax = tax)
})
ftb$total_tax[ftb$taxable_year == 2017 & ftb$agic == "Zero"] <- NA   # a suppressed cell
ftb <- bind_rows(ftb, tibble(taxable_year = NA_integer_,
                             agic = "Note: detail may not add to totals because of rounding"))
ftb_b4a <- bind_cols(row_num = 3L + seq_len(nrow(ftb)), ftb)

# =============================================================================
# Write the database
# =============================================================================

con <- dbConnect(SQLite(), db_path)
dbWriteTable(con, "rtb_all_combined", panel, overwrite = TRUE,
             field.types = c(date = "TEXT", forbes_id = "TEXT", forbes_name = "TEXT",
                             state = "TEXT", country_citizenship = "TEXT",
                             source = "TEXT", industries = "TEXT",
                             forbes_worth = "REAL", forbes_public_worth = "REAL",
                             forbes_private_worth = "REAL"))
dbWriteTable(con, "rtb_ca_cik", cik, overwrite = TRUE,
             field.types = c(forbes_id = "TEXT", cik = "INTEGER"))
dbWriteTable(con, "rtb_residency_overrides", overrides, overwrite = TRUE,
             field.types = c(forbes_id = "TEXT", rule = "TEXT", note = "TEXT"))
dbWriteTable(con, "data_sec_all", data_sec_all, overwrite = TRUE,
             field.types = c(row_num = "INTEGER", year = "INTEGER", forbes_id = "TEXT",
                             setNames(rep("REAL", length(dsa_money)), dsa_money)))
dbWriteTable(con, "data_sec_agg_exclude", data_sec_agg_exclude, overwrite = TRUE,
             field.types = c(forbes_id = "TEXT"))
dbWriteTable(con, "ftb_b4a", ftb_b4a, overwrite = TRUE,
             field.types = c(row_num = "INTEGER", taxable_year = "INTEGER", agic = "TEXT",
                             all_returns = "REAL", ca_agi = "REAL",
                             taxable_income = "REAL", total_tax = "REAL"))
invisible(dbExecute(con, "CREATE INDEX idx_rtb_all_combined_date ON rtb_all_combined (date)"))
invisible(dbExecute(con, "CREATE INDEX idx_rtb_all_combined_id ON rtb_all_combined (forbes_id)"))
dbDisconnect(con)

cat(sprintf("%s: rtb_all_combined %d rows (%d people x %d dates), rtb_ca_cik %d, overrides %d\n",
            db_path, nrow(panel), n_people, n_dates, nrow(cik), nrow(overrides)))
cat("Top-4 ids used in module-06/solution.sql:",
    paste(people$forbes_id[1:4], collapse = ", "), "\n")
cat(sprintf("data_sec_all %d rows (excluded id %s, re-pasted rows %d to %d), ftb_b4a %d rows\n",
            nrow(data_sec_all), excluded_id, nrow(data_sec_all) - 3, nrow(data_sec_all),
            nrow(ftb_b4a)))

# =============================================================================
# Reference results for module 6
# =============================================================================
# Run the reference solution on a scratch copy (it creates tables) with the
# sqlite3 CLI, then write one CSV per output table. NULL is written as an
# empty field.

tmp <- tempfile(fileext = ".sqlite")
invisible(file.copy(db_path, tmp))
status <- system2("sqlite3", tmp, stdin = "module-06/solution.sql")
if (status != 0) stop("module-06/solution.sql failed under sqlite3")

expected_dir <- "module-06/expected"
dir.create(expected_dir, showWarnings = FALSE, recursive = TRUE)
con <- dbConnect(SQLite(), tmp)
outputs <- c(
  rtb_ca_all                 = "date, forbes_id",
  rtb_ca_eoy                 = "date, forbes_worth DESC, forbes_id",
  rtb_ca_2026_01_01_industry = "(industries = 'Total'), fraction_forbes_worth DESC, industries",
  rtb_ca_aggregate           = "date",
  data_sec_all_kept          = "row_num",
  data_sec_agg               = "year",
  ftb_b4a_year               = "taxable_year",
  ftb_b4a_top                = "taxable_year, row_num"
)
for (t in names(outputs)) {
  df <- dbGetQuery(con, sprintf("SELECT * FROM %s ORDER BY %s", t, outputs[[t]]))
  write_csv(df, file.path(expected_dir, paste0(t, ".csv")), na = "")
  cat(sprintf("  %-28s %5d rows -> %s\n", t, nrow(df), file.path(expected_dir, paste0(t, ".csv"))))
}
dbDisconnect(con)
unlink(tmp)
