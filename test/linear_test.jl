@testset "Linear Spaces" begin
    @testset "AffineSubspace" begin
        A = AffineSubspace([1 0 3; 2 1 3], [5, -2])
        @test dim(A) == dim(intrinsic(A)) == dim(extrinsic(A)) == 1
        @test codim(A) == codim(intrinsic(A)) == codim(extrinsic(A)) == 2
        @test ambient_dim(A) == 3
        @test startswith(sprint(show, A), "1-dim. affine subspace")
        @test identity.(A) == A

        @test intrinsic(A) isa AffineIntrinsic
        @test startswith(sprint(show, intrinsic(A)), "AffineIntrinsic")
        @test extrinsic(A) isa AffineExtrinsic
        @test startswith(sprint(show, extrinsic(A)), "AffineExtrinsic")

        @test identity.(extrinsic(A)) == extrinsic(A)
        @test identity.(intrinsic(A)) == intrinsic(A)
        @test identity.(Intrinsic) == Intrinsic

        u = rand(1)
        x = A(u, Intrinsic)
        @test coord_change(A, Extrinsic, Intrinsic, x) ≈ u rtol = 1e-12
        @test coord_change(A, Intrinsic, Extrinsic, u) ≈ x rtol = 1e-12
        @test norm(A(x, Extrinsic)) ≈ 0 atol = 1e-14
        @test norm(AffineExtrinsic(intrinsic(A))(x)) ≈ 0.0 atol = 1e-12

        B = rand_affine_subspace(3; codim = 2)
        @test B != A
        copy!(B, A)
        @test extrinsic(B) == extrinsic(A)
        @test intrinsic(B) == intrinsic(A)
        @test B == A
        @test copy(A) == A
        @test copy(A) !== A

        C = rand_affine_subspace(3, dim = 1, real = true)
        @test geodesic_distance(A, C) > 0
        γ = geodesic(A, C)
        @test size(γ(1)) == size(intrinsic(A).Y)
    end

    @testset "AffineSubspaceHomotopy" begin
        @var x[1:4]
        f1 = rand_poly(x, 2)
        f2 = rand_poly(x, 2)
        F = System([f1, f2], x)

        A = rand_affine_subspace(4; codim = 2)
        # Commpute witness set
        L = A(x, Extrinsic)
        res = track.(total_degree(F ∩ L)...)
        W = solution.(res)

        B = rand_affine_subspace(4, codim = 2)

        graff_tracker = Tracker(
            AffineSubspaceHomotopy(F, A, B),
            options = (automatic_differentiation = 3,),
        )
        graff_result = track.(graff_tracker, W)
        @test all(is_success, graff_result)

        C = rand_affine_subspace(4, codim = 2)
        copy_A = copy(A)
        set_subspaces!(graff_tracker.homotopy, B, C)
        @test A == copy_A
        @test all(is_success, track.(graff_tracker, solution.(graff_result)))

        graff_path_tracker = EndgameTracker(AffineSubspaceHomotopy(F, A, B))
        graff_path_result = track.(graff_path_tracker, W)
        @test all(is_success, graff_path_result)

        @test all(isapprox.(
            solution.(graff_path_result),
            solution.(graff_result),
            rtol = 1e-12,
        ))
    end
end
