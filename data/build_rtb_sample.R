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
invisible(dbExecute(con, "CREATE INDEX idx_rtb_all_combined_date ON rtb_all_combined (date)"))
invisible(dbExecute(con, "CREATE INDEX idx_rtb_all_combined_id ON rtb_all_combined (forbes_id)"))
dbDisconnect(con)

cat(sprintf("%s: rtb_all_combined %d rows (%d people x %d dates), rtb_ca_cik %d, overrides %d\n",
            db_path, nrow(panel), n_people, n_dates, nrow(cik), nrow(overrides)))
cat("Top-4 ids used in module-06/solution.sql:",
    paste(people$forbes_id[1:4], collapse = ", "), "\n")

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
  rtb_ca_aggregate           = "date"
)
for (t in names(outputs)) {
  df <- dbGetQuery(con, sprintf("SELECT * FROM %s ORDER BY %s", t, outputs[[t]]))
  write_csv(df, file.path(expected_dir, paste0(t, ".csv")), na = "")
  cat(sprintf("  %-28s %5d rows -> %s\n", t, nrow(df), file.path(expected_dir, paste0(t, ".csv"))))
}
dbDisconnect(con)
unlink(tmp)
