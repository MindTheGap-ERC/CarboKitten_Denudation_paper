import json

# Runs the dissolution model for every entry of a parameter file and stores the output
# on iRODS. Defaults to the one-at-a-time scan; the Morris scan uses the same rules:
#
#   OAT:    snakemake --cores <n>
#   Morris: snakemake --cores <n> --config param_file=param_dissolution_morris.json collection=dissolution_morris
#
# Add any extra storage options you normally use; a dry run (-n) lists the jobs first.
#
# (Generate param_dissolution_morris.json first with
#  cloud_parameterscan/createjson/param_input_morris.jl.)

param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

PARAM_FILE = config.get("param_file", "param_dissolution.json")
COLLECTION = config.get("collection", "dissolution")
BASE_COLLECTION = "irods://nluu11p/home/research-mindthegap/denudation/" + COLLECTION

with open(PARAM_FILE) as f:
    param_configs = json.load(f)

PARAMS = {entry["id"]: entry for entry in param_configs}
ID = list(PARAMS.keys())

rule all:
    input:
        storage(expand(BASE_COLLECTION+"/results/output_{run_id}.csv", run_id=ID)),
        storage(expand(BASE_COLLECTION+"/results/output_{run_id}.toml", run_id=ID)),
        storage(expand(BASE_COLLECTION+"/results/output_{run_id}.h5", run_id=ID)),
        storage(expand(BASE_COLLECTION+"/results/waterdepth_{run_id}.csv", run_id=ID))
        # storage(expand(BASE_COLLECTION+"/plots/plot_{run_id}.png", run_id=ID))

# rule create_params:
#     output:
#         param_result = storage(BASE_COLLECTION+ "params.json")
#     shell:
#         """julia --project=. param_input.jl {output.param_result} """
        

rule run_model:
    input:
        param_file = PARAM_FILE,
        run_script = "cloud_parameterscan/runs/run_dissolution.jl"
    output:
        csv = storage(BASE_COLLECTION + "/results/output_{run_id}.csv"),
        toml = storage(BASE_COLLECTION + "/results/output_{run_id}.toml"),
        h5 = storage(BASE_COLLECTION + "/results/output_{run_id}.h5"),
        wd = storage(BASE_COLLECTION + "/results/waterdepth_{run_id}.csv")
    shell:
        """
        julia --project=. {input.run_script:q} {input.param_file:q} {wildcards.run_id:q} {output.csv:q} {output.toml:q} {output.h5:q} {output.wd:q}
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
