# MISO Market Evaluation Case Study

## Day-Ahead vs. Real-Time LMP Divergence on September 1, 2026

This project examines Day-Ahead (DA) and Real-Time (RT) electricity price divergence in the Midcontinent Independent System Operator (MISO) market.

The analysis focuses on September 1, 2026, when an unusually large DA–RT price divergence emerged during Hour Ending 19 (HE19). The objective is to identify the event, decompose the price change into LMP components, and evaluate whether system-wide load conditions provide a simple explanation for the event.

The analysis uses public MISO market reports and is implemented in R.

---

## Key Findings

### 1. HE19 showed an extreme DA–RT price divergence

Across eight major MISO pricing hubs, DA and RT LMPs were generally much closer during most hours of the day. A pronounced divergence appeared in HE19.

The effect was strongly regional:

- Michigan: approximately **+$673/MWh**
- Illinois: approximately **+$650/MWh**
- Indiana: approximately **+$591/MWh**
- Minnesota: approximately **+$442/MWh**
- Arkansas: approximately **−$66/MWh**
- Mississippi: approximately **−$68/MWh**
- Louisiana: approximately **−$114/MWh**
- Texas: approximately **−$110/MWh**

Positive values indicate RT LMP above DA LMP.

![DA-RT LMP Spread Heatmap](figures/fig1_named_hub_da_rt_spread_heatmap.png)

The heatmap shows both the timing and geographic pattern of the event. HE19 stands out sharply relative to the rest of the day.

---

## 2. The common energy component increased by about $608/MWh

For each hub, LMP was decomposed using:

\[
LMP = MEC + MCC + MLC
\]

where:

- **MEC** = Marginal Energy Component
- **MCC** = Marginal Congestion Component
- **MLC** = Marginal Loss Component

Because the public LMP files directly provide LMP, MCC, and MLC, the marginal energy component was recovered as:

\[
MEC = LMP - MCC - MLC
\]

For HE19, the inferred DA-to-RT change in MEC was approximately:

\[
\Delta MEC \approx +\$608/MWh
\]

at all eight named hubs analyzed.

This indicates that a large common energy-price increase was present across the market.

---

## 3. Congestion produced sharply different regional price outcomes

The common MEC increase did not translate into similar LMP changes at every location.

In Michigan, Illinois, and Indiana, congestion and loss adjustments were relatively small compared with the common MEC increase. As a result, most of the energy-price increase remained visible in the final RT–DA LMP spread.

In the southern hubs, however, large negative congestion-component changes offset the common energy increase.

For example:

- **Michigan**
  - MEC change: approximately +$608/MWh
  - MCC change: approximately +$55/MWh
  - MLC change: approximately +$10/MWh
  - Total LMP spread: approximately **+$673/MWh**

- **Louisiana**
  - MEC change: approximately +$608/MWh
  - MCC change: approximately −$670/MWh
  - MLC change: approximately −$52/MWh
  - Total LMP spread: approximately **−$114/MWh**

![HE19 LMP Decomposition](figures/fig2_he19_lmp_spread_decomposition.png)

The black points in the figure show the total RT–DA LMP spread. The bars show the MEC, MCC, and MLC contributions.

The decomposition satisfies, up to numerical rounding,

\[
\Delta LMP =
\Delta MEC +
\Delta MCC +
\Delta MLC
\]

for every hub included in the analysis.

---

## 4. HE19 was not the system-load peak

MISO-wide historical forecast and actual load data were used to provide additional context.

On September 1, 2026:

- HE19 reported ActualLoad: approximately **116,540 MWh**
- Daily maximum ActualLoad: approximately **120,422 MWh**
- Daily maximum occurred at **HE17**
- HE19 load forecast error: approximately **−776 MWh**

Therefore, the extreme HE19 price divergence did **not** coincide with the day's maximum system load.

The HE19 system-wide forecast error was also smaller than several forecast errors observed earlier in the day.

This suggests that neither peak system load nor an unusually large system-wide load forecast error provides a sufficient standalone explanation for the HE19 pricing event.

---

## Analytical Workflow

The project follows a simple market-evaluation workflow:

1. **Prepare market data**
   - Read MISO Day-Ahead ExPost LMP data
   - Read MISO Real-Time Final LMP data
   - Convert hourly columns from wide to long format
   - Match DA and RT observations by market day, hour, node, node type, and LMP component

2. **Detect DA–RT divergence**
   - Calculate

     \[
     Spread = RT - DA
     \]

   - Compare spreads by hour and pricing hub

3. **Identify the event**
   - HE19 is identified as the most pronounced divergence period on the sample day

4. **Decompose the LMP spread**
   - Separate the change into MEC, MCC, and MLC contributions

5. **Evaluate load context**
   - Compare HE19 load with the daily peak
   - Examine forecast-versus-actual load error

6. **Validate results**
   - Check the algebraic LMP decomposition
   - Check hourly load completeness
   - Check for duplicate date-hour-zone observations

---

## Data

The case study uses three MISO public market reports:

```text
20260901_da_expost_lmp.csv
20260901_rt_lmp_final.csv
20260925_dfal_HIST.xls
```

### Obtaining the raw data

Raw MISO source files are not stored in this repository because they are public market reports and can be relatively large.

To reproduce the case study, download the corresponding reports from the MISO Market Reports page and place them in:

```text
market-evaluation/data/raw/
```

using the following filenames:

```text
20260901_da_expost_lmp.csv
20260901_rt_lmp_final.csv
20260925_dfal_HIST.xls
```

The analysis scripts expect these filenames and this directory structure.

The September 25 historical load report contains observations for earlier market dates, including September 1. The analysis matches observations using the `MarketDay` field rather than the report publication date.

---

## Data Quality Checks

The historical load file was checked for completeness and duplicate observations.

For each included market date, the data contain 24 hourly observations for each load-resource-zone category, with no duplicate combinations of:

```text
MarketDay × HourEnding × LoadResourceZone
```

Three calendar dates are absent from the historical source file:

```text
2026-04-20
2026-08-17
2026-08-18
```

These missing dates do not affect the September 1 case study.

---

## Reproducing the Analysis

Required R packages:

```r
install.packages(c("tidyverse", "readxl"))
```

After placing the raw MISO files in:

```text
market-evaluation/data/raw/
```

run the scripts from the repository root in order:

```r
source("market-evaluation/R/01_prepare_data.R")
source("market-evaluation/R/02_he19_event_analysis.R")
```

The first script cleans and validates the source data. The second performs the event analysis, creates the figures, and exports the processed summary tables.

---

## Interpretation and Limitations

This case study identifies the price-component structure of the September 1 HE19 event.

The results show that a large common MEC increase occurred, while congestion and losses produced substantially different regional LMP outcomes. The event did not coincide with the day's system-load peak, and the system-wide load forecast error was not unusually large.

The analysis does **not** establish the operational cause of the event.

Additional information on generation availability, outages, reserves, interchange, transmission constraints, and other system conditions would be required for causal attribution.
