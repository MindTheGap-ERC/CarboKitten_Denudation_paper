# Sediment accumulation curves for two runs of the dissolution scan, and a test of
# the size of the dissolution rate that those runs actually used.
#
# Left panel: sediment thickness through time at one location.
# Right panel: dissolution rate measured in each run during exposure, compared with
# the CarboKitten equation as coded and with its equilibrium denudation divided by
# 1000. While a cell is exposed, disintegration is switched off, so the sediment the
# model records as removed in those steps is the dissolved amount.
#
# Usage, from the repository root:
#     julia --project=. local_parameterscan/sac_comparison.jl

const COMPLETENESS_SCAN_LIBRARY_ONLY = true
include(joinpath(@__DIR__, "..", "Visualization", "completeness_scan.jl"))

import CarboKitten.Denudation.DissolutionMod: dissolution
using CarboKitten.Export: read_slice
using CarboKitten.Output.Storage: sediment_thickness
using Printf
using Unitful

const TRIALS = ["reactionrate_1.0e-5", "reactionrate_0.002"]
const TRIAL_LABELS = ["Reaction rate 1×10⁻⁵ m yr⁻¹", "Reaction rate 2×10⁻³ m yr⁻¹"]
const LOCATION = 10
const SAC_FIGURE = joinpath(ROOT, "data", "figure", "sac_reactionrate_comparison.png")

"""Read the time series of one run at `LOCATION`, and find its exposed time steps."""
function read_trial(h5_file::AbstractString)
    header, profile = read_slice(h5_file, :profile)
    column = profile.slice[2]
    d = (thickness=ustrip.(u"m", sediment_thickness(profile)[LOCATION, :]),
         removed=ustrip.(u"m", vec(sum(profile.disintegration[:, LOCATION, :], dims=1))),
         sea_level=ustrip.(u"m", header.sea_level), t=ustrip.(u"Myr", header.axes.t),
         topography=ustrip(u"m", header.initial_topography[LOCATION, column]),
         subsidence=ustrip(u"m/Myr", header.subsidence_rate), dt=ustrip(u"Myr", header.Δt))

    bathymetry = d.topography .+ d.thickness .- d.subsidence .* (d.t .- d.t[1])
    water_depth = d.sea_level .- bathymetry

    # Output frame i+1 holds what happened during time step i.
    steps = 1:length(d.t)-1
    exposed = [i for i in steps if water_depth[i] < 0 && d.thickness[i] > 0]
    return (t=d.t, thickness=d.thickness, height=-water_depth[exposed],
            rate=d.removed[exposed .+ 1] ./ d.dt, dt=d.dt)
end

"""Dissolution rate (m/Myr) from the CarboKitten equation at `height` above sea level."""
function equation_rate(p, height)
    facies = (reactive_surface=p.reactive_surface * u"m^2/m^3",
              mass_density=p.mass_density * u"kg/m^3",
              infiltration_coefficient=p.infiltration_coefficient)
    rate = dissolution(Float64(p.temp), Float64(p.precip), Float64(p.pco2),
                       Float64(p.reactionrate), -height, facies)
    return ustrip(u"m/Myr", rate)
end

function plot_trials(trials, parameters, figure_file)
    colors = Makie.wong_colors()[1:2]
    fig = Figure(size=(1150, 560), fontsize=15)

    sac = Axis(fig[1, 1]; xlabel="Time (Myr)", ylabel="Sediment thickness (m)",
               title="Sediment accumulation at location $(LOCATION)",
               xgridvisible=false, ygridvisible=false)
    rates = Axis(fig[1, 2]; xlabel="Height above sea level (m)", ylabel="Dissolution rate (m Myr⁻¹)",
                 title="Measured rate against the equation", yscale=log10,
                 xgridvisible=false, ygridvisible=false)

    for (trial, p, color) in zip(trials, parameters, colors)
        lines!(sac, trial.t, trial.thickness; color=color, linewidth=1.5)

        measured = trial.rate .> 0
        scatter!(rates, trial.height[measured], trial.rate[measured];
                 color=(color, 0.35), markersize=5)
        heights = range(max(minimum(trial.height), 0.05), maximum(trial.height), length=100)
        as_coded = equation_rate.(Ref(p), heights)
        lines!(rates, heights, as_coded; color=color, linewidth=2)
        lines!(rates, heights, as_coded ./ 1000; color=color, linewidth=2, linestyle=:dash)
    end

    elements = [[LineElement(color=c, linewidth=2) for c in colors];
                MarkerElement(color=:gray40, marker=:circle, markersize=8);
                LineElement(color=:black, linewidth=2);
                LineElement(color=:black, linewidth=2, linestyle=:dash)]
    labels = [TRIAL_LABELS; "Measured in the run"; "Equation as coded"; "Equation with D_eq ÷ 1000"]
    Legend(fig[2, 1:2], elements, labels; orientation=:horizontal, nbanks=2, framevisible=false)

    mkpath(dirname(figure_file))
    save(figure_file, fig; px_per_unit=2)
end

function compare_trials()
    runs = scan_runs(PARAM_FILE)
    entries = JSON3.read(read(PARAM_FILE, String))
    parameters = [only(filter(e -> e.id == id, entries)) for id in TRIALS]

    trials = mktempdir() do dir
        map(TRIALS) do id
            file = download_from_irods("output_$(id).h5", dir)  # the full HDF5 output
            file === nothing && error("Run $id was not found on iRODS.")
            trial = read_trial(file)
            GC.gc()
            rm(file; force=true)
            trial
        end
    end

    # Some exposed steps record no dissolution at all, so the equation is compared
    # with the measurement only on the steps where dissolution happened.
    @printf("%-24s %8s %12s %14s %14s %14s %12s\n", "trial", "exposed", "no dissol.",
            "measured (m)", "as coded (m)", "D_eq/1000 (m)", "meas/coded")
    for (id, trial, p) in zip(TRIALS, trials, parameters)
        dissolving = trial.rate .> 0
        measured = sum(trial.rate) * trial.dt
        coded = sum(equation_rate.(Ref(p), trial.height[dissolving])) * trial.dt
        @printf("%-24s %8d %11.1f%% %14.4f %14.4f %14.6f %12.4f\n", id, length(trial.height),
                100 * mean(.!dissolving), measured, coded, coded / 1000, measured / coded)
    end

    plot_trials(trials, parameters, SAC_FIGURE)
    @info "Saved" SAC_FIGURE
end

compare_trials()
