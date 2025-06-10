module Physical_Input
using JSON3

const param_names = [ "infiltration_coefficient", "precip", "erodibility"]

bounds = [     
        (0.1, 0.9),
        (1, 2),         
        (1e-3, 5e-3)         
        ]

default_value = Dict(
        "infiltration_coefficient" => 0.5,
        "precip" => 1.5,      
        "erodibility" => 0.0023,
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
            paramset_j["id"] = "Phys_$(param_name)_$param_value"
            push!(paramsets, paramset_j)
        end
    end
    return paramsets
end

paramsets = get_param_sets()

for param_name in param_names
    open("param_physics.json", "w") do io
        JSON3.write(io, paramsets)
    end
end

end
