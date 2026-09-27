# ============================================================
# MISO Market Evaluation Project
# 04_alert_monitor.R
#
# Purpose:
#   Evaluate Sept. 1, 2026 DA-RT LMP spreads against a
#   historical baseline and generate automated divergence alerts.
#
# Historical baseline:
#   2026-07-01 through 2026-08-31
#
# Alert date:
#   2026-09-01
# ============================================================

library(tidyverse)

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

alert_date <- as.Date("2026-09-01")

processed_dir <- "market-evaluation/data/processed"

history_file <- file.path(
  processed_dir,
  "named_hub_da_rt_history_20260701_20260831.rds"
)

event_file <- file.path(
  processed_dir,
  "lmp_sample_20260901.rds"
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

# ------------------------------------------------------------
# Read historical baseline
# ------------------------------------------------------------

history <- readRDS(
  history_file
) %>%
  filter(
    Component == "LMP",
    Node %in% named_hubs
  )

# ------------------------------------------------------------
# Read Sept. 1 event data
# ------------------------------------------------------------

event <- readRDS(
  event_file
) %>%
  filter(
    MarketDay == alert_date,
    Component == "LMP",
    Node %in% named_hubs
  )

# ------------------------------------------------------------
# Method 1:
# Hub-specific empirical thresholds
#
# Each hub has:
# 62 days × 24 hours = 1,488 historical observations.
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Method 2:
# Hub × Hour robust historical baseline
#
# Median and MAD are resistant to extreme price spikes.
#
# RobustZ =
#   |spread - historical median| /
#   (1.4826 × MAD)
#
# 1.4826 scales MAD to be comparable with standard deviation
# under an approximately normal distribution.
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Evaluate Sept. 1 against historical baseline
# ------------------------------------------------------------

alerts <- event %>%
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
    
    # Robust scale estimate.
    RobustScale = 1.4826 * HistoricalMAD,
    
    RobustZ = if_else(
      RobustScale > 0,
      abs(
        Spread - HistoricalMedian
      ) / RobustScale,
      NA_real_
    ),
    
    # Empirical hub-level alert.
    Alert_HubP99 =
      AbsSpread > HubP99,
    
    # Robust hour-adjusted alert.
    #
    # 6 is intentionally conservative because electricity
    # price spreads have heavy tails.
    Alert_Robust =
      RobustZ >= 6,
    
    # Operational magnitude filter.
    LargeDollarMove =
      AbsSpread >= 100,
    
    # Combined alert:
    # require a meaningful price move plus evidence that it is
    # unusual relative to historical behavior.
    # Primary automated alert rule:
    # flag a hub-hour when the absolute DA-RT spread exceeds
    # that hub's historical 99th percentile.
    Alert_Primary = Alert_HubP99
  )

# ------------------------------------------------------------
# Rank strongest alerts
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Save detailed alert results
# ------------------------------------------------------------

write_csv(
  alert_table,
  file.path(
    processed_dir,
    "automated_lmp_alerts_20260901.csv"
  )
)

# ------------------------------------------------------------
# Summaries
# ------------------------------------------------------------

cat("\n")
cat("============================================\n")
cat("Automated DA-RT LMP Alert Evaluation\n")
cat("============================================\n")

cat(
  "Alert date:",
  as.character(alert_date),
  "\n"
)

cat(
  "Historical LMP observations:",
  nrow(history),
  "\n"
)

cat(
  "Event observations:",
  nrow(event),
  "\n"
)

cat("\nHub-specific thresholds:\n")

print(
  hub_thresholds %>%
    arrange(
      desc(P99_AbsSpread)
    )
)

cat("\nAlert counts:\n")

print(
  alerts %>%
    summarise(
      Primary_Alerts =
        sum(
          Alert_Primary,
          na.rm = TRUE
        ),
      
      Robust_Diagnostic_Flags =
        sum(
          Alert_Robust,
          na.rm = TRUE
        )
    )
)

cat("\nHE19 results:\n")

print(
  alert_table %>%
    filter(
      HourEnding == 19
    ) %>%
    arrange(
      desc(AbsSpread)
    )
)

cat("\n Strongest primary alerts:\n")

print(
  alert_table %>%
    filter(
      Alert_Primary
    ) %>%
    arrange(
      desc(AbsSpread)
    )
)