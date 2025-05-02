process assemble {

    // debug true

    executor params.assemble.executor
    container params.assemble.container

    publishDir "$launchDir/${params.publishDir}", overwrite: true, mode: 'copy'

    errorStrategy { task.exitStatus in 137..140 ? 'retry' : 'finish' }
    maxRetries { params.assemble.maxRetries }
    // cpus { opts.cpus }
    // memory { opts.memory.GB * task.attempt }

    tag "${id}"

    input:
    tuple val(id), val(opts_id), path(reads), val(opts), path(dbs), path(mf_db), val(genetic_code)

    output:
    tuple val("${id}"),
        path("${id}/assemble/${opts_id}/${id}_assembly_*.fasta"),             // Assemblies Output
        path("${id}/assemble/${opts_id}/${id}_reads.tar.gz"),                 // Trimmed Reads Out
        path("${id}/assemble/${opts_id}/${id}_summary.txt"),                  // getOrganelle summary
        val("${opts_id}"),                                                    // options id
        path("${id}/assemble/${opts_id}/assembler.log.txt"),                     // getOrganelle log
        path("${id}/assemble/${opts_id}/NF_work_dir_assemble.txt"),                     // Nextflow working directory, for troubleshooting
        val("${opts.assembler}")                                                         // assembler

    shell:
    workingDir = "${id}/assemble"
    outDir = "${workingDir}/${opts_id}"

    '''
    mkdir -p !{workingDir}
    if [ !{opts.assembler} == "GetOrganelle" ]; then
        mkdir -p !{workingDir}
        get_organelle_from_reads.py \
            -1 !{reads[0]} \
            -2 !{reads[1]} \
            -o !{workingDir}/ --overwrite \
            -s !{dbs[0]} \
            --genes !{dbs[1]} \
            -t !{task.cpus} \
            !{opts.getOrganelle}
        mkdir -p !{outDir}
        ### LOGS ####
        cp !{workingDir}/get_org.log.txt !{outDir}/assembler.log.txt
        echo "!{opts.getOrganelle}" > !{outDir}/opts.txt
        summary_get_organelle_output.py !{workingDir} -o !{outDir}/!{id}_summary.txt
        ### work dir info for troubleshooting ####
        echo "Nextflow assemble working directory:" > !{outDir}/NF_work_dir_assemble.txt
        echo "$PWD" >> !{outDir}/NF_work_dir_assemble.txt
        ### ARCHIVE READS ###
        tar -czvf !{outDir}/!{id}_reads.tar.gz !{workingDir}/extended*.fq
        ### FORMAT ASSEMBLIES ###
        export topology=$(awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($i=="circular"){col=i;break;}}} NR>1{if($col=="yes") print "circular"; else if($col=="no") print "linear";}' !{outDir}/!{id}_summary.txt)
        shopt -s nullglob
        files=(!{workingDir}/*.fasta)
        if [ ${#files[@]} -eq 0 ]; then
            echo ">No assembly found" > !{outDir}/!{id}_assembly_0.fasta
        else
            parallel -j !{task.cpus} 'awk -v topo=$topology "/^>/ {print \\">!{id}.{#}.\\" ++count[\\">\\"] \\" \\" topo} !/^>/ {print}" {} > !{outDir}/!{id}_assembly_{#}.fasta' ::: "${files[@]}"
        fi
    elif [ !{opts.assembler} == "MitoFinder" ]; then      
        cd !{workingDir}
        # run MitoFinder
        mitofinder \
            !{opts.mitofinder} \
            --ignore \
            -j !{id} \
            -1 ../../!{reads[0]} \
            -2 ../../!{reads[1]} \
            -r ../../!{mf_db} \
            -o !{genetic_code.intValue()} \
            -p !{task.cpus} \
            -m !{task.memory.toGiga()} 
        cd ../..
        mkdir -p !{outDir}
        ### LOGS ####
        cp !{workingDir}/*_MitoFinder.log !{outDir}/assembler.log.txt
        echo "!{opts.mitofinder}" > !{outDir}/opts.txt
        
        # TO DO - generate summary file for mitofinder
        #summary_get_organelle_output.py !{workingDir} -o !{outDir}/!{id}_summary.txt
        touch !{outDir}/!{id}_summary.txt # temporary placeholder summary file

        ### ARCHIVE READS ###
        tar -czvf !{outDir}/!{id}_reads.tar.gz *.fastq.gz

        ### work dir info for troubleshooting ####
        echo "Nextflow assemble working directory:" > !{outDir}/NF_work_dir_assemble.txt
        echo "$PWD" >> !{outDir}/NF_work_dir_assemble.txt
        
        ### FORMAT ASSEMBLIES ###
        export topology=$(awk '/Circularization:/ {print ($2 == "Yes" ? "circular" : "linear")}' !{workingDir}/!{id}/*_Final_Results/!{id}.infos)   
        shopt -s nullglob
        files=(!{workingDir}/!{id}/*_Final_Results/*_mtDNA_contig.fasta)
        if [ ${#files[@]} -eq 0 ]; then
            echo ">No assembly found" > !{outDir}/!{id}_assembly_0.fasta
        else
            parallel -j !{task.cpus} 'awk -v topo=$topology "/^>/ {print \\">!{id}.{#}.\\" ++count[\\">\\"] \\" \\" topo} !/^>/ {print}" {} > !{outDir}/!{id}_assembly_{#}.fasta' ::: "${files[@]}"
        fi
    fi

    '''
}
