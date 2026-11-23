using CairoMakie
using CarboKitten.Visualization: sediment_profile, summary_plot, stratigraphic_column!
using CarboKitten.Export: read_slice, Header, DataSlice, read_column, DataColumn, sediment_thickness
using CarboKitten.Output.Storage: water_depth

using Unitful

const HDF5_file = "data/output/dissolution_validation.h5"

header, data = read_slice(HDF5_file, :profile)

const location = [10, 30, 50, 70]

function plot_sediment_profile(HDF5_file::String)
    header, data = read_slice(HDF5_file, :profile)
	fig = sediment_profile(header, data, show_unconformities = false)
    save("data/figure/denudation_sediment_profile.png", fig)
end


function plot_sediment_accumulation(header::Header, data::DataSlice, location::Int; ax::Axis)
    time_interval = (header.axes.t[end] - header.axes.t[1]) /
                     (size(data.bathymetry, 2) - 1)
    times_range = header.axes.t[1]:time_interval:header.axes.t[end]
    times = collect(times_range)
    times = Float64.(vec(times) ./ u"Myr")

    thickness = Float64.(vec(sediment_thickness(data)[location, :]) ./ u"m")

    lines!(ax, times, thickness, color = :black)
end

function plot_stratigraphic_column(header::Header, data::DataSlice, location::Int; ax::Axis)
    fig = Figure()
    ax = Axis(fig[1, 1]; title="Stratigraphic Column at Location $(location)", ylabel="Depth [m]")
    
    column = data[location]
    
    stratigraphic_column!(ax, header, column; color = Makie.wong_colors())
    
    return fig
end


function plot_barrel(header::Header, data::DataSlice, location::Int)
    fig = Figure()

    ax1 = Axis(fig[1, 1]; title = "Sediment Accumulation at Location $(location)", xlabel = "Time (Myr)", ylabel = "Sediment Thickness (m)")
    plot_sediment_accumulation(header, data, location; ax = ax1)

    ax2 = Axis(fig[1, 2]; title = "Stratigraphic Column)", ylabel = "Depth (m)")
    colsize!(fig.layout, 2, Relative(0.15))
    
    linkaxes!(ax1, ax2)
    
    column = data[location]
    stratigraphic_column!(ax2, header, column; color = Makie.wong_colors())
    save("data/figure/denudation_barrel_location_$(location).png", fig)
    return fig
end

for loc in location
    plot_barrel(header, data, loc)
end

function calculate_mean_denudation_rates(
    header::Header,
    data::DataSlice,
    location::Int)

    depths = water_depth(header, data)
    times = header.axes.t[1:data.write_interval:end]

    # The profile output is written every timestep, so each disintegration
    # value (after the initial zero frame) records removal during one interval.
    data.write_interval == 1 || error(
        "Integrated denudation requires profile output with write_interval=1; " *
        "the saved disintegration values are per-step amounts.")

    n = min(length(times), size(depths, 2), size(data.disintegration, 3))
    durations = diff(times[1:n])
    exposed = vec(depths[location, 1:n-1] .<= 0u"m")
    exposed_duration = sum(durations[exposed]; init=0u"Myr")
    if iszero(exposed_duration)
        println("No exposed intervals found at location $(location).")
        return nothing
    end

    # Frame 1 is the initial state; frame i contains removal during t[i-1] → t[i].
    removed_per_interval = dropdims(
        sum(data.disintegration[:, location, 2:n]; dims=1), dims=1)
    denudated_thickness = sum(removed_per_interval[exposed]; init=0u"m")
    return uconvert(u"mm/kyr", denudated_thickness / exposed_duration)
end

function plot_mean_denudation_rates(header::Header, data::DataSlice, locations::Vector{Int}; ax::Axis)
    mean_rates = [calculate_mean_denudation_rates(header, data, loc) for loc in locations]
    valid = findall(rate -> rate !== nothing, mean_rates)
    isempty(valid) && return ax

    rates = Float64[ustrip(u"mm/kyr", mean_rates[i]) for i in valid]
    CairoMakie.lines!(ax, locations[valid], rates, color = :black)
    ax.xlabel = "Location"
    ax.ylabel = "Mean Denudation Rate (mm/kyr)"
    ax.title = "Mean Denudation Rates at Different Locations"
    return ax
end

function plot_water_depth(header::Header, data::DataSlice, location::Int; ax::Axis)
    depths = water_depth(header, data)
    time_interval = (header.axes.t[end] - header.axes.t[1]) /
                     (size(data.bathymetry, 2) - 1)
    times_range = header.axes.t[1]:time_interval:header.axes.t[end]
    times = collect(times_range)
    times = Float64.(vec(times ./ u"Myr"))

    depth_values = Float64.(vec(depths[location, :]) ./ u"m")

    lines!(ax, times, depth_values, color = :blue)
    ax.xlabel = "Time (Myr)"
    ax.ylabel = "Water Depth (m)"
    ax.title = "Water Depth at Location $(location)"
end


for loc in location
    mean_rate = calculate_mean_denudation_rates(header, data, loc)
    println("Mean denudation rate at location $(loc): $(mean_rate)")
end

mean_rate_fig = Figure()
plot_mean_denudation_rates(header, data, location; ax = Axis(mean_rate_fig[1, 1]))
save("data/figure/denudation_mean_rates.png", mean_rate_fig)

water_depth_fig = Figure()
for (i, loc) in enumerate(location)
    plot_water_depth(header, data, loc; ax = Axis(water_depth_fig[i, 1], width = 600, height = 50 * length(location)))
    resize_to_layout!(water_depth_fig)
end
save("data/figure/denudation_water_depth.png", water_depth_fig)



#save("data/figure/denudation_summary.png", summary_plot(HDF5_file))
