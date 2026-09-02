import json
import re

param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

BASE_COLLECTION="irods://nluu11p/home/research-mindthegap/denudation/dissolution"

with open("param_dissolution.json") as f:
    param_configs = json.load(f)

PARAMS = {entry["id"]: entry for entry in param_configs}

def storage_id(index, run_id):
    safe_id = re.sub(r"[^A-Za-z0-9]+", "_", run_id).strip("_")
    return f"{index:03d}_{safe_id}"

RUN_IDS = {
    storage_id(index, entry["id"]): entry["id"]
    for index, entry in enumerate(param_configs, start=1)
}

rule all:
    input:
        storage(expand(BASE_COLLECTION+"/results/output_{storage_id}.csv", storage_id=RUN_IDS.keys())),
        storage(expand(BASE_COLLECTION+"/results/output_{storage_id}.toml", storage_id=RUN_IDS.keys())),
        storage(expand(BASE_COLLECTION+"/results/output_{storage_id}.h5", storage_id=RUN_IDS.keys()))
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
        csv = storage(BASE_COLLECTION + "/results/output_{storage_id}.csv"),
        toml = storage(BASE_COLLECTION + "/results/output_{storage_id}.toml"),
        h5 = storage(BASE_COLLECTION + "/results/output_{storage_id}.h5")
    params:
        run_id = lambda wildcards: RUN_IDS[wildcards.storage_id]
    shell:
        """
        julia --project=. {input.run_script:q} {input.param_file:q} {params.run_id:q} {output.csv:q} {output.toml:q} {output.h5:q}
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
