version 1.0

workflow trust4_create_reference {
    input {
        # Which docker registry to use
        String docker_registry = "quay.io/cumulus"
        # trust4 version
        String trust4_version = "master"

        # Disk space in GB
        Int disk_space = 50
        # Google cloud zones
        String zones = "us-central1-a us-central1-b us-central1-c us-central1-f us-east1-b us-east1-c us-east1-d us-west1-a us-west1-b us-west1-c"
        # Memory string
        String memory = "8G"

        # Number of preemptible tries
        Int preemptible = 2
        # Arn string of AWS queue
        String awsQueueArn = ""
        # Backend
        String backend = "gcp"

        # Reference FASTA file
        File reference_fasta
        # Annotation GTF file
        File annotation_gtf
        # gene name list of interest
        File gene_name_list
        # Species name
        String species
        # Reference name
        String ref_name

        # Output directory, URL
        String output_directory
    }

    # Output directory, with trailing slashes stripped
    String output_directory_stripped = sub(output_directory, "[/\\s]+$", "")

    call run_trust4_create_reference {
        input:
            docker_registry = docker_registry,
            trust4_version = trust4_version,
            disk_space = disk_space,
            zones = zones,
            memory = memory,
            preemptible = preemptible,
            awsQueueArn = awsQueueArn,
            backend = backend,
            reference_fasta = reference_fasta,
            annotation_gtf = annotation_gtf,
            gene_name_list = gene_name_list,
            species = species,
            ref_name = ref_name,
            output_dir = output_directory_stripped
    }

    output {
        File output_reference = run_trust4_create_reference.output_reference
    }

}

task run_trust4_create_reference {
    input {
        String docker_registry
        String trust4_version
        Int disk_space
        String zones
        String memory
        Int preemptible
        String awsQueueArn
        String backend
        File reference_fasta
        File annotation_gtf
        File gene_name_list
        String species
        String ref_name
        String output_dir
    }

    command {
        set -e
        export TMPDIR=/tmp
        export BACKEND=~{backend}
        monitor_script.sh > monitoring.log &

        mkdir -p ~{ref_name}

        python <<CODE
        from subprocess import run, check_call
        import os

        def uncompress_file(compressed_file):
            call_args = ['gunzip', compressed_file]
            print(' '.join(call_args))
            check_call(call_args)
            return(os.path.splitext(compressed_file)[0])

        ref_fa = '~{reference_fasta}'
        annotation_gtf = '~{annotation_gtf}'
        if ref_fa.endswith('.gz'):
            ref_fa = uncompress_file(ref_fa)
        if annotation_gtf.endswith('.gz'):
            annotation_gtf = uncompress_file(annotation_gtf)

        with open('~{ref_name}/bcrtcr.fa', "w") as outfile1:
            call_args = ['perl', '/BuildDatabaseFa.pl', ref_fa, annotation_gtf, '~{gene_name_list}']
            print(' '.join(call_args))
            run(call_args, stdout = outfile1, check = True)

        with open('~{ref_name}/IMGT+C.fa', "w") as outfile2:
            call_args = ['perl', '/BuildImgtAnnot.pl', '~{species}']
            print(' '.join(call_args))
            run(call_args, stdout = outfile2, check = True)

        CODE

        tar -czf ~{ref_name}.tar.gz ~{ref_name}

        strato cp --backend ~{backend} -m ~{ref_name}.tar.gz ~{output_dir}/


    }

    output {
        File output_reference = "~{ref_name}.tar.gz"
        File monitoringLog = "monitoring.log"
    }

    runtime {
        docker: "~{docker_registry}/trust4:~{trust4_version}"
        zones: zones
        memory: memory
        disks: "local-disk ~{disk_space} HDD"
        cpu: 1
        preemptible: preemptible
        queueArn: awsQueueArn
    }
}
