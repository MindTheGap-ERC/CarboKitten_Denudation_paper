BASE_COLLECTION="irods://nluu11p/home/research-mindthegap/denudation/dissolution"


rule all:
    input:
        storage(expand(BASE_COLLECTION+"/results/output.txt"))


rule run_model:
    input:
        "test.jl"
    output:
        storage(BASE_COLLECTION+"/results/output.txt")
    shell:
        """
        julia --project=. {input} {output}
        """

