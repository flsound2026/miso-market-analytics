# ============================================================
# MISO Market R&D Portfolio Project
# 01_baseline_dcopf.py
#
# Purpose:
#   Solve a synthetic 5-bus DC optimal power flow (DC-OPF)
#   problem using Pyomo and HiGHS.
#
#   The model demonstrates:
#     - least-cost generation dispatch
#     - DC power-flow equations
#     - transmission limits
#     - nodal power balance
#     - locational marginal prices (LMPs) from dual values
#
# Important:
#   This is a synthetic educational system. It is NOT a model
#   of the actual MISO transmission network.
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
# 1. Synthetic system data
# ============================================================

# ------------------------------------------------------------
# Buses and fixed load
# ------------------------------------------------------------

buses = [1, 2, 3, 4, 5]

load = {
    1: 40.0,
    2: 55.0,
    3: 70.0,
    4: 65.0,
    5: 50.0,
}

# Total system load = 280 MW


# ------------------------------------------------------------
# Generators
#
# cost = linear marginal production cost ($/MWh)
# pmax = maximum generation capacity (MW)
# ------------------------------------------------------------

generators = {
    "G1": {
        "bus": 1,
        "pmax": 120.0,
        "cost": 18.0,
    },
    "G2": {
        "bus": 2,
        "pmax": 100.0,
        "cost": 22.0,
    },
    "G3": {
        "bus": 3,
        "pmax": 80.0,
        "cost": 35.0,
    },
    "G4": {
        "bus": 4,
        "pmax": 70.0,
        "cost": 50.0,
    },
    "G5": {
        "bus": 5,
        "pmax": 60.0,
        "cost": 65.0,
    },
}


# ------------------------------------------------------------
# Transmission lines
#
# x     = line reactance (per unit)
# limit = symmetric thermal capacity (MW)
#
# DC flow:
#
#     F_ij = BaseMVA / x_ij * (theta_i - theta_j)
#
# ------------------------------------------------------------

lines = {
    "L12": {
        "from_bus": 1,
        "to_bus": 2,
        "x": 0.10,
        "limit": 120.0,
    },
    "L13": {
        "from_bus": 1,
        "to_bus": 3,
        "x": 0.12,
        "limit": 120.0,
    },
    "L23": {
        "from_bus": 2,
        "to_bus": 3,
        "x": 0.10,
        "limit": 100.0,
    },
    "L24": {
        "from_bus": 2,
        "to_bus": 4,
        "x": 0.15,
        "limit": 100.0,
    },
    "L35": {
        "from_bus": 3,
        "to_bus": 5,
        "x": 0.10,
        "limit": 100.0,
    },
    "L45": {
        "from_bus": 4,
        "to_bus": 5,
        "x": 0.10,
        "limit": 100.0,
    },
}

BASE_MVA = 100.0


# ============================================================
# 2. Build Pyomo model
# ============================================================

model = pyo.ConcreteModel()

model.BUSES = pyo.Set(
    initialize=buses
)

model.GENERATORS = pyo.Set(
    initialize=list(generators.keys())
)

model.LINES = pyo.Set(
    initialize=list(lines.keys())
)


# ============================================================
# 3. Decision variables
# ============================================================

# Generator output (MW)

def generator_bounds(model, g):
    return 0.0, generators[g]["pmax"]


model.pg = pyo.Var(
    model.GENERATORS,
    within=pyo.NonNegativeReals,
    bounds=generator_bounds
)


# Voltage phase angle (radians)

model.theta = pyo.Var(
    model.BUSES,
    within=pyo.Reals
)


# Directed line flow (MW)

model.flow = pyo.Var(
    model.LINES,
    within=pyo.Reals
)


# ============================================================
# 4. Objective function
# ============================================================

def total_generation_cost(model):

    return sum(
        generators[g]["cost"] * model.pg[g]
        for g in model.GENERATORS
    )


model.objective = pyo.Objective(
    rule=total_generation_cost,
    sense=pyo.minimize
)


# ============================================================
# 5. DC power-flow equations
# ============================================================

def dc_flow_rule(model, line):

    from_bus = lines[line]["from_bus"]
    to_bus = lines[line]["to_bus"]
    x = lines[line]["x"]

    return (
        model.flow[line]
        ==
        BASE_MVA / x
        * (
            model.theta[from_bus]
            - model.theta[to_bus]
        )
    )


model.dc_flow = pyo.Constraint(
    model.LINES,
    rule=dc_flow_rule
)


# ============================================================
# 6. Transmission capacity constraints
# ============================================================

def line_upper_rule(model, line):

    return (
        model.flow[line]
        <= lines[line]["limit"]
    )


def line_lower_rule(model, line):

    return (
        -model.flow[line]
        <= lines[line]["limit"]
    )


model.line_upper = pyo.Constraint(
    model.LINES,
    rule=line_upper_rule
)

model.line_lower = pyo.Constraint(
    model.LINES,
    rule=line_lower_rule
)


# ============================================================
# 7. Nodal power balance
#
# Formulation:
#
#   Load
#   + outbound flow
#   - inbound flow
#   - generation
#   = 0
#
# The economic LMP is recovered from the solver dual.
# With the HiGHS/Pyomo dual convention used here,
# LMP = -dual(balance constraint).
# ============================================================

def nodal_balance_rule(model, bus):

    generation_at_bus = sum(
        model.pg[g]
        for g in model.GENERATORS
        if generators[g]["bus"] == bus
    )

    outbound_flow = sum(
        model.flow[line]
        for line in model.LINES
        if lines[line]["from_bus"] == bus
    )

    inbound_flow = sum(
        model.flow[line]
        for line in model.LINES
        if lines[line]["to_bus"] == bus
    )

    return (
        load[bus]
        + outbound_flow
        - inbound_flow
        - generation_at_bus
        == 0
    )


model.balance = pyo.Constraint(
    model.BUSES,
    rule=nodal_balance_rule
)


# ============================================================
# 8. Reference bus angle
#
# Only angle differences matter in DC power flow.
# Fix Bus 1 angle to zero.
# ============================================================

model.reference_bus = pyo.Constraint(
    expr=model.theta[1] == 0
)


# ============================================================
# 9. Request dual values
#
# Duals of nodal balance constraints are used as LMPs.
# ============================================================

model.dual = pyo.Suffix(
    direction=pyo.Suffix.IMPORT
)


# ============================================================
# 10. Solve model
# ============================================================

# Prefer the standard HiGHS interface.
# Fall back to appsi_highs if needed.

highs_solver = pyo.SolverFactory("highs")

if highs_solver.available(exception_flag=False):
    solver = highs_solver
    solver_name = "highs"
else:
    solver = pyo.SolverFactory("appsi_highs")
    solver_name = "appsi_highs"


print("\nSolving baseline DC-OPF...")
print(f"Solver: {solver_name}")

results = solver.solve(
    model,
    tee=False
)


# ============================================================
# 11. Check solver status
# ============================================================

if results.solver.termination_condition != TerminationCondition.optimal:

    raise RuntimeError(
        "Optimization did not terminate with an optimal solution. "
        f"Termination condition: "
        f"{results.solver.termination_condition}"
    )


# ============================================================
# 12. Extract generation dispatch
# ============================================================

dispatch_records = []

for g in model.GENERATORS:

    dispatch_records.append(
        {
            "Generator": g,
            "Bus": generators[g]["bus"],
            "MarginalCost": generators[g]["cost"],
            "Pmax": generators[g]["pmax"],
            "DispatchMW": pyo.value(model.pg[g]),
        }
    )


dispatch_df = pd.DataFrame(dispatch_records)


# ============================================================
# 13. Extract line flows
# ============================================================

flow_records = []

for line in model.LINES:

    flow_value = pyo.value(
        model.flow[line]
    )

    limit = lines[line]["limit"]

    flow_records.append(
        {
            "Line": line,
            "FromBus": lines[line]["from_bus"],
            "ToBus": lines[line]["to_bus"],
            "Reactance": lines[line]["x"],
            "LimitMW": limit,
            "FlowMW": flow_value,
            "UtilizationPct": (
                abs(flow_value) / limit * 100
            ),
        }
    )


flow_df = pd.DataFrame(flow_records)


# ============================================================
# 14. Extract bus angles and LMPs
# ============================================================

bus_records = []

for bus in model.BUSES:

    raw_dual = model.dual[
        model.balance[bus]
    ]

    # HiGHS/Pyomo returns the equality-constraint dual
    # with the opposite sign from the economic marginal
    # cost interpretation used here.
    lmp = -raw_dual

    bus_records.append(
        {
             "Bus": bus,
             "LoadMW": load[bus],
             "AngleRad": pyo.value(
                 model.theta[bus]
             ),
             "LMP": lmp,
        }
    )


bus_df = pd.DataFrame(bus_records)


# ============================================================
# 15. System-level validation
# ============================================================

total_load = sum(
    load.values()
)

total_generation = dispatch_df[
    "DispatchMW"
].sum()

total_cost = pyo.value(
    model.objective
)


if abs(
    total_generation - total_load
) > 1e-6:

    raise RuntimeError(
        "System generation does not equal system load."
    )


# ============================================================
# 16. Print results
# ============================================================

print("\n" + "=" * 60)
print("BASELINE DC-OPF RESULTS")
print("=" * 60)

print(
    f"\nTotal system load: "
    f"{total_load:.2f} MW"
)

print(
    f"Total generation: "
    f"{total_generation:.2f} MW"
)

print(
    f"Total generation cost: "
    f"${total_cost:,.2f}/h"
)


print("\nGenerator Dispatch")
print("-" * 60)

print(
    dispatch_df.to_string(
        index=False,
        float_format=lambda x: f"{x:,.2f}"
    )
)


print("\nTransmission Flows")
print("-" * 60)

print(
    flow_df.to_string(
        index=False,
        float_format=lambda x: f"{x:,.2f}"
    )
)


print("\nBus LMPs")
print("-" * 60)

print(
    bus_df.to_string(
        index=False,
        float_format=lambda x: f"{x:,.2f}"
    )
)


# ============================================================
# 17. Save results
# ============================================================

dispatch_df.to_csv(
    RESULTS_DIR
    / "baseline_generator_dispatch.csv",
    index=False
)

flow_df.to_csv(
    RESULTS_DIR
    / "baseline_line_flows.csv",
    index=False
)

bus_df.to_csv(
    RESULTS_DIR
    / "baseline_bus_lmps.csv",
    index=False
)


print(
    "\nBaseline results saved to:"
)

print(
    RESULTS_DIR.resolve()
)

print(
    "\nBaseline DC-OPF completed successfully."
)
