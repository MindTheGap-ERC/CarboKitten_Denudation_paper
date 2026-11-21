# Morris sensitivity indices of the dissolution scan.
#
# For every run in `param_dissolution_morris.json` this script temporarily downloads
# its exported sediment accumulation curves (CSV, ~0.4 MB) and metadata (TOML) from
# iRODS, computes completeness, Dev and Dev_max at the four exported locations with
# the same functions as the OAT scan (`completeness_scan.jl`), and deletes the
# download. The CSV holds the same curves as the `:profile` slice of the HDF5 output,
# so the 189 MB HDF5 files never need to be downloaded.
#
# From the proxies it computes, for every proxy column and parameter, the elementary
# effects along each trajectory step
#
#     EE_i = (y(x + Δ e_i) - y(x)) / Δ
#
# with Δ the signed step in unit space (so EEs share units with the proxy, per unit of
# the normalised parameter range), and over the trajectories
#
#     μ   mean EE          (sign: average direction of the effect)
#     μ*  mean |EE|        (overall importance, Campolongo et al. 2007)
#     σ   std of EE        (non-linearity and/or interaction with other parameters)
#
# plus a bootstrap 95% confidence interval on μ*. Steps where either run has a
# non-finite proxy (Dev is NaN when no sediment is preserved) are skipped and counted
# in `n_skipped`.
#
# Outputs (data/output/)
#   morris_proxies.csv              design and proxies of every run (also the cache)
#   morris_elementary_effects.csv   every elementary effect
#   morris_indices.csv              μ, μ*, σ and the CI of μ* per proxy and parameter
# Figures are made separately by `Visualization/morris_sensitivity.jl`.
#
# Requirements: a valid iRODS login (run `ibridges init` once if it has expired)
# and a Python environment with `ibridges` installed.
#
# Usage, from the repository root:
#     julia --project=. Visualization/morris_scan.jl
#
# Finished runs are cached in morris_proxies.csv, so an interrupted scan resumes
# where it stopped. Delete that CSV to recompute everything.

const COMPLETENESS_SCAN_LIBRARY_ONLY = true
include(joinpath(@__DIR__, "completeness_scan.jl"))

using Random
using TOML

const MORRIS_PARAM_FILE = joinpath(ROOT, "param_dissolution_morris.json")
const IRODS_MORRIS_RESULTS = "/nluu11p/home/research-mindthegap/denudation/dissolution_morris/results"
const PROXIES_CSV = joinpath(ROOT, "data", "output", "morris_proxies.csv")
const EFFECTS_CSV = joinpath(ROOT, "data", "output", "morris_elementary_effects.csv")
const INDICES_CSV = joinpath(ROOT, "data", "output", "morris_indices.csv")

const N_BOOTSTRAP = 1000
const BOOTSTRAP_SEED = 1

const METRICS = [["completeness_$(l)" for l in LOCATIONS];
                 ["dev_$(l)" for l in LOCATIONS];
                 ["dev_max_$(l)" for l in LOCATIONS]]

# ---------------------------------------------------------------------------
# Design
# ---------------------------------------------------------------------------

"""Runs of the Morris design, and the scanned parameter names in design order."""
function read_design(json_file::AbstractString)
    design = JSON3.read(read(json_file, String))
    param_names = [replace(String(k), "u_" => "") for k in keys(design[1])
                   if startswith(String(k), "u_")]
    changed = Set(String(e.changed_parameter) for e in design if e.changed_parameter != "none")
    changed == Set(param_names) ||
        error("Parameters changed along trajectories ($(changed)) differ from the design ($(param_names)).")
    return design, param_names
end

design_columns(param_names) = ["run_id", "trajectory", "step", "changed_parameter", param_names...]

# ---------------------------------------------------------------------------
# Proxies of one run
# ---------------------------------------------------------------------------

"""
    csv_proxies(csv_file)

Completeness, Dev and Dev_max at `LOCATIONS` from the sediment accumulation curves
exported by `run_dissolution.jl` (columns: timestep, time, sac_1 … sac_4, in metres).
"""
function csv_proxies(csv_file::AbstractString)
    data, _ = readdlm(csv_file, ',', Float64; header=true)
    sac = permutedims(data[:, 3:end])   # (location, t)
    size(sac, 1) == length(LOCATIONS) ||
        error("$(csv_file) has $(size(sac, 1)) locations, expected $(length(LOCATIONS)).")
    dev, dev_max = adm_deviation(sac)
    return [completeness(sac); dev; dev_max]
end

"""Download one file from the Morris results collection. Returns `nothing` if absent."""
function fetch_file(file::AbstractString, dir::AbstractString)
    local_file = joinpath(dir, file)
    process = run(ignorestatus(`$PYTHON -c $DOWNLOAD_SCRIPT $IRODS_MORRIS_RESULTS/$file $local_file`))
    process.exitcode == 3 && error("Could not log in to iRODS. Run `ibridges init` and try again.")
    process.exitcode == 2 && return nothing
    process.exitcode == 0 || error("Download of $file failed (exit code $(process.exitcode)).")
    return local_file
end

"""Download the CSV and TOML of one run. Returns their paths, or `nothing` if missing."""
function fetch_run(run_id::AbstractString, dir::AbstractString)
    csv = fetch_file("output_$(run_id).csv", dir)
    csv === nothing && return nothing
    toml = fetch_file("output_$(run_id).toml", dir)
    toml === nothing && return nothing
    return (csv=csv, toml=toml)
end

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

function read_cache(csv::AbstractString, header::Vector{String})
    isfile(csv) || return Dict{String,Vector{Any}}()
    rows, file_header = readdlm(csv, ',', Any; header=true)
    if string.(vec(file_header)) != header
        @warn "Ignoring cached results with different columns, recomputing all runs: $csv"
        return Dict{String,Vector{Any}}()
    end
    return Dict(string(rows[i, 1]) => vec(rows[i, :]) for i in axes(rows, 1))
end

function write_csv(file::AbstractString, header::Vector{String}, rows)
    mkpath(dirname(abspath(file)))
    open(file, "w") do io
        writedlm(io, permutedims(header), ',')
        for row in rows
            writedlm(io, permutedims(row), ',')
        end
    end
end

# ---------------------------------------------------------------------------
# Morris indices
# ---------------------------------------------------------------------------

"""Elementary effects as named tuples (trajectory, step, parameter, delta_u, metric, ee)."""
function elementary_effects(design, proxies::AbstractDict)
    effects = NamedTuple[]
    by_trajectory = Dict{Int,Vector{Any}}()
    for entry in design
        push!(get!(by_trajectory, Int(entry.trajectory), Any[]), entry)
    end

    for t in sort(collect(keys(by_trajectory)))
        runs = sort(by_trajectory[t], by=e -> Int(e.step))
        for s in 2:length(runs)
            previous, current = runs[s-1], runs[s]
            id_prev, id_curr = String(previous.id), String(current.id)
            # A trajectory with a missing run loses only the steps touching that run.
            (haskey(proxies, id_prev) && haskey(proxies, id_curr)) || continue

            parameter = String(current.changed_parameter)
            key = Symbol("u_$(parameter)")
            delta_u = Float64(current[key]) - Float64(previous[key])
            delta_u == 0 && error("Run $(id_curr) does not change $(parameter).")

            for m in METRICS
                ee = (proxies[id_curr][m] - proxies[id_prev][m]) / delta_u
                push!(effects, (trajectory=t, step=Int(current.step), parameter=parameter,
                                delta_u=delta_u, metric=m, ee=ee))
            end
        end
    end
    return effects
end

"""Split a metric column such as `dev_max_30` into ("dev_max", 30)."""
function split_metric(metric::AbstractString)
    m = match(r"^(.*)_(\d+)$", metric)
    return (String(m[1]), parse(Int, m[2]))
end

function bootstrap_ci(values::Vector{Float64}, rng::AbstractRNG; n=N_BOOTSTRAP)
    length(values) < 2 && return (NaN, NaN)
    estimates = [mean(abs, rand(rng, values, length(values))) for _ in 1:n]
    return (quantile(estimates, 0.025), quantile(estimates, 0.975))
end

function morris_indices(effects, param_names)
    rng = Xoshiro(BOOTSTRAP_SEED)
    rows = Vector{Any}[]
    for m in METRICS, p in param_names
        all_ee = [e.ee for e in effects if e.metric == m && e.parameter == p]
        ee = filter(isfinite, all_ee)
        n = length(ee)
        mu = n > 0 ? mean(ee) : NaN
        mu_star = n > 0 ? mean(abs, ee) : NaN
        sigma = n > 1 ? std(ee) : NaN
        ci_low, ci_high = bootstrap_ci(ee, rng)
        proxy, location = split_metric(m)
        push!(rows, Any[m, proxy, location, p, n, length(all_ee) - n,
                        mu, mu_star, sigma, ci_low, ci_high])
    end
    return rows
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function main(; fetch=fetch_run, param_file=MORRIS_PARAM_FILE, proxies_csv=PROXIES_CSV,
              effects_csv=EFFECTS_CSV, indices_csv=INDICES_CSV, check_tag=true)
    design, param_names = read_design(param_file)
    header = [design_columns(param_names); METRICS]
    results = read_cache(proxies_csv, header)
    missing_runs = String[]

    mktempdir() do dir
        for (i, entry) in enumerate(design)
            run_id = String(entry.id)
            haskey(results, run_id) && continue
            @info "[$i/$(length(design))] $(run_id)"

            files = fetch(run_id, dir)
            if files === nothing
                @warn "Not found on iRODS, skipping: $(run_id)"
                push!(missing_runs, run_id)
                continue
            end

            # Guards against attributing a result to the wrong parameter values.
            tag = TOML.parsefile(files.toml)["global"]["tag"]
            check_tag && tag != run_id &&
                error("output_$(run_id).toml contains run '$tag', expected '$(run_id)'.")

            proxies = csv_proxies(files.csv)
            rm(files.csv; force=true)
            rm(files.toml; force=true)

            design_values = Any[run_id, Int(entry.trajectory), Int(entry.step),
                                String(entry.changed_parameter),
                                (Float64(entry[Symbol(p)]) for p in param_names)...]
            results[run_id] = [design_values; proxies]
            write_csv(proxies_csv, header, [results[k] for k in sort(collect(keys(results)))])
        end
    end

    isempty(results) && error("No runs could be processed.")
    n_design = length(design_columns(param_names))
    proxies = Dict(id => Dict(m => Float64(row[n_design+j]) for (j, m) in enumerate(METRICS))
                   for (id, row) in results)

    effects = elementary_effects(design, proxies)
    write_csv(effects_csv, ["trajectory", "step", "parameter", "delta_u", "metric", "ee"],
              [Any[e.trajectory, e.step, e.parameter, e.delta_u, e.metric, e.ee] for e in effects])
    write_csv(indices_csv,
              ["metric", "proxy", "location", "parameter", "n", "n_skipped",
               "mu", "mu_star", "sigma", "mu_star_ci_low", "mu_star_ci_high"],
              morris_indices(effects, param_names))

    @info "Processed $(length(results)) of $(length(design)) runs" proxies_csv effects_csv indices_csv
    isempty(missing_runs) || @warn "Missing runs: $(join(missing_runs, ", "))"
    return results
end

# Scripts that only need the functions above define `MORRIS_SCAN_LIBRARY_ONLY = true`
# before including.
if !(@isdefined(MORRIS_SCAN_LIBRARY_ONLY) && MORRIS_SCAN_LIBRARY_ONLY)
    main()
end
