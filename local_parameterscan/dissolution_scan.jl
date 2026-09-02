using CarboKitten
using CarboKitten.Models: WithDenudation as WDn

using .FaciesParam
using Json3


input(tag, denudation, facies) = WDn.Input(
    tag=tag,
    box=Box{Coast}(grid_size=(100, 50), phys_scale=150.0m),
    time=TimeProperties(
        Δt=0.0002Myr,
        steps=5000),
    output=Dict(
        :topography => OutputSpec(slice=(:,:), write_interval=10),
        :profile => OutputSpec(slice=(:, 25), write_interval=1)),
    ca_interval=1,
    initial_topography=(x, y) -> -x / 300.0,
    sea_level=t -> AMPLITUDE * sin(2π * t / PERIOD),
    subsidence_rate=20.0m / Myr,
    disintegration_rate=500.0m / Myr,
    insolation=400.0u"W/m^2",
    sediment_buffer_size=50,
    depositional_resolution=0.5m,
    lithification_time=100.0u"yr",
    facies=facies,
    denudation = denudation)



function dissolution_runmodel()
    FACIES = facies(SURF,DENS,INFIL)
    INPUT = input(TAG, DENUDATION, FACIES)
    run_model(Model{WDn}, INPUT, "$(PATH)/$(TAG).h5")
        header, profile = read_slice("$(PATH)/$(TAG).h5", :profile)
    columns = [profile[i] for i in 10:20:70]
    data_export(
        CSV(:sediment_accumulation_curve => "$(PATH)/$(TAG)_sac.csv",
            :age_depth_model => "$(PATH)/$(TAG)_adm.csv",
            :stratigraphic_column => "$(PATH)/$(TAG)_sc.csv",
            :water_depth => "$(PATH)/$(TAG)_wd.csv",
            :metadata => "$(PATH)/$(TAG).toml"),
         header,
         columns)
end

const RANGE = Dict(
    "reactive_surface" => (10, 200),
    "mass_density" => (2530, 2830),
    "infiltration_coefficient" => (0.1, 0.9),
    "temp" => (293, 303),
    "precip" => (1, 2),
    "pco2" => (1e-4, 1e-2),
    "reactionrate" => (1e-5, 2e-3)
)

function parameter_scan(NAME::String)

    if haskey(RANGE, NAME)
        (min_p, max_p) = RANGE[NAME]
        range = collect(range(min_p, max=max_p, length=10))
        return range
    end

    
        

end