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
build_binaries <- function(filenames, host, port=8765, ...,
                           dest = tempfile()) {
  if (identical(host, FALSE)) {
    ## This might not do the best thing with stdout.
    ##
    ## TODO: we should advertise the desired binary type (here and
    ## in the server) so that the correct type is always created.
    return(vcapply(filenames, do_build_binary, dest))
  }
  buildr_client(host, port)$build(filenames, ...)
}

order_packages <- function(filenames) {
  desc <- lapply(filenames, extract_DESCRIPTION)
  name <- vcapply(desc, function(x) as.vector(x[, "Package"]))
  names(desc) <- name
  deps <- lapply(desc, get_deps, FALSE)
  filenames[match(topological_order(deps), name)]
}

## This comes from odin:
topological_order <- function(graph) {
  no_dep <- lengths(graph) == 0L
  graph_sorted <- names(no_dep[no_dep])
  graph <- graph[!no_dep]

  while (length(graph) > 0L) {
    acyclic <- FALSE
    for (i in seq_along(graph)) {
      edges <- graph[[i]]
      if (!any(edges %in% names(graph))) {
        acyclic <- TRUE
        graph_sorted <- c(graph_sorted, names(graph[i]))
        graph <- graph[-i]
        break
      }
    }
    if (!acyclic) {
      f <- function(x) {
        y <- graph[[x]]
        i <- vapply(graph[y], function(el) x %in% el, logical(1))
        sprintf("\t%s: depends on %s", x, y[i])
      }
      err <- intersect(edges, names(graph))
      stop(sprintf("A cyclic dependency detected for %s:\n%s",
                   paste(err, collapse=", "),
                   paste(vcapply(err, f), collapse="\n")), call.=FALSE)
    }
  }

  graph_sorted
}
