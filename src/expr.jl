# 方程表达式：受限的 ESML 方程语法
#
# 支持：数字、标识符、+ - * / ^、括号、D(x)。
# 这不是完整的表达式前端；第 2 章会在同一 AST 上扩展函数、索引与比较。

const TOKEN_RE = r"\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[A-Za-z_]\w*|[()+\-*/^,]"

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
    ast = parse_add(p)
    peek(p) == "" || error("unexpected token '$(peek(p))' in '$s'")
    ast
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
    end
    error("unsupported expression node: $(ast[1])")
end
