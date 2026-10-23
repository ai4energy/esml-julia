# 方程表达式：受限的 ESML 方程语法
#
# 支持：数字、标识符、+ - * / ^、括号、D(x)。
# 这不是完整的表达式前端；第 2 章会在同一 AST 上扩展函数、索引与比较。

const TOKEN_RE = r"\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|<=|>=|==|[A-Za-z_]\w*|[()+\-*/^,<>]"

function tokenize(s::AbstractString)
    toks = String[]
    pos = 1
    while pos <= lastindex(s)
        m = match(TOKEN_RE, s, pos)
        m === nothing && (pos = nextind(s, pos); continue)
        push!(toks, m.match)
        pos = m.offset + ncodeunits(m.match)
    end
    toks
end

mutable struct ExprParser
    tokens::Vector{String}
    pos::Int
end

peek(p::ExprParser) = p.pos <= length(p.tokens) ? p.tokens[p.pos] : ""
function take!(p::ExprParser)
    t = peek(p)
    p.pos += 1
    t
end

function parse_expr(s::AbstractString)
    p = ExprParser(tokenize(s), 1)
    ast = parse_cmp(p)
    peek(p) == "" || error("unexpected token '$(peek(p))' in '$s'")
    ast
end

function parse_cmp(p)
    node = parse_add(p)
    if peek(p) in ("<", ">", "<=", ">=", "==")
        op = take!(p)
        node = (:cmp, op, node, parse_add(p))
    end
    node
end

function parse_add(p)
    node = parse_mul(p)
    while peek(p) in ("+", "-")
        op = take!(p)
        node = (:bin, op, node, parse_mul(p))
    end
    node
end

function parse_mul(p)
    node = parse_pow(p)
    while peek(p) in ("*", "/")
        op = take!(p)
        node = (:bin, op, node, parse_pow(p))
    end
    node
end

function parse_pow(p)
    node = parse_unary(p)
    if peek(p) == "^"
        take!(p)
        return (:bin, "^", node, parse_pow(p))
    end
    node
end

function parse_unary(p)
    if peek(p) == "-"
        take!(p)
        return (:neg, parse_unary(p))
    end
    parse_primary(p)
end

function parse_primary(p)
    t = take!(p)
    isempty(t) && error("unexpected end of expression")
    if t == "("
        node = parse_add(p)
        take!(p) == ")" || error("missing ')'")
        return node
    elseif occursin(r"^\d", t)
        return (:num, parse(Float64, t))
    elseif t == "D"
        take!(p) == "(" || error("D must be followed by '('")
        arg = parse_add(p)
        take!(p) == ")" || error("missing ')' after D(...)")
        return (:call, "D", [arg])
    elseif occursin(r"^[A-Za-z_]\w*$", t) && peek(p) == "("
        take!(p)
        args = Any[]
        if peek(p) != ")"
            push!(args, parse_cmp(p))
            while peek(p) == ","
                take!(p); push!(args, parse_cmp(p))
            end
        end
        take!(p) == ")" || error("missing ')' after $t(...)")
        return (:call, t, args)
    else
        return (:var, t)
    end
end

function to_symbolic(ast, states, params, t)
    if ast[1] == :num
        return ast[2]
    elseif ast[1] == :var
        name = ast[2]
        haskey(states, name) && return states[name]
        haskey(params, name) && return params[name]
        return Symbolics.variable(Symbol(name))
    elseif ast[1] == :neg
        return -to_symbolic(ast[2], states, params, t)
    elseif ast[1] == :bin
        op, l, r = ast[2], ast[3], ast[4]
        a = to_symbolic(l, states, params, t)
        b = to_symbolic(r, states, params, t)
        op == "+" && return a + b
        op == "-" && return a - b
        op == "*" && return a * b
        op == "/" && return a / b
        op == "^" && return a^b
        error("unknown operator $op")
    elseif ast[1] == :call && ast[2] == "D"
        arg = ast[3][1]
        arg[1] == :var || error("D(...) argument must be a variable")
        name = arg[2]
        haskey(states, name) || error("D($name): '$name' is not a state")
        return Differential(t)(states[name])
    elseif ast[1] == :cmp
        op, l, r = ast[2], ast[3], ast[4]
        a = to_symbolic(l, states, params, t); b = to_symbolic(r, states, params, t)
        op == "<" && return a < b
        op == ">" && return a > b
        op == "<=" && return a <= b
        op == ">=" && return a >= b
        op == "==" && return a == b
        error("unknown comparison $op")
    elseif ast[1] == :call
        fn = ast[2]
        args = [to_symbolic(a, states, params, t) for a in ast[3]]
        fn == "exp" && return exp(args[1])
        fn == "log" && return log(args[1])
        fn == "log10" && return log10(args[1])
        fn == "sqrt" && return sqrt(args[1])
        fn == "abs" && return abs(args[1])
        fn == "sin" && return sin(args[1])
        fn == "cos" && return cos(args[1])
        fn == "tan" && return tan(args[1])
        fn == "sinh" && return sinh(args[1])
        fn == "asinh" && return asinh(args[1])
        fn == "acosh" && return acosh(args[1])
        fn == "atanh" && return atanh(args[1])
        fn == "cosh" && return cosh(args[1])
        fn == "tanh" && return tanh(args[1])
        fn == "ifelse" && return ifelse(args[1], args[2], args[3])
        fn == "min" && return min(args...)
        fn == "max" && return max(args...)
        error("unsupported function $fn")
    end
    error("unsupported expression node: $(ast[1])")
end
