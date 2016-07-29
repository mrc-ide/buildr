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

    active=function() {
      buildr_http_client_response(httr::GET(file.path(self$base_url, "active")),
                                  empty=NULL)
    },

    packages=function(binary=FALSE, translate=FALSE) {
      type <- if (binary) "binary" else "source"
      query <- list(translate = tolower(as.character(translate)))
      r <- httr::GET(file.path(self$base_url, "packages", type), query=query)
      buildr_http_client_response(r, empty=character(0))
    },

    status=function(package_id=NULL) {
      if (is.null(package_id)) {
        package_id <- "queue"
      }
      r <- httr::GET(file.path(self$base_url, "status", package_id))
      buildr_http_client_response(r, empty=character(0))
    },

    info=function(package_id) {
      r <- httr::GET(file.path(self$base_url, "info", package_id))
      if (httr::status_code(r) == 202) {
        NULL
      } else {
        buildr_http_client_response(r)
      }
    },

    log=function(package_id, n=NULL) {
      query <- if (is.null(n)) NULL else list(n = n)
      r <- httr::GET(file.path(self$base_url, "log", package_id), query=query)
      log <- buildr_http_client_response(r)
      if (package_id == "queue") {
        log <- parse_queue_log(log)
      } else {
        class(log) <- "build_log"
      }
      log
    },

    download=function(package_id, dest=tempfile(), binary=TRUE) {
      dir.create(dest, FALSE, TRUE)
      if (!file.info(dest, extra_cols=FALSE)[["isdir"]]) {
        stop("dest must be a directory")
      }
      type <- if (binary) "binary" else "source"
      r <- httr::GET(file.path(self$base_url, "download", package_id, type))
      dat <- buildr_http_client_response(r)
      ret <- file.path(dest, self$info(package_id)[[paste0("filename_", type)]])
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

    wait=function(package_id, dest=tempfile(), poll=1, timeout=60,
                  verbose=TRUE, log_on_failure=FALSE) {
      dir.create(dirname(dest), FALSE, TRUE)
      times_up <- time_checker(timeout)
      repeat {
        info <- self$info(package_id)
        if (is.null(info)) {
          if (times_up()) {
            log <- try(cat(self$log(package_id)), silent=TRUE)
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
          if (log_on_failure) {
            log <- self$log(package_id)
            message(paste(log, collapse="\n"))
            stop(sprintf("Build failed; see above for details (id: %s)",
                         package_id))
          } else {
            stop(sprintf("Build failed; see '$log(\"%s\")' for details",
                         package_id))
          }
        } else {
          return(self$download(package_id, dest))
        }
      }
    },

    build=function(filenames, dest=tempfile(), poll=1, timeout=60,
                   verbose=TRUE, log_on_failure=TRUE) {
      ok <- file.exists(filenames)
      if (!all(ok)) {
        stop("files not found: ", paste(filenames[!ok], collapse=", "))
      }
      res <- lapply(filenames, self$submit)
      ret <- character(length(filenames))
      for (i in seq_along(filenames)) {
        if (verbose) {
          message(
            sprintf("Waiting for %s to build: ", basename(filenames[[i]])),
            appendLF=FALSE)
        }
        ret[[i]] <- self$wait(res[[i]], dest, poll, timeout, verbose,
                              log_on_failure)
        if (verbose) {
          message(basename(ret[[i]]))
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

parse_queue_log <- function(x) {
  x <- strsplit(x, "\n", fixed=TRUE)[[1]]
  re <- "^\\[([^\\]+)\\] \\(([^)]+)\\) (.*)$"
  all(grepl(re, x))
  data.frame(time=trimws(sub(re, "\\1", x)),
             id=trimws(sub(re, "\\2", x)),
             message=trimws(sub(re, "\\3", x)),
             stringsAsFactors=FALSE)
}
