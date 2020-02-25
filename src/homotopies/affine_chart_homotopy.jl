export AffineChartHomotopy, on_affine_chart

"""
    AffineChartHomotopy(H::AbstractHomotopy, v::PVector)

Augment the homotopy `H` with the given patch `v`.
This results in the system `[H(x,t); vᵀx - 1]`.
"""
struct AffineChartHomotopy{H<:AbstractHomotopy,N} <: AbstractHomotopy
    homotopy::H
    chart::PVector{ComplexF64,N}
end

"""
    on_affine_chart(H::AbstractHomotopy, proj_dims::NTuple{N,Int}) where {N}

Construct an `AffineChartHomotopy` on a randomly generated chart `v`. Each entry is drawn
idepdently from a univariate normal distribution.
"""
function on_affine_chart(H::AbstractHomotopy, dims::NTuple{N,Int}) where {N}
    chart = PVector(randn(ComplexF64, sum(dims) + N), dims)
    AffineChartHomotopy(H, chart)
end

function Base.size(H::AffineChartHomotopy{<:AbstractHomotopy,N}) where {N}
    m, n = size(H.homotopy)
    (m + N, n)
end

function evaluate_chart!(u, v::PVector{<:Any,N}, x::PVector{<:Any,N}) where {N}
    ranges = dimension_indices(v)
    n = length(u) - N
    for (k, range) in enumerate(ranges)
        out = zero(eltype(u))
        @inbounds for i in range
            out += v[i] * x[i]
        end
        u[n+k] = out - 1.0
    end
    nothing
end

function jacobian_chart!(U, v::PVector{<:Any,N}, x::PVector{<:Any,N}) where {N}
    ranges = dimension_indices(v)
    n = size(U, 1) - N
    for j = 1:size(U, 2), i = (n+1):size(U, 1)
        U[i, j] = zero(eltype(U))
    end
    for (k, range) in enumerate(ranges)
        for j in range
            U[n+k, j] = v[j]
        end
    end
    nothing
end

on_chart!(x::PVector, H::AffineChartHomotopy) = on_chart!(x, H.chart)
function on_chart!(x::PVector{<:Any,N}, v::PVector{<:Any,N}) where {N}
    ranges = dimension_indices(v)
    for range in ranges
        λ = zero(eltype(x))
        @inbounds for i in range
            λ += v[i] * x[i]
        end
        λ⁻¹ = @fastmath inv(λ)
        for i in range
            x[i] *= λ⁻¹
        end
    end
    x
end

function evaluate!(u, H::AffineChartHomotopy{<:Any,N}, x::PVector{<:Any,N}, t) where {N}
    evaluate!(u, H.homotopy, x, t)
    evaluate_chart!(u, H.chart, x)
    u
end

function evaluate_and_jacobian!(
    u,
    U,
    H::AffineChartHomotopy{<:Any,N},
    x::PVector{<:Any,N},
    t,
) where {N}
    evaluate_and_jacobian!(u, U, H.homotopy, x, t)
    evaluate_chart!(u, H.chart, x)
    jacobian_chart!(U, H.chart, x)
    nothing
end

function diff_t!(u, H::AffineChartHomotopy, x::PVector{<:Any,N}, t, dx = ()) where {N}
    u .= zero(eltype(u))
    diff_t!(u, H.homotopy, x, t, dx)
    # affine chart part is always zero since it is a affine linear form
    u
end