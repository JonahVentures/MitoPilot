#' Open The MitoPilot GUI
#'
#' @export
#'
MitoPilot <- function() {
  run_app()
}

#' Run the Shiny Application
#'
#' @param ... arguments to pass to golem_opts.
#' See `?golem::get_golem_options` for more details.
#' @inheritParams shiny::shinyApp
#'
#' @export
#' @importFrom shiny shinyApp
#' @importFrom golem with_golem_options
run_app <- function(
    onStart = NULL,
    options = list(shiny.launch.browser = T),
    enableBookmarking = NULL,
    uiPattern = "/",
    ...) {

  # check if user has provided an assembly directory
  conf <- tryCatch({
    readLines(".config")
  }, error = function(e) {
    stop("Error reading .config file: ", e$message)
  })
  asmbDir <- tryCatch({
    stringr::str_trim(stringr::str_split(stringr::str_split(conf[grep("asmbDir", conf)], "=")[[1]][2], "'")[[1]][2])
  }, error = function(e) {
    stop("Errpr, .config file missing \"asmbDir\": ", e$message)
  })
  if(asmbDir == "NA"){
    with_golem_options(
      app = shinyApp(
        ui = app_ui,
        server = app_server,
        onStart = onStart,
        options = options,
        enableBookmarking = enableBookmarking,
        uiPattern = uiPattern
      ),
      golem_opts = list(...)
    )
  } else {
    with_golem_options(
      app = shinyApp(
        ui = app_ui_userAsmb,
        server = app_server_userAsmb,
        onStart = onStart,
        options = options,
        enableBookmarking = enableBookmarking,
        uiPattern = uiPattern
      ),
      golem_opts = list(...)
    )
  }



}
