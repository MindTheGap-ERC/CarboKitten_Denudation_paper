module Empirical_Input
using JSON3

const param_names = ["precip"]

bounds = [  
        (1, 2)         
        ]
    
default_value = Dict(
        "precip" => 1.5, 
        "id" => "default"    
        )

N = 10
dim = length(param_names)
Chosen_Parameter_Place = collect(0:1/N:1)
paramsets = []

function get_param_sets()

        for (j,val) in enumerate(Chosen_Parameter_Place)
            paramset = copy(default_value)
            param_value = bounds[1][1] + (bounds[1][2] - bounds[1][1]) * val
            paramset[param_names[1]] = param_value
            paramset["id"] = "Emp_$param_value"
            push!(paramsets, paramset)
        end
    return paramsets
end

paramsets = get_param_sets()

for param_name in param_names
    open("param_emp.json", "w") do io
        JSON3.write(io, paramsets)
    end
end

end
