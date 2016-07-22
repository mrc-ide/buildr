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

    status=function(hash=NULL) {
      if (is.null(hash)) {
        hash <- "queue"
      }
      r <- httr::GET(file.path(self$base_url, "status", hash))
      buildr_http_client_response(r)
    },

    info=function(hash) {
      r <- httr::GET(file.path(self$base_url, "info", hash))
      buildr_http_client_response(r)
    },

    log=function(hash, n=NULL) {
      query <- if (is.null(n)) NULL else list(n = n)
      r <- httr::GET(file.path(self$base_url, "log", hash), query=query)
      log <- buildr_http_client_response(r)
      class(log) <- "build_log"
      log
    },

    download=function(hash, dest=tempfile(), binary=TRUE) {
      dir.create(dest, FALSE, TRUE)
      if (!file.info(dest, extra_cols=FALSE)[["isdir"]]) {
        stop("dest must be a directory")
      }
      type <- if (binary) "binary" else "source"
      r <- httr::GET(file.path(self$base_url, "download", hash, type))
      dat <- buildr_http_client_response(r)
      ret <- file.path(dest, self$info(hash)[[paste0("filename_", type)]])
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

    upgrade=function() {
      ## This should possibly be key protected I think?
      r <- httr::PATCH(file.path(self$base_url, "upgrade"))
      buildr_http_client_response(r)
    },

    wait=function(hash, dest=tempfile(), poll=1, timeout=60, verbose=TRUE) {
      dir.create(dirname(dest), FALSE, TRUE)
      times_up <- time_checker(timeout)
      repeat {
        info <- tryCatch(self$info(hash),
                         error=function(e) NULL)
        if (is.null(info)) {
          if (times_up()) {
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
        } else if (is.null(info$filename_binary)) {
          stop(sprintf("Build failed; see '$log(\"%s\")' for details", hash))
        } else {
          return(self$download(hash, dest))
        }
      }
    }))

##' @export
print.build_log <- function(x, ...) {
  n <- length(x)
  if (n > 0) {
    x[[n]] <- sub("\\n+$", "", x[[n]])
  }
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
  if (grepl("^\\s*\\[\\]\\s*", x)) empty else jsonlite::fromJSON(x)
}

time_checker <- function(timeout) {
  t0 <- Sys.time()
  timeout <- as.difftime(timeout, units="secs")
  function() {
    Sys.time() - t0 > timeout
  }
}
