#' Initialize new MitoPilot Project
#'
#' @param path Path to the project directory (default = current working
#'   directory)
#' @param mapping_fn Path to a mapping file. Should be a csv that minimally
#'   includes an `ID` column with a unique identifier for each sample, a `Taxon`
#'   column containing taxonomic information for each sample, and columns
#'   `R1` and `R2` specifying the names of the raw paired read inputs. May include
#'   additional columns with other sample metadata.
#' @param mapping_id The name of the column in the mapping file that contains
#'   the unique sample identifiers (default = "ID").
#' @param data_path Path to the directory where the raw data is located. Can be
#'   a AWS s3 bucket even if not using AWS for pipeline execution..
#' @param min_depth Minimum sequencing depth after pre-processing to proceed
#'   with assembly (default: 2000000)
#' @param genetic_code Translation table for your organisms. See NCBI website
#'   for more info https://www.ncbi.nlm.nih.gov/Taxonomy/Utils/wprintgc.cgi
#' @param executor The executor to use for running the nextflow pipeline. Must
#'   be one of "local" (default) or "awsbatch", "NMNH_Hydra", or "NOAA_SEDNA".
#' @param Rproj (logical) Initialize and open an RStudio project in the project
#'   directory (default = TRUE). This option has no effect if not running
#'   interactively in RStudio.
#' @param custom_seeds_db Full path to custom seeds database for GetOrganelle
#' @param custom_labels_db Full path to custom labels database for GetOrganelle
#' @param force (logical) Force recreating of existing project database and
#'   config files (default = FALSE).
#' @param config (optional) provide a path to an existing custom nextflow config
#'   file. If not provided a config file template will be created based on the
#'   specified executor.
#' @param container The docker container to use for pipeline execution.
#' @param ... Additional arguments passed as default processing parameters to
#'   `new_db()`
#'
#' @export
#'
new_project <- function(
    path = ".",
    mapping_fn = NULL,
    mapping_id = "ID",
    data_path = NULL,
    min_depth = 2000000,
    genetic_code = 2,
    executor = c("local", "awsbatch", "NMNH_Hydra", "NOAA_SEDNA"),
    container = paste0("macguigand/mitopilot:", utils::packageVersion("MitoPilot")),
    custom_seeds_db = NULL,
    custom_labels_db = NULL,
    config = NULL,
    Rproj = TRUE,
    force = FALSE,
    ...) {

  # Create directory if it doesn't exist ----
  if (!dir.exists(path)) {
    message("Creating project directory: ", path)
    dir.create(path, recursive = TRUE)
  }
  path <- normalizePath(path)

  # Normalize data path (if provided)----
  if(length(data_path)==1){
    data_path <- normalizePath(data_path)
  }

  # Read mapping file ----
  if (is.null(mapping_fn) || !file.exists(mapping_fn)) {
    stop("A mapping file is required to initialize a new project")
  }
  mapping_out <- file.path(path, "mapping.csv")
  if (!identical(mapping_fn, mapping_out)) {
    file.copy(mapping_fn, mapping_out)
  }

  # Validate executor ----
  executor <- executor[1]
  if (is.null(executor) || executor %nin% c("local", "awsbatch", "NMNH_Hydra", "NOAA_SEDNA")) {
    stop("Invalid executor.")
  }

  # Create directory if it doesn't exist ----
  if (!dir.exists(path)) {
    message("Creating project directory: ", path)
    dir.create(path, recursive = TRUE)
  }

  path <- normalizePath(path)

  # Initialize RStudio Project ----
  # (optional & only if running form RStudio)
  if (Rproj && !isFALSE(Sys.getenv("RSTUDIO", FALSE))) {
    if (isFALSE(requireNamespace("rstudioapi", quietly = TRUE))) {
      message("package 'rstudioapi' not available. Skipping RStudio project initialization.")
    } else {
      rstudioapi::initializeProject(path)
      on.exit(rstudioapi::openProject(path, newSession = TRUE))
    }
  }

  # Initialize sqlite db ----
  db <- file.path(path, ".sqlite")
  if (file.exists(db) && !force) {
    message("Database already exists. Use force = TRUE to overwrite (old data will be lost).")
    return()
  }
  if (file.exists(db) && force) {
    message("Overwriting existing database")
    file.remove(db)
  }

  new_db(
    db_path = file.path(path, ".sqlite"),
    genetic_code = genetic_code,
    mapping_fn = mapping_out,
    mapping_id = mapping_id,
    seeds_db = custom_seeds_db,
    labels_db = custom_labels_db,
    ...
  )


  # Config file ----
  config <- config %||% app_sys(paste0("config.", executor))
  if (!file.exists(config)) {
    stop("Config file not found.")
    return()
  }
  readLines(config) |>
    stringr::str_replace("<<CONTAINER_ID>>", container %||% "<<CONTAINER_ID>>") |>
    stringr::str_replace("<<RAW_DIR>>", data_path %||% "<<RAW_DIR>>") |>
    stringr::str_replace("<<ASMB_DIR>>", "NA" %||% "<<ASMB_DIR>>") |>
    stringr::str_replace("<<MIN_DEPTH>>", format(min_depth %||% "<<MIN_DEPTH>>", scientific = F)) |>
    stringr::str_replace("<<GENETIC_CODE>>", format(genetic_code %||% "<<GENETIC_CODE>>", scientific = F)) |>
    writeLines(file.path(path, ".config"))

  message("Project initialized successfully.")
  message("Please open and review the .config file to ensure all required options are specified.")
}
