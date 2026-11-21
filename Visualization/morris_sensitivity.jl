# Figures for the Morris sensitivity scan of the dissolution model.
#
#   morris_mu_sigma.png  μ* against σ for each parameter, per proxy and location. Points
#                        far from the origin matter; points above the σ/μ* = 1 line act
#                        non-linearly or through interactions with other parameters.
#   morris_mu_star.png   μ* with its bootstrap 95% CI, per proxy and location.
#
# Run `Visualization/morris_scan.jl` first; it writes data/output/morris_indices.csv.
#
# Usage, from the repository root:
#     julia --project=. Visualization/morris_sensitivity.jl
#         reads data/output/morris_indices.csv, writes the figures to data/figure/
#     julia --project=. Visualization/morris_sensitivity.jl <indices_csv> <mu_sigma_png> <mu_star_png>

# Reuses the parameter labels of the OAT scan.
const COMPLETENESS_SCAN_LIBRARY_ONLY = true
include(joinpath(@__DIR__, "completeness_scan.jl"))

const LOCAL_INDICES = joinpath(ROOT, "data", "output", "morris_indices.csv")
const MU_SIGMA_FILE = joinpath(ROOT, "data", "figure", "morris_mu_sigma.png")
const MU_STAR_FILE = joinpath(ROOT, "data", "figure", "morris_mu_star.png")

# Proxies (rows) and locations (columns) drawn. The indices CSV has all of them.
const PLOT_PROXIES = [("completeness", "Completeness"), ("dev", "Dev")]
const MORRIS_PLOT_LOCATIONS = [10, 30]

# Reference lines in the μ*–σ plane (Garcia Sanchez et al. 2014): below 0.1 almost
# linear, 0.1–0.5 monotonic, 0.5–1 almost monotonic, above 1 non-linear/interacting.
const SIGMA_RATIOS = [0.1, 0.5, 1.0]

# Points closer to the origin than this fraction of the axis range get no direct label.
const LABEL_THRESHOLD = 0.08

const PARAM_ORDER = first.(PARAMETERS)
const PARAM_LABEL = Dict(name => label for (name, label, _) in PARAMETERS)
# Fixed colour per parameter, the same in every panel.
const PARAM_COLOR = Dict(zip(PARAM_ORDER, Makie.wong_colors()[1:length(PARAM_ORDER)]))

short_label(name) = replace(PARAM_LABEL[name], r"\s*\(.*\)$" => "")

"""Indices as a vector of named tuples, one per (metric, parameter)."""
function read_indices(csv::AbstractString)
    rows, header = readdlm(csv, ',', Any; header=true)
    header = string.(vec(header))
    col(name) = findfirst(==(name), header)
    num(x) = x isa Number ? Float64(x) : NaN
    return [(proxy=string(rows[i, col("proxy")]),
             location=Int(rows[i, col("location")]),
             parameter=string(rows[i, col("parameter")]),
             mu_star=num(rows[i, col("mu_star")]),
             sigma=num(rows[i, col("sigma")]),
             ci_low=num(rows[i, col("mu_star_ci_low")]),
             ci_high=num(rows[i, col("mu_star_ci_high")])) for i in axes(rows, 1)]
end

select(indices, proxy, location) =
    sort(filter(r -> r.proxy == proxy && r.location == location, indices),
         by=r -> findfirst(==(r.parameter), PARAM_ORDER))

function panel_grid(f)
    fig = Figure(size=(1000, 430 * length(PLOT_PROXIES) + 90), fontsize=15)
    for (row, (proxy, proxy_label)) in enumerate(PLOT_PROXIES),
        (column, location) in enumerate(MORRIS_PLOT_LOCATIONS)
        f(fig[row, column], proxy, proxy_label, location)
    end
    return fig
end

function plot_mu_sigma(indices, figure_file::AbstractString)
    fig = panel_grid() do position, proxy, proxy_label, location
        selected = filter(r -> isfinite(r.mu_star) && isfinite(r.sigma),
                          select(indices, proxy, location))
        ax = Axis(position; title="$(proxy_label), location $(location)",
                  xlabel="μ* ($(proxy_label) per unit range)", ylabel="σ",
                  xgridvisible=false, ygridvisible=false)
        isempty(selected) && return

        limit = 1.1 * max(maximum(r.mu_star for r in selected),
                          maximum(r.sigma for r in selected), eps())
        for ratio in SIGMA_RATIOS
            lines!(ax, [0, limit], [0, ratio * limit]; color=:gray70, linestyle=:dash,
                   linewidth=1)
            text!(ax, limit, ratio * limit; text="σ/μ* = $(ratio)", color=:gray45,
                  fontsize=11, align=(:right, :top), offset=(-4, -4))
        end
        for r in selected
            scatter!(ax, [r.mu_star], [r.sigma]; color=PARAM_COLOR[r.parameter],
                     markersize=12, strokecolor=:white, strokewidth=1.5)
            # Points clustered at the origin are named by the legend only, so their
            # labels do not pile up.
            hypot(r.mu_star, r.sigma) < LABEL_THRESHOLD * limit && continue
            near_right = r.mu_star > 0.7 * limit
            text!(ax, r.mu_star, r.sigma; text=short_label(r.parameter), fontsize=11,
                  color=:gray20, offset=(near_right ? -6 : 6, 4),
                  align=(near_right ? :right : :left, :bottom))
        end
        limits!(ax, 0, limit, 0, limit)
    end

    handles = [MarkerElement(marker=:circle, color=PARAM_COLOR[p], markersize=12)
               for p in PARAM_ORDER]
    Legend(fig[length(PLOT_PROXIES)+1, :], handles, short_label.(PARAM_ORDER);
           orientation=:horizontal, nbanks=2, framevisible=false, tellheight=true)

    mkpath(dirname(abspath(figure_file)))
    save(figure_file, fig; px_per_unit=2)
    return fig
end

function plot_mu_star(indices, figure_file::AbstractString)
    n = length(PARAM_ORDER)
    fig = panel_grid() do position, proxy, proxy_label, location
        selected = select(indices, proxy, location)
        ax = Axis(position; title="$(proxy_label), location $(location)",
                  xlabel="μ* ($(proxy_label) per unit range)",
                  yticks=(1:n, short_label.(PARAM_ORDER)), yreversed=true,
                  xgridvisible=false, ygridvisible=false)
        xlims!(ax, 0, nothing)
        isempty(selected) && return

        y = [findfirst(==(r.parameter), PARAM_ORDER) for r in selected]
        barplot!(ax, y, [r.mu_star for r in selected]; direction=:x,
                 color=:steelblue, gap=0.35)
        with_ci = [i for (i, r) in enumerate(selected) if isfinite(r.ci_low)]
        isempty(with_ci) && return
        rangebars!(ax, y[with_ci], [selected[i].ci_low for i in with_ci],
                   [selected[i].ci_high for i in with_ci];
                   direction=:x, color=:gray20, whiskerwidth=6, linewidth=1.5)
    end

    Label(fig[length(PLOT_PROXIES)+1, :], "Bars: μ*; whiskers: bootstrap 95% CI";
          color=:gray35, fontsize=13, tellwidth=false)

    mkpath(dirname(abspath(figure_file)))
    save(figure_file, fig; px_per_unit=2)
    return fig
end

function morris_figures(args=ARGS)
    if isempty(args)
        isfile(LOCAL_INDICES) ||
            error("$(LOCAL_INDICES) not found. Run Visualization/morris_scan.jl first.")
        indices_csv, mu_sigma_file, mu_star_file = LOCAL_INDICES, MU_SIGMA_FILE, MU_STAR_FILE
    elseif length(args) == 3
        indices_csv, mu_sigma_file, mu_star_file = args
    else
        error("Expected no arguments, or <indices_csv> <mu_sigma_png> <mu_star_png>.")
    end

    indices = read_indices(indices_csv)
    plot_mu_sigma(indices, mu_sigma_file)
    plot_mu_star(indices, mu_star_file)
    @info "Morris figures written" mu_sigma_file mu_star_file
end

morris_figures()
