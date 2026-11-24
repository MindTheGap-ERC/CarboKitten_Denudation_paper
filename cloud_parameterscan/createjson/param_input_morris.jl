# Morris (elementary effects) design for the dissolution parameter scan.
#
# Same parameters and bounds as the one-at-a-time scan in `param_input_diss.jl`.
# The design follows Morris (1991) with the trajectory selection of Campolongo et al.
# (2007):
#
#   * every parameter is mapped to the unit interval and discretised into `LEVELS`
#     levels, with jump size Δ = LEVELS / (2 (LEVELS - 1)) (2/3 for 4 levels);
#   * a trajectory starts at a random grid point and changes one parameter at a time
#     by ±Δ, in random order, giving k + 1 = 8 runs per trajectory;
#   * `N_CANDIDATES` random trajectories are generated and the `N_TRAJECTORIES` most
#     spread out are kept, which covers the parameter space better than drawing
#     `N_TRAJECTORIES` directly. Campolongo's brute-force selection is infeasible for
#     these sizes, so the selection is greedy: start from the most distant pair and
#     keep adding the trajectory with the largest summed distance to those chosen.
#
# Each run in the JSON has the model inputs (read by `runs/run_dissolution.jl`), plus
# `trajectory`, `step`, `changed_parameter` and the unit-space coordinates `u_<name>`
# that `analysis/morris_indices.jl` needs to compute the elementary effects.
#
# Usage, from the repository root:
#     julia --project=. cloud_parameterscan/createjson/param_input_morris.jl
#
# Writes `param_dissolution_morris.json`. Commit it: the Snakemake workflow
# (`morris.smk`) reads it, and it also uploads it to iRODS next to the results.
module Morris_Input
using JSON3
using Random

# Keep in sync with `param_input_diss.jl`.
const PARAM_NAMES = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

const BOUNDS = [
        (50, 1500),       
        (2530, 2830),     
        (0.1, 0.9),
        (293, 303), 
        (1, 2),      
        (1e-4, 1e-3),    
        (1e-8, 2e-7),          
        ]

# Parameters sampled uniformly in log10 space instead of linearly. Empty to match the
# linear spacing of the OAT scan. Bounds spanning orders of magnitude (reactive_surface,
# pco2, reactionrate) are candidates: with linear spacing every level but the lowest
# lies within the top 1-2 orders of magnitude.
const LOG_SCALE = String[]

const LEVELS = 4
const N_TRAJECTORIES = 20     # runs = N_TRAJECTORIES * (k + 1) = 160
const N_CANDIDATES = 200
const SEED = 20261121
const OUTPUT_FILE = "param_dissolution_morris.json"

jump(p) = p / (2 * (p - 1))

"""
    random_trajectory(rng, k, p)

One Morris trajectory as a (k + 1) × k matrix in unit space, and the order in which the
parameters are changed. All coordinates lie on the grid 0, 1/(p-1), …, 1.
"""
function random_trajectory(rng::AbstractRNG, k::Int, p::Int)
    Δ = jump(p)
    grid = (0:p-1) ./ (p - 1)
    start_up = grid[grid .+ Δ .<= 1 + 1e-12]       # levels that can move up by Δ
    up = rand(rng, Bool, k)
    x = [rand(rng, start_up) + (up[i] ? 0.0 : Δ) for i in 1:k]

    order = randperm(rng, k)
    trajectory = zeros(k + 1, k)
    trajectory[1, :] = x
    for (step, i) in enumerate(order)
        x[i] += up[i] ? Δ : -Δ
        trajectory[step+1, :] = x
    end
    # Snap to the grid to remove floating-point drift.
    return round.(trajectory .* (p - 1)) ./ (p - 1), order
end

"""Summed Euclidean distance between all pairs of points of two trajectories."""
function trajectory_distance(a::AbstractMatrix, b::AbstractMatrix)
    return sum(sqrt(sum(abs2, a[i, :] .- b[j, :])) for i in axes(a, 1), j in axes(b, 1))
end

"""Greedy approximation of the Campolongo et al. (2007) maximum-spread selection."""
function select_spread(candidates, r::Int)
    M = length(candidates)
    D = [i == j ? 0.0 : trajectory_distance(candidates[i][1], candidates[j][1])
         for i in 1:M, j in 1:M]
    first_pair = Tuple(argmax(D))
    chosen = [first_pair...]
    while length(chosen) < r
        remaining = setdiff(1:M, chosen)
        scores = [sum(D[c, chosen]) for c in remaining]
        push!(chosen, remaining[argmax(scores)])
    end
    return candidates[chosen]
end

function to_physical(u::Real, name::AbstractString, (low, high))
    if name in LOG_SCALE
        return 10^(log10(low) + u * (log10(high) - log10(low)))
    end
    return low + u * (high - low)
end

function get_param_sets(; r=N_TRAJECTORIES, n_candidates=N_CANDIDATES, p=LEVELS, seed=SEED)
    rng = Xoshiro(seed)
    k = length(PARAM_NAMES)
    candidates = [random_trajectory(rng, k, p) for _ in 1:n_candidates]
    trajectories = select_spread(candidates, r)

    paramsets = Dict{String,Any}[]
    for (t, (trajectory, order)) in enumerate(trajectories)
        for step in 0:k
            u = trajectory[step+1, :]
            paramset = Dict{String,Any}(
                "id" => "morris_t$(lpad(t, 2, '0'))_s$(step)",
                "trajectory" => t,
                "step" => step,
                "changed_parameter" => step == 0 ? "none" : PARAM_NAMES[order[step]])
            for (i, name) in enumerate(PARAM_NAMES)
                paramset[name] = to_physical(u[i], name, BOUNDS[i])
                paramset["u_$(name)"] = u[i]
            end
            push!(paramsets, paramset)
        end
    end
    return paramsets
end

if abspath(PROGRAM_FILE) == @__FILE__
    paramsets = get_param_sets()
    open(OUTPUT_FILE, "w") do io
        JSON3.write(io, paramsets)
    end
    @info "Wrote $(length(paramsets)) runs ($(N_TRAJECTORIES) trajectories) to $(OUTPUT_FILE)"
end

end
