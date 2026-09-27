# ============================================================
# MISO Market Evaluation Project
# 03_build_history.R
#
# Purpose:
#   Build a historical baseline of Day-Ahead vs Real-Time
#   LMP spreads for eight named MISO hubs.
#
# Baseline window:
#   2026-07-01 through 2026-08-31
#
# Sept. 1, 2026 is intentionally excluded so it can be
# evaluated out-of-sample by the alert-monitoring workflow.
# ============================================================

library(tidyverse)

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

baseline_start <- as.Date("2026-07-01")
baseline_end   <- as.Date("2026-08-31")

market_days <- seq(
  baseline_start,
  baseline_end,
  by = "day"
)

base_url <- "https://docs.misoenergy.org/marketreports"

raw_history_dir <- "market-evaluation/data/raw/history"
processed_dir <- "market-evaluation/data/processed"

dir.create(
  raw_history_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  processed_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

named_hubs <- c(
  "MINN.HUB",
  "MICHIGAN.HUB",
  "ILLINOIS.HUB",
  "INDIANA.HUB",
  "ARKANSAS.HUB",
  "MS.HUB",
  "LOUISIANA.HUB",
  "TEXAS.HUB"
)

components_to_keep <- c(
  "LMP",
  "MCC",
  "MLC"
)

# ------------------------------------------------------------
# Helper: validate downloaded MISO LMP file
# ------------------------------------------------------------

valid_miso_lmp_file <- function(file) {
  
  if (!file.exists(file)) {
    return(FALSE)
  }
  
  if (file.info(file)$size < 1000) {
    return(FALSE)
  }
  
  first_lines <- tryCatch(
    readLines(file, n = 5, warn = FALSE),
    error = function(e) character(0)
  )
  
  if (length(first_lines) < 5) {
    return(FALSE)
  }
  
  str_detect(
    first_lines[5],
    "^Node,Type,Value,"
  )
}

# ------------------------------------------------------------
# Helper: download a report if it is not already cached
# ------------------------------------------------------------

download_miso_report <- function(url, destination) {
  
  # Reuse a previously downloaded valid file.
  if (valid_miso_lmp_file(destination)) {
    return("cached")
  }
  
  temp_file <- paste0(destination, ".part")
  
  if (file.exists(temp_file)) {
    file.remove(temp_file)
  }
  
  result <- tryCatch(
    {
      
      suppressWarnings(
        download.file(
          url,
          temp_file,
          mode = "wb",
          quiet = TRUE
        )
      )
      
      if (!valid_miso_lmp_file(temp_file)) {
        
        if (file.exists(temp_file)) {
          file.remove(temp_file)
        }
        
        return("failed")
      }
      
      file.rename(
        temp_file,
        destination
      )
      
      "downloaded"
    },
    error = function(e) {
      
      if (file.exists(temp_file)) {
        file.remove(temp_file)
      }
      
      "failed"
    }
  )
  
  result
}

# ------------------------------------------------------------
# Helper: read MISO LMP report
# ------------------------------------------------------------

read_miso_lmp <- function(file, market_label, market_day) {
  
  read_csv(
    file,
    skip = 4,
    show_col_types = FALSE
  ) %>%
    pivot_longer(
      cols = matches("^HE\\s*\\d+$"),
      names_to = "HourEnding",
      values_to = "MarketValue"
    ) %>%
    mutate(
      MarketDay = market_day,
      HourEnding = as.integer(
        readr::parse_number(HourEnding)
      ),
      Market = market_label
    ) %>%
    rename(
      Component = Value
    ) %>%
    select(
      MarketDay,
      HourEnding,
      Node,
      Type,
      Component,
      Market,
      MarketValue
    )
}

# ------------------------------------------------------------
# Download and process each market day
# ------------------------------------------------------------

history_list <- vector(
  "list",
  length(market_days)
)

download_log <- vector(
  "list",
  length(market_days)
)

for (i in seq_along(market_days)) {
  
  market_day <- market_days[i]
  
  date_string <- format(
    market_day,
    "%Y%m%d"
  )
  
  cat(
    "[",
    i,
    "/",
    length(market_days),
    "] Processing ",
    as.character(market_day),
    "...\n",
    sep = ""
  )
  
  # ----------------------------------------------------------
  # Construct filenames and URLs
  # ----------------------------------------------------------
  
  da_filename <- paste0(
    date_string,
    "_da_expost_lmp.csv"
  )
  
  rt_filename <- paste0(
    date_string,
    "_rt_lmp_final.csv"
  )
  
  da_file <- file.path(
    raw_history_dir,
    da_filename
  )
  
  rt_file <- file.path(
    raw_history_dir,
    rt_filename
  )
  
  da_url <- paste0(
    base_url,
    "/",
    da_filename
  )
  
  rt_url <- paste0(
    base_url,
    "/",
    rt_filename
  )
  
  # ----------------------------------------------------------
  # Download
  # ----------------------------------------------------------
  
  da_status <- download_miso_report(
    da_url,
    da_file
  )
  
  rt_status <- download_miso_report(
    rt_url,
    rt_file
  )
  
  download_log[[i]] <- tibble(
    MarketDay = market_day,
    DA_Status = da_status,
    RT_Status = rt_status
  )
  
  # Skip this date if either report failed.
  if (
    da_status == "failed" ||
    rt_status == "failed"
  ) {
    
    message(
      "Skipping ",
      market_day,
      ": DA=",
      da_status,
      ", RT=",
      rt_status
    )
    
    next
  }
  
  # ----------------------------------------------------------
  # Read DA and RT reports
  # ----------------------------------------------------------
  
  da_long <- read_miso_lmp(
    da_file,
    market_label = "DA",
    market_day = market_day
  )
  
  rt_long <- read_miso_lmp(
    rt_file,
    market_label = "RT",
    market_day = market_day
  )
  
  # ----------------------------------------------------------
  # Restrict immediately to the eight named hubs and
  # LMP / congestion / loss components.
  # ----------------------------------------------------------
  
  da_hubs <- da_long %>%
    filter(
      Node %in% named_hubs,
      Component %in% components_to_keep
    )
  
  rt_hubs <- rt_long %>%
    filter(
      Node %in% named_hubs,
      Component %in% components_to_keep
    )
  
  # ----------------------------------------------------------
  # Join Day-Ahead and Real-Time observations
  # ----------------------------------------------------------
  
  history_list[[i]] <- da_hubs %>%
    select(
      MarketDay,
      HourEnding,
      Node,
      Type,
      Component,
      DA_Value = MarketValue
    ) %>%
    inner_join(
      rt_hubs %>%
        select(
          MarketDay,
          HourEnding,
          Node,
          Type,
          Component,
          RT_Value = MarketValue
        ),
      by = c(
        "MarketDay",
        "HourEnding",
        "Node",
        "Type",
        "Component"
      )
    ) %>%
    mutate(
      Spread = RT_Value - DA_Value,
      AbsSpread = abs(Spread)
    )
}

# ------------------------------------------------------------
# Combine all successful dates
# ------------------------------------------------------------

historical_spreads <- bind_rows(
  history_list
)

download_log <- bind_rows(
  download_log
)

# ------------------------------------------------------------
# Coverage QA
# ------------------------------------------------------------

expected_grid <- expand_grid(
  MarketDay = market_days,
  HourEnding = 1:24,
  Node = named_hubs,
  Component = components_to_keep
)

observed_grid <- historical_spreads %>%
  distinct(
    MarketDay,
    HourEnding,
    Node,
    Component
  )

missing_observations <- expected_grid %>%
  anti_join(
    observed_grid,
    by = c(
      "MarketDay",
      "HourEnding",
      "Node",
      "Component"
    )
  )

# ------------------------------------------------------------
# Save processed outputs
# ------------------------------------------------------------

write_csv(
  historical_spreads,
  file.path(
    processed_dir,
    "named_hub_da_rt_history_20260701_20260831.csv"
  )
)

saveRDS(
  historical_spreads,
  file.path(
    processed_dir,
    "named_hub_da_rt_history_20260701_20260831.rds"
  )
)

write_csv(
  download_log,
  file.path(
    processed_dir,
    "history_download_log_20260701_20260831.csv"
  )
)

write_csv(
  missing_observations,
  file.path(
    processed_dir,
    "history_missing_observations_20260701_20260831.csv"
  )
)

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

cat("\n")
cat("============================================\n")
cat("Historical baseline build completed\n")
cat("============================================\n")

cat(
  "Baseline:",
  as.character(baseline_start),
  "to",
  as.character(baseline_end),
  "\n"
)

cat(
  "Requested market days:",
  length(market_days),
  "\n"
)

cat(
  "Observed market days:",
  n_distinct(historical_spreads$MarketDay),
  "\n"
)

cat(
  "Historical rows:",
  nrow(historical_spreads),
  "\n"
)

cat(
  "Missing expected observations:",
  nrow(missing_observations),
  "\n"
)

cat("\nDownload status:\n")

print(
  download_log %>%
    count(
      DA_Status,
      RT_Status
    )
)

cat("\nLMP spread summary:\n")

print(
  historical_spreads %>%
    filter(
      Component == "LMP"
    ) %>%
    summarise(
      N = n(),
      MeanSpread = mean(
        Spread,
        na.rm = TRUE
      ),
      MedianSpread = median(
        Spread,
        na.rm = TRUE
      ),
      P95_AbsSpread = quantile(
        AbsSpread,
        0.95,
        na.rm = TRUE
      ),
      P99_AbsSpread = quantile(
        AbsSpread,
        0.99,
        na.rm = TRUE
      ),
      MaxAbsSpread = max(
        AbsSpread,
        na.rm = TRUE
      )
    )
)