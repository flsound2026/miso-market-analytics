# MISO Market Analytics Portfolio

This repository contains quantitative market-analysis projects developed using public Midcontinent Independent System Operator (MISO) data.

The projects demonstrate reproducible data analysis, market-event evaluation, statistical reasoning, optimization, and visualization using R and Python.

## Projects

### 1. Market Evaluation

[View the Market Evaluation Case Study](market-evaluation/README.md)

Analysis of Day-Ahead versus Real-Time LMP divergence, including:

- hourly DA–RT price-spread analysis;
- MEC, MCC, and MLC decomposition;
- regional congestion effects;
- MISO load forecast and actual-load context;
- data-quality and reproducibility checks.

The current case study examines an extreme pricing event on September 1, 2026, with particular focus on Hour Ending 19.

### 2. Energy Markets R&D

[View the Energy Market R&D Case Study](market-rnd/README.md)

A synthetic DC optimal power flow study examining:

- least-cost generation dispatch;
- transmission congestion and redispatch;
- nodal locational marginal prices;
- transmission-capacity sensitivity; and
- dual/shadow-price interpretation.

The project connects binding transmission constraints with production cost, locational price separation, and the marginal economic value of transmission capacity.

## Tools

- R
- Python
- Data visualization
- Statistical analysis
- Optimization

## Data

The Market Evaluation case study uses publicly available MISO market data.

The Energy Markets R&D case study uses a synthetic five-bus system designed to demonstrate market-clearing optimization, transmission congestion, LMP formation, and dual sensitivity analysis.

Large raw source files are excluded from version control. Reproducible scripts and compact analytical outputs are retained in the repository.
