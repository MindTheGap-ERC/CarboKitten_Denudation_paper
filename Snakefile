import json
import os

param_names = ["reactive_surface", "mass_density", "infiltration_coefficient", "temp",
         "precip", "pco2", "reactionrate"]

BASE_COLLECTION="irods://nluu11p/home/research-mindthegap/denudation/dissolution/"

rule all:
    input:
        expand(BASE_COLLECTION+"/results/output_{run_id}.csv"),
        expand(BASE_COLLECTION+"/plots/plot_{run_id}.png")

rule create_params:
    output:
        param_result = storage(BASE_COLLECTION+ "params.json")
    shell:
        """
        julia param_input.jl {output} 
        """

rule run_model:
    input:
        param_file = storage(BASE_COLLECTION+ "params.json")
    output:
        storage(BASE_COLLECTION+"/results/output_{run_id}.csv")
    shell:
        """
        julia run_dissolution.jl {input} {output.csv} {output.toml} {output.h5}
        """

rule generate_plot
    input:
        result_file = storage(BASE_COLLECTION+"/results/output_{run_id}.csv")
    output:
        storage(BASE_COLLECTION+"/plots/plot_{run_id}.png")
    shell:
        """
        julia plot_results.jl {input} {output}
        """