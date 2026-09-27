# ============================================================
# MISO Market Evaluation Project
# 05_run_daily_monitor.R
#
# Purpose:
#   Run the daily MISO DA-RT monitoring workflow with one command:
#
#     1. Download/cached Day-Ahead ExPost and Real-Time Final LMP reports
#     2. Build DA-RT spreads for eight named hubs
#     3. Compare the monitored day with the historical baseline
#     4. Generate automated primary alerts
#     5. Save daily processed outputs
#     6. Render the parameterized HTML monitoring report
#
# Example:
#   source("market-evaluation/R/05_run_daily_monitor.R")
#   run_daily_monitor("2026-09-01")
#
# Historical baseline:
#   2026-07-01 through 2026-08-31
#   built by 03_build_history.R
# ============================================================

library(tidyverse)

# ------------------------------------------------------------
# Helper: validate a downloaded MISO LMP report
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
# Helper: download report if not already cached
# ------------------------------------------------------------

download_miso_report <- function(url, destination) {

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

      moved <- file.rename(
        temp_file,
        destination
      )

      if (!moved) {
        file.copy(
          temp_file,
          destination,
          overwrite = TRUE
        )
        file.remove(temp_file)
      }

      if (!valid_miso_lmp_file(destination)) {
        return("failed")
      }

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
# Helper: read a MISO LMP report
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
# Main function
# ------------------------------------------------------------

run_daily_monitor <- function(
    market_date,
    render_report = TRUE,
    baseline_file =
      "market-evaluation/data/processed/named_hub_da_rt_history_20260701_20260831.rds"
) {

  # ----------------------------------------------------------
  # Configuration
  # ----------------------------------------------------------

  market_date <- as.Date(market_date)

  if (is.na(market_date)) {
    stop("market_date must be coercible to a valid Date.")
  }

  if (!file.exists("market-evaluation")) {
    stop(
      "Run this function from the repository root ",
      "(the folder containing 'market-evaluation')."
    )
  }

  if (!file.exists(baseline_file)) {
    stop(
      "Historical baseline file not found: ",
      baseline_file,
      "\nRun 03_build_history.R first."
    )
  }

  base_url <- "https://docs.misoenergy.org/marketreports"

  raw_daily_dir <- "market-evaluation/data/raw/daily"
  processed_dir <- "market-evaluation/data/processed"
  report_dir <- "market-evaluation/report"

  dir.create(
    raw_daily_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )

  dir.create(
    processed_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )

  dir.create(
    report_dir,
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

  date_string <- format(
    market_date,
    "%Y%m%d"
  )

  # ----------------------------------------------------------
  # Construct report filenames and URLs
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
    raw_daily_dir,
    da_filename
  )

  rt_file <- file.path(
    raw_daily_dir,
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
  # Download reports
  # ----------------------------------------------------------

  cat("\n")
  cat("============================================\n")
  cat("MISO Daily Market Monitor\n")
  cat("============================================\n")
  cat("Market date:", as.character(market_date), "\n\n")

  cat("Downloading / checking Day-Ahead report...\n")

  da_status <- download_miso_report(
    da_url,
    da_file
  )

  cat("DA status:", da_status, "\n")

  cat("Downloading / checking Real-Time report...\n")

  rt_status <- download_miso_report(
    rt_url,
    rt_file
  )

  cat("RT status:", rt_status, "\n")

  if (
    da_status == "failed" ||
    rt_status == "failed"
  ) {
    stop(
      "Daily monitoring stopped because at least one ",
      "market report could not be downloaded or validated."
    )
  }

  # ----------------------------------------------------------
  # Read and clean the monitored day
  # ----------------------------------------------------------

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

  daily_spreads_all <- da_hubs %>%
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

  # ----------------------------------------------------------
  # Daily QA
  #
  # Expected:
  # 8 hubs x 24 hours x 3 components = 576 rows
  # ----------------------------------------------------------

  expected_rows_all <- 8 * 24 * 3

  if (nrow(daily_spreads_all) != expected_rows_all) {
    stop(
      "Unexpected number of joined daily rows. Expected ",
      expected_rows_all,
      ", found ",
      nrow(daily_spreads_all),
      "."
    )
  }

  if (!all(named_hubs %in% unique(daily_spreads_all$Node))) {
    stop("One or more named hubs are missing from the daily data.")
  }

  if (!all(components_to_keep %in% unique(daily_spreads_all$Component))) {
    stop("One or more LMP components are missing from the daily data.")
  }

  # Save all three components for audit/reuse.
  daily_spread_file <- file.path(
    processed_dir,
    paste0(
      "named_hub_da_rt_spreads_",
      date_string,
      ".csv"
    )
  )

  write_csv(
    daily_spreads_all,
    daily_spread_file
  )

  # ----------------------------------------------------------
  # Primary alert analysis uses LMP only
  # ----------------------------------------------------------

  event_lmp <- daily_spreads_all %>%
    filter(
      Component == "LMP"
    )

  # Expected:
  # 8 hubs x 24 hours = 192 LMP rows
  if (nrow(event_lmp) != 8 * 24) {
    stop(
      "Unexpected LMP row count. Expected 192, found ",
      nrow(event_lmp),
      "."
    )
  }

  # ----------------------------------------------------------
  # Read historical baseline
  # ----------------------------------------------------------

  history <- readRDS(
    baseline_file
  ) %>%
    filter(
      Component == "LMP",
      Node %in% named_hubs
    )

  # ----------------------------------------------------------
  # Hub-specific empirical thresholds
  # ----------------------------------------------------------

  hub_thresholds <- history %>%
    group_by(Node) %>%
    summarise(
      N = n(),
      MedianAbsSpread = median(
        AbsSpread,
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
      ),
      .groups = "drop"
    )

  # ----------------------------------------------------------
  # Hub x Hour robust diagnostic baseline
  # ----------------------------------------------------------

  hub_hour_baseline <- history %>%
    group_by(
      Node,
      HourEnding
    ) %>%
    summarise(
      N_History = n(),

      HistoricalMedian = median(
        Spread,
        na.rm = TRUE
      ),

      HistoricalMAD = mad(
        Spread,
        center = HistoricalMedian,
        constant = 1,
        na.rm = TRUE
      ),

      HistoricalP95Abs = quantile(
        AbsSpread,
        0.95,
        na.rm = TRUE
      ),

      .groups = "drop"
    )

  # ----------------------------------------------------------
  # Evaluate monitored day
  # ----------------------------------------------------------

  alerts <- event_lmp %>%
    left_join(
      hub_thresholds %>%
        select(
          Node,
          HubP95 = P95_AbsSpread,
          HubP99 = P99_AbsSpread
        ),
      by = "Node"
    ) %>%
    left_join(
      hub_hour_baseline,
      by = c(
        "Node",
        "HourEnding"
      )
    ) %>%
    mutate(

      RobustScale =
        1.4826 * HistoricalMAD,

      RobustZ = if_else(
        RobustScale > 0,
        abs(
          Spread - HistoricalMedian
        ) / RobustScale,
        NA_real_
      ),

      # Primary automated alert rule:
      # flag a hub-hour when the absolute DA-RT spread
      # exceeds that hub's historical 99th percentile.
      Alert_HubP99 =
        AbsSpread > HubP99,

      # Secondary diagnostic only.
      Alert_Robust =
        RobustZ >= 6,

      Alert_Primary =
        Alert_HubP99
    )

  # ----------------------------------------------------------
  # Save alert table
  # ----------------------------------------------------------

  alert_table <- alerts %>%
    arrange(
      desc(Alert_Primary),
      desc(AbsSpread)
    ) %>%
    select(
      MarketDay,
      HourEnding,
      Node,
      DA_Value,
      RT_Value,
      Spread,
      AbsSpread,
      HubP99,
      HistoricalMedian,
      HistoricalMAD,
      RobustZ,
      Alert_HubP99,
      Alert_Robust,
      Alert_Primary
    )

  alert_file <- file.path(
    processed_dir,
    paste0(
      "automated_lmp_alerts_",
      date_string,
      ".csv"
    )
  )

  write_csv(
    alert_table,
    alert_file
  )

  # ----------------------------------------------------------
  # Summary
  # ----------------------------------------------------------

  primary_alerts <- alert_table %>%
    filter(
      Alert_Primary
    )

  primary_alert_count <- nrow(
    primary_alerts
  )

  robust_flag_count <- sum(
    alert_table$Alert_Robust,
    na.rm = TRUE
  )

  cat("\n")
  cat("Daily data QA passed.\n")
  cat("Joined hub/component rows:", nrow(daily_spreads_all), "\n")
  cat("LMP hub-hour rows:", nrow(event_lmp), "\n")
  cat("Primary alerts:", primary_alert_count, "\n")
  cat("Robust diagnostic flags:", robust_flag_count, "\n")

  if (primary_alert_count > 0) {

    cat("\nPrimary alerts:\n")

    print(
      primary_alerts %>%
        select(
          HourEnding,
          Node,
          DA_Value,
          RT_Value,
          Spread,
          HubP99
        )
    )
  }

  # ----------------------------------------------------------
  # Render parameterized HTML report
  # ----------------------------------------------------------

  report_output <- NA_character_

  if (render_report) {

    if (!requireNamespace(
      "rmarkdown",
      quietly = TRUE
    )) {
      stop(
        "Package 'rmarkdown' is required to render the HTML report."
      )
    }

    rmd_file <- file.path(
      report_dir,
      "daily_market_monitor.Rmd"
    )

    if (!file.exists(rmd_file)) {
      stop(
        "R Markdown report template not found: ",
        rmd_file
      )
    }

    report_filename <- paste0(
      "daily_market_monitor_",
      date_string,
      ".html"
    )

    cat("\nRendering HTML report...\n")

    report_output <- rmarkdown::render(
      input = rmd_file,
      params = list(
        market_date = as.character(
          market_date
        )
      ),
      output_file = report_filename,
      output_dir = normalizePath(
        report_dir,
        mustWork = FALSE
      ),
      knit_root_dir = getwd(),
      quiet = TRUE
    )

    cat(
      "Report created:",
      report_output,
      "\n"
    )
  }

  cat("\n")
  cat("============================================\n")
  cat("Daily monitoring workflow completed\n")
  cat("============================================\n")

  # ----------------------------------------------------------
  # Return useful objects invisibly
  # ----------------------------------------------------------

  invisible(
    list(
      market_date = market_date,
      da_status = da_status,
      rt_status = rt_status,
      daily_spread_file = daily_spread_file,
      alert_file = alert_file,
      report_output = report_output,
      primary_alert_count = primary_alert_count,
      robust_flag_count = robust_flag_count,
      alerts = alert_table
    )
  )
}
