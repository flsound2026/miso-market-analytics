# ============================================================
# MISO Market R&D Portfolio Project
# 03_visualize_scenarios.py
#
# Purpose:
#   Create presentation-ready figures comparing the baseline
#   and transmission-constrained DC-OPF scenarios.
# ============================================================

from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt


# ============================================================
# Paths
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent

RESULTS_DIR = PROJECT_DIR / "results"
FIGURES_DIR = PROJECT_DIR / "figures"

FIGURES_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# Read scenario results
# ============================================================

dispatch = pd.read_csv(
    RESULTS_DIR / "scenario_generator_dispatch.csv"
)

lmps = pd.read_csv(
    RESULTS_DIR / "scenario_bus_lmps.csv"
)


# ============================================================
# Figure 1
# Generator dispatch comparison
# ============================================================

dispatch_plot = dispatch.pivot(
    index="Generator",
    columns="Scenario",
    values="DispatchMW"
)

ax = dispatch_plot.plot(
    kind="bar",
    figsize=(9, 5.5)
)

ax.set_title(
    "Generator Redispatch Under Transmission Congestion",
    fontweight="bold"
)

ax.set_xlabel("Generator")
ax.set_ylabel("Dispatch (MW)")

ax.legend(
    title="Scenario"
)

ax.grid(
    axis="y",
    alpha=0.3
)

plt.xticks(
    rotation=0
)

plt.tight_layout()

plt.savefig(
    FIGURES_DIR / "fig1_generator_redispatch.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# ============================================================
# Figure 2
# Nodal LMP comparison
# ============================================================

lmp_plot = lmps.pivot(
    index="Bus",
    columns="Scenario",
    values="LMP"
)

ax = lmp_plot.plot(
    kind="bar",
    figsize=(9, 5.5)
)

ax.set_title(
    "Transmission Congestion Creates Nodal LMP Separation",
    fontweight="bold"
)

ax.set_xlabel("Bus")
ax.set_ylabel("LMP ($/MWh)")

ax.legend(
    title="Scenario"
)

ax.grid(
    axis="y",
    alpha=0.3
)

plt.xticks(
    rotation=0
)

plt.tight_layout()

plt.savefig(
    FIGURES_DIR / "fig2_nodal_lmp_comparison.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


print("\nScenario figures created successfully.")
print(FIGURES_DIR.resolve())
