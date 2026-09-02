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

#const json_file_path = "data/input/$(ARGS[1]).json"

const PATH = "data/output"
const TAG = "Physical_Denudation"

function read_json(json_file::String)
    PARAMS = DataFrame(JSON3.read(json_file)) 
    return PARAMS 
end

PARAMS1 = read_json("$(ARGS[1])")

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
            reactive_surface=  1000 * 1.0u"m^2/m^3",
            mass_density= 2730 * 1.0u"kg/m^3",
            infiltration_coefficient= P.infiltration_coefficient,
            erodibility = P.erodibility .* 1.0u"m/yr"
            ),
        WDn.Facies(
            viability_range=(4, 10),
            activation_range=(6, 10),
            maximum_growth_rate=400u"m/Myr",
            extinction_coefficient=0.1u"m^-1",
            saturation_intensity=60u"W/m^2",
            diffusion_coefficient=5u"m/yr",
            reactive_surface=  1000 * 1.0u"m^2/m^3",
            mass_density= 2730 * 1.0u"kg/m^3",
            infiltration_coefficient= P.infiltration_coefficient,
            erodibility = P.erodibility .* 1.0u"m/yr"
            ),
        WDn.Facies(
            viability_range=(4, 10),
            activation_range=(6, 10),
            maximum_growth_rate=100u"m/Myr",
            extinction_coefficient=0.005u"m^-1",
            saturation_intensity=60u"W/m^2",
            diffusion_coefficient=7u"m/yr",
            reactive_surface=  1000 * 1.0u"m^2/m^3",
            mass_density= 2730 * 1.0u"kg/m^3",
            infiltration_coefficient= P.infiltration_coefficient,
            erodibility = P.erodibility .* 1.0u"m/yr"
            )
    ]
    
    DENUDATION = PhysicalErosion()
    
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

function main(input,ID::String, CSV_FILE::String, TOML_FILE::String, H5_FILE::String)
    H5Writer.run_model(Model{WDn}, input, H5_FILE)

    data_export(
        CSV(tuple.(10:20:70, 25),
          :sediment_accumulation_curve => CSV_FILE,
          :metadata => TOML_FILE),
        H5_FILE)
end

run_id = "$(ARGS[2])"
p = filter(row -> row.id == run_id, eachrow(PARAMS1))

INPUT, _ , ID = determine_denu_input(p[1])
main(INPUT,ID,"$(ARGS[3])", "$(ARGS[4])","$(ARGS[5])")
