# ============================================================
# MISO Market R&D Portfolio Project
# 02_congested_dcopf.py
#
# Purpose:
#   Compare a baseline DC-OPF with a transmission-constrained
#   scenario and examine:
#     - generator redispatch
#     - binding transmission constraints
#     - total production cost
#     - nodal LMP separation
#
# Synthetic system only — not the actual MISO network.
# ============================================================

from pathlib import Path

import pandas as pd
import pyomo.environ as pyo
from pyomo.opt import TerminationCondition


# ============================================================
# Project paths
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
RESULTS_DIR = PROJECT_DIR / "results"

RESULTS_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# Synthetic system data
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
# DC-OPF solver function
# ============================================================

def solve_dcopf(scenario_name, line_limit_overrides=None):

    if line_limit_overrides is None:
        line_limit_overrides = {}

    lines = {
        name: values.copy()
        for name, values in base_lines.items()
    }

    # Apply scenario-specific transmission limits
    for line, new_limit in line_limit_overrides.items():
        lines[line]["limit"] = new_limit

    model = pyo.ConcreteModel()

    model.BUSES = pyo.Set(initialize=buses)
    model.GENERATORS = pyo.Set(initialize=list(generators.keys()))
    model.LINES = pyo.Set(initialize=list(lines.keys()))

    # --------------------------------------------------------
    # Variables
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # Objective
    # --------------------------------------------------------

    model.objective = pyo.Objective(
        expr=sum(
            generators[g]["cost"] * model.pg[g]
            for g in model.GENERATORS
        ),
        sense=pyo.minimize
    )

    # --------------------------------------------------------
    # DC power flow
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # Transmission limits
    # --------------------------------------------------------

    def line_upper_rule(model, line):
        return model.flow[line] <= lines[line]["limit"]

    def line_lower_rule(model, line):
        return -model.flow[line] <= lines[line]["limit"]

    model.line_upper = pyo.Constraint(
        model.LINES,
        rule=line_upper_rule
    )

    model.line_lower = pyo.Constraint(
        model.LINES,
        rule=line_lower_rule
    )

    # --------------------------------------------------------
    # Nodal balance
    # --------------------------------------------------------

    def nodal_balance_rule(model, bus):

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
        rule=nodal_balance_rule
    )

    # --------------------------------------------------------
    # Reference bus
    # --------------------------------------------------------

    model.reference_bus = pyo.Constraint(
        expr=model.theta[1] == 0
    )

    # --------------------------------------------------------
    # Dual values
    # --------------------------------------------------------

    model.dual = pyo.Suffix(
        direction=pyo.Suffix.IMPORT
    )

    # --------------------------------------------------------
    # Solve
    # --------------------------------------------------------

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
            f"{scenario_name}: optimization failed."
        )

    # --------------------------------------------------------
    # Dispatch results
    # --------------------------------------------------------

    dispatch_records = []

    for g in model.GENERATORS:

        dispatch_records.append(
            {
                "Scenario": scenario_name,
                "Generator": g,
                "Bus": generators[g]["bus"],
                "MarginalCost": generators[g]["cost"],
                "Pmax": generators[g]["pmax"],
                "DispatchMW": pyo.value(model.pg[g]),
            }
        )

    dispatch_df = pd.DataFrame(dispatch_records)

    # --------------------------------------------------------
    # Transmission results
    # --------------------------------------------------------

    flow_records = []

    for line in model.LINES:

        flow_value = pyo.value(model.flow[line])
        limit = lines[line]["limit"]

        flow_records.append(
            {
                "Scenario": scenario_name,
                "Line": line,
                "FromBus": lines[line]["from_bus"],
                "ToBus": lines[line]["to_bus"],
                "LimitMW": limit,
                "FlowMW": flow_value,
                "UtilizationPct":
                    abs(flow_value) / limit * 100,
                "Binding":
                    abs(abs(flow_value) - limit) < 1e-5,
            }
        )

    flow_df = pd.DataFrame(flow_records)

    # --------------------------------------------------------
    # LMP results
    # --------------------------------------------------------

    bus_records = []

    for bus in model.BUSES:

        raw_dual = model.dual[
            model.balance[bus]
        ]

        # Convert solver dual to economic LMP sign convention
        lmp = -raw_dual

        bus_records.append(
            {
                "Scenario": scenario_name,
                "Bus": bus,
                "LoadMW": load[bus],
                "LMP": lmp,
            }
        )

    bus_df = pd.DataFrame(bus_records)

    total_cost = pyo.value(model.objective)

    return {
        "dispatch": dispatch_df,
        "flows": flow_df,
        "lmps": bus_df,
        "total_cost": total_cost,
    }


# ============================================================
# Solve baseline
# ============================================================

baseline = solve_dcopf(
    scenario_name="Baseline"
)


# ============================================================
# Solve congested scenario
#
# L24 is reduced from 100 MW to 50 MW.
# ============================================================

congested = solve_dcopf(
    scenario_name="L24 Limit = 50 MW",
    line_limit_overrides={
        "L24": 50.0
    }
)


# ============================================================
# Combine results
# ============================================================

dispatch_compare = pd.concat(
    [
        baseline["dispatch"],
        congested["dispatch"]
    ],
    ignore_index=True
)

flow_compare = pd.concat(
    [
        baseline["flows"],
        congested["flows"]
    ],
    ignore_index=True
)

lmp_compare = pd.concat(
    [
        baseline["lmps"],
        congested["lmps"]
    ],
    ignore_index=True
)


# ============================================================
# Scenario summary
# ============================================================

cost_change = (
    congested["total_cost"]
    - baseline["total_cost"]
)

print("\n" + "=" * 68)
print("TRANSMISSION CONGESTION SCENARIO")
print("=" * 68)

print(
    f"\nBaseline production cost: "
    f"${baseline['total_cost']:,.2f}/h"
)

print(
    f"Congested production cost: "
    f"${congested['total_cost']:,.2f}/h"
)

print(
    f"Increase due to congestion: "
    f"${cost_change:,.2f}/h"
)


# ============================================================
# Dispatch comparison
# ============================================================

dispatch_pivot = dispatch_compare.pivot(
    index="Generator",
    columns="Scenario",
    values="DispatchMW"
)

dispatch_pivot["ChangeMW"] = (
    dispatch_pivot["L24 Limit = 50 MW"]
    - dispatch_pivot["Baseline"]
)

print("\nGenerator Redispatch")
print("-" * 68)

print(
    dispatch_pivot.to_string(
        float_format=lambda x: f"{x:,.2f}"
    )
)


# ============================================================
# Congested network flows
# ============================================================

print("\nCongested Scenario Line Flows")
print("-" * 68)

print(
    congested["flows"].to_string(
        index=False,
        float_format=lambda x: f"{x:,.2f}"
    )
)


# ============================================================
# LMP comparison
# ============================================================

lmp_pivot = lmp_compare.pivot(
    index="Bus",
    columns="Scenario",
    values="LMP"
)

lmp_pivot["Change"] = (
    lmp_pivot["L24 Limit = 50 MW"]
    - lmp_pivot["Baseline"]
)

print("\nNodal LMP Comparison")
print("-" * 68)

print(
    lmp_pivot.to_string(
        float_format=lambda x: f"{x:,.2f}"
    )
)


# ============================================================
# Save outputs
# ============================================================

dispatch_compare.to_csv(
    RESULTS_DIR / "scenario_generator_dispatch.csv",
    index=False
)

flow_compare.to_csv(
    RESULTS_DIR / "scenario_line_flows.csv",
    index=False
)

lmp_compare.to_csv(
    RESULTS_DIR / "scenario_bus_lmps.csv",
    index=False
)

print(
    "\nScenario results saved successfully."
)

print(
    "\nCongestion analysis completed successfully."
)
