module Dissolution_Input
using JSON3

const PARAM_NAMES = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

const BOUNDS = [
        (50, 1500),       
        (2530, 2830),     
        (0.1, 0.9),
        (293, 303), 
        (1, 2),      
        (1e-4, 1e-3),    
        (1e-8, 2e-7),          
        ]

const DEFAULT_VALUE = Dict(
        "reactive_surface" => 100,       
        "mass_density" => 2730,     
        "infiltration_coefficient" => 0.5,
        "temp" => 298, 
        "precip" => 1.3,      
        "pco2" => 2.8e-4,    
        "reactionrate" => 8e-8,
        "id" => "default"    
        )


function get_param_sets(N::Int64, param_names::Vector{String}, bounds::Vector{<:Tuple{Real, Real}}, default_value::Dict{String, Any})
    Chosen_Parameter_Place = collect(0:1/N:1)
    paramsets = []

    for i in 1:length(param_names)
        param_name = param_names[i]
        for (j,val) in enumerate(Chosen_Parameter_Place)
            paramset_j = copy(default_value)
            param_value = bounds[i][1] + (bounds[i][2] - bounds[i][1]) * val
            paramset_j[param_name] = param_value
            paramset_j["id"] = "$(param_name)_$param_value"
            push!(paramsets, paramset_j)
        end
    end
    return paramsets
end

const N = 10

paramsets = get_param_sets(N, PARAM_NAMES, BOUNDS, DEFAULT_VALUE)

for param_name in PARAM_NAMES
    open("param_dissolution.json", "w") do io
        JSON3.write(io, paramsets)
    end
end

end
