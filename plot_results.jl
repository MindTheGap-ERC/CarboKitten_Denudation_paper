module plot_denudation_results
    using GLMakie
    using DataFrames

    function read_data(path::String)
        data = DataFrame(CSV.File(path))
        return data
    end
    
    data = read_data("$([ARG2]).csv")

    function plot_sac(data::DataFrame)
        age = data[:,1]
        SAC= data[:,2]
        fig = Figure()
        ax = Axis(fig[1, 1], title="SAC_$([ARG2])", xlabel="Age (Myr)", ylabel="sediment_accumulation_height (m)")
        lines!(ax, age, SAC, color=:blue)
        save(path, fig)
    end

    function compute_ADM(data::DataFrame)
        age = data[:,1]
        SAC= data[:,2]
        ADM = SAC |> reverse |> accumulate(min) |> reverse
        return age, ADM, SAC
    end
        
    function get_completeness(age::Vector{Float64}, ADM::Vector{Float64})
        completeness = zeros(length(age))
        for i in 1:length(age)
            if ADM[i] ≈ 0.0
                completeness[i] = 0
            else
                completeness[i] = 1
            end
        end
        return sum(completeness)/length(completeness)
    end


end