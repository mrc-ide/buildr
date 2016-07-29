##' Build a set of binaries, waiting until complete
##' @title Build a set of binaries, waiting until complete
##' @param filenames Vector of filenames of the source packages
##'
##' @param host A hostname for the build server, or \code{FALSE} to
##'   build locally.
##'
##' @param port Port number for the build server
##'
##' @param ... Arguments passed through to the \code{build} method of
##'   \code{\link{buildr_client}}; includes \code{dest} (place to put
##'   binaries), \code{poll} (frequency to poll for job completion),
##'   \code{timeout} (time until giving up), \code{verbose} (controls
##'   printed output) and \code{log_on_failure} (print logs if a build
##'   fails).
##'
##' @export
##' @return A character vector of filenames
build_binaries <- function(filenames, host, port=8765, ...) {
  if (identical(host, FALSE)) {
    ## This might not do the best thing with stdout.
    ##
    ## TODO: we should advertise the desired binary type (here and
    ## in the server) so that the correct type is always created.
    return(vcapply(filenames, do_build_binary, dest))
  }
  cl <- buildr_client(host, port)
  cl$build(filenames, ...)
}
