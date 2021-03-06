export solve, Solver, solver, solver_startsolutions, paths_to_track

struct SolveStats
    regular::Threads.Atomic{Int}
    regular_real::Threads.Atomic{Int}
    singular::Threads.Atomic{Int}
    singular_real::Threads.Atomic{Int}
end
SolveStats() = SolveStats(Threads.Atomic{Int}.((0, 0, 0, 0))...)

function init!(SS::SolveStats)
    SS.regular[] = SS.regular_real[] = SS.singular[] = SS.singular_real[] = 0
    SS
end

function update!(stats::SolveStats, R::PathResult)
    is_success(R) || return stats

    if is_singular(R)
        Threads.atomic_add!(stats.singular_real, Int(is_real(R)))
        Threads.atomic_add!(stats.singular, 1)
    else
        Threads.atomic_add!(stats.regular_real, Int(is_real(R)))
        Threads.atomic_add!(stats.regular, 1)
    end
    stats
end

struct Solver{T<:AbstractPathTracker}
    trackers::Vector{T}
    seed::Union{Nothing,UInt32}
    stats::SolveStats
    start_system::Union{Nothing,Symbol}
end
Solver(
    tracker::AbstractPathTracker;
    seed::Union{Nothing,UInt32} = nothing,
    start_system = nothing,
) = Solver([tracker], seed, SolveStats(), start_system)

solver(args...; kwargs...) = first(solver_startsolutions(args...; kwargs...))
function solver_startsolutions(
    F::AbstractVector{Expression},
    starts = nothing;
    parameters = Variable[],
    variables = setdiff(variables(F), parameters),
    variable_groups = nothing,
    kwargs...,
)
    sys = System(
        F,
        variables = variables,
        parameters = parameters,
        variable_groups = variable_groups,
    )
    solver_startsolutions(sys, starts; kwargs...)
end
function solver_startsolutions(
    F::AbstractVector{<:MP.AbstractPolynomial},
    starts = nothing;
    parameters = similar(MP.variables(F), 0),
    variables = setdiff(MP.variables(F), parameters),
    variable_ordering = variables,
    variable_groups = nothing,
    target_parameters = nothing,
    kwargs...,
)
    # handle special case that we have no parameters
    # to shift the coefficients of the polynomials to the parameters
    # this was the behaviour of HC.jl v1
    if isnothing(target_parameters) && isempty(parameters)
        sys, target_parameters = ModelKit.system_with_coefficents_as_params(
            F,
            variables = variables,
            variable_groups = variable_groups,
        )
    else
        sys = System(
            F,
            variables = variables,
            parameters = parameters,
            variable_groups = variable_groups,
        )
    end
    solver_startsolutions(sys, starts; target_parameters = target_parameters, kwargs...)
end
function solver_startsolutions(
    F::Union{System,AbstractSystem},
    starts = nothing;
    seed = rand(UInt32),
    start_system = isnothing(variable_groups(F)) ? :polyhedral : :total_degree,
    generic_parameters = nothing,
    p₁ = generic_parameters,
    start_parameters = p₁,
    p₀ = generic_parameters,
    target_parameters = p₀,
    kwargs...,
)
    !isnothing(seed) && Random.seed!(seed)

    used_start_system = nothing
    if start_parameters !== nothing
        tracker = parameter_homotopy(
            F;
            start_parameters = start_parameters,
            target_parameters = target_parameters,
            kwargs...,
        )
    elseif start_system == :polyhedral
        used_start_system = :polyhedral
        tracker, starts = polyhedral(F; target_parameters = target_parameters, kwargs...)
    elseif start_system == :total_degree
        used_start_system = :total_degree
        tracker, starts = total_degree(F; target_parameters = target_parameters, kwargs...)
    else
        throw(KeywordArgumentException(
            :start_system,
            start_system,
            "Possible values are: `:polyhedral` and `:total_degree`.",
        ))
    end

    Solver(tracker; seed = seed, start_system = used_start_system), starts
end

function solver_startsolutions(
    G::Union{System,AbstractSystem},
    F::Union{System,AbstractSystem},
    starts = nothing;
    seed = rand(UInt32),
    tracker_options = TrackerOptions(),
    endgame_options = EndgameOptions(),
    kwargs...,
)
    !isnothing(seed) && Random.seed!(seed)
    H = start_target_homotopy(G, F; kwargs...)
    tracker =
        EndgameTracker(H; tracker_options = tracker_options, options = endgame_options)

    Solver(tracker; seed = seed), starts
end

function parameter_homotopy(
    F::Union{System,AbstractSystem};
    generic_parameters = nothing,
    p₁ = generic_parameters,
    start_parameters = p₁,
    p₀ = generic_parameters,
    target_parameters = p₀,
    tracker_options = TrackerOptions(),
    endgame_options = EndgameOptions(),
    kwargs...,
)
    unsupported_kwargs(kwargs)
    isnothing(start_parameters) && throw(UndefKeywordError(:start_parameters))
    isnothing(target_parameters) && throw(UndefKeywordError(:target_parameters))
    m, n = size(F)
    H = ParameterHomotopy(F, start_parameters, target_parameters)
    f = System(F)
    if is_homogeneous(f)
        vargroups = variable_groups(f)
        if vargroups === nothing
            m ≥ (n - 1) || throw(FiniteException(n - 1 - m))
            H = on_affine_chart(H)
        else
            m ≥ (n - length(vargroups)) || throw(FiniteException(n - length(vargroups) - m))
            H = on_affine_chart(H, length.(vargroups,) .- 1)
        end
    else
        m ≥ n || throw(FiniteException(n - m))
    end

    EndgameTracker(H; tracker_options = tracker_options, options = endgame_options)
end

function start_target_homotopy(
    G::Union{System,AbstractSystem},
    F::Union{System,AbstractSystem};
    start_parameters = nothing,
    target_parameters = nothing,
    γ = 1.0,
    gamma = γ,
    kwargs...,
)
    unsupported_kwargs(kwargs)
    f, g = System(F), System(G)

    size(F) == size(G) || error("The provided systems don't have the same size.")
    is_homogeneous(f) == is_homogeneous(g) ||
        error("The provided systems are not both homogeneous.")
    variable_groups(f) == variable_groups(g) ||
        error("The provided systems don't decalare the same variable groups.")

    m, n = size(F)

    if !isnothing(start_parameters)
        G = FixedParameterSystem(G, start_parameters)
    end

    if !isnothing(target_parameters)
        F = FixedParameterSystem(F, target_parameters)
    end

    H = StraightLineHomotopy(G, F; gamma = gamma)
    if is_homogeneous(f)
        vargroups = variable_groups(f)
        if vargroups === nothing
            m ≥ (n - 1) || throw(FiniteException(n - 1 - m))
            H = on_affine_chart(H)
        else
            m ≥ (n - length(vargroups)) || throw(FiniteException(n - length(vargroups) - m))
            H = on_affine_chart(H, length.(vargroups,) .- 1)
        end
    else
        m ≥ n || throw(FiniteException(n - m))
    end

    H
end

function solver_startsolutions(
    H::Union{Homotopy,AbstractHomotopy},
    starts = nothing;
    seed = nothing,
    kwargs...,
)
    !isnothing(seed) && Random.seed!(seed)
    Solver(EndgameTracker(H); seed = seed), starts
end

always_false(x) = false

"""
    solve(f; options...)
    solve(f, start_solutions; start_parameters, target_parameters, options...)
    solve(g, f, start_solutions; options...)
    solve(homotopy, start_solutions; options...)

Solve the given problem. If only a single polynomial system `f` is given, then all
(complex) isolated solutions are computed.
If a system `f` depending on parameters together with start and target parameters is given
then a parameter homotopy is performed.
If two systems `g` and `f` with solutions of `g` are given then the solutions are tracked
during the deformation of `g` to `f`.
Similarly, for a given homotopy `homotopy` ``H(x,t)`` with solutions at ``t=1`` the solutions
at ``t=0`` are computed.
See the documentation for examples.
If the input is a *homogeneous* polynomial system, solutions on a random affine chart of
projective space are computed.

## General Options
The `solve` routines takes the following options:
* `catch_interrupt = true`: If this is `true`, the computation is gracefully stopped and a
  partial result is returned when the computation is interruped.
* `endgame_options`: The options and parameters for the endgame.
  Expects an [`EndgameOptions`](@ref) struct.
* `seed`: The random seed used during the computations. The seed is also reported in the
  result. For a given random seed the result is always identical.
* `show_progress= true`: Indicate whether a progress bar should be displayed.
* `stop_early_cb`: Here it is possible to provide a function (or any callable struct) which
  accepts a `PathResult` `r` as input and returns a `Bool`. If `stop_early_cb(r)` is `true`
  then no further paths are tracked and the computation is finished. This is only called
  for successfull paths. This is for example useful if you only want to compute one solution
  of a polynomial system. For this `stop_early_cb = _ -> true` would be sufficient.

* `threading = true`: Enable multi-threading for the computation. The number of
  available threads is controlled by the environment variable `JULIA_NUM_THREADS`.
* `tracker_options`: The options and parameters for the path tracker. Expects a
  [`TrackerOptions`](@ref) struct.


## Options depending on input

If only a polynomial system is given:
* `start_system`: Possible values are `:total_degree` and `:polyhedral`. Depending on the
  choice furhter options are possible. See also [`total_degree`](@ref) and
  [`polyhedral`](@ref).

If a system `f` depending on parameters together with start parameters, start solutions and
*multiple* target parameters then the following options are also available:

* `flatten`: Flatten the output of `transform_result`. This is useful for example if
   `transform_result` returns a vector of solutions, and you only want a single vector of
   solutions as the result (instead of a vector of vector of solutions).
* `transform_parameters = identity`: Transform a parameters values `p` before passing it to
  `target_parameters = ...`.
* `transform_result`: A function taking two arguments, the `result` and the
  parameters `p`. By default this returns the tuple `(result, p)`.

## Basic example

```julia-repl
julia> @var x y;

julia> F = System([x^2+y^2+1, 2x+3y-1])
System of length 2
 2 variables: x, y

 1 + x^2 + y^2
 -1 + 2*x + 3*y

julia> solve(F)
Result with 2 solutions
=======================
• 2 non-singular solutions (0 real)
• 0 singular solutions (0 real)
• 2 paths tracked
• random seed: 0x75a6a462
• start_system: :polyhedral
```
"""
function solve(
    args...;
    show_progress::Bool = true,
    threading::Bool = Threads.nthreads() > 1,
    catch_interrupt::Bool = true,
    target_parameters = nothing,
    stop_early_cb = always_false,
    # many parameter options,
    transform_result = nothing,
    transform_parameters = identity,
    flatten = nothing,
    kwargs...,
)
    many_parameters = false
    if isnothing(target_parameters)
        solver, starts = solver_startsolutions(args...; kwargs...)
    else
        # check if we have many parameters solve
        if !isa(transform_parameters(first(target_parameters)), Number)
            many_parameters = true
            solver, starts = solver_startsolutions(
                args...;
                target_parameters = transform_parameters(first(target_parameters)),
                kwargs...,
            )
        else
            solver, starts = solver_startsolutions(
                args...;
                target_parameters = target_parameters,
                kwargs...,
            )
        end
    end
    if many_parameters
        solve(
            solver,
            starts,
            target_parameters;
            show_progress = show_progress,
            threading = threading,
            catch_interrupt = catch_interrupt,
            transform_result = transform_result,
            transform_parameters = transform_parameters,
            flatten = flatten,
        )
    else
        solve(
            solver,
            starts;
            stop_early_cb = stop_early_cb,
            show_progress = show_progress,
            threading = threading,
            catch_interrupt = catch_interrupt,
        )
    end
end

function solve(
    S::Solver,
    starts;
    stop_early_cb = always_false,
    show_progress::Bool = true,
    threading::Bool = Threads.nthreads() > 1,
    catch_interrupt::Bool = true,
)
    n = length(starts)
    progress = show_progress ? make_progress(n; delay = 0.3) : nothing
    if threading
        threaded_solve(
            S,
            starts,
            progress,
            stop_early_cb;
            catch_interrupt = catch_interrupt,
        )
    else
        serial_solve(S, starts, progress, stop_early_cb; catch_interrupt = catch_interrupt)
    end
end
(solver::Solver)(starts; kwargs...) = solve(solver, starts; kwargs...)
track(solver::Solver, s; kwargs...) = track(solver.trackers[1], s; kwargs...)

function make_progress(n::Integer; delay::Float64 = 0.0)
    desc = "Tracking $n paths... "
    barlen = min(ProgressMeter.tty_width(desc), 40)
    progress = ProgressMeter.Progress(n; dt = 0.3, desc = desc, barlen = barlen)
    progress.tlast += delay
    progress
end
function update_progress!(progress, stats, ntracked)
    t = time()
    if ntracked == progress.n || t > progress.tlast + progress.dt
        showvalues = make_showvalues(stats, ntracked)
        ProgressMeter.update!(progress, ntracked; showvalues = showvalues)
    end
    nothing
end
@noinline function make_showvalues(stats, ntracked)
    showvalues = (("# paths tracked", ntracked),)
    nsols = stats.regular[] + stats.singular[]
    nreal = stats.regular_real[] + stats.singular_real[]
    (
        ("# paths tracked", ntracked),
        ("# non-singular solutions (real)", "$(stats.regular[]) ($(stats.regular_real[]))"),
        ("# singular solutions (real)", "$(stats.singular[]) ($(stats.singular_real[]))"),
        ("# total solutions (real)", "$(nsols[]) ($(nreal[]))"),
    )
end
update_progress!(::Nothing, stats, ntracked) = nothing

function serial_solve(
    solver::Solver,
    starts,
    progress = nothing,
    stop_early_cb = always_false;
    catch_interrupt::Bool = true,
)
    path_results = Vector{PathResult}()
    tracker = solver.trackers[1]
    try
        for (k, s) in enumerate(starts)
            r = track(tracker, s; path_number = k)
            push!(path_results, r)
            update!(solver.stats, r)
            update_progress!(progress, solver.stats, k)
            if is_success(r) && stop_early_cb(r)
                break
            end
        end
    catch e
        (catch_interrupt && isa(e, InterruptException)) || rethrow(e)
    end

    Result(path_results; seed = solver.seed, start_system = solver.start_system)
end
function threaded_solve(
    solver::Solver,
    starts,
    progress = nothing,
    stop_early_cb = always_false;
    catch_interrupt::Bool = true,
)
    S = collect(starts)
    N = length(S)
    path_results = Vector{PathResult}(undef, N)
    interrupted = false
    started = Threads.Atomic{Int}(0)
    finished = Threads.Atomic{Int}(0)
    try
        Threads.resize_nthreads!(solver.trackers)
        tasks = map(solver.trackers) do tracker
            Threads.@spawn begin
                while (k = Threads.atomic_add!(started, 1) + 1) ≤ N && !interrupted
                    r = track(tracker, S[k]; path_number = k)
                    path_results[k] = r
                    nfinished = Threads.atomic_add!(finished, 1) + 1
                    update!(solver.stats, r)
                    update_progress!(progress, solver.stats, nfinished[])
                    if is_success(r) && stop_early_cb(r)
                        interrupted = true
                    end
                end
            end
        end
        for task in tasks
            wait(task)
        end
    catch e
        if (
            isa(e, InterruptException) ||
            (isa(e, TaskFailedException) && isa(e.task.exception, InterruptException))
        )
            interrupted = true
        end
        if !interrupted || !catch_interrupt
            rethrow(e)
        end
    end
    # if we got interrupted we need to remove the unassigned filedds
    if interrupted
        assigned_results = Vector{PathResult}()
        for i = 1:started[]
            if isassigned(path_results, i)
                push!(assigned_results, path_results[i])
            end
        end
        Result(assigned_results; seed = solver.seed, start_system = solver.start_system)
    else
        Result(path_results; seed = solver.seed, start_system = solver.start_system)
    end
end

function start_parameters!(solver::Solver, p)
    for tracker in solver.trackers
        start_parameters!(tracker, p)
    end
    solver
end

function target_parameters!(solver::Solver, p)
    for tracker in solver.trackers
        target_parameters!(tracker, p)
    end
    solver
end



"""
    paths_to_track(f; optopms..)

Returns the number of paths tracked when calling [`solve`](@ref) with the given arguments.
"""
function paths_to_track(
    f::Union{System,AbstractSystem};
    start_system::Symbol = :polyhedral,
    kwargs...,
)
    paths_to_track(f, Val(start_system); kwargs...)
end

#############################
### Many parameter solver ###
#############################


struct ManySolveStats
    solutions::Threads.Atomic{Int}
end

function solve(
    S::Solver,
    starts,
    target_parameters;
    show_progress::Bool = true,
    threading::Bool = Threads.nthreads() > 1,
    catch_interrupt::Bool = true,
    transform_result = nothing,
    transform_parameters = nothing,
    flatten = nothing,
)
    transform_result = something(transform_result, tuple) # (solutions ∘ first) ∘ tuple
    transform_parameters = something(transform_parameters, identity)
    flatten = something(flatten, false)

    n = length(target_parameters)

    progress = show_progress ? make_many_progress(n; delay = 0.3) : nothing
    many_solve(
        S,
        starts,
        target_parameters,
        progress,
        transform_result,
        transform_parameters,
        Val(flatten);
        catch_interrupt = catch_interrupt,
        threading = threading,
    )
end


function make_many_progress(n::Integer; delay::Float64 = 0.0)
    desc = "Solving for $n parameters... "
    barlen = min(ProgressMeter.tty_width(desc), 40)
    progress = ProgressMeter.Progress(n; dt = 0.3, desc = desc, barlen = barlen)
    progress.tlast += delay
    progress
end
function update_many_progress!(progress, results, k; flatten::Bool)
    t = time()
    if k == progress.n || t > progress.tlast + progress.dt
        showvalues = make_many_showvalues(results, k; flatten = flatten)
        ProgressMeter.update!(progress, k; showvalues = showvalues)
    end
    nothing
end
@noinline function make_many_showvalues(results, k; flatten::Bool)
    if flatten
        [("# parameters solved", k), ("# results", length(results))]
    else
        [("# parameters solved", k)]
    end
end
update_many_progress!(::Nothing, results, k; kwargs...) = nothing

function many_solve(
    solver::Solver,
    starts,
    many_target_parameters,
    progress,
    transform_result,
    transform_parameters,
    ::Val{flatten};
    threading::Bool,
    catch_interrupt::Bool,
) where {flatten}
    q = first(many_target_parameters)
    target_parameters!(solver, transform_parameters(q))
    if threading
        res = threaded_solve(solver, starts; catch_interrupt = false)
    else
        res = serial_solve(solver, starts; catch_interrupt = false)
    end
    if flatten
        results = transform_result(res, q)
        if !(results isa AbstractArray)
            throw(ArgumentError("Cannot flatten arguments of type `$(typeof(results))`"))
        end
    else
        results = [transform_result(res, q)]
    end
    k = 1
    update_many_progress!(progress, results, k; flatten = flatten)
    try
        for q in Iterators.drop(many_target_parameters, 1)
            target_parameters!(solver, transform_parameters(q))
            if threading
                res = threaded_solve(solver, starts; catch_interrupt = false)
            else
                res = serial_solve(solver, starts; catch_interrupt = false)
            end

            if flatten
                append!(results, transform_result(res, q))
            else
                push!(results, transform_result(res, q))
            end
            k += 1
            update_many_progress!(progress, results, k; flatten = flatten)
        end
    catch e
        if !(
            isa(e, InterruptException) ||
            (isa(e, TaskFailedException) && isa(e.task.exception, InterruptException))
        )
            rethrow(e)
        end
    end

    results
end
