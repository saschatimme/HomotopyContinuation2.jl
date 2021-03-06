@testset "Tracker" begin
    @testset "tracking - AD : $AD" for AD = 0:3
        @var x a y b
        F = System([x^2 - a, x * y - a + b], [x, y], [a, b])

        tracker = Tracker(
            ParameterHomotopy(F, [1, 0], [2, 4]),
            options = TrackerOptions(automatic_differentiation = AD),
        )
        s = [1, 1]
        res = track(tracker, s, 1, 0)
        @test is_success(res)
        @test steps(res) ≤ 5
        @test isa(solution(res), Vector{ComplexF64})
        @test solution(res) ≈ [sqrt(2), -sqrt(2)]
        @test length(solution(res)) == 2
        @test is_success(track(tracker, res, 0, 1))

        code = track!(tracker, s, 1, 0)
        @test is_success(code)
        s0 = copy(tracker.state.x)
        @unpack μ, ω = tracker.state
        @test is_success(track(tracker, s0, 0, 1))
        @test is_success(track(tracker, s0, 0, 1, μ = μ, ω = ω))

        s = @SVector [1, 1]
        @test is_success(track(tracker, s, 1, 0))
    end

    @testset "projective tracking- AD: $AD" for AD = 0:3
        @var x a y b z
        F = System([x^2 - a * z^2, x * y + (b - a) * z^2], [x, y, z], [a, b])
        H = ParameterHomotopy(F, [1, 0], [2, 4])
        tracker = Tracker(
            on_affine_chart(H, (2,)),
            options = TrackerOptions(automatic_differentiation = AD),
        )

        s = [1, 1, 1]
        res = track(tracker, s, 1, 0)
        @test is_success(res)
        @test isa(solution(res), Vector{ComplexF64})
        x₀ = abs(solution(res)[end])
        @test affine_chart(PVector(solution(res))) ≈ [sqrt(2), -sqrt(2)] rtol = 1e-12 / x₀
    end

    @testset "iterator" begin
        @var x a y b
        F = System([x^2 - a, x * y - a + b], [x, y], [a, b])
        tracker = Tracker(ParameterHomotopy(F, [1, 0], [2, 4]))
        s = [1, 1]

        # path iterator
        typeof(first(iterator(tracker, s, 1.0, 0.0))) == Tuple{Vector{ComplexF64},Float64}

        tracker.options.max_step_size = 0.01
        @test length(collect(iterator(tracker, s, 1.0, 0.0))) ≥ 101

        F = System([x - a], [x], [a])
        ct = Tracker(
            ParameterHomotopy(F, [1], [2]),
            options = TrackerOptions(max_step_size = 0.015625),
        )
        Xs = Vector{ComplexF64}[]
        for (x, t) in iterator(ct, [1.0], 1.0, 0.0)
            push!(Xs, x)
        end

        @test length(Xs) ≥ length(1:0.015625:2)
    end

    @testset "path info" begin
        @var x a y b
        F = System([x^2 - a, x * y - a + b], [x, y], [a, b])
        tracker = Tracker(ParameterHomotopy(F, [1, 0], [2, 4]))
        info = path_info(tracker, [1, 1], 1, 0)
        @test !isempty(sprint(show, info))
    end

    @testset "Change parameters" begin
        @var x a y b
        F = System([x^2 - a, x * y - a + b]; parameters = [a, b])
        s = [1.0, 1.0 + 0im]
        tracker = Tracker(ParameterHomotopy(F, [2.2, 3.2], [2.2, 3.2]))
        start_parameters!(tracker, [1, 0])
        target_parameters!(tracker, [2, 4])
        res = track(tracker, s, 1.0, 0.0)
        @test is_success(res)
    end

    @testset "Straight Line Homotopy" begin
        @var x y
        F = System([x^2 + y^2 - 2.3, 2x + 3y - 4], [x, y])
        G = System((0.2 + 0.4im) .* [x^2 - 1, y - 1], [x, y])
        H = StraightLineHomotopy(G, F)
        S = [[1, 1], [-1, 1]]
        tracker = Tracker(H, options = (automatic_differentiation = 3,))

        @test is_success(track(tracker, S[1], 1, 0))
        @test is_success(track(tracker, S[2], 1, 0))
    end

    include("test_cases/steiner_higher_prec.jl")
    include("test_cases/four_bar.jl")
end
