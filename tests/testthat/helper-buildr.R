skip_if_no_buildr <- function(port=8765) {
  if (buildr_available("localhost", port)) {
    return()
  }
  skip("buildr not running")
}

download_file <- function(url, dest=tempfile(), overwrite=FALSE) {
  code <- download.file(
    "https://github.com/richfitz/kitten/archive/master.tar.gz",
    dest)
  if (code != 0) {
    stop(DownloadError(url, code))
  }
  dest
}
DownloadError <- function(url, code) {
  msg <- sprintf("Downloading %s failed with code %d", url, code)
  structure(list(message=msg, call=NULL),
            class=c("DownloadError", "error", "condition"))
}
