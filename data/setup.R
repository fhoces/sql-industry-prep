# =============================================================================
# Build the synthetic SQLite database used by all SQL exercises in this repo
# =============================================================================
#
# Tables:
#   cities       (city_id, name, country, lead_pm)
#   neighborhoods(nbhd_id, city_id, name, pct_minority, median_income)
#   drivers      (driver_id, signup_date, gender, home_nbhd_id)
#   riders       (rider_id, signup_date, home_nbhd_id)
#   requests     (request_id, rider_id, pickup_nbhd_id, dropoff_nbhd_id,
#                 requested_at, accepted, accepted_by_driver_id)
#   rides        (ride_id, request_id, driver_id, started_at, ended_at,
#                 distance_mi, fare_usd, surge_mult, rider_rating)
#
# Run with: Rscript data/setup.R

library(DBI)
library(RSQLite)
library(tidyverse)
set.seed(2026)

dir.create("data", showWarnings = FALSE)
db_path <- "data/uber.sqlite"
if (file.exists(db_path)) file.remove(db_path)

con <- dbConnect(SQLite(), db_path)

# =============================================================================
# Cities and neighborhoods
# =============================================================================

cities <- tibble(
  city_id  = 1:5,
  name     = c("San Francisco", "Chicago", "Boston", "Seattle", "Austin"),
  country  = "US",
  lead_pm  = c("Maya Chen", "Jordan Patel", "Riley Kim", "Sam Liu", "Avery Reyes")
)

dbWriteTable(con, "cities", cities, overwrite = TRUE)

n_nbhd_per_city <- 8
neighborhoods <- map_dfr(cities$city_id, function(cid) {
  tibble(
    city_id      = cid,
    name         = paste0(cities$name[cid], " ", LETTERS[1:n_nbhd_per_city]),
    pct_minority = round(runif(n_nbhd_per_city, 0.10, 0.85), 2),
    median_income = round(rnorm(n_nbhd_per_city, 65000, 20000))
  )
}) |>
  mutate(nbhd_id = row_number())

dbWriteTable(con, "neighborhoods", neighborhoods, overwrite = TRUE)

# =============================================================================
# Drivers
# =============================================================================

n_drivers <- 800
drivers <- tibble(
  driver_id    = 1:n_drivers,
  signup_date  = as.character(sample(seq(as.Date("2022-01-01"), as.Date("2025-12-01"), by = "day"),
                        n_drivers, replace = TRUE)),
  gender       = sample(c("M", "F"), n_drivers, replace = TRUE, prob = c(0.78, 0.22)),
  home_nbhd_id = sample(neighborhoods$nbhd_id, n_drivers, replace = TRUE)
)

dbWriteTable(con, "drivers", drivers, overwrite = TRUE)

# =============================================================================
# Riders
# =============================================================================

n_riders <- 4000
riders <- tibble(
  rider_id     = 1:n_riders,
  signup_date  = as.character(sample(seq(as.Date("2022-01-01"), as.Date("2025-12-01"), by = "day"),
                        n_riders, replace = TRUE)),
  home_nbhd_id = sample(neighborhoods$nbhd_id, n_riders, replace = TRUE)
)

dbWriteTable(con, "riders", riders, overwrite = TRUE)

# =============================================================================
# Requests + rides
# =============================================================================

n_requests <- 50000
requests <- tibble(
  request_id    = 1:n_requests,
  rider_id      = sample(riders$rider_id, n_requests, replace = TRUE),
  pickup_nbhd_id  = sample(neighborhoods$nbhd_id, n_requests, replace = TRUE),
  dropoff_nbhd_id = sample(neighborhoods$nbhd_id, n_requests, replace = TRUE),
  requested_at  = as.character(
    sample(seq(as.POSIXct("2025-01-01"), as.POSIXct("2025-12-31 23:59:00"), by = "5 min"),
           n_requests, replace = TRUE)
  ),
  accepted      = rbinom(n_requests, 1, 0.78),
  accepted_by_driver_id = NA_integer_
)
requests$accepted_by_driver_id[requests$accepted == 1] <-
  sample(drivers$driver_id, sum(requests$accepted), replace = TRUE)

dbWriteTable(con, "requests", requests, overwrite = TRUE)

ride_idx <- which(requests$accepted == 1)
n_rides <- length(ride_idx)
# as.character(POSIXct) drops " 00:00:00" for midnight-exact timestamps, and
# as.POSIXct(character) picks its format from the FIRST element -- if that one
# is date-only, every element parses date-only and the time of day is silently
# discarded. Parse with the full format first, then fill the midnight-only
# stragglers explicitly.
parse_ts <- function(x) {
  out <- as.POSIXct(x, format = "%Y-%m-%d %H:%M:%S")
  mid <- is.na(out)
  out[mid] <- as.POSIXct(x[mid], format = "%Y-%m-%d")
  out
}
rides <- tibble(
  ride_id      = 1:n_rides,
  request_id   = requests$request_id[ride_idx],
  driver_id    = requests$accepted_by_driver_id[ride_idx],
  started_at   = as.character(parse_ts(requests$requested_at[ride_idx]) +
                              runif(n_rides, 60, 600)),
  ended_at     = NA_character_,
  distance_mi  = round(rlnorm(n_rides, 1.5, 0.5), 2),
  fare_usd     = NA_real_,
  surge_mult   = pmax(1, round(rnorm(n_rides, 1.2, 0.3), 2)),
  rider_rating = sample(c(NA, 3, 4, 5), n_rides, replace = TRUE,
                         prob = c(0.05, 0.10, 0.25, 0.60))
)
rides <- rides |>
  mutate(
    ended_at = as.character(parse_ts(started_at) + distance_mi * 180 + rnorm(n_rides, 0, 60)),
    fare_usd = round(2.50 + 1.50 * distance_mi * surge_mult + rnorm(n_rides, 0, 1), 2)
  )

dbWriteTable(con, "rides", rides, overwrite = TRUE)

cat("\nBuilt", db_path, "\n")
cat("Tables:", paste(dbListTables(con), collapse = ", "), "\n")
cat("Counts:\n")
for (t in dbListTables(con)) {
  n <- dbGetQuery(con, paste0("SELECT COUNT(*) AS n FROM ", t))$n
  cat(sprintf("  %-15s %d\n", t, n))
}

dbDisconnect(con)
