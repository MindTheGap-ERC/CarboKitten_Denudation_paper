using CairoMakie
using CarboKitten.Visualization: sediment_profile, summary_plot, stratigraphic_column!
using CarboKitten.Export: read_slice, Header, DataSlice, read_column, DataColumn, sediment_thickness
using CarboKitten.Output.Storage: water_depth

using Unitful

const HDF5_file = "data/output/dissolution_validation.h5"

header, data = read_slice(HDF5_file, :profile)

const location = [5, 25, 45, 65]

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
    locations::Int)

    depths = water_depth(header, data)
    thickness = sediment_thickness(data)[locations, :]
    times = header.axes.t[1:data.write_interval:end]


    durations = diff(times)
    thickness_changes = diff(thickness)
    exposed = vec(depths[locations, 1:end-1] .< 0u"m")
    exposed_duration = sum(durations[exposed]; init=0u"Myr")
    @show exposed_duration
    @show -sum(thickness_changes[exposed])
    if iszero(exposed_duration)
        println("No exposed intervals found at location $(locations).")
        return nothing
    end

    sediment_loss = -sum(thickness_changes[exposed])
    return uconvert(u"mm/kyr", sediment_loss / exposed_duration)
end

calculate_mean_denudation_rates(header, data, 25)

for loc in location
    mean_rate = calculate_mean_denudation_rates(header, data, loc)
    println("Mean denudation rate at location $(loc): $(mean_rate)")
end

#save("data/figure/denudation_summary.png", summary_plot(HDF5_file))