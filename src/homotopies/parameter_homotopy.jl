"""
    ParameterHomotopy(F::ModelKit.System, p, q)

Construct the `ParameterHomotopy` ``F(x; t p + (1 - t) q)``.
"""
struct ParameterHomotopy{T} <: AbstractHomotopy
    F::ModelKit.CompiledSystem{T}
    p::Vector{ComplexF64}
    q::Vector{ComplexF64}
    #cache
    pt::Vector{ComplexF64}
    ṗt::Tuple{Vector{ComplexF64}}
end

function ParameterHomotopy(F::ModelKit.System, p, q)
    @assert length(p) == length(q) == length(F.parameters)
    ParameterHomotopy(ModelKit.compile(F), p, q)
end
function ParameterHomotopy(F::ModelKit.CompiledSystem, p, q)
    @assert length(p) == length(q)

    p̂ = Vector{ComplexF64}(p)
    q̂ = Vector{ComplexF64}(q)
    pt = zero(p̂)
    ṗt = (zero(p̂),)

    ParameterHomotopy(F, p̂, q̂, pt, ṗt)
end

Base.size(H::ParameterHomotopy) = size(H.F)

p!(H::ParameterHomotopy, t) = (H.pt .= t .* H.p .+ (1.0 .- t) .* H.q; H.pt)
ṗ!(H::ParameterHomotopy, t) = (ṗt = first(H.ṗt); ṗt .= H.p .- H.q; H.ṗt)

evaluate!(u, H::ParameterHomotopy, x, t) =
    ModelKit.evaluate!(u, H.F, x, p!(H, t))
jacobian!(U, H::ParameterHomotopy, x, t) =
    ModelKit.jacobian!(U, H.F, x, p!(H, t))
evaluate_and_jacobian!(u, U, H::ParameterHomotopy, x, t) =
    ModelKit.evaluate_and_jacobian!(u, U, H.F, x, p!(H, t))
diff_t!(u, H::ParameterHomotopy, x, t, dx = ()) =
    ModelKit.diff_t!(u, H.F, x, dx, p!(H, t), ṗ!(H, t))