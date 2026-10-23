"""
ESML.jl — 《ESML 编译器》第二卷的公开参考实现。

第 1 章只覆盖最小链：
    XML → Document → Symbolics → ModelingToolkit → ODEProblem → 数值解

设计边界：这是教学用最小实现，不是生产引擎；生产引擎的工程细节不在本仓。
"""
module ESML

import EzXML: readxml, root, elements, nodename, nodecontent
using Unitful
using Symbolics
using ModelingToolkit
using OrdinaryDiffEq
using DifferentialEquations
using Statistics
using LinearAlgebra

import ModelingToolkit: @variables, @independent_variables, Differential,
                         ODESystem, structural_simplify, ODEProblem

const _T = only(@independent_variables t)

include("document.jl")
include("expr.jl")
include("units.jl")
include("hir.jl")
include("dimensions.jl")
include("structure.jl")
include("symbolic.jl")
include("discrete.jl")
include("tasks.jl")
include("system.jl")
include("components.jl")
include("solve.jl")
include("codegen.jl")

export Document, Parameter, State, Instance, parse_document, ParseError
export parse_unit, check_units, UnitReport, UnitIssue
export check_dimensions, DimensionReport, DimensionIssue
export analyze_structure, StructureReport
export symbolic_rhs, symbolic_derivative, simulate_with_reset
export parse_expr, build_hir, HIR, HirVar, HirParam, compile_model
export simulate, SimulationResult, final_state, solve_steady, build_residual, assemble_components
export TaskSpec, sensitivity, run_task, run_tasks, eval_ast
export CompiledRHS, compile_rhs, rhs_at, rhs_at!, rhs_inputs, sci_rhs

end # module
