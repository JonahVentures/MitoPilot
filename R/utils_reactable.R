#' Highlight selected row(s)
#'
#' @noRd
rt_highlight_row <- function() {
  htmlwidgets::JS(
    "
    function(rowInfo) {
      if ( typeof rowInfo === 'undefined') return
      var col = rowInfo.selected ? '#D3BEC2' : '#FFFFFF'
      return { background: col }
    }
    "
  )
}

#' Dynamic Icon
#'
#' @param icons a named character vector list of icons to use.
#'
#' @noRd
rt_dynamicIcon <- function(icons = NULL) {
  if (length(icons) == 0) {
    return({
      htmlwidgets::JS("function(cellInfo) {return cellInfo.value}")
    })
  }

  key <- purrr::imap_chr(icons, ~ {
    paste0(.y, ": '", .x, "'")
  }) |>
    unname() |>
    paste(collapse = ", ")

  sprintf(
    "
    function(cellInfo){
      var { value } = cellInfo;
      var icons = { %s };
      var icon = icons[value] || '';
      return `<i class='${icon} reactable-btth' ` +
        `style='padding-left: 0.2em;'></i>`
    }
    ",
    key
  ) |> htmlwidgets::JS()
}

#' Add hover info to truncated text in reactable
#'
#' Assumes that wrap=FALSE in the table so that long text is truncated.
#'
#' @noRd
rt_longtext <- function() {
  htmlwidgets::JS(
    "function(cellInfo) {
      var text = cellInfo.value ? cellInfo.value : ''
      return `<abbr style='cursor: info; text-decoration: none;' ` +
      `title='${text}'>${text}</abbr>`
    }"
  )
}

#' Add text click action to a cell
#'
#' @param InputId shiny input id to use
#' @noRd
rt_link <- function(InputId) {
  sprintf(
    "function(cellInfo) {
                var clickid = '%s';
                var sampid = cellInfo.index+1;
                return `<a href='#' id=${sampid} class='grow'` +
                `onclick='event.stopPropagation(); Shiny.onInputChange(&#39;${clickid}&#39;, this.id, {priority: &#39;event&#39;})'>` +
                cellInfo.value +
                `</a>`;
                }",
    InputId
  ) |>
    htmlwidgets::JS()
}

#' Format unix timestamp as a date in UI
#'
#' @noRd
rt_ts_date <- function() {
  htmlwidgets::JS(
    "
    function(cellInfo) {
      var options = { year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric' };
      var date = new Date(1000*cellInfo.value).toLocaleDateString('en-US', options);
      return date!=='Invalid Date' ? date : null;
    }
    "
  )
}

#' Add reactable icon button
#'
#' @param inputId shiny input id to use
#' @param icon font awesome icon name
#'
#' @noRd
rt_icon_bttn <- function(inputId, icon) {
  sprintf(
    "
    function(cellInfo) {
      var { index } = cellInfo;
      return `<i class='%s grow' ` +
        `id='${index+1}' ` +
        `onclick='event.stopPropagation(); Shiny.setInputValue(&#39;%s&#39;, this.id, {priority: &#39;event&#39;})' ` +
        `style='padding-left: 0.2em;'></i>`
    }
    ",
    icon, inputId
  ) |>
    htmlwidgets::JS()
}

#' Add reactable icon button with text
#'
#' @param inputId shiny input id to use
#' @param icon font awesome icon name
#'
#' @noRd
rt_icon_bttn_text <- function(inputId, icon, text = "") {
  stringr::str_glue(
    "
    function(cellInfo) {{
      var {{ index, value }} = cellInfo;
      value = value ? value : '{text}';
      if (value === undefined || value === null || value==='') {{
        return;
      }}
      return `<button ` +
        `class='icon-bttn-text grow' ` +
        `id='${{index+1}}' ` +
        `onclick='event.stopPropagation(); Shiny.setInputValue(&#39;{inputId}&#39;, this.id, {{priority: &#39;event&#39;}})'>` +
        `<i class='{icon}' ` +
        `style='margin-right: 4px;'></i>` +
        `<small>${{value}}</small>` +
        `</button>`
    }}
    "
  ) |>
    htmlwidgets::JS()
}

#' Add reactable icon button
#'
#' @param inputId shiny input id to use
#' @param icon font awesome icon name
#'
#' @noRd
rt_bool_bttn <- function(inputId, ticon, ficon) {
  stringr::str_glue(
    "
    function(cellInfo) {{
      var {{ index }} = cellInfo;
      var icon = cellInfo.value ? '{ticon}' : '{ficon}';
      return `<i class='${{icon}} grow' ` +
        `id='${{index+1}}' ` +
        `onclick='event.stopPropagation(); Shiny.setInputValue(&#39;{inputId}&#39;, this.id, {{priority: &#39;event&#39;}})' ` +
        `style='padding-left: 0.2em;'></i>`
    }}
    "
  ) |>
    htmlwidgets::JS()
}
