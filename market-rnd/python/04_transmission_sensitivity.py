# ============================================================
# MISO Market R&D Portfolio Project
# 04_transmission_sensitivity.py
#
# Purpose:
#   Evaluate how progressively tightening the L24 transmission
#   limit affects:
#     - total production cost
#     - generator dispatch
#     - nodal LMPs
#     - price dispersion
#
# Synthetic system only — not the actual MISO network.
# ============================================================

from pathlib import Path

import pandas as pd
import pyomo.environ as pyo
from pyomo.opt import TerminationCondition
import matplotlib.pyplot as plt


# ============================================================
# Paths
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent

RESULTS_DIR = PROJECT_DIR / "results"
FIGURES_DIR = PROJECT_DIR / "figures"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)
FIGURES_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# System data
# ============================================================

buses = [1, 2, 3, 4, 5]

load = {
    1: 40.0,
    2: 55.0,
    3: 70.0,
    4: 65.0,
    5: 50.0,
}

generators = {
    "G1": {"bus": 1, "pmax": 120.0, "cost": 18.0},
    "G2": {"bus": 2, "pmax": 100.0, "cost": 22.0},
    "G3": {"bus": 3, "pmax": 80.0, "cost": 35.0},
    "G4": {"bus": 4, "pmax": 70.0, "cost": 50.0},
    "G5": {"bus": 5, "pmax": 60.0, "cost": 65.0},
}

base_lines = {
    "L12": {"from_bus": 1, "to_bus": 2, "x": 0.10, "limit": 120.0},
    "L13": {"from_bus": 1, "to_bus": 3, "x": 0.12, "limit": 120.0},
    "L23": {"from_bus": 2, "to_bus": 3, "x": 0.10, "limit": 100.0},
    "L24": {"from_bus": 2, "to_bus": 4, "x": 0.15, "limit": 100.0},
    "L35": {"from_bus": 3, "to_bus": 5, "x": 0.10, "limit": 100.0},
    "L45": {"from_bus": 4, "to_bus": 5, "x": 0.10, "limit": 100.0},
}

BASE_MVA = 100.0


# ============================================================
# Solver function
# ============================================================

def solve_case(l24_limit):

    lines = {
        name: values.copy()
        for name, values in base_lines.items()
    }

    lines["L24"]["limit"] = l24_limit

    model = pyo.ConcreteModel()

    model.BUSES = pyo.Set(initialize=buses)
    model.GENERATORS = pyo.Set(initialize=list(generators.keys()))
    model.LINES = pyo.Set(initialize=list(lines.keys()))

    def generator_bounds(model, g):
        return 0.0, generators[g]["pmax"]

    model.pg = pyo.Var(
        model.GENERATORS,
        within=pyo.NonNegativeReals,
        bounds=generator_bounds
    )

    model.theta = pyo.Var(
        model.BUSES,
        within=pyo.Reals
    )

    model.flow = pyo.Var(
        model.LINES,
        within=pyo.Reals
    )

    model.objective = pyo.Objective(
        expr=sum(
            generators[g]["cost"] * model.pg[g]
            for g in model.GENERATORS
        ),
        sense=pyo.minimize
    )

    def dc_flow_rule(model, line):

        i = lines[line]["from_bus"]
        j = lines[line]["to_bus"]
        x = lines[line]["x"]

        return (
            model.flow[line]
            ==
            BASE_MVA / x
            * (model.theta[i] - model.theta[j])
        )

    model.dc_flow = pyo.Constraint(
        model.LINES,
        rule=dc_flow_rule
    )

    def upper_rule(model, line):
        return model.flow[line] <= lines[line]["limit"]

    def lower_rule(model, line):
        return -model.flow[line] <= lines[line]["limit"]

    model.line_upper = pyo.Constraint(
        model.LINES,
        rule=upper_rule
    )

    model.line_lower = pyo.Constraint(
        model.LINES,
        rule=lower_rule
    )

    def balance_rule(model, bus):

        generation = sum(
            model.pg[g]
            for g in model.GENERATORS
            if generators[g]["bus"] == bus
        )

        outbound = sum(
            model.flow[line]
            for line in model.LINES
            if lines[line]["from_bus"] == bus
        )

        inbound = sum(
            model.flow[line]
            for line in model.LINES
            if lines[line]["to_bus"] == bus
        )

        return (
            load[bus]
            + outbound
            - inbound
            - generation
            == 0
        )

    model.balance = pyo.Constraint(
        model.BUSES,
        rule=balance_rule
    )

    model.reference_bus = pyo.Constraint(
        expr=model.theta[1] == 0
    )

    model.dual = pyo.Suffix(
        direction=pyo.Suffix.IMPORT
    )

    solver = pyo.SolverFactory("highs")

    results = solver.solve(
        model,
        tee=False
    )

    if (
        results.solver.termination_condition
        != TerminationCondition.optimal
    ):
        raise RuntimeError(
            f"L24 limit {l24_limit}: optimization failed."
        )

    total_cost = pyo.value(model.objective)

    l24_flow = pyo.value(
        model.flow["L24"]
    )
    
    # ------------------------------------------------------------
    # Transmission constraint duals
    #
    # For a minimization problem, the dual of a binding
    # upper-bound constraint is typically negative.
    #
    # Economic interpretation:
    #   CapacityValuePerMW =
    #   reduction in optimal production cost from increasing
    #   the symmetric L24 transmission limit by 1 MW.
    # ------------------------------------------------------------

    upper_dual = (
        model.dual.get(
            model.line_upper["L24"],
            0.0
        )
        or 0.0
    )

    lower_dual = (
        model.dual.get(
            model.line_lower["L24"],
            0.0
        )
        or 0.0
    )

    capacity_value_per_mw = -(
        upper_dual + lower_dual
    )

    lmps = {
        bus: -model.dual[model.balance[bus]]
        for bus in buses
    }

    dispatch = {
        g: pyo.value(model.pg[g])
        for g in generators
    }

    return {
           "limit": l24_limit,
           "cost": total_cost,
           "flow": l24_flow,
           "lmps": lmps,
           "dispatch": dispatch,
           "upper_dual": upper_dual,
           "lower_dual": lower_dual,
           "capacity_value_per_mw": capacity_value_per_mw,
    }


# ============================================================
# Sensitivity cases
# ============================================================

limits = [
    100,
    80,
    70,
    60,
    55,
    50,
    45,
    40,
]

cases = []

for limit in limits:

    print(
        f"Solving L24 limit = {limit} MW..."
    )

    cases.append(
        solve_case(limit)
    )


# ============================================================
# Build summary table
# ============================================================

records = []

for case in cases:

    lmp_values = list(
        case["lmps"].values()
    )

    record = {
        "L24LimitMW": case["limit"],
        "L24FlowMW": case["flow"],
        "UtilizationPct":
            abs(case["flow"])
            / case["limit"]
            * 100,
        "TotalCostPerHour": case["cost"],
        "LMPDispersion":
            max(lmp_values)
            - min(lmp_values),
        "UpperConstraintDual":
            case["upper_dual"],
        "LowerConstraintDual":
            case["lower_dual"],
        "CapacityValuePerMW":
            case["capacity_value_per_mw"],
    }

    for bus in buses:
        record[f"Bus{bus}_LMP"] = (
            case["lmps"][bus]
        )

    for g in generators:
        record[f"{g}_DispatchMW"] = (
            case["dispatch"][g]
        )

    records.append(record)


sensitivity = pd.DataFrame(records)

sensitivity.to_csv(
    RESULTS_DIR
    / "transmission_limit_sensitivity.csv",
    index=False
)


# ============================================================
# Print results
# ============================================================

print("\n" + "=" * 75)
print("L24 TRANSMISSION-LIMIT SENSITIVITY")
print("=" * 75)

print(
    sensitivity[
        [
            "L24LimitMW",
            "L24FlowMW",
            "UtilizationPct",
            "TotalCostPerHour",
            "LMPDispersion",
            "CapacityValuePerMW",
        ]
    ].to_string(
        index=False,
        float_format=lambda x: f"{x:,.2f}"
    )
)


# ============================================================
# Figure 3
# Total system production cost
# ============================================================

fig, ax = plt.subplots(
    figsize=(8.5, 5.5)
)

ax.plot(
    sensitivity["L24LimitMW"],
    sensitivity["TotalCostPerHour"],
    marker="o"
)

ax.set_title(
    "Production Cost Increases as Transmission Capacity Tightens",
    fontweight="bold"
)

ax.set_xlabel(
    "L24 Transmission Limit (MW)"
)

ax.set_ylabel(
    "Production Cost ($/h)"
)

ax.invert_xaxis()

ax.grid(
    alpha=0.3
)

plt.tight_layout()

plt.savefig(
    FIGURES_DIR
    / "fig3_transmission_limit_cost_sensitivity.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


# ============================================================
# Figure 4
# Nodal LMP sensitivity
# ============================================================

fig, ax = plt.subplots(
    figsize=(9, 5.5)
)

for bus in buses:

    ax.plot(
        sensitivity["L24LimitMW"],
        sensitivity[f"Bus{bus}_LMP"],
        marker="o",
        label=f"Bus {bus}"
    )

ax.set_title(
    "Nodal LMP Response to a Tightening Transmission Constraint",
    fontweight="bold"
)

ax.set_xlabel(
    "L24 Transmission Limit (MW)"
)

ax.set_ylabel(
    "LMP ($/MWh)"
)

ax.invert_xaxis()

ax.legend(
    title="Location"
)

ax.grid(
    alpha=0.3
)

plt.tight_layout()

plt.savefig(
    FIGURES_DIR
    / "fig4_transmission_limit_lmp_sensitivity.png",
    dpi=300,
    bbox_inches="tight"
)

plt.show()


print(
    "\nTransmission sensitivity analysis completed successfully."
)
