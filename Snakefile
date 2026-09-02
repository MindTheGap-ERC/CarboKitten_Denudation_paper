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
        storage(expand(BASE_COLLECTION+"/results/output_{run_id}.toml", run_id=ID)),
        storage(expand(BASE_COLLECTION+"/results/output_{run_id}.h5", run_id=ID))
        # storage(expand(BASE_COLLECTION+"/plots/plot_{run_id}.png", run_id=ID))

# rule create_params:
#     output:
#         param_result = storage(BASE_COLLECTION+ "params.json")
#     shell:
#         """julia --project=. param_input.jl {output.param_result} """
        

rule run_model:
    input:
        param_file = "param_dissolution.json",
        run_script = "cloud_parameterscan/runs/run_dissolution.jl"
    output:
        csv = storage(BASE_COLLECTION + "/results/output_{run_id}.csv"),
        toml = storage(BASE_COLLECTION + "/results/output_{run_id}.toml"),
        h5 = storage(BASE_COLLECTION + "/results/output_{run_id}.h5")    
    shell:
        """
        julia --project=. {input.run_script:q} {input.param_file:q} {wildcards.run_id:q} {output.csv:q} {output.toml:q} {output.h5:q}
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
