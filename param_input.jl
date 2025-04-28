module Dissolution_Input
using JSON3
using Unitful

param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

struct ParamSet
    id::String
    reactive_surface::typeof("m^2/m^3")
    mass_density::typeof("kg/m^3")
    infiltration_coefficient::Float64
    temp::typeof("K")
    precip::typeof("m/yr")
    pco2::typeof("atm")
    reactionrate::typeof("m/yr")
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
        "reactive_surface" => ps.reactive_surface,
        "mass_density" => ps.mass_density,
        "infiltration_coefficient" => ps.infiltration_coefficient,
        "temp" => ps.temp,
        "precip" => ps.precip,
        "pco2" => ps.pco2,
        "reactionrate" => ps.reactionrate,
    )
end

paramsets = ParamSet[]

for (i, val) in enumerate(Chosen_Parameter_Place)
    scaled_vals = [
        bounds[j][1] + (bounds[j][2] - bounds[j][1]) * val
        for j in 1:dim
    ]
    id = "run_$(lpad(i, 4, '0'))"
    ps = ParamSet(id, scaled_vals...)
    push!(paramsets, ps)
end

dicts = addnames.(paramsets)

open("params.json", "w") do io
    JSON3.write(io, dicts)
end


end
