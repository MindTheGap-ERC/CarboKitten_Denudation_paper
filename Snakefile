BASE_COLLECTION="irods://nluu11p/home/research-mindthegap/denudation/dissolution"


rule all:
    input:
        meta=storage(expand(BASE_COLLECTION+"/results/output.txt"))

    output:
        "metadata.json"

    shell:
        "cp {input} {output}"

rule create:
    output:
        file=storage(expand(BASE_COLLECTION+"/results/output.txt")),


    shell:
        "julia --project=. test.jl {output.file}"
 