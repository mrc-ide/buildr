##' Client for submitting and retrieving packages from a buildr
##' server.
##' @title buildr Client
##' @param host Hostname that the buildr server is running on
##' @param port Port that the buildr server is running on (the default
##'   here matches the buildr server default)
##' @export
buildr_client <- function(host, port=8765) {
  .R6_buildr_http_client$new(host, port)
}

##' @export
##' @rdname buildr_client
buildr_available <- function(host, port=8765) {
  res <- try(buildr_client(host, port)$ping(), silent=TRUE)
  !inherits(res, "try-error") && any(grepl("buildr", res))
}

##' @importFrom R6 R6Class
.R6_buildr_http_client <- R6::R6Class(
  "buildr_http_client",
  public=list(
    base_url=NULL,
    initialize=function(host, port) {
      self$base_url <- sprintf("http://%s:%d", host, port)
    },

    ping=function() {
      buildr_http_client_response(httr::GET(self$base_url))
    },

    packages=function(binary=FALSE) {
      type <- if (binary) "binary" else "source"
      r <- httr::GET(file.path(self$base_url, "packages", type))
      buildr_http_client_response(r, empty=character(0))
    },

    status=function(hash) {
      r <- httr::GET(file.path(self$base_url, "status", hash))
      buildr_http_client_response(r)
    },

    binary=function(hash, dest=tempfile()) {
      dir.create(dest, FALSE, TRUE)
      if (!file.info(dest, extra_cols=FALSE)[["isdir"]]) {
        stop("dest must be a directory")
      }
      r <- httr::GET(file.path(self$base_url, "binary", hash))
      dat <- buildr_http_client_response(r)
      ret <- file.path(dest, self$filename_binary(hash))
      writeBin(dat, ret)
      ret
    },

    submit=function(filename) {
      if (!file.exists(filename)) {
        stop("Cannot find file at ", filename)
      }
      r <- httr::POST(file.path(self$base_url, "submit", basename(filename)),
                      body=httr::upload_file(filename))
      buildr_http_client_response(r)
    },

    ## This is not quite the right response because we really want to
    ## do the right thing on error too.  Because R will handle the
    ## requests one after another we can't really do much about this
    ## but wait.
    ##
    ## Try breaking the package and seeing what is returned here.
    wait=function(hash, dest=tempfile(), poll=1, timeout=60, verbose=TRUE) {
      t_end <- Sys.time() + timeout
      dir.create(dirname(dest), FALSE, TRUE)
      force(poll)
      repeat {
        ok <- tryCatch(self$filename_binary(hash),
                       error=function(e) NULL)
        if (is.null(ok)) {
          if (Sys.time() > t_end) {
            log <- try(cat(self$log(hash)), silent=TRUE)
            msg <- "Package not created in time"
            if (inherits(log, "try-error")) {
              msg <- paste(msg, "(and error getting log)")
            }
            stop(msg)
          }
          if (verbose) {
            message(".", appendLF=FALSE)
          }
          Sys.sleep(poll)
        } else if (ok == "") {
          stop(sprintf("Build failed; see '$log(\"%s\")' for details", hash))
        } else {
          return(self$binary(hash, dest))
        }
      }
    },

    log=function(hash) {
      r <- httr::GET(file.path(self$base_url, "log", hash))
      log <- buildr_http_client_response(r)
      class(log) <- "build_log"
      log
    },

    filename_binary=function(hash) {
      r <- httr::GET(file.path(self$base_url, "filename_binary", hash))
      buildr_http_client_response(r)
    },

    queue_status=function() {
      r <- httr::GET(file.path(self$base_url, "queue_status"))
      buildr_http_client_response(r)
    }))

##' @export
print.build_log <- function(x, ...) {
  writeLines(x)
}

buildr_http_client_response <- function(r, empty=list()) {
  httr::stop_for_status(r)
  type <- httr::headers(r)$"content-type"
  if (type == "application/json") {
    x <- httr::content(r, "text", encoding="UTF-8")
    from_json(x, empty)
  } else if (type == "application/octet-stream") {
    httr::content(r, "raw")
  } else if (type == "text/plain") {
    httr::content(r, "text", encoding="UTF-8")
  } else {
    stop("Unexpected response type")
  }
}

from_json <- function(x, empty=list()) {
  if (x == "[]") empty else jsonlite::fromJSON(x)
}
