# MISO Market Analytics Portfolio

This repository contains two quantitative electricity-market projects developed to demonstrate market evaluation, reproducible data analysis, optimization, automated monitoring, and technical communication using R and Python.

The projects are intentionally complementary:

- **Market Evaluation** uses public MISO market reports to analyze Day-Ahead (DA) versus Real-Time (RT) LMP behavior and automate historical-baseline alerts.
- **Energy Markets R&D** uses a synthetic 5-bus power system to demonstrate DC optimal power flow, congestion, redispatch, nodal LMP formation, and transmission sensitivity.

![MISO DA-RT LMP Spread Heatmap](market-evaluation/figures/fig1_named_hub_da_rt_spread_heatmap.png)

## Projects

### 1. Market Evaluation and Automated Monitoring

[View the Market Evaluation project](market-evaluation/README.md)

This project builds a reproducible R workflow around public MISO Day-Ahead ExPost and Real-Time Final LMP reports.

Key elements include:

- automated download and caching of daily MISO LMP reports;
- a 62-day historical baseline covering July 1-August 31, 2026;
- hub-specific empirical 99th-percentile DA-RT spread thresholds;
- automated divergence alerts for eight named MISO hubs;
- a parameterized HTML daily monitoring report;
- MEC, MCC, and MLC decomposition of the September 1, 2026 HE19 event;
- system-load and forecast-error context;
- data-quality and reproducibility checks.

The September 1 out-of-sample monitoring run generated four primary alerts, all at HE19, at the Michigan, Illinois, Indiana, and Minnesota hubs.

A complete daily monitoring run can be executed with:

```r
source("market-evaluation/R/05_run_daily_monitor.R")
run_daily_monitor("2026-09-01")
```

### 2. Energy Markets R&D

[View the Energy Markets R&D project](market-rnd/README.md)

This project uses a **synthetic 5-bus DC optimal power flow model** implemented in Python with Pyomo and HiGHS.

The analysis examines:

- least-cost generation dispatch;
- binding transmission constraints and redispatch;
- nodal locational marginal prices;
- production-cost impacts of congestion;
- transmission-capacity sensitivity; and
- dual/shadow-price interpretation and finite-difference validation.

In the congested scenario, tightening one transmission limit forced approximately 16 MW of redispatch, increased production cost by about $237 per operating hour, and separated a uniform $35/MWh price into nodal LMPs ranging from approximately $29.84 to $50.00/MWh.

The project is designed to demonstrate market-clearing and optimization concepts; it does **not** represent the actual MISO network.

## Tools and Methods

- **R:** data cleaning, market-event analysis, historical baselines, automated alerts, R Markdown reporting
- **Python:** optimization modeling and scenario analysis
- **Pyomo + HiGHS:** DC-OPF formulation and solution
- **Data visualization:** heatmaps, decomposition plots, sensitivity plots
- **Statistical analysis:** empirical thresholds, robust diagnostics, forecasting/load context
- **Optimization:** dispatch, transmission constraints, dual values, sensitivity analysis

## Data and Reproducibility

The two projects use different data sources by design:

- **Market Evaluation:** public MISO market reports, including DA ExPost LMP, RT Final LMP, and historical load data.
- **Energy Markets R&D:** a synthetic 5-bus test system created for demonstration of market-clearing and congestion concepts.

Large raw MISO source files are excluded from version control. Reproducible scripts, compact processed analytical outputs, figures, and example reports are retained in the repository.

## Repository Structure

```text
miso-market-analytics/
├── market-evaluation/
│   ├── R/
│   ├── data/
│   ├── figures/
│   ├── report/
│   └── README.md
├── market-rnd/
│   ├── python/
│   ├── data/
│   ├── figures/
│   └── README.md
└── README.md
```

## Scope

These projects are portfolio case studies intended to demonstrate quantitative analysis, reproducible workflows, and electricity-market modeling. Statistical alerts identify unusual market behavior but do not establish operational causality. The synthetic R&D model is illustrative rather than a representation of the MISO production network.
