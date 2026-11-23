# Stratigraphic completeness, age-depth deviation and denudation rate across the
# dissolution parameter scan.
#
# For every run in `param_dissolution.json` this script temporarily downloads the
# small CSV and TOML exports of the run from iRODS (Yoda), never the HDF5 file,
# computes the proxies at the four exported locations on the `:profile` transect,
# deletes the download, and plots each proxy against the value of each scanned
# parameter, with one line per location.
#
# Completeness is the fraction of time steps preserved in the stratigraphy. The
# age-depth model (ADM) at a grid cell is the sediment accumulation curve with
# all later-eroded sediment removed, so a time step is preserved when the ADM
# rises during that step.
#
# Dev measures how far the ADM departs from the assumed ADM, the straight line
# between its first and last points:
#
#     Dev     = sqrt(mean((ADM(t) - L(t))^2)) / (ADM(T) - ADM(t0))
#     Dev_max = maximum(abs(ADM(t) - L(t)))   / (ADM(T) - ADM(t0))
#
# Both are 0 for a perfectly linear ADM. They also read as age errors: Dev is the
# typical error, and Dev_max the largest, as a fraction of the run duration when
# ages are read from the assumed ADM.
#
# The denudation rate is the total thickness removed while the cell is exposed,
# divided by the exposed time (m/Myr). A time step counts as exposed when the cell
# is at or above sea level and still holds sediment, the same condition under which
# CarboKitten applies dissolution. Cells that are never exposed return `NaN`.
# The removed thickness is the drop in the sediment accumulation curve during an
# exposed step, which equals what dissolution removed because nothing is deposited
# on an exposed cell. On the HDF5 output this agrees with the recorded removal to
# within 0.01%. It needs the water-depth export (`waterdepth_<run_id>.csv`); runs
# made before that export existed get `NaN` for the rate.
#
# Requirements: a valid iRODS login (run `ibridges init` once if it has expired)
# and a Python environment with `ibridges` installed.
#
# Usage, from the repository root:
#     julia --project=. Visualization/completeness_scan.jl
#
# Finished runs are cached in the results CSV, so an interrupted scan resumes
# where it stopped. Delete that CSV to recompute everything.

using CairoMakie
using DelimitedFiles
using JSON3
using Statistics
using Unitful: @u_str, ustrip

const ROOT = dirname(@__DIR__)
const PARAM_FILE = joinpath(ROOT, "param_dissolution.json")
# Separate from `completeness_dissolution.csv`, which caches results of the older scan.
const RESULT_CSV = joinpath(ROOT, "data", "output", "completeness_dissolution_rerun.csv")
const FIGURE_FILE = joinpath(ROOT, "data", "figure", "completeness_dissolution_scan_rerun.png")
const DEV_FIGURE_FILE = joinpath(ROOT, "data", "figure", "dev_dissolution_scan_rerun.png")
const RATE_FIGURE_FILE = joinpath(ROOT, "data", "figure", "denudation_rate_dissolution_scan_rerun.png")

const IRODS_RESULTS = "/nluu11p/home/research-mindthegap/denudation/dissolution/results"
const PYTHON = get(ENV, "IBRIDGES_PYTHON", "python")

# ADM rises smaller than this are treated as floating-point noise.
const ADM_TOLERANCE = 1e-9  # m

# Grid cells along the transect that `run_dissolution.jl` exports as CSV columns, in
# the same order as the columns.
const LOCATIONS = 10:20:70

# Locations drawn in the figure. The results CSV always keeps all of `LOCATIONS`.
const PLOT_LOCATIONS = [10, 30]

# Scanned parameters in plotting order: name, axis label, default value.
const PARAMETERS = [
    ("reactive_surface", "Reactive surface (m² m⁻³)", 100.0),
    ("mass_density", "Mass density (kg m⁻³)", 2730.0),
    ("infiltration_coefficient", "Infiltration coefficient (–)", 0.5),
    ("temp", "Temperature (K)", 298.0),
    ("precip", "Precipitation (m yr⁻¹)", 1.3),
    ("pco2", "pCO₂ (atm)", 2.8e-4),
    ("reactionrate", "Reaction rate (m yr⁻¹)", 8e-8),
]

const CSV_HEADER = ["run_id", "parameter", "value",
                    ("completeness_$(l)" for l in LOCATIONS)...,
                    ("dev_$(l)" for l in LOCATIONS)...,
                    ("dev_max_$(l)" for l in LOCATIONS)...,
                    ("denudation_rate_$(l)" for l in LOCATIONS)...]

# ---------------------------------------------------------------------------
# Proxies
# ---------------------------------------------------------------------------

"""
    age_depth_model(sac)

Age-depth model for a matrix of sediment accumulation curves with dimensions
(x, t): at each time, the lowest thickness reached at that time or any later time.
"""
function age_depth_model(sac::AbstractMatrix)
    adm = copy(sac)
    for t in size(adm, 2)-1:-1:1
        adm[:, t] .= min.(adm[:, t], adm[:, t+1])
    end
    return adm
end

"""
    completeness(sac; tolerance=ADM_TOLERANCE)

Fraction of time steps preserved at each grid cell, from a (x, t) matrix of
sediment accumulation curves in metres.
"""
function completeness(sac::AbstractMatrix; tolerance=ADM_TOLERANCE)
    preserved = diff(age_depth_model(sac), dims=2) .> tolerance
    return vec(mean(preserved, dims=2))
end

"""
    adm_deviation(sac)

Dev and Dev_max at each grid cell, from a (x, t) matrix of sediment accumulation curves
in metres with evenly spaced time steps. The assumed ADM is the straight line between
the first and last points of the ADM. Cells that preserve no sediment have no assumed
ADM to compare with and return `NaN`.
"""
function adm_deviation(sac::AbstractMatrix)
    adm = age_depth_model(sac)
    n_x, n_t = size(adm)
    dev = fill(NaN, n_x)
    dev_max = fill(NaN, n_x)

    for x in 1:n_x
        curve = adm[x, :]
        preserved_thickness = curve[end] - curve[1]
        preserved_thickness > ADM_TOLERANCE || continue

        residual = curve .- range(curve[1], curve[end], length=n_t)
        dev[x] = sqrt(mean(abs2, residual)) / preserved_thickness
        dev_max[x] = maximum(abs, residual) / preserved_thickness
    end
    return dev, dev_max
end

"""
    denudation_rate(thickness, removed, water_depth, dt)

Mean denudation rate at each grid cell: thickness removed during exposed time steps
divided by the exposed time. All matrices are (x, t) output frames; frame `i + 1` holds
what was removed during time step `i`, which starts from the state in frame `i`.
Thickness and removal in metres, water depth in metres (positive below sea level),
`dt` in Myr. Returns m/Myr, or `NaN` for cells that are never exposed with sediment.
"""
function denudation_rate(thickness::AbstractMatrix, removed::AbstractMatrix,
                         water_depth::AbstractMatrix, dt::Real)
    n_x, n_t = size(thickness)
    rate = fill(NaN, n_x)
    for x in 1:n_x
        exposed = [i for i in 1:n_t-1 if water_depth[x, i] <= 0 && thickness[x, i] > 0]
        isempty(exposed) && continue
        rate[x] = sum(removed[x, exposed .+ 1]) / (length(exposed) * dt)
    end
    return rate
end

"""
    read_export(csv_file, prefix)

Read a CarboKitten CSV export. Returns the time in Myr and the (location, t) matrix of
the columns whose name starts with `prefix`, e.g. `"sac_"` or `"wd_"`, in metres.
"""
function read_export(csv_file::AbstractString, prefix::AbstractString)
    table, header = readdlm(csv_file, ','; header=true)
    names = string.(vec(header))
    time_column = findfirst(n -> startswith(n, "time ["), names)
    columns = findall(n -> startswith(n, prefix), names)
    length(columns) == length(LOCATIONS) ||
        error("$csv_file has $(length(columns)) '$prefix' columns, expected $(length(LOCATIONS)).")
    return Float64.(table[:, time_column]), permutedims(Float64.(table[:, columns]))
end

"""Run tag stored in the metadata TOML that CarboKitten writes next to the CSV export."""
function run_tag(toml_file::AbstractString)
    m = match(r"^tag\s*=\s*\"(.*)\"\s*$"m, read(toml_file, String))
    m === nothing && error("No tag found in $toml_file.")
    return String(m[1])
end

"""
    location_proxies(files)

Returns the run tag and the completeness, Dev, Dev_max and denudation rate at each of
`LOCATIONS`, from the downloaded exports of one run: `files.sac` (sediment accumulation
curve CSV), `files.toml` (metadata) and `files.water_depth` (water-depth CSV, or
`nothing` when the run has none, which gives `NaN` rates).
"""
function location_proxies(files)
    time, sac = read_export(files.sac, "sac_")
    dev, dev_max = adm_deviation(sac)

    rate = fill(NaN, length(LOCATIONS))
    if files.water_depth !== nothing
        wd_time, water_depth = read_export(files.water_depth, "wd_")
        wd_time ≈ time || error("$(files.water_depth) and $(files.sac) have different time steps.")
        # Frame i + 1 holds the drop in thickness during step i.
        removed = hcat(zeros(size(sac, 1)), max.(.-diff(sac, dims=2), 0.0))
        rate = denudation_rate(sac, removed, water_depth, time[2] - time[1])
    end

    return run_tag(files.toml), (completeness=completeness(sac), dev=dev, dev_max=dev_max,
                                 denudation_rate=rate)
end

# ---------------------------------------------------------------------------
# Temporary retrieval from iRODS
# ---------------------------------------------------------------------------

# Uses the cached login only, so an expired login stops with a clear message
# rather than waiting on a password prompt.
const DOWNLOAD_SCRIPT = raw"""
import sys
from pathlib import Path
from ibridges import IrodsPath, download
from ibridges.session import Session

remote, local = sys.argv[1:3]
try:
    session = Session(Path.home() / ".irods" / "irods_environment.json")
except Exception as exc:
    print(f"iRODS login failed: {type(exc).__name__}: {exc}", file=sys.stderr)
    sys.exit(3)

with session:
    path = IrodsPath(session, remote)
    if not path.dataobject_exists():
        sys.exit(2)
    download(path, local, overwrite=True, progress_bar=False)
"""

"""
    remote_files(run_id)

Names of a run's exports on iRODS as written by the Snakefile.
"""
remote_files(run_id::AbstractString) = (sac="output_$(run_id).csv", toml="output_$(run_id).toml",
                                        water_depth="waterdepth_$(run_id).csv")

"""Download one file from the results collection into `dir`. Returns the local path, or
`nothing` if it is not on iRODS."""
function download_from_irods(file::AbstractString, dir::AbstractString)
    local_file = joinpath(dir, file)
    # iRODS transfers occasionally fail for a moment, so retry before giving up.
    for attempt in 1:3
        process = run(ignorestatus(`$PYTHON -c $DOWNLOAD_SCRIPT $IRODS_RESULTS/$file $local_file`))
        process.exitcode == 3 && error("Could not log in to iRODS. Run `ibridges init` and try again.")
        process.exitcode == 2 && return nothing
        process.exitcode == 0 && return local_file
        @warn "Download of $file failed (exit code $(process.exitcode)), attempt $attempt of 3."
        sleep(10)
    end
    error("Download of $file failed three times.")
end

"""Download the exports of one run into `dir`. Returns their local paths, or `nothing` if
the run is not on iRODS. `water_depth` is `nothing` for runs made without that export."""
function fetch_from_irods(scan_run, dir::AbstractString)
    names = remote_files(scan_run.id)
    sac = download_from_irods(names.sac, dir)
    sac === nothing && return nothing
    toml = download_from_irods(names.toml, dir)
    toml === nothing && error("$(names.sac) is on iRODS but $(names.toml) is not.")
    return (sac=sac, toml=toml, water_depth=download_from_irods(names.water_depth, dir))
end

# ---------------------------------------------------------------------------
# Scan bookkeeping
# ---------------------------------------------------------------------------

"""List the runs in the scan, using the id to find the varied parameter."""
function scan_runs(param_file::AbstractString)
    names = first.(PARAMETERS)
    return map(JSON3.read(read(param_file, String))) do entry
        id = String(entry.id)
        index = findfirst(n -> startswith(id, n * "_"), names)
        index === nothing && error("Run id $id does not match a scanned parameter.")
        (id=id, file=remote_files(id).sac, parameter=names[index],
         value=Float64(entry[Symbol(names[index])]))
    end
end

function read_results(csv::AbstractString)
    isfile(csv) || return Dict{String,Vector{Any}}()
    rows, header = readdlm(csv, ',', Any; header=true)
    if string.(vec(header)) != CSV_HEADER
        @warn "Ignoring cached results with different columns, recomputing all runs: $csv"
        return Dict{String,Vector{Any}}()
    end
    return Dict(string(rows[i, 1]) => vec(rows[i, :]) for i in axes(rows, 1))
end

function write_results(csv::AbstractString, results::AbstractDict)
    mkpath(dirname(csv))
    rows = permutedims(reduce(hcat, [results[k] for k in sort(collect(keys(results)))]))
    open(csv, "w") do io
        writedlm(io, permutedims(CSV_HEADER), ',')
        writedlm(io, rows, ',')
    end
end

# ---------------------------------------------------------------------------
# Figure
# ---------------------------------------------------------------------------

"""
    plot_scan(results, proxy, y_label, figure_file)

Plot one proxy against each scanned parameter. `proxy` is the CSV column prefix,
`"completeness"`, `"dev"` or `"denudation_rate"`.
"""
function plot_scan(results::AbstractDict, proxy::AbstractString, y_label::AbstractString,
                   figure_file::AbstractString)
    rows = collect(values(results))
    column(name) = findfirst(==(name), CSV_HEADER)

    fig = Figure(size=(1100, 1250), fontsize=15)
    location_keys = ["$(proxy)_$(l)" for l in PLOT_LOCATIONS]
    colors = Makie.wong_colors()[1:length(PLOT_LOCATIONS)]

    # Zoom to the plotted values so small changes are visible. All panels share
    # one y-axis to keep the sensitivity to each parameter comparable.
    plotted = filter(isfinite, Float64[r[column(key)] for r in rows for key in location_keys])
    low, high = isempty(plotted) ? (0.0, 1.0) : extrema(plotted)
    padding = max(0.1 * (high - low), 0.005)
    y_limits = (low - padding, high + padding)

    for (i, (name, label, default)) in enumerate(PARAMETERS)
        selected = sort(filter(r -> r[column("parameter")] == name, rows),
                        by=r -> r[column("value")])
        position = fldmod1(i, 2)
        ax = Axis(fig[position...]; xlabel=label, ylabel=y_label,
                  xgridvisible=false, ygridvisible=false)
        ylims!(ax, y_limits...)
        isempty(selected) && continue

        get_values(key) = Float64[r[column(key)] for r in selected]
        x = get_values("value")
        vlines!(ax, default; color=:gray40, linestyle=:dash)
        for (key, color) in zip(location_keys, colors)
            lines!(ax, x, get_values(key); color=color, linewidth=2)
        end
    end

    handles = [[LineElement(color=c, linewidth=2) for c in colors];
               LineElement(color=:gray40, linestyle=:dash)]
    labels = [["Location $(l)" for l in PLOT_LOCATIONS]; "Default value"]
    Legend(fig[4, 2], handles, labels;
           framevisible=false, tellwidth=false, tellheight=false)

    mkpath(dirname(figure_file))
    save(figure_file, fig; px_per_unit=2)
    return fig
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function main(; fetch=fetch_from_irods, param_file=PARAM_FILE,
              csv=RESULT_CSV, figure_file=FIGURE_FILE, dev_figure_file=DEV_FIGURE_FILE,
              rate_figure_file=RATE_FIGURE_FILE, check_tag=true)
    runs = scan_runs(param_file)
    results = read_results(csv)
    missing_runs = String[]

    mktempdir() do dir
        for (i, run) in enumerate(runs)
            haskey(results, run.id) && continue
            @info "[$i/$(length(runs))] $(run.id)"

            files = fetch(run, dir)
            if files === nothing
                @warn "Not found on iRODS, skipping: $(run.file)"
                push!(missing_runs, run.id)
                continue
            end
            files.water_depth === nothing &&
                @warn "No water-depth export for $(run.id), so its denudation rate is NaN."

            tag, proxies = location_proxies(files)
            foreach(f -> f === nothing || rm(f; force=true), files)

            # Guards against plotting a result against the wrong parameter value.
            check_tag && tag != run.id &&
                error("$(run.file) contains run '$tag', expected '$(run.id)'.")

            results[run.id] = Any[run.id, run.parameter, run.value, proxies.completeness...,
                                  proxies.dev..., proxies.dev_max...,
                                  proxies.denudation_rate...]
            write_results(csv, results)
        end
    end

    isempty(results) && error("No runs could be processed.")
    plot_scan(results, "completeness", "Completeness (–)", figure_file)
    plot_scan(results, "dev", "Dev (–)", dev_figure_file)
    plot_scan(results, "denudation_rate", "Denudation rate (m Myr⁻¹)", rate_figure_file)

    @info "Processed $(length(results)) of $(length(runs)) runs" csv figure_file dev_figure_file rate_figure_file
    isempty(missing_runs) || @warn "Missing runs: $(join(missing_runs, ", "))"
    return results
end

# Runs both from the terminal and from the VS Code REPL. Scripts that only need the
# functions above define `COMPLETENESS_SCAN_LIBRARY_ONLY = true` before including.
if !(@isdefined(COMPLETENESS_SCAN_LIBRARY_ONLY) && COMPLETENESS_SCAN_LIBRARY_ONLY)
    main()
end
