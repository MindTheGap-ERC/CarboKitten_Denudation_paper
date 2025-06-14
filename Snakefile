import json

param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

BASE_COLLECTION="irods://nluu11p/home/research-mindthegap/denudation/dissolution"

with open("param_dissolution.json") as f:
    param_configs = json.load(f)

PARAMS = {entry["id"]: entry for entry in param_configs}
ID = list(PARAMS.keys())

rule all:
    input:
        storage(expand(BASE_COLLECTION+"/results/output_{run_id}.csv", run_id=ID)),
        # storage(expand(BASE_COLLECTION+"/plots/plot_{run_id}.png", run_id=ID))

# rule create_params:
#     output:
#         param_result = storage(BASE_COLLECTION+ "params.json")
#     shell:
#         """julia --project=. param_input.jl {output.param_result} """
        

rule run_model:
    # input:
        # param_file = storage(BASE_COLLECTION+ "params.json")
    output:
        csv = storage(BASE_COLLECTION + "/results/output_{run_id}.csv"),
        toml = storage(BASE_COLLECTION + "/results/output_{run_id}.toml"),
        h5 = storage(BASE_COLLECTION + "/results/output_{run_id}.h5")    
    shell:
        """
        julia --project=. run_dissolution.jl param_dissolution.json {wildcards.run_id} output_{wildcards.run_id}.csv output_{wildcards.run_id}.toml output_{wildcards.run_id}.h5
                
        cp output_{wildcards.run_id}.csv {output.csv}
        cp output_{wildcards.run_id}.toml {output.toml}
        cp output_{wildcards.run_id}.h5 {output.h5}
        
        rm output_{wildcards.run_id}.csv output_{wildcards.run_id}.toml output_{wildcards.run_id}.h5
        """

# rule generate_plot:
#     input:
#         result_file = storage(BASE_COLLECTION+"/results/output_{run_id}.csv")
#     output:
#         storage(BASE_COLLECTION+"/plots/plot_{run_id}.png")
#     shell:
#         """
#         julia plot_results.jl {input} {output}
#         """