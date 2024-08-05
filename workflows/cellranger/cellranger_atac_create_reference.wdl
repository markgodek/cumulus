version 1.0

workflow cellranger_atac_create_reference {
    input {
        # Which docker registry to use
        String docker_registry = "quay.io/cumulus"
        # cellranger-atac version: 2.1.0, 2.0.0, 1.2.0, 1.1.0
        String cellranger_atac_version = "2.1.0"

        # Disk space in GB
        Int disk_space = 100
        # Google cloud zones
        String zones = "us-central1-a us-central1-b us-central1-c us-central1-f us-east1-b us-east1-c us-east1-d us-west1-a us-west1-b us-west1-c"
        # Memory string
        String memory = "32G"

        # Number of preemptible tries
        Int preemptible = 2
        # Backend
        String backend = "gcp"
        # Arn string of AWS queue
        String awsQueueArn = ""

        # Organism name
        String organism = ""
        # Genome name
        String genome
        # GSURL for input fasta file
        File input_fasta
        # GSURL for input GTF file
        File input_gtf
        # A comma separated list of names of contigs that are not in nucleus
        String non_nuclear_contigs = "chrM"
        # Optional file containing transcription factor motifs in JASPAR format
        File? input_motifs

        # Output directory, gs URL
        String output_directory
    }

    # Output directory, with trailing slashes stripped
    String output_directory_stripped = sub(output_directory, "[/\\s]+$", "")

    call run_cellranger_atac_create_reference {
        input:
            docker_registry = docker_registry,
            cellranger_atac_version = cellranger_atac_version,
            disk_space = disk_space,
            zones = zones,
            memory = memory,
            preemptible = preemptible,
            awsQueueArn = awsQueueArn,
            backend = backend,
            organism = organism,
            genome = genome,
            input_fasta = input_fasta,
            input_gtf = input_gtf,
            non_nuclear_contigs = non_nuclear_contigs,
            input_motifs = input_motifs,
            output_dir = output_directory_stripped
    }

    output {
        File output_reference = run_cellranger_atac_create_reference.output_reference
    }

}

task run_cellranger_atac_create_reference {
    input {
        String docker_registry
        String cellranger_atac_version
        Int disk_space
        String zones
        String memory

        Int preemptible
        String awsQueueArn
        String backend

        String? organism
        String genome
        File input_fasta
        File input_gtf
        String? non_nuclear_contigs
        File? input_motifs

        String output_dir
    }

    command {
        set -e
        export TMPDIR=/tmp
        export BACKEND=~{backend}
        monitor_script.sh > monitoring.log &

        python <<CODE
        with open("ref.config", "w") as fout:
            fout.write("{\n")
            if '~{organism}' != "":
                fout.write("    organism: \"~{organism}\"\n")
            fout.write("    genome: [\"~{genome}\"]\n")
            fout.write("    input_fasta: [\"~{input_fasta}\"]\n")
            fout.write("    input_gtf: [\"~{input_gtf}\"]\n")
            if '~{non_nuclear_contigs}' != "":
                fout.write("    non_nuclear_contigs: [" + ", ".join(['"' + x + '"' for x in '~{non_nuclear_contigs}'.split(',')]) + "]\n")
            if '~{input_motifs}' != "":
                fout.write("    input_motifs: \"~{input_motifs}\"\n")
            fout.write("\x7D\n") # '\x7D' refers to right brace bracket
        CODE

        cellranger-atac mkref --config=ref.config
        tar -czf ~{genome}.tar.gz ~{genome}
        strato cp -m ~{genome}.tar.gz "~{output_dir}"/
    }

    output {
        File output_reference = "~{genome}.tar.gz"
        File monitoringLog = "monitoring.log"
    }

    runtime {
        docker: "~{docker_registry}/cellranger-atac:~{cellranger_atac_version}"
        zones: zones
        memory: memory
        disks: "local-disk ~{disk_space} HDD"
        cpu: 1
        preemptible: preemptible
        queueArn: awsQueueArn
    }
}
