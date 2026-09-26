# ============================================================
# MISO Market Evaluation Project
# 02_he19_event_analysis.R
#
# Case study:
#   Extreme Day-Ahead vs. Real-Time price divergence
#   on September 1, 2026, especially HE19.
# ============================================================

library(tidyverse)

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

processed_dir <- "market-evaluation/data/processed"
figure_dir <- "market-evaluation/figures"

dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# Load prepared data
# ------------------------------------------------------------

lmp <- readRDS(
  file.path(processed_dir, "lmp_sample_20260901.rds")
)

load_data <- readRDS(
  file.path(processed_dir, "miso_load_20260901.rds")
)

# ------------------------------------------------------------
# Named hubs
# Ordered approximately north to south for presentation
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

hub_labels <- c(
  "MINN.HUB" = "Minnesota",
  "MICHIGAN.HUB" = "Michigan",
  "ILLINOIS.HUB" = "Illinois",
  "INDIANA.HUB" = "Indiana",
  "ARKANSAS.HUB" = "Arkansas",
  "MS.HUB" = "Mississippi",
  "LOUISIANA.HUB" = "Louisiana",
  "TEXAS.HUB" = "Texas"
)

# ============================================================
# Figure 1
# Heatmap of Real-Time minus Day-Ahead LMP spreads
# ============================================================

heatmap_data <- lmp %>%
  filter(
    Node %in% named_hubs,
    Component == "LMP"
  ) %>%
  mutate(
    Hub = recode(Node, !!!hub_labels),
    Hub = factor(
      Hub,
      levels = rev(unname(hub_labels[named_hubs]))
    )
  )

# Symmetric scale around zero for a fair comparison
heat_limit <- ceiling(
  max(abs(heatmap_data$Spread), na.rm = TRUE) / 100
) * 100

fig1 <- ggplot(
  heatmap_data,
  aes(
    x = HourEnding,
    y = Hub,
    fill = Spread
  )
) +
  geom_tile() +
  geom_vline(
    xintercept = 19,
    linetype = "dashed",
    linewidth = 0.6
  ) +
  scale_x_continuous(
    breaks = 1:24,
    expand = c(0, 0)
  ) +
  scale_fill_gradient2(
    midpoint = 0,
    limits = c(-heat_limit, heat_limit),
    breaks = seq(-heat_limit, heat_limit, by = 200),
    name = "RT - DA\n($/MWh)"
  ) +
  labs(
    title = "Day-Ahead vs. Real-Time LMP Divergence Across MISO Hubs",
    subtitle = "September 1, 2026 | Extreme divergence emerged in HE19",
    x = "Hour Ending (EST)",
    y = NULL,
    caption = paste(
      "Source: MISO Day-Ahead ExPost and Real-Time Final LMP reports.",
      "Dashed line marks HE19."
    )
  ) +
  theme_minimal(base_size = 13) +
  theme(
    panel.grid = element_blank(),
    legend.position = "right",
    plot.title = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0)
  )

fig1

ggsave(
  file.path(
    figure_dir,
    "fig1_named_hub_da_rt_spread_heatmap.png"
  ),
  fig1,
  width = 11,
  height = 6,
  dpi = 300
)

# ============================================================
# Figure 2
# HE19 LMP spread decomposition
#
# LMP = MEC + MCC + MLC
# ============================================================

he19_wide <- lmp %>%
  filter(
    Node %in% named_hubs,
    HourEnding == 19
  ) %>%
  select(
    Node,
    Component,
    DA_Value,
    RT_Value,
    Spread
  ) %>%
  pivot_wider(
    names_from = Component,
    values_from = c(
      DA_Value,
      RT_Value,
      Spread
    )
  ) %>%
  mutate(
    DA_MEC =
      DA_Value_LMP -
      DA_Value_MCC -
      DA_Value_MLC,
    
    RT_MEC =
      RT_Value_LMP -
      RT_Value_MCC -
      RT_Value_MLC,
    
    MECSpread =
      RT_MEC - DA_MEC,
    
    MCCSpread =
      Spread_MCC,
    
    MLCSpread =
      Spread_MLC,
    
    LMPSpread =
      Spread_LMP,
    
    Hub = recode(Node, !!!hub_labels),
    
    Hub = factor(
      Hub,
      levels = unname(hub_labels[named_hubs])
    )
  )

# ------------------------------------------------------------
# Verify decomposition
# ------------------------------------------------------------

he19_wide <- he19_wide %>%
  mutate(
    ReconstructedSpread =
      MECSpread +
      MCCSpread +
      MLCSpread,
    
    DecompositionError =
      LMPSpread -
      ReconstructedSpread,
    
    TotalLabel = sprintf("%+.0f", LMPSpread),
    
    LabelVjust = if_else(
      LMPSpread >= 0,
      -0.9,
      1.5
    )
  )

stopifnot(
  max(
    abs(he19_wide$DecompositionError),
    na.rm = TRUE
  ) < 0.1
)

# ------------------------------------------------------------
# Long format
# ------------------------------------------------------------

component_data <- he19_wide %>%
  select(
    Hub,
    MECSpread,
    MCCSpread,
    MLCSpread
  ) %>%
  pivot_longer(
    cols = c(
      MECSpread,
      MCCSpread,
      MLCSpread
    ),
    names_to = "Component",
    values_to = "SpreadContribution"
  ) %>%
  mutate(
    Component = recode(
      Component,
      "MECSpread" = "MEC (Energy)",
      "MCCSpread" = "MCC (Congestion)",
      "MLCSpread" = "MLC (Loss)"
    ),
    Component = factor(
      Component,
      levels = c(
        "MEC (Energy)",
        "MCC (Congestion)",
        "MLC (Loss)"
      )
    )
  )

# ------------------------------------------------------------
# Plot
# ------------------------------------------------------------

fig2 <- ggplot(
  component_data,
  aes(
    x = Hub,
    y = SpreadContribution,
    fill = Component
  )
) +
  geom_col() +
  geom_hline(
    yintercept = 0,
    linewidth = 0.4
  ) +
  geom_point(
    data = he19_wide,
    aes(
      x = Hub,
      y = LMPSpread
    ),
    inherit.aes = FALSE,
    size = 3
  ) +
  geom_text(
    data = he19_wide,
    aes(
      x = Hub,
      y = LMPSpread,
      label = TotalLabel,
      vjust = LabelVjust
    ),
    inherit.aes = FALSE,
    size = 3.3
  ) +
  scale_y_continuous(
    labels = scales::label_number(
      accuracy = 1,
      big.mark = ","
    ),
    expand = expansion(mult = c(0.10, 0.15))
  ) +
  labs(
    title = "HE19 Day-Ahead to Real-Time LMP Spread Decomposition",
    subtitle = paste(
      "A common MEC increase was amplified or offset",
      "by locational congestion and losses"
    ),
    x = NULL,
    y = "RT - DA Component Change ($/MWh)",
    fill = "LMP Component",
    caption = paste(
      "Black points and labels show total RT - DA LMP spread.",
      "Source: MISO public market reports."
    )
  ) +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(
      angle = 30,
      hjust = 1
    ),
    legend.position = "right",
    plot.title = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0)
  )

fig2

ggsave(
  file.path(
    figure_dir,
    "fig2_he19_lmp_spread_decomposition.png"
  ),
  fig2,
  width = 11,
  height = 6.5,
  dpi = 300
)

# ============================================================
# Export small summary tables for GitHub / README
# ============================================================

write_csv(
  he19_wide %>%
    transmute(
      Node,
      DA_LMP = DA_Value_LMP,
      RT_LMP = RT_Value_LMP,
      LMP_Spread = LMPSpread,
      DA_MEC,
      RT_MEC,
      MEC_Spread = MECSpread,
      MCC_Spread = MCCSpread,
      MLC_Spread = MLCSpread
    ),
  file.path(
    processed_dir,
    "he19_lmp_decomposition_20260901.csv"
  )
)

cat("HE19 event analysis completed successfully.\n")