# 离散事件的最小演示：连续积分 + 一个时间事件 + 复位
#
# 本章的 ESML 子集还没有 <when> 解析；这里先用 SciML 回调演示
# 「事件在求解器里长什么样」，第 9 章会说明它与语言层 when 的对应。

function simulate_with_reset(doc::Document; t_event=30.0, new_value=50.0, saveat=1.0)
    c = compile_model(doc)
    u0 = Dict(c.states[s.name] => s.initial for s in doc.states)
    p = Dict(c.params[p.name] => p.default for p in doc.params)
    prob = ODEProblem(c.sys, merge(u0, p), doc.tspan)
    cb = ContinuousCallback(
        (u, t, integrator) -> t - t_event,
        integrator -> (integrator.u[1] = new_value),
    )
    sol = solve(prob, Tsit5(); callback=cb, tstops=[t_event], saveat=saveat)
    (sol=sol, sys=c.sys, states=c.states)
end
