module Dissolution_Input
using JSON3

const param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

bounds = [
        (10, 200),       
        (2530, 2830),     
        (0.1, 0.9),
        (293, 303), 
        (1, 2),      
        (1e-4, 1e-2),    
        (1e-5, 2e-3),          
        ]

default_value = Dict(
        "reactive_surface" => 50,       
        "mass_density" => 2730,     
        "infiltration_coefficient" => 0.5,
        "temp" => 298, 
        "precip" => 1.5,      
        "pco2" => 1e-3,    
        "reactionrate" => 2e-4,
        "id" => "default"    
        )

    

N = 10
dim = length(param_names)
Chosen_Parameter_Place = collect(0:1/N:1)
paramsets = []

function get_param_sets()
    for i in 1:dim
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

paramsets = get_param_sets()

for param_name in param_names
    open("param_dissolution.json", "w") do io
        JSON3.write(io, paramsets)
    end
end

end
