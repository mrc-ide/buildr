##' Build a set of binaries, waiting until complete
##' @title Build a set of binaries, waiting until complete
##' @param filenames Vector of filenames of the source packages
##'
##' @param config Configuation options; a list with options "host"
##'   (required), port, poll and timeout (all optional and passed to
##'   \code{\link{buildr_client}} and \code{buildr_client$wait}).
##'
##' @param dest A directory to place generated files.
##' @export
##' @return A character vector of filenames
build_binaries <- function(filenames, config, dest=tempfile()) {
  n <- length(filenames)
  if (n == 0L) {
    return()
  }
  dir.create(dest, FALSE, TRUE)
  if (is.character(config)) {
    if (identical(config, "local")) {
      return(build_binaries_local(filenames))
    } else {
      config <- list(host=config)
    }
  }
  if (!is.list(config)) {
    stop("Invalid configuration")
  }
  unk <- setdiff(names(config), c("host", "port", "poll", "timeout"))
  if (length(unk) > 0L) {
    stop("Unknown build configuration: %s", paste(unk, collapse=", "))
  }
  host <- config$host %or% stop("host must be given")
  port <- config$port %or% 8765

  cl <- buildr_client(host, port)
  message(cl$ping())
  timeout <- config$timeout %or% formals(cl$wait)$timeout
  poll <- config$poll       %or% formals(cl$wait)$poll
  res <- lapply(filenames, cl$submit)
  ret <- character(n)
  for (i in seq_len(n)) {
    message(sprintf("Waiting for %s to build: ", basename(filenames[[i]])),
            appendLF=FALSE)
    ret[[i]] <- cl$wait(res[[i]]$hash_source, dest=dest,
                        poll=poll, timeout=timeout, verbose=TRUE)
    message(basename(ret[[i]]))
  }
  ret
}
