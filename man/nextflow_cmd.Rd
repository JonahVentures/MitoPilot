% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/update_mitopilot.R
\name{nextflow_cmd}
\alias{nextflow_cmd}
\title{Generate Nextflow command to run pipline}
\usage{
nextflow_cmd(
  workflow = c("assemble", "annotate"),
  path = NULL,
  source = app_sys("nextflow"),
  userAsmbs = FALSE
)
}
\arguments{
\item{workflow}{Which module to update (default = c("assemble",
"annotate"))}

\item{path}{MitoPilot project directory}

\item{source}{Nextflow script source. By default, this will be in the
`nextflow/` subdirectory of the package installation.}

\item{userAsmbs}{User supplied assemblies, TRUE/FALSE? (default = FALSE)}
}
\description{
Generate Nextflow command to run pipline
}
