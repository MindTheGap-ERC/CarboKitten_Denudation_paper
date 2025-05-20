using CarboKitten
using Unitful
using CarboKitten.Components
using CarboKitten.Components.Common
using CarboKitten.Components.Denudation
using CarboKitten.Models: WithDenudation as WDn
using CarboKitten.Export: data_export, CSV
using CarboKitten.Denudation
using JSON3
using DataFrames


const m = u"m"
const Myr = u"Myr"

const json_file_path = "data/input/$(ARGS[1]).json"

const PATH = "data/output"
const TAG = "dissolution"

function read_json(json_file::String)
    PARAMS = DataFrame(JSON3.read(json_file)) 
    return PARAMS 
end

PARAMS1 = read_json("param_dissolution.json")

function determine_denu_input(P::DataFrameRow)
    ID = P.id
    
    FACIES = [
        WDn.Facies(
            viability_range=(4, 10),
            activation_range=(6, 10),
            maximum_growth_rate=500u"m/Myr",
            extinction_coefficient=0.8u"m^-1",
            saturation_intensity=60u"W/m^2",
            diffusion_coefficient=10u"m/yr",
            reactive_surface= P.reactive_surface * 1.0u"m^2/m^3",
            mass_density= P.mass_density * 1.0u"kg/m^3",
            infiltration_coefficient=0.5,
            erodibility = 0.23u"m/yr"
            ),
        WDn.Facies(
            viability_range=(4, 10),
            activation_range=(6, 10),
            maximum_growth_rate=400u"m/Myr",
            extinction_coefficient=0.1u"m^-1",
            saturation_intensity=60u"W/m^2",
            diffusion_coefficient=5u"m/yr",
            reactive_surface= P.reactive_surface * 1.0u"m^2/m^3",
            mass_density= P.mass_density * 1.0u"kg/m^3",
            infiltration_coefficient=0.5,
            erodibility = 0.23u"m/yr"
            ),
        WDn.Facies(
            viability_range=(4, 10),
            activation_range=(6, 10),
            maximum_growth_rate=100u"m/Myr",
            extinction_coefficient=0.005u"m^-1",
            saturation_intensity=60u"W/m^2",
            diffusion_coefficient=7u"m/yr",
            reactive_surface= P.reactive_surface * 1.0u"m^2/m^3",
            mass_density=2730u"kg/m^3",
            infiltration_coefficient=0.5,
            erodibility = 0.23u"m/yr"
            )
    ]
    
    DENUDATION = Dissolution(P.temp * 1.0u"K", P.precip*1.0u"m", P.pco2 * 1.0u"atm", P.reactionrate * 1.0u"m/yr")
    
     PERIOD = 0.2Myr
     AMPLITUDE = 20.0m    
     INPUT = WDn.Input(
        tag="$(ID)",
        box=Box{Coast}(grid_size=(100, 50), phys_scale=150.0m),
        time=TimeProperties(
            Δt=0.0002Myr,
            steps=5000,
            write_interval=1),
        ca_interval=1,
        initial_topography=(x, y) -> -x / 300.0,
        sea_level=t -> AMPLITUDE * sin(2π * t / PERIOD),
        subsidence_rate=20.0m / Myr,
        disintegration_rate=500.0m / Myr,
        insolation=400.0u"W/m^2",
        sediment_buffer_size=50,
        depositional_resolution=0.5m,
        facies=FACIES,
        denudation = DENUDATION)

        return (INPUT, DENUDATION, ID)
end

function main(input,ID::String)
    H5Writer.run_model(Model{WDn}, input, "$(ID).h5")

    data_export(
        CSV(tuple.(10:20:70, 25),
          :sediment_accumulation_curve => "$([ARG2]).csv",
          :metadata => "$([ARG3]).toml"),
        "$([ARG4]).h5")
end

for P in eachrow(PARAMS1)
    INPUT, _ , ID = determine_denu_input(P)
    main(INPUT,ID)
end