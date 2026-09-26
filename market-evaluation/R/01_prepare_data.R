# ============================================================
# MISO Market Evaluation Project
# 01_prepare_data.R
#
# Purpose:
#   Read and clean MISO Day-Ahead LMP, Real-Time Final LMP,
#   and forecast/actual load data for a sample market day.
# ============================================================

library(tidyverse)
library(readxl)

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

market_date <- as.Date("2026-09-01")

raw_dir <- "market-evaluation/data/raw"
processed_dir <- "market-evaluation/data/processed"

dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

da_file <- file.path(
  raw_dir,
  "20260901_da_expost_lmp.csv"
)

rt_file <- file.path(
  raw_dir,
  "20260901_rt_lmp_final.csv"
)

load_file <- file.path(
  raw_dir,
  "20260925_dfal_HIST.xls"
)

# ------------------------------------------------------------
# Helper function: read MISO LMP report
#
# MISO files contain:
#   Node
#   Type
#   Value = LMP / MCC / MLC
#   HE 1 ... HE 24
#
# The first four lines contain report metadata.
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
      HourEnding = as.integer(readr::parse_number(HourEnding)),
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
# Read Day-Ahead and Real-Time files
# ------------------------------------------------------------

da_long <- read_miso_lmp(
  da_file,
  market_label = "DA",
  market_day = market_date
)

rt_long <- read_miso_lmp(
  rt_file,
  market_label = "RT",
  market_day = market_date
)

# ------------------------------------------------------------
# Join Day-Ahead and Real-Time markets
# ------------------------------------------------------------

lmp_joined <- da_long %>%
  select(
    MarketDay,
    HourEnding,
    Node,
    Type,
    Component,
    DA_Value = MarketValue
  ) %>%
  inner_join(
    rt_long %>%
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

# ------------------------------------------------------------
# Read historical forecast / actual load
#
# Header begins on row 6.
# MarketDay is stored as an Excel serial date.
# ------------------------------------------------------------

load_clean <- read_excel(
  load_file,
  skip = 5,
  col_types = "text"
) %>%
  rename(
    LoadResourceZone = `LoadResource Zone`,
    ForecastLoad = `MTLF (MWh)`,
    ActualLoad = `ActualLoad (MWh)`
  ) %>%
  # Keep only actual hourly data rows.
  filter(
    str_detect(MarketDay, "^\\d+(\\.\\d+)?$"),
    str_detect(HourEnding, "^\\d+$"),
    !is.na(LoadResourceZone)
  ) %>%
  mutate(
    MarketDay = as.Date(
      as.numeric(MarketDay),
      origin = "1899-12-30"
    ),
    HourEnding = as.integer(HourEnding),
    ForecastLoad = as.numeric(ForecastLoad),
    ActualLoad = as.numeric(ActualLoad),
    ForecastError = ActualLoad - ForecastLoad,
    AbsForecastError = abs(ForecastError)
  )

# ------------------------------------------------------------
# MISO-wide load for sample date
# ------------------------------------------------------------

miso_load_sample <- load_clean %>%
  filter(
    MarketDay == market_date,
    LoadResourceZone == "MISO"
  )

# ------------------------------------------------------------
# Named MISO hubs used in this analysis
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Basic validation
# ------------------------------------------------------------

stopifnot(
  nrow(miso_load_sample) == 24,
  all(c("LMP", "MCC", "MLC") %in% unique(lmp_joined$Component)),
  all(named_hubs %in% unique(lmp_joined$Node))
)

# ------------------------------------------------------------
# Save processed sample objects
#
# These RDS files are convenient locally.
# We will not rely on them as the public data source.
# ------------------------------------------------------------

saveRDS(
  lmp_joined,
  file.path(processed_dir, "lmp_sample_20260901.rds")
)

saveRDS(
  miso_load_sample,
  file.path(processed_dir, "miso_load_20260901.rds")
)

# ------------------------------------------------------------
# Quick diagnostic
# ------------------------------------------------------------

cat("LMP joined rows:", nrow(lmp_joined), "\n")
cat("MISO load rows:", nrow(miso_load_sample), "\n")
cat("Preparation completed successfully.\n")

# ------------------------------------------------------------
# Load-data completeness check
# ------------------------------------------------------------

expected_dates <- tibble(
  MarketDay = seq(
    min(load_clean$MarketDay),
    max(load_clean$MarketDay),
    by = "day"
  )
)

missing_load_dates <- expected_dates %>%
  anti_join(
    load_clean %>% distinct(MarketDay),
    by = "MarketDay"
  )

if (nrow(missing_load_dates) > 0) {
  message(
    "Note: historical load file is missing ",
    nrow(missing_load_dates),
    " calendar day(s): ",
    paste(missing_load_dates$MarketDay, collapse = ", ")
  )
}