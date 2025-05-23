#' Populate export table
#'
#' @param db database connection
#' @param session reactive session
#'
#' @noRd
fetch_export_data <- function(session = getDefaultReactiveDomain()) {
  db <- session$userData$con

  samples <- dplyr::tbl(db, "samples") |>
    dplyr::select(-dplyr::any_of("topology"))

  dplyr::tbl(db, "assemble") |>
    dplyr::filter(assemble_lock == 1) |>
    dplyr::select(ID) |>
    dplyr::left_join(dplyr::tbl(db, "annotate"), by = "ID") |>
    dplyr::filter(annotate_lock == 1) |>
    dplyr::select(ID, curate_opts, topology, structure, PCGCount, tRNACount, rRNACount, missing, extra, warnings) |>
    dplyr::left_join(samples, by = "ID") |>
    dplyr::select(-R1, -R2) |>
    dplyr::relocate(Taxon, .after = ID) |>
    dplyr::collect() |>
    dplyr::mutate(
      structure = stringr::str_replace_all(structure, "trn[A-Z]", "\u2022"),
      export_group = as.character(export_group)
    )
}
