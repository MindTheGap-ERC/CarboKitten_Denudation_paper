module Dissolution_Input
using JSON3
using Unitful

param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

struct ParamSet
    id::String
    reactive_surface::u"m^2/m^3"
    mass_density::u"kg/m^3"
    infiltration_coefficient::Float64
    temp::u"K"
    precip::u"m/y"
    pco2::u"atm"
    reactionrate::u"m/y"
end

bounds = [
        (10000, 50000),       
        (2530, 2830),     
        (0.1, 0.9),
        (293, 303), 
        (1, 2),      
        (1e-4, 1e-2),    
        (1e-5, 2e-3),          
        ]

N = 10
dim = length(param_names)
Chosen_Parameter_Place = collect(0:1/N:1)

function addnames(ps::ParamSet)
    return Dict(
        "id" => ps.id,
        "param1" => ps.param1,
        "param2" => ps.param2,
        "param3" => ps.param3,
        "param4" => ps.param4,
        "param5" => ps.param5,
        "param6" => ps.param6,
        "param7" => ps.param7,
    )
end

paramsets = ParamSet[]
for (i, row) in enumerate(eachrow(Chosen_Parameter_Place))
    scaled_vals = [
        bounds[j][1] + (bounds[j][2] - bounds[j][1]) * row[j]
        for j in 1:dim
    ]
    id = "run_$(lpad(i, 4, '0'))"
    ps = ParamSet(id, scaled_vals...)
    push!(paramsets, ps)
end

dicts = to_dict.(paramsets)

open("params.json", "w") do io
    JSON3.write(io, params)
end


end
