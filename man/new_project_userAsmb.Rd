% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/init_project_userAsmb.R
\name{new_project_userAsmb}
\alias{new_project_userAsmb}
\title{Initialize new MitoPilot Project with user-provided mitogenome assemblies}
\usage{
new_project_userAsmb(
  path = ".",
  mapping_fn = NULL,
  mapping_id = "ID",
  data_path = NULL,
  assembly_path = "NA",
  genetic_code = 2,
  executor = c("local", "awsbatch", "NMNH_Hydra", "NOAA_SEDNA"),
  container = paste0("macguigand/mitopilot:", utils::packageVersion("MitoPilot")),
  config = NULL,
  Rproj = TRUE,
  force = FALSE,
  ...
)
}
\arguments{
\item{path}{Path to the project directory (default = current working
directory)}

\item{mapping_fn}{Path to a mapping file. Should be a csv that minimally
includes an `ID` column with a unique identifier for each sample, a `Taxon`
column containing taxonomic information for each sample, and columns
`R1` and `R2` specifying the names of the raw paired read inputs, an `Assembly` column
containing names of mitogenome assembly fasta files (one contig/scaffold sequence per sample),
and a `Topology` column containing information about the assembly topology
("circular" or "linear") May include additional columns with other sample metadata.}

\item{mapping_id}{The name of the column in the mapping file that contains
the unique sample identifiers (default = "ID").}

\item{data_path}{Path to the directory where the raw data is located. Can be
a AWS s3 bucket even if not using AWS for pipeline execution.}

\item{assembly_path}{Path to the directory where the mitogenome assemblies are located. Can be
a AWS s3 bucket even if not using AWS for pipeline execution.}

\item{genetic_code}{Translation table for your organisms. See NCBI website
for more info https://www.ncbi.nlm.nih.gov/Taxonomy/Utils/wprintgc.cgi}

\item{executor}{The executor to use for running the nextflow pipeline. Must
be one of "local" (default) or "awsbatch", "NMNH_Hydra", or "NOAA_SEDNA".}

\item{container}{The docker container to use for pipeline execution.}

\item{config}{(optional) provide a path to an existing custom nextflow config
file. If not provided a config file template will be created based on the
specified executor.}

\item{Rproj}{(logical) Initialize and open an RStudio project in the project
directory (default = TRUE). This option has no effect if not running
interactively in RStudio.}

\item{force}{(logical) Force recreating of existing project database and
config files (default = FALSE).}

\item{...}{Additional arguments passed as default processing parameters to
`new_db()`}
}
\description{
Initialize new MitoPilot Project with user-provided mitogenome assemblies
}
