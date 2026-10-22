using Test
using ESML

const ROOT = normpath(joinpath(@__DIR__, ".."))

@testset "ESML.jl · 第 1 章最小链" begin
    doc = parse_document(joinpath(ROOT, "examples", "decay.esml"))
    @test doc.model == "Decay"
    @test doc.name == "DecayDemo"
    @test length(doc.params) == 1
    @test doc.params[1].name == "lambda"
    @test doc.params[1].default == 0.05
    @test length(doc.states) == 1
    @test doc.states[1].initial == 100.0
    @test doc.tspan == (0.0, 60.0)
    @test length(doc.equations) == 1

    report = check_units(doc)
    @test report.checked == 2
    @test isempty(report.issues)

    result = simulate(doc; saveat=60.0)
    n60 = final_state(result, "N")
    @test isapprox(n60, 4.978422606072985; rtol=1e-3)

    # 第 2 章：必需属性缺失必须响亮失败，并指出属性名。
    err = try
        parse_document(joinpath(ROOT, "examples", "decay_missing_name.esml"))
        nothing
    catch e
        e
    end
    @test err isa ESML.ParseError
    @test occursin("missing required attribute 'name'", sprint(showerror, err))

    # 第 3 章：实例 → 路径；方程里的名字被改写成路径。
    hir = build_hir(doc)
    @test length(hir.vars) == 1
    @test hir.vars[1].path == "g__N"
    @test length(hir.params) == 1
    @test hir.params[1].path == "g__lambda"
    @test hir.equations == ["D(g__N) = -g__lambda * g__N"]

    two = parse_document(joinpath(ROOT, "examples", "two_decay.esml"))
    hir2 = build_hir(two)
    @test [v.path for v in hir2.vars] == ["g__N", "h__N"]
    @test [p.path for p in hir2.params] == ["g__lambda", "h__lambda"]
    @test hir2.equations == [
        "D(g__N) = -g__lambda * g__N",
        "D(h__N) = -h__lambda * h__N",
    ]

    # 第 4 章：量纲检查（好例通过，坏例报两侧量纲）。
    good = parse_document(joinpath(ROOT, "examples", "decay_units.esml"))
    rgood = check_dimensions(good)
    @test rgood.checked == 1
    @test isempty(rgood.issues)

    bad = parse_document(joinpath(ROOT, "examples", "decay_bad_units.esml"))
    rbad = check_dimensions(bad)
    @test rbad.checked == 1
    @test length(rbad.issues) == 1
    @test occursin("𝐓^-1", rbad.issues[1].message)
    @test occursin("NoDims", rbad.issues[1].message)

    # 第 5 章：自由度与匹配。
    @test analyze_structure(build_hir(doc)).dof == 0
    @test isempty(analyze_structure(build_hir(doc)).unmatched_vars)

    under = build_hir(parse_document(joinpath(ROOT, "examples", "under.esml")))
    ru = analyze_structure(under)
    @test ru.dof == 1
    @test ru.unmatched_vars == ["g__M"]

    over = build_hir(parse_document(joinpath(ROOT, "examples", "over.esml")))
    ro = analyze_structure(over)
    @test ro.dof == -1
    @test ro.unmatched_eqs == [2]

    # 第 6 章：数组实例展开为带下标的路径。
    arr = parse_document(joinpath(ROOT, "examples", "array_decay.esml"))
    @test arr.instances[1].count == 2
    ha = build_hir(arr)
    @test [v.path for v in ha.vars] == ["g_1__N", "g_2__N"]
    @test length(ha.equations) == 2

    # 第 7 章：符号右端与导数。
    sr = symbolic_rhs(doc)
    @test string(sr.rhs) == "-N(t)*lambda"
    @test string(symbolic_derivative(doc, "N")) == "-lambda"
end
