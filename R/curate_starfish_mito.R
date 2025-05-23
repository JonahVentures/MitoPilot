#' Annotation curation for starfish mitogenomes
#'
#' @param annotations_fn Path to the annotations file (csv)
#' @param assembly_fn Path to the assembly file (fasta)
#' @param coverage_fn Path to the coverage file (csv)
#' @param genetic_code Genetic code to use (default = 2)
#' @param out_dir Path to the output directory
#' @param max_blast_hits Maximum number of top BLAST hits to retain (default = 100)
#' @param params Nested list of curation parameters. Can also provided as a
#'   base64 encoded json string.
#'
#' @export
#'
curate_starfish_mito <- function(
    annotations_fn = NULL,
    assembly_fn = NULL,
    coverage_fn = NULL,
    genetic_code = 9,
    out_dir = NULL,
    max_blast_hits = 100,
    params = NULL) {
  # Prepare environment ----

  ## load annotations ----
  annotations <- tryCatch(
    read.csv(annotations_fn),
    error = function(e) {
      stop("Invalid annotations.")
    }
  )
  annotations <- annotations |>
    add_cols(
      list(
        notes = NA_character_,
        warnings = NA_character_,
        refHits = NA_character_
      )
    )

  ## load assembly ----
  assembly <- tryCatch(
    Biostrings::readDNAStringSet(assembly_fn),
    error = function(e) {
      stop("Invalid assembly.")
    }
  )
  contig_key <- names(assembly) |>
    {
      \(x) setNames(x, stringr::str_extract(x, "^\\S+"))
    }()

  ## load coverage ----
  if (!is.null(coverage_fn)) {
    coverage <- tryCatch(
      read.csv(coverage_fn),
      error = function(e) {
        stop("Invalid coverage.")
      }
    )
  } else {
    coverage <- NULL
  }

  ## Load params to env ----
  if (!is.null(params) && !is.list(params)) {
    params <- tryCatch(
      jsonlite::fromJSON(rawToChar(base64enc::base64decode(params))),
      error = function(e) {
        stop("Invalid JSON string.")
      }
    )
  }
  list2env(params, envir = environment())

  ## Prepare rules ----
  rules <- rules |>
    purrr::map(~ modifyList(default_rules[[.x$type]] %||% list(), .x))

  ## Set genetic code ----
  genetic_code <- tryCatch(
    Biostrings::getGeneticCode(as.character(genetic_code)),
    error = function(e) {
      stop("Invalid genetic code.")
    }
  )

  # rRNA ----
  ## enforce + strand ----
  rRNA_rev <- annotations |>
    dplyr::filter(type == "rRNA") |>
    dplyr::filter(all(direction == "-"), .by = "contig") |>
    dplyr::pull(contig) |>
    unique()
  for (seqid in rRNA_rev) {
    wdth <- assembly[contig_key[seqid]]@ranges@width
    annotations_updated <- annotations |>
      dplyr::filter(contig == !!seqid) |>
      dplyr::mutate(
        pos1_old = pos1,
        pos2_old = pos2,
        pos1 = wdth - pos2_old + 1,
        pos2 = wdth - pos1_old + 1,
        direction = dplyr::case_match(
          direction, "+" ~ "-", "-" ~ "+"
        )
      ) |>
      dplyr::select(-pos1_old, -pos2_old)

    annotations <- annotations |>
      dplyr::filter(contig != seqid) |>
      dplyr::bind_rows(
        annotations_updated
      ) |>
      dplyr::arrange(contig, pos1)

    assembly[contig_key[seqid]] <- assembly[contig_key[seqid]] |>
      Biostrings::reverseComplement()

    if (!is.null(coverage)) {
      coverage_flip <- coverage |>
        dplyr::filter(SeqId == !!seqid) |>
        dplyr::arrange(desc(Position)) |>
        dplyr::mutate(
          Position = dplyr::row_number(),
          Call = as.character(assembly) |> stringr::str_split("") |> unlist()
        )
      coverage <- dplyr::bind_rows(
        coverage |> dplyr::filter(SeqId != seqid),
        coverage_flip
      )
    }
  }

  ## apply punctuation model ----
  gene_idx <- which(annotations$type == "rRNA")
  for (idx in gene_idx) {
    # Apply tRNA punctuation model
    before <- annotations[idx - 1, ] |>
      dplyr::filter(type == "tRNA" & contig == annotations$contig[idx])
    if (nrow(before) == 1) {
      if (annotations$pos1[idx] - before$pos2 != 1) {
        pos1_new <- before$pos2 + 1
        if (annotations$pos2[idx] - pos1_new + 1 <= rules[[annotations$gene[idx]]][["max_len"]]) {
          pos1_change <- pos1_new - annotations$pos1[idx]
          annotations$pos1[idx] <- pos1_new
          annotations$notes[idx] <- semicolon_paste(
            annotations$notes[idx],
            stringr::str_glue("Applied punctuation model- moved pos1 by {pos1_change} bp")
          )
        }
      }
    }
    after <- annotations[idx + 1, ] |>
      dplyr::filter(type == "tRNA" & contig == annotations$contig[idx])
    if (nrow(after) == 1) {
      if (after$pos1 - annotations$pos2[idx] != 1) {
        pos2_new <- after$pos1 - 1
        if (pos2_new - annotations$pos1[idx] + 1 <= rules[[annotations$gene[idx]]][["max_len"]]) {
          pos2_change <- pos2_new - annotations$pos2[idx]
          annotations$pos2[idx] <- pos2_new
          annotations$notes[idx] <- semicolon_paste(
            annotations$notes[idx],
            stringr::str_glue("Applied punctuation model - moved pos2 by {pos2_change} bp")
          )
        }
      }
    }
    annotations$length[idx] <- 1 + abs(annotations$pos2[idx] - annotations$pos1[idx])
  }

  # PCGs ----
  ## Get top ref hits for each PCG ----
  annotations$refHits <- annotations |>
    dplyr::select(type, gene, translation) |>
    purrr::pmap(function(type, gene, translation) {
      if (type != "PCG") {
        return(NA)
      }

      ## Gene ref database ----
      ref_db <- ref_dbs[[gene]] %||% ref_dbs[["default"]] |>
        stringr::str_glue()

      out <- get_top_hits(ref_db, translation,
                          max_blast_hits) |>
        json_string()
      out %||% '{}'
    })

  ## Curate against top hits ----
  annotations <- purrr::pmap_dfr(annotations, function(...) {
    cur <- list(...)
    if (cur$type != "PCG") {
      return(cur)
    }
    list2env(cur, envir = environment())

    # Stop if no hits above threshold
    refHits <- json_parse(refHits[[1]], TRUE)
    if (nrow(refHits) == 0L || !any(refHits$similarity >= hit_threshold)) {
      return(cur)
    }

    # start / stop codon options
    start_opts <- rules[[gene]][["start_codons"]]
    stop_opts <- rules[[gene]][["stop_codons"]] |>
      {
        \(x) x[order(nchar(x), decreasing = T)]
      }()

    ## Fix TRUNCATION ----
    ### START ----
    if (refHits$gap_leading[1] != 0 && (sum(refHits$gap_leading > 0L) / nrow(refHits)) > 0.5) {
      gaps_target <- max(refHits$gap_leading)
      if (direction == "+") {
        while (gaps_target > 0) {
          pos1_new <- pos1 - (3 * gaps_target)
          if (pos1_new <= 0) {
            gaps_target <- gaps_target - 1
            next
          }
          new_start_codon <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1_new,
            pos1_new + 2
          ) |>
            as.character()
          if (!new_start_codon %in% start_opts) {
            gaps_target <- gaps_target - 1
            next
          }
          cur$notes <- semicolon_paste(cur$notes, stringr::str_glue("extending start {pos1 - pos1_new} bp"))
          cur$pos1 <- pos1 <- pos1_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$start_codon <- start_codon <- new_start_codon
          cur$translation <- translation <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1,
            pos2 - nchar(stop_codon)
          ) |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation,
            max_blast_hits
          )
          break
        }
      }
      if (direction == "-") {
        while (gaps_target > 0) {
          pos2_new <- pos2 + (3 * gaps_target)
          if (pos2_new >= assembly[contig_key[contig]]@ranges@width) {
            gaps_target <- gaps_target - 1
            next
          }
          new_start_codon <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos2_new - 2,
            pos2_new
          ) |>
            Biostrings::reverseComplement() |>
            as.character()
          if (!new_start_codon %in% start_opts) {
            gaps_target <- gaps_target - 1
            next
          }
          cur$notes <- notes <- semicolon_paste(notes, stringr::str_glue("extending start {pos2_new - pos2} bp"))
          cur$pos2 <- pos2 <- pos2_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$start_codon <- start_codon <- new_start_codon
          cur$translation <- translation <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1 + nchar(stop_codon),
            pos2
          ) |>
            Biostrings::reverseComplement() |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation,
            max_blast_hits
          )
          break
        }
      }
    }

    ### STOP ----
    if (refHits$gap_trailing[1] != 0 && (sum(refHits$gap_trailing > 0L) / nrow(refHits)) > 0.5) {
      gaps_target <- max(refHits$gap_trailing)
      if (direction == "+") {
        while (gaps_target > 0) {
          pos2_new <- pos2 - nchar(stop_codon) + 3 + (3 * gaps_target)
          if ((pos2_new + 1) > assembly[contig_key[contig]]@ranges@width) {
            gaps_target <- gaps_target - 1
            next
          }
          new_stop_codon <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos2_new - 2,
            min(pos2_new, assembly[contig_key[contig]]@ranges@width)
          ) |>
            as.character()
          while (nchar(new_stop_codon) > 0 && !new_stop_codon %in% stop_opts) {
            new_stop_codon <- stringr::str_remove(new_stop_codon, ".$")
            pos2_new <- pos2_new - 1
          }
          if (nchar(new_stop_codon) == 0L) {
            gaps_target <- gaps_target - 1
            next
          }
          cur$notes <- notes <- semicolon_paste(
            notes,
            stringr::str_glue("extending end {abs(pos2_new - pos2)} bp")
          )
          cur$pos2 <- pos2 <- pos2_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$stop_codon <- stop_codon <- new_stop_codon
          cur$translation <- translation <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1,
            pos2 - nchar(stop_codon)
          ) |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation,
            max_blast_hits
          )
          break
        }
      }
      if (direction == "-") {
        while (gaps_target > 0) {
          pos1_new <- pos1 + nchar(stop_codon) - 3 - (3 * gaps_target)
          if ((pos1_new + 2) < 1) {
            gaps_target <- gaps_target - 1
            next
          }
          new_stop_codon <- Biostrings::subseq(
            assembly[contig_key[contig]],
            max(pos1_new, 1),
            pos1_new + 2
          ) |>
            Biostrings::reverseComplement() |>
            as.character()
          if(nchar(new_stop_codon) < 3L) {
            pos1_new <- pos1_new + (3 - nchar(new_stop_codon))
          }
          while (nchar(new_stop_codon) > 0 && !new_stop_codon %in% stop_opts) {
            new_stop_codon <- stringr::str_remove(new_stop_codon, ".$")
            pos1_new <- pos1_new + 1
          }
          if (nchar(new_stop_codon) == 0L) {
            gaps_target <- gaps_target - 1
            next
          }
          cur$notes <- notes <- semicolon_paste(
            notes,
            stringr::str_glue("extending end {abs(pos1_new - pos1)} bp")
          )
          cur$pos1 <- pos1 <- pos1_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$stop_codon <- stop_codon <- new_stop_codon
          cur$translation <- translation <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1 + nchar(stop_codon),
            pos2
          ) |>
            Biostrings::reverseComplement() |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation,
            max_blast_hits
          )
          break
        }
      }
    }

    ## Fix OVER-EXTENSION ----
    ### START ----
    if (refHits$gap_leading[1] != 0 && (sum(refHits$gap_leading < 0L) / nrow(refHits)) > 0.5) {
      if (direction == "+") {
        alt_starts <- Biostrings::subseq(
          assembly[contig_key[contig]],
          pos1 + 3,
          pos1 + 3 + (3 * max(abs(refHits$gap_leading[refHits$gap_leading < 0]))) - 1
        ) |>
          as.character() |>
          stringr::str_extract_all(".{1,3}") |>
          unlist() |>
          purrr::set_names() |>
          purrr::map(~ {
            .x %in% start_opts
          })
        alt_idx <- 1
        while (alt_idx <= length(alt_starts)) {
          if (!alt_starts[[alt_idx]]) {
            alt_idx <- alt_idx + 1
            next
          }
          pos1_new <- pos1 + (3 * alt_idx)
          translation_new <- Biostrings::subseq(assembly[contig_key[contig]], pos1_new, pos2 - nchar(stop_codon)) |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits_new <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation_new,
            max_blast_hits
          )
          if (refHits_new$gap_leading[1] != 0 && (sum(refHits_new$gap_leading < 0L) / nrow(refHits_new)) > 0.5) {
            alt_idx <- alt_idx + 1
            next
          }
          cur$notes <- notes <- semicolon_paste(
            notes,
            stringr::str_glue("trimming start {abs(pos1_new - pos1)} bp")
          )
          cur$pos1 <- pos1 <- pos1_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$start_codon <- start_codon <- names(alt_starts)[alt_idx]
          cur$translation <- translation <- translation_new
          refHits <- refHits_new
          break
        }
      }
      if (direction == "-") {
        alt_starts <- Biostrings::subseq(
          assembly[contig_key[contig]],
          pos2 - 3 - (3 * max(abs(refHits$gap_leading[refHits$gap_leading < 0]))) + 1,
          pos2 - 3
        ) |>
          Biostrings::reverseComplement() |>
          as.character() |>
          stringr::str_extract_all(".{1,3}") |>
          unlist() |>
          purrr::set_names() |>
          purrr::map(~ {
            .x %in% start_opts
          })
        alt_idx <- 1
        while (alt_idx <= length(alt_starts)) {
          if (!alt_starts[[alt_idx]]) {
            alt_idx <- alt_idx + 1
            next
          }
          pos2_new <- pos2 - (3 * alt_idx)
          translation_new <- Biostrings::subseq(assembly[contig_key[contig]], pos1 + nchar(stop_codon), pos2_new) |>
            Biostrings::reverseComplement() |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits_new <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation_new,
            max_blast_hits
          )
          if (refHits_new$gap_leading[1] != 0 && (sum(refHits_new$gap_leading < 0L) / nrow(refHits_new)) > 0.5) {
            alt_idx <- alt_idx + 1
            next
          }
          cur$notes <- notes <- semicolon_paste(
            notes,
            stringr::str_glue("trimming start {abs(pos2_new - pos2)} bp")
          )
          cur$pos2 <- pos2 <- pos2_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$start_codon <- start_codon <- new_start_codon
          cur$translation <- translation <- translation_new
          refHits <- refHits_new
          break
        }
      }
    }

    ### STOP ----
    if (refHits$gap_trailing[1] != 0 && (sum(refHits$gap_trailing < 0L) / nrow(refHits)) > 0.5) {
      if (direction == "+") {
        alt_stops <- Biostrings::subseq(
          assembly[contig_key[contig]],
          pos2 - nchar(stop_codon) - (3 * max(abs(refHits$gap_trailing[refHits$gap_trailing < 0]))) + 1,
          pos2 - nchar(stop_codon)
        ) |>
          as.character() |>
          stringr::str_extract_all(".{1,3}") |>
          unlist() |>
          purrr::map(~ {
            s <- stringr::str_extract(.x, paste0("^", stop_opts)) |>
              na.omit()
            s[1] |> unlist()
          }) |>
          rev()
        alt_idx <- 1
        while (alt_idx <= length(alt_stops)) {
          if (is.na(alt_stops[[alt_idx]])) {
            alt_idx <- alt_idx + 1
            next
          }
          pos2_new <- pos2 - nchar(stop_codon) + 3 - (3 * alt_idx) - (3 - nchar(alt_stops[[alt_idx]]))
          translation_new <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1,
            pos2_new - nchar(alt_stops[[alt_idx]])
          ) |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits_new <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation_new,
            max_blast_hits
          )
          if (refHits_new$gap_trailing[1] != 0 && (sum(refHits_new$gap_trailing < 0L) / nrow(refHits_new)) > 0.5) {
            alt_idx <- alt_idx + 1
            next
          }
          cur$notes <- notes <- semicolon_paste(
            notes,
            stringr::str_glue("trimming end {abs(pos2_new - pos2)} bp")
          )
          cur$pos2 <- pos2 <- pos2_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$stop_codon <- stop_codon <- alt_stops[[alt_idx]]
          cur$translation <- translation <- translation_new
          refHits <- refHits_new
          break
        }
      }
      if (direction == "-") {
        alt_stops <- Biostrings::subseq(
          assembly[contig_key[contig]],
          pos1 + nchar(stop_codon),
          pos1 + nchar(stop_codon) + (3 * max(abs(refHits$gap_trailing[refHits$gap_trailing < 0]))) - 1
        ) |>
          Biostrings::reverseComplement() |>
          as.character() |>
          stringr::str_extract_all(".{1,3}") |>
          unlist() |>
          purrr::map(~ {
            s <- stringr::str_extract(.x, paste0("^", stop_opts)) |>
              na.omit()
            s[1] |> unlist()
          }) |>
          rev()
        alt_idx <- 1
        while (alt_idx <= length(alt_stops)) {
          if (is.na(alt_stops[[alt_idx]])) {
            alt_idx <- alt_idx + 1
            next
          }
          pos1_new <- pos1 + nchar(stop_codon) - 3 + (3 * alt_idx) + (3 - nchar(alt_stops[[alt_idx]]))
          translation_new <- Biostrings::subseq(
            assembly[contig_key[contig]],
            pos1 + nchar(alt_stops[[alt_idx]]),
            pos2
          ) |>
            Biostrings::reverseComplement() |>
            Biostrings::translate(genetic.code = genetic_code) |>
            as.character()
          refHits_new <- get_top_hits(
            stringr::str_glue(ref_dbs[[gene]] %||% ref_dbs[["default"]]),
            translation_new,
            max_blast_hits
          )
          if (refHits_new$gap_trailing[1] != 0 && (sum(refHits_new$gap_trailing < 0L) / nrow(refHits_new)) > 0.5) {
            alt_idx <- alt_idx + 1
            next
          }
          cur$notes <- notes <- semicolon_paste(
            notes,
            stringr::str_glue("trimming end {abs(pos1_new - pos1)} bp")
          )
          cur$pos1 <- pos1 <- pos1_new
          cur$length <- length <- abs(pos2 - pos1) + 1
          cur$stop_codon <- stop_codon <- alt_stops[[alt_idx]]
          cur$translation <- translation <- translation_new
          refHits <- refHits_new
          break
        }
      }
    }

    cur$refHits <- json_string(refHits)

    return(cur)
  })

  ## Stop codon trimming ----
  for (idx in seq_len(nrow(annotations))) {
    if (annotations$type[idx] != "PCG") next
    gene <- annotations$gene[idx]
    overlap_rules <- rules[[gene]][["overlap"]]
    stop_opts <- rules[[gene]][["stop_codons"]]
    while (annotations$direction[idx] == "+") {
      if (idx == nrow(annotations)) break
      if (overlap_rules$stop) break
      codon_positions <- (annotations$pos2[idx] - nchar(annotations$stop_codon[idx]) + 1):annotations$pos2[idx]
      overlaps <- annotations[(idx + 1):nrow(annotations), ] |>
        dplyr::filter(pos1 %in% codon_positions) |>
        dplyr::filter(direction == annotations$direction[idx])
      if (nrow(overlaps) != 1L) break
      overlap <- sum(overlaps$pos1:overlaps$pos2 %in% codon_positions)
      new_stop <- stringr::str_sub(annotations$stop_codon[idx], 1, nchar(annotations$stop_codon[idx]) - overlap)
      if (nchar(new_stop) < 1) break
      if (!new_stop %in% stop_opts) break
      annotations$stop_codon[idx] <- new_stop
      annotations$pos2[idx] <- annotations$pos2[idx] - overlap
      annotations$length[idx] <- annotations$length[idx] - overlap
      annotations$notes[idx] <- semicolon_paste(
        annotations$notes[idx],
        stringr::str_glue("stop codon trimmed  by {overlap} bp")
      )
      break
    }
    while (annotations$direction[idx] == "-") {
      if (idx == 1) break
      if (overlap_rules$stop) break
      codon_positions <- annotations$pos1[idx]:(annotations$pos1[idx] + nchar(annotations$stop_codon[idx]) - 1)
      overlaps <- annotations[1:(idx - 1), ] |>
        dplyr::filter(pos2 %in% codon_positions) |>
        dplyr::filter(direction == annotations$direction[idx])
      if (nrow(overlaps) != 1L) break
      overlap <- sum(overlaps$pos1:overlaps$pos2 %in% codon_positions)
      new_stop <- stringr::str_sub(annotations$stop_codon[idx], 1, nchar(annotations$stop_codon[idx]) - overlap)
      if (nchar(new_stop) < 1) break
      if (!new_stop %in% stop_opts) break
      annotations$stop_codon[idx] <- new_stop
      annotations$pos1[idx] <- annotations$pos1[idx] + overlap
      annotations$length[idx] <- annotations$length[idx] - overlap
      annotations$notes[idx] <- semicolon_paste(
        annotations$notes[idx],
        stringr::str_glue("stop codon trimmed by {overlap} bp")
      )
      break
    }
  }

  # End trimming ----
  # Remove un-annotated regions at the beginning or end of linear contigs
  purrr::iwalk(contig_key, ~ {
    # Skip circular contigs
    if (stringr::str_detect(.x, "circular")) {
      return()
    }
    ## Check beginning ----
    min_ann <- annotations |>
      dplyr::filter(contig == .y) |>
      dplyr::mutate(min_ann = pmin(pos1, pos2)) |>
      dplyr::pull(min_ann) |>
      min()
    if (min_ann > 1) {
      assembly[.x] <<- Biostrings::subseq(assembly[.x], min_ann, -1)
      annotations <<- annotations |>
        dplyr::mutate(
          pos1 = dplyr::case_when(
            contig == .y ~ pos1 - min_ann + 1,
            .default = pos1
          ),
          pos2 = dplyr::case_when(
            contig == .y ~ pos2 - min_ann + 1,
            .default = pos2
          )
        )
      coverage <<- coverage |>
        dplyr::mutate(
          Position = dplyr::case_when(
            SeqId == .y ~ Position - min_ann + 1,
            .default = Position
          )
        ) |>
        dplyr::filter(Position > 0)
    }
    ## Check end ----
    max_ann <- annotations |>
      dplyr::filter(contig == .y) |>
      dplyr::mutate(max_ann = pmax(pos1, pos2)) |>
      dplyr::pull(max_ann) |>
      max()
    if (max_ann < assembly[.x]@ranges@width) {
      assembly[.x] <<- Biostrings::subseq(assembly[.x], 1, max_ann)
      coverage <<- coverage |>
        dplyr::filter(
          SeqId != .y | Position <= max_ann
        )
    }
  })

  # Outputs ----
  readr::write_csv(
    annotations,
    file.path(out_dir, basename(annotations_fn)),
    na = ""
  )
  Biostrings::writeXStringSet(assembly, file.path(out_dir, basename(assembly_fn)))
  if (!is.null(coverage_fn)) {
    readr::write_csv(coverage, file.path(out_dir, basename(coverage_fn)), quote = "none", na = "")
  }

  return(invisible(annotations))
}
