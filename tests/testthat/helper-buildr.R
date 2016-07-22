skip_if_no_buildr <- function(port=8765) {
  if (buildr_available("localhost", port)) {
    return()
  }
  skip("buildr not running")
}

download_file <- function(url, dest=tempfile(), overwrite=FALSE) {
  content <- httr::GET(url,
                       httr::write_disk(dest, overwrite),
                       httr::progress("down"))
  cat("\n")
  code <- httr::status_code(content)
  if (code >= 300L) {
    stop(DownloadError(url, code))
  }
  dest
}
DownloadError <- function(url, code) {
  msg <- sprintf("Downloading %s failed with code %d", url, code)
  structure(list(message=msg, call=NULL),
            class=c("DownloadError", "error", "condition"))
}

wait_until_finished <- function(cl, timeout, poll) {
  times_up <- time_checker(timeout)
  repeat {
    ac <- cl$active()
    if (is.null(ac)) {
      return()
    } else if (times_up()) {
      stop("server never finished in time :(")
    } else {
      message("*", appendLF=FALSE)
      Sys.sleep(poll)
    }
  }
}
