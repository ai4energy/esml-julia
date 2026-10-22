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
end
