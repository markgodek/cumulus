version 1.0

workflow trust4 {
    input {
        # TRUST4 version
        String trust4_version = "master"
        # Sample ID
        String sample_id
        # A comma-separated list of input FASTQs directories (urls)
        String? input_fastqs_directories
        # Output directory, URL
        String output_directory

        # Keywords or a URL to a tar.gz file
        String genome
        # Index TSV file
        File acronym_file

        # Number of cpus per trust4 job
        Int num_cpu = 8
        # Memory string
        String memory = "32G"
        # Disk space in GB
        Int disk_space = 200

        # R2 Fastq pattern SE data
        String se_fastq_pattern = "_S*_L*_R2_001.fastq.gz"
        # R1 Fastq pattern PE data
        String? pe_read1_fastq_pattern
        # R2 Fastq pattern PE data
        String? pe_read2_fastq_pattern
        # start, end(-1 for length-1), in -1/-u files for genomic sequence
        String? read1_range
        # start, end(-1 for length-1), in -2 files for genomic sequence
        String? read2_range

        # Barcode Fastq pattern
        String barcode_fastq_pattern = "_S*_L*_R1_001.fastq.gz"
        # start, end(-1 for length-1), strand in a barcode is the true barcode
        String barcode_range = "0,15,+"
        # Barcode whitelist, can be gzipped
        File? barcode_whitelist
        # UMI Fastq pattern
        String umi_fastq_pattern = "_S*_L*_R1_001.fastq.gz"
        # start, end(-1 for length-1), strand in a UMI is the true UMI
        String umi_range = "16,-1,+"

        # path to bam file
        File? input_bam
        # bam field for barcode
        String? bam_barcode_field
        # bam field for for UMI
        String? bam_umi_field
        # the flag in BAM for the unmapped read-pair is nonconcordant
        String? bam_abnormal_unmap_flag

        # do not extend assemblies with mate information, useful for SMART-seq
        Boolean? skipMateExtension
        # the suffix length in read id for mate
        Int? mateIdSuffixLen
        # directly use the files from provided -1 -2/-u to assemble
        Boolean? noExtraction
        # the data is from TCR-seq or BCR-seq
        Boolean? repseq
        # output read assignment results to the prefix_assign.out file
        Boolean? outputReadAssignment

        # Which docker registry to use: quay.io/cumulus (default) or cumulusprod
        String docker_registry = "quay.io/cumulus"
        # Google cloud zones, default to "us-central1-b"
        String zones = "us-central1-b"
        # Backend
        String backend = "gcp"
        # Number of preemptible tries
        Int preemptible = 2
        # Arn string of AWS queue
        String awsQueueArn = ""
    }
    # Output directory, with trailing slashes stripped
    String output_directory_stripped = sub(output_directory, "[/\\s]+$", "")
    String docker_registry_stripped = sub(docker_registry, "/+$", "")

    Map[String, String] acronym2gsurl = read_map(acronym_file)
    Boolean is_url = sub(genome, "^.+\\.(tgz|gz)$", "URL") == "URL"
    File genome_file = (if is_url then genome else acronym2gsurl[genome])

    call run_trust4 {
        input:
            trust4_version = trust4_version,
            sample_id = sample_id,
            input_fastqs_directories = input_fastqs_directories,
            output_directory = output_directory_stripped,
            genome_file = genome_file,
            num_cpu = num_cpu,
            memory = memory,
            disk_space = disk_space,
            se_fastq_pattern = se_fastq_pattern,
            pe_read1_fastq_pattern = pe_read1_fastq_pattern,
            pe_read2_fastq_pattern = pe_read2_fastq_pattern,
            read1_range = read1_range,
            read2_range = read2_range,
            barcode_fastq_pattern = barcode_fastq_pattern,
            barcode_range = barcode_range,
            barcode_whitelist = barcode_whitelist,
            umi_fastq_pattern = umi_fastq_pattern,
            umi_range = umi_range,
            input_bam = input_bam,
            bam_barcode_field = bam_barcode_field,
            bam_umi_field = bam_umi_field,
            bam_abnormal_unmap_flag = bam_abnormal_unmap_flag,
            skipMateExtension = skipMateExtension,
            mateIdSuffixLen = mateIdSuffixLen,
            noExtraction = noExtraction,
            repseq = repseq,
            outputReadAssignment = outputReadAssignment,
            docker_registry = docker_registry_stripped,
            zones = zones,
            preemptible = preemptible,
            awsQueueArn = awsQueueArn,
            backend = backend
    }


    output {
        String output_vdj_directory = run_trust4.output_vdj_directory
        File monitoringLog = run_trust4.monitoringLog
    }

}

task run_trust4 {
    input {
        String trust4_version
        String sample_id
        String? input_fastqs_directories
        String output_directory
        File genome_file
        Int num_cpu
        String memory
        Int disk_space
        String se_fastq_pattern
        String? pe_read1_fastq_pattern
        String? pe_read2_fastq_pattern
        String? read1_range
        String? read2_range
        String barcode_fastq_pattern
        String barcode_range
        File? barcode_whitelist
        String umi_fastq_pattern
        String umi_range
        File? input_bam
        String? bam_barcode_field
        String? bam_umi_field
        String? bam_abnormal_unmap_flag
        Boolean? skipMateExtension
        Int? mateIdSuffixLen
        Boolean? noExtraction
        Boolean? repseq
        Boolean? outputReadAssignment
        String docker_registry
        String zones
        Int preemptible
        String awsQueueArn
        String backend
    }

    command {
        set -e
        export TMPDIR=/tmp
        export BACKEND=~{backend}
        monitor_script.sh > monitoring.log &
        mkdir -p genome_dir
        tar xf ~{genome_file} -C genome_dir --strip-components 1

        python <<CODE
        import re
        import os
        import sys
        from subprocess import check_call, CalledProcessError, DEVNULL, STDOUT

        Path = os.path.join

        if ('~{input_fastqs_directories}' != '' and '~{input_bam}' != '') or ('~{input_fastqs_directories}' == '' and '~{input_bam}' == ''):
            sys.exit("Please provide either Fastq OR BAM as input (not both)")

        call_args = ['run-trust4', '-f', 'genome_dir/bcrtcr.fa' ,
                     '--ref', 'genome_dir/IMGT+C.fa','-t', '~{num_cpu}', '--od',
                     'trust4_~{sample_id}', '-o', '~{sample_id}']

        if '~{input_bam}' != '':
            if '~{bam_barcode_field}' != '':
                call_args.extend(['--barcode', '~{bam_barcode_field}'])
            if '~{bam_umi_field}' != '':
                call_args.extend(['--UMI', '~{bam_umi_field}'])
            if '~{bam_abnormal_unmap_flag}' != '':
                call_args.extend(['--abnormalUnmapFlag', '~{bam_abnormal_unmap_flag}'])
            call_args.extend(['-b', '~{input_bam}'])
        else:
            assert '~{input_fastqs_directories}' != ''

            fastq_dirs = []
            for i, directory in enumerate('~{input_fastqs_directories}'.split(',')):
                directory = re.sub('/+$', '', directory) # remove trailing slashes
                target = "~{sample_id}_" + str(i)
                try:
                    strato_call_args = ['strato', 'exists', '--backend', '~{backend}', directory + '/~{sample_id}/']
                    print(' '.join(strato_call_args))
                    check_call(strato_call_args, stdout=DEVNULL, stderr=STDOUT)
                    strato_call_args = ['strato', 'sync', '--backend', '~{backend}', '-m', directory + '/~{sample_id}', target]
                    print(' '.join(strato_call_args))
                    check_call(strato_call_args)
                except CalledProcessError:
                    if not os.path.exists(target):
                        os.mkdir(target)
                    strato_call_args = ['strato', 'cp', '--backend', '~{backend}', '-m', directory + '/~{sample_id}*', target + '/']
                    print(' '.join(strato_call_args))
                    check_call(strato_call_args)

                fastq_dirs.append(target)

            if '~{pe_read1_fastq_pattern}' != '' and '~{pe_read2_fastq_pattern}' != '':
                for pe_fastq_dir in fastq_dirs:
                    call_args.extend(['-1', Path(pe_fastq_dir, '~{sample_id}~{pe_read1_fastq_pattern}'),
                                      '-2', Path(pe_fastq_dir, '~{sample_id}~{pe_read2_fastq_pattern}')])
                if '~{read2_range}' != '':
                    call_args.extend(['--read2Range'] + '~{read2_range}'.split(','))
            else:
                for se_fastq_dir in fastq_dirs:
                    call_args.extend(['-u', Path(se_fastq_dir, '~{sample_id}~{se_fastq_pattern}')])

            if '~{read1_range}' != '':
                call_args.extend(['--read1Range'] + '~{read1_range}'.split(','))

            if '~{barcode_fastq_pattern}' != '':
                for barcode_fastq_dir in fastq_dirs:
                    call_args.extend(['--barcode', Path(barcode_fastq_dir, '~{sample_id}~{barcode_fastq_pattern}')])

            if '~{umi_fastq_pattern}' != '':
                for umi_fastq_dir in fastq_dirs:
                    call_args.extend(['--UMI', Path(umi_fastq_dir, '~{sample_id}~{umi_fastq_pattern}')])

        def uncompress_file(compressed_file):
            call_args = ['gunzip', compressed_file]
            print(' '.join(call_args))
            check_call(call_args)
            return(os.path.splitext(compressed_file)[0])

        if '~{barcode_whitelist}' != '':
            whitelist = '~{barcode_whitelist}'
            if whitelist.endswith('.gz'):
                whiltelist = uncompress_file(whitelist)
            call_args.extend(['--barcodeWhitelist', whitelist])
        if '~{skipMateExtension}' != '':
            call_args.append('--skipMateExtension')
        if '~{mateIdSuffixLen}' != '':
            call_args.extend(['--mateIdSuffixLen', '~{mateIdSuffixLen}'])
        if '~{noExtraction}' != '':
            call_args.append('--noExtraction')
        if '~{repseq}' != '':
            call_args.append('--repseq')
        if '~{outputReadAssignment}' != '':
            call_args.append('--outputReadAssignment')

        if '~{barcode_range}' != '':
            call_args.extend(['--barcodeRange'] + '~{barcode_range}'.split(','))
        if '~{umi_range}' != '':
            call_args.extend(['--umiRange'] + '~{umi_range}'.split(','))

        print(' '.join(call_args))
        check_call(call_args)
        CODE

        strato sync --backend '~{backend}' -m 'trust4_~{sample_id}' '~{output_directory}/~{sample_id}/'
    }

    output {
        String output_vdj_directory = "~{output_directory}/~{sample_id}"
        File monitoringLog = "monitoring.log"
    }

    runtime {
        docker: "~{docker_registry}/trust4:~{trust4_version}"
        zones: zones
        memory: memory
        bootDiskSizeGb: 12
        disks: "local-disk ~{disk_space} HDD"
        cpu: num_cpu
        preemptible: preemptible
        queueArn: awsQueueArn
    }
}
