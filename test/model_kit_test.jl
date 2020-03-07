using HomotopyContinuation2.ModelKit

@testset "ModelKit" begin
    @testset "Variables" begin
        @var a b x[1:2] y[1:2, 1:3]

        @test a isa Variable
        @test b isa Variable
        @test x isa Vector{Variable}
        @test length(x) == 2
        @test y isa Matrix{Variable}
        @test size(y) == (2, 3)
        @test join(x, " ") == "x₁ x₂"

        @var c, d
        @test c isa Variable
        @test d isa Variable

        let
            c2 = @unique_var c
            @test c != c2
        end

        f = a + b
        @test variables(f) == Set([a, b])
        @test nvariables(f) == 2
        g = x[1]
        @test variables([f, g]) == Set([a, b, x[1]])
        @test nvariables([f, g]) == 3
    end

    @testset "Subs" begin
        @var x y w z u
        f = x^2 * (x + y * w)

        @test subs(f, x => z) == z^2 * (z + w * y)
        @test subs([f], x => z) == [z^2 * (z + w * y)]
        @test subs(f, [x, y] => [z^2, z + 2]) == z^4 * (w * (2 + z) + z^2)
        @test subs(f, [x, y] => [z^2, z + 2], w => u) ==
              z^4 * (u * (2 + z) + z^2)
        @test subs(f, x => z^2, y => 3, w => u) == z^4 * (3 * u + z^2)
    end

    @testset "Evaluation" begin
        @var x y w
        f = x^2 * (x + y * w)
        @test evaluate([f, f], [x, y, w] => [2, 3, -5]) == [-52, -52]
        @test [f, 2f]([x, y, w] => [2, 3, -5]) == [-52, -104]
    end

    @testset "Linear Algebra" begin
        @var x[1:2, 1:2]
        @test det(x) == -x[2, 1] * x[1, 2] + x[2, 2] * x[1, 1]
        @test det(x') == -x[2, 1] * x[1, 2] + x[2, 2] * x[1, 1]
        @test det(transpose(x)) == -x[2, 1] * x[1, 2] + x[2, 2] * x[1, 1]
    end

    @testset "Differentation" begin
        @var x y

        f = x^2 + y^2
        g = x^3 + y^3

        @test differentiate(f, x) == 2x
        @test differentiate(f, [x, y]) == [2x, 2y]

        @test differentiate([f, g], x) == [2x, 3 * x^2]
        @test differentiate([f, g], [x, y]) == [2x 2y; 3 * x^2 3 * y^2]
    end

    @testset "Expand" begin
        @var x y
        @test expand((x + y)^2) == 2 * x * y + x^2 + y^2
    end

    @testset "to_dict" begin
        @var x y a
        @test ModelKit.to_dict(x^2 + y * x * a + y * x, [x, y]) ==
              Dict([2, 0] => Expression(1), [1, 1] => a + 1)
        @test ModelKit.degree(x * y^5 + y^2, [x, y]) == 6
    end

    @testset "Modeling" begin
        @testset "Bottleneck" begin
            @var x y z
            f = [
                (0.3 * x^2 + 0.5z + 0.3x + 1.2 * y^2 - 1.1)^2 +
                    (0.7 * (y - 0.5x)^2 + y + 1.2 * z^2 - 1)^2 - 0.3,
            ]

            I = let x = [x, y, z]
                n, m = length(x), length(f)
                @unique_var y[1:n] v[1:m] w[1:m]
                J = differentiate(f, x)
                f′ = f(x => y)
                J′ = J(x => y)
                Nx = (x - y) - J' * v
                Ny = (x - y) - J′' * w
                System([f; f′; Nx; Ny], [x; y; v; w])
            end
            @test I isa System
            @test size(I) == (8, 8)
        end

        @testset "Steiner" begin
            @var x[1:2] a[1:5] c[1:6] y[1:2, 1:5]

            #tangential conics
            f = sum([a; 1] .* monomials(x, 2))
            ∇ = differentiate(f, x)
            #5 conics
            g = sum(c .* monomials(x, 2))
            ∇_2 = differentiate(g, x)
            #the general system
            #f_a_0 is tangent to g_b₀ at x₀
            function Incidence(f, a₀, g, b₀, x₀)
                fᵢ = f(x => x₀, a => a₀)
                ∇ᵢ = ∇(x => x₀, a => a₀)
                Cᵢ = g(x => x₀, c => b₀)
                ∇_Cᵢ = ∇_2(x => x₀, c => b₀)

                [fᵢ; Cᵢ; det([∇ᵢ ∇_Cᵢ])]
            end
            @var v[1:6, 1:5]
            I = vcat(map(i -> Incidence(f, a, g, v[:, i], y[:, i]), 1:5)...)
            F = System(I, [a; vec(y)], vec(v))
            @test size(F) == (15, 15)
        end

        @testset "Reach plane curve" begin
            @var x y
            f = (x^3 - x * y^2 + y + 1)^2 * (x^2 + y^2 - 1) + y^2 - 5
            ∇ = differentiate(f, [x; y]) # the gradient
            H = differentiate(∇, [x; y]) # the Hessian

            g = ∇ ⋅ ∇
            v = [-∇[2]; ∇[1]]
            h = v' * H * v
            dg = differentiate(g, [x; y])
            dh = differentiate(h, [x; y])

            ∇σ = g .* dh - ((3 / 2) * h) .* dg

            F = System([v ⋅ ∇σ; f], [x, y])
            @test size(F) == (2, 2)
        end
    end

    @testset "Horner" begin
        # use fano scheme as test
        n = 4
        s = 1
        @var x[1:n]
        ν = monomials(x, 5)
        N = length(ν)
        q₀ = randn(ComplexF64, N - 1)
        @var q[1:N-1]
        F = sum(q[i] * ν[i] for i = 1:N-1) + 1

        @var a[1:n-1] b[1:n-1] t
        L = [a; 1] .* t + [b; 0]

        G = subs(F, x => L)

        FcapL = collect(values(ModelKit.to_dict(expand(G), [t])))

        @test all(FcapL) do f
            g = ModelKit.horner(f)
            expand(g) == f
        end
        @test all(FcapL) do f
            g = ModelKit.horner(f, [a; b])
            expand(g) == f
        end

    end

    @testset "System" begin
        @var x y a b
        f = [(x + y)^3 + x^2 + x + 5y + 3a, 2 * x^2 + b]
        F = System(f, [x, y], [b, a])

        show_F = """
        System of length 2
         2 variables: x, y
         2 parameters: b, a

         3*a + x + 5*y + x^2 + (x + y)^3
         b + 2*x^2"""
        @test sprint(show, F) == show_F
        @test ModelKit.degree(F) == [3, 2]
        T = ModelKit.compile(F)
        F2 = ModelKit.interpret(T)
        @test F == F2
        @test sprint(show, T) == "Compiled: $show_F"
        @test size(T) == size(F) == (2, 2)
    end

    @testset "Homotopy" begin
        @var x y z t

        h = [x^2 + y + z + 2t, 4 * x^2 * z^2 * y + 4z - 6x * y * z^2]
        H = Homotopy(h, [x, y, z], t)

        show_H = """
        Homotopy in t of length 2
         3 variables: x, y, z

         2*t + y + z + x^2
         4*z - 6*x*y*z^2 + 4*x^2*y*z^2"""

        @test sprint(show, H) == show_H

        T = ModelKit.compile(H)
        H2 = ModelKit.interpret(T)
        @test H == H2
        @test sprint(show, T) == "Compiled: $show_H"
        @test size(T) == size(H) == (2, 3)
    end


    @testset "Codegen helpers" begin
        @test ModelKit.sqr(3 + 2im) == (3 + 2im)^2
        @test ModelKit.sqr(3) == 3^2
    end

    @testset "Instructions" begin

        @testset "Simple dt" begin
            @var x a b t
            a = 0.5
            b = 0.1
            h = (x - (t - (a + im * b))^2) * (x + (t - (a + im * b))^2)
            list, _ = ModelKit.instruction_list([h])
            D = ModelKit.DiffMap()
            D[:t, 1] = 1
            slp = @eval ModelKit begin
                function dt_test1(x, t)
                    $(ModelKit.to_expr(ModelKit.univariate_diff!(list, 1, D)))
                end
            end
            expr1 = ModelKit.expand(ModelKit.dt_test1(x, t))
            expr2 = ModelKit.expand(ModelKit.differentiate(h, t))
            @test expr1 == expr2
        end
        @testset "Higher order pow diff" begin
            for d = 2:10
                @var x
                f = x^d
                list, _ = ModelKit.instruction_list([f])

                D = ModelKit.DiffMap()
                D[:x, 1] = :x1
                D[:x, 2] = :x2
                D[:x, 3] = :x3

                @eval ModelKit begin
                    function __diff_4_pow(x, x1, x2, x3)
                        $(ModelKit.to_expr(ModelKit.univariate_diff!(
                            list,
                            4,
                            D,
                        )))
                    end
                end

                @var x1 x2 x3 λ

                @test expand(
                    subs(
                        differentiate(
                            subs(f, x => x .+ λ .* x1 .+ λ^2 .* x2 + λ^3 .* x3),
                            λ,
                            4,
                        ),
                        λ => 0,
                    ) / 24,
                ) == expand(ModelKit.__diff_4_pow(x, x1, x2, x3))
            end
        end

        @testset "Higher order mul" begin
            @var x y
            f = x * y
            list, _ = ModelKit.instruction_list([f])
            D = ModelKit.DiffMap()
            D[:x, 1] = :x1
            D[:x, 2] = :x2
            D[:x, 3] = :x3
            D[:y, 1] = :y1
            D[:y, 2] = :y2
            D[:y, 3] = :y3

            @eval ModelKit begin
                function __diff_4_mul__(x, y, (x1, x2, x3), (y1, y2, y3))
                    $(ModelKit.to_expr(ModelKit.univariate_diff!(list, 4, D)))
                end
            end
            @var x1 x2 x3 y1 y2 y3 λ

            @test expand(
                subs(
                    differentiate(
                        subs(
                            f,
                            x => x .+ λ .* x1 .+ λ^2 .* x2 + λ^3 .* x3,
                            y => y .+ λ .* y1 .+ λ^2 .* y2 + λ^3 .* y3,
                        ),
                        λ,
                        4,
                    ),
                    λ => 0,
                ) / 24,
            ) == expand(ModelKit.__diff_4_mul__(
                x,
                y,
                (x1, x2, x3),
                (y1, y2, y3),
            ))
        end

        @testset "Higher order plus" begin
            @var x y
            f = x + y
            list, _ = ModelKit.instruction_list([f])

            D = ModelKit.DiffMap()
            D[:x, 1] = :x1
            D[:x, 2] = :x2
            D[:x, 3] = :x3
            D[:y, 1] = :y1
            D[:y, 2] = :y2
            D[:y, 3] = :y3

            @eval ModelKit begin
                function __diff_3_plus__(x, y, (x1, x2, x3), (y1, y2, y3))
                    $(ModelKit.to_expr(ModelKit.univariate_diff!(list, 3, D)))
                end
            end

            @var x1 x2 x3 y1 y2 y3 λ

            @test expand(
                subs(
                    differentiate(
                        subs(
                            f,
                            x => x .+ λ .* x1 .+ λ^2 .* x2 + λ^3 .* x3,
                            y => y .+ λ .* y1 .+ λ^2 .* y2 + λ^3 .* y3,
                        ),
                        λ,
                        3,
                    ),
                    λ => 0,
                ) / 6,
            ) == expand(ModelKit.__diff_3_plus__(
                x,
                y,
                (x1, x2, x3),
                (y1, y2, y3),
            ))
        end
    end


    @testset "Homotopy codegen (Katsura(3))" begin
        n = 3
        @var x[0:n] ẋ[0:n] ẍ[0:n] x3[0:n] t γ
        K = [
            (
                sum(
                    x[abs(l)+1] * x[abs(m - l)+1]
                    for l = -n:n if abs(m - l) <= n
                ) - x[m+1] for m = 0:n-1
            )...,
            x[1] + 2 * sum(x[i+1] for i = 1:n) - 1,
        ]

        h = γ .* t .* [x[1:n] .^ 2 .- 1; x[n+1] - 1] + (1 - t) .* K
        H = ModelKit.Homotopy(h, x, t, [γ])
        TH = ModelKit.compile(H)


        dt1 = ModelKit.diff_t(TH, x, t, (), [γ])
        dt2 = ModelKit.diff_t(TH, x, t, (ẋ,), [γ])
        dt3 = ModelKit.diff_t(TH, x, t, (ẋ, ẍ), [γ])
        dt4 = ModelKit.diff_t(TH, x, t, (ẋ, ẍ, x3), [γ])

        @var λ
        Hd1 = subs(H.expressions, t => t + λ)
        true_dt1 = subs(differentiate(Hd1, λ, 1), λ => 0)

        Hd2 = subs(H.expressions, x => x .+ λ .* ẋ, t => t + λ)
        true_dt2 = subs(differentiate(Hd2, λ, 2), λ => 0) / 2

        Hd3 = subs(H.expressions, x => x .+ λ .* ẋ .+ λ^2 .* ẍ, t => t + λ)
        true_dt3 = subs(differentiate(Hd3, λ, 3), λ => 0) / 6

        Hd4 = subs(
            H.expressions,
            x => x .+ λ .* ẋ .+ λ^2 .* ẍ .+ λ^3 .* x3,
            t => t + λ,
        )
        true_dt4 = subs(differentiate(Hd4, λ, 4), λ => 0) / 24

        @test expand.(ModelKit.evaluate(TH, x, t, [γ])) == expand.(h)
        @test expand.(ModelKit.jacobian(TH, x, t, [γ])) ==
              expand.(differentiate(h, x))
        @test expand.(dt1) == expand.(true_dt1)
        @test expand.(dt2) == expand.(true_dt2)
        @test expand.(dt3) == expand.(true_dt3)
        @test expand.(dt4) == expand.(true_dt4)
    end
end
