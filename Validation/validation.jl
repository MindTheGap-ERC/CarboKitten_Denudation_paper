using CairoMakie
using CarboKitten
using CarboKitten.Models: WithDenudation as WDn
include("denudation_param_config.jl")
using .DenudationParamConfig
using CarboKitten.Export: data_export, read_slice, CSV

const PATH = "data/output"
const TAG = "dissolution_validation"
const SURF = [400u"m^2/m^3", 9000u"m^2/m^3", 10000u"m^2/m^3"]
const DENS = [2230u"kg/m^3", 2730u"kg/m^3", 2530u"kg/m^3"]
const INF = [0.5, 0.5, 0.5]
const DENUDATION = CarboKitten.Denudation.Dissolution(temp=293.0u"K", precip=1.0u"m/yr", pco2=0.02 * 10^(-2) * u"atm", reactionrate=2e-3u"m/yr")

function run_diss_validation()
    FACIES = DenudationParamConfig.facies(SURF, DENS, INF)
    INPUT = DenudationParamConfig.input(TAG, DENUDATION, FACIES)
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

run_diss_validation()

