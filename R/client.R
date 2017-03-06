##' Client for submitting and retrieving packages from a buildr
##' server.
##' @title buildr Client
##' @param host Hostname that the buildr server is running on
##' @param port Port that the buildr server is running on (the default
##'   here matches the buildr server default)
##' @export
buildr_client <- function(host, port = 8765) {
  .R6_buildr_http_client$new(host, port)
}

##' @export
##' @rdname buildr_client
buildr_available <- function(host, port = 8765) {
  res <- try(buildr_client(host, port)$ping(), silent = TRUE)
  !inherits(res, "try-error") && any(grepl("buildr", res))
}

##' @importFrom R6 R6Class
.R6_buildr_http_client <- R6::R6Class(
  "buildr_http_client",
  public = list(
    base_url = NULL,
    initialize = function(host, port) {
      self$base_url <- sprintf("http://%s:%d", host, port)
    },

    ping = function() {
      buildr_http_client_response(httr::GET(self$base_url))
    },

    active = function() {
      buildr_http_client_response(httr::GET(file.path(self$base_url, "active")),
                                  empty = NULL)
    },

    packages = function(binary = FALSE, translate = FALSE) {
      type <- if (binary) "binary" else "source"
      query <- list(translate  =  tolower(as.character(translate)))
      r <- httr::GET(file.path(self$base_url, "packages", type), query = query)
      buildr_http_client_response(r, empty = character(0))
    },

    installed = function() {
      r <- httr::GET(file.path(self$base_url, "packages", "lib"),
                     query = list(translate = "false"))
      buildr_http_client_response(r, empty = character(0))
    },

    status = function(package_id = NULL) {
      if (is.null(package_id)) {
        package_id <- "queue"
      }
      r <- httr::GET(file.path(self$base_url, "status", package_id))
      buildr_http_client_response(r, empty = character(0))
    },

    source_info = function(package_id) {
      r <- httr::GET(file.path(self$base_url, "source_info", package_id))
      buildr_http_client_response(r)
    },

    filename = function(package_id) {
      self$source_info(package_id)$filename_source
    },

    info = function(package_id) {
      r <- httr::GET(file.path(self$base_url, "info", package_id))
      if (httr::status_code(r) == 202) {
        NULL
      } else {
        buildr_http_client_response(r)
      }
    },

    log = function(package_id, n = NULL, missing_ok = FALSE) {
      query <- if (is.null(n)) NULL else list(n = n)
      r <- httr::GET(file.path(self$base_url, "log", package_id), query = query)
      if (missing_ok && httr::status_code(r) == 404) {
        return(NULL)
      }
      log <- buildr_http_client_response(r)
      if (package_id == "queue") {
        log <- parse_queue_log(log)
      } else {
        class(log) <- "build_log"
      }
      log
    },

    download = function(package_id, dest = tempfile(), binary = TRUE) {
      dir.create(dest, FALSE, TRUE)
      if (!file.info(dest, extra_cols = FALSE)[["isdir"]]) {
        stop("dest must be a directory")
      }
      type <- if (binary) "binary" else "source"
      info <- self$info(package_id)
      filename <- info[[paste0("filename_", type)]]
      r <- httr::GET(file.path(self$base_url, "download", package_id, type))
      dat <- buildr_http_client_response(r)
      ret <- file.path(dest, filename)
      writeBin(dat, ret)
      ret
    },

    submit = function(filename, build = TRUE) {
      if (length(filename) != 1L) {
        stop("Expected exactly one filename")
      }
      if (!file.exists(filename)) {
        stop("Cannot find file at ", filename)
      }
      if (is_dir(filename)) {
        stop("Please create a .tar.gz from this directory")
      }
      query <- list(build = tolower(as.character(build)))
      r <- httr::POST(file.path(self$base_url, "submit", basename(filename)),
                      body = httr::upload_file(filename), query = query)
      buildr_http_client_response(r)
    },

    upgrade = function() {
      ## This should possibly be key protected I think?
      r <- httr::PATCH(file.path(self$base_url, "upgrade"))
      buildr_http_client_response(r)
    },

    wait = function(package_id, dest = tempfile(), poll = 1, timeout = 600,
                    verbose = TRUE, log_on_failure = TRUE) {
      batch <- grepl(",", package_id, fixed = TRUE)
      fn <- if (batch) client_wait_batch else client_wait_1
      fn(self, package_id, dest, poll, timeout, verbose, log_on_failure)
    },

    batch = function(ids) {
      stopifnot(is.character(ids) && length(ids) > 0)
      json <- jsonlite::toJSON(unname(ids), auto_unbox = FALSE)
      r <- httr::POST(file.path(self$base_url, "batch"),
                      body = json, httr::content_type_json())
      buildr_http_client_response(r)
    },

    build = function(filenames, dest = tempfile(), poll = 1, timeout = 600,
                     verbose = TRUE, log_on_failure = TRUE) {
      ok <- file.exists(filenames)
      if (!all(ok)) {
        stop("files not found: ", paste(filenames[!ok], collapse = ", "))
      }

      if (length(filenames) == 1L) {
        message("building 1 package")
        package_id <- self$submit(filenames)
        self$wait(package_id, dest, poll, timeout, verbose,
                  log_on_failure)
      } else {
        message(sprintf("building %d packages", length(filenames)))
        package_ids <- vcapply(filenames, self$submit, build = FALSE,
                               USE.NAMES = FALSE)
        batch_id <- self$batch(package_ids)
        self$wait(batch_id, dest, poll, timeout, verbose,
                  log_on_failure)
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

buildr_http_client_response <- function(r, empty = list()) {
  httr::stop_for_status(r)
  type <- httr::headers(r)$"content-type"
  if (type == "application/json") {
    x <- httr::content(r, "text", encoding = "UTF-8")
    from_json(x, empty)
  } else if (type == "application/octet-stream") {
    httr::content(r, "raw")
  } else if (type == "text/plain") {
    httr::content(r, "text", encoding = "UTF-8")
  } else {
    stop("Unexpected response type")
  }
}

from_json <- function(x, empty = list()) {
  if (grepl("^\\s*\\[\\]\\s*", x)) empty else jsonlite::fromJSON(x)
}

time_checker <- function(timeout) {
  t0 <- Sys.time()
  timeout <- as.difftime(timeout, units = "secs")
  function() {
    Sys.time() - t0 > timeout
  }
}

parse_queue_log <- function(x) {
  x <- strsplit(x, "\n", fixed = TRUE)[[1]]
  re <- "^\\[([^\\]+)\\] \\(([^)]+)\\) (.*)$"
  all(grepl(re, x))
  data.frame(time = trimws(sub(re, "\\1", x)),
             id = trimws(sub(re, "\\2", x)),
             message = trimws(sub(re, "\\3", x)),
             stringsAsFactors = FALSE)
}

buildr_reset <- function(host, port, timeout = 60, poll = 1) {
  cl <- buildr_client(host, port)
  r <- httr::PATCH(file.path(cl$base_url, "reset"))
  ret <- buildr_http_client_response(r)
  if (timeout > 0L) {
    wait_until_finished(cl, timeout, poll)
  }
  ret
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
      message("*", appendLF = FALSE)
      Sys.sleep(poll)
    }
  }
}

client_wait_1 <- function(cl, package_id,
                          dest = tempfile(), poll = 1, timeout = 600,
                          verbose = TRUE, log_on_failure = TRUE) {
  dir.create(dirname(dest), FALSE, TRUE)
  times_up <- time_checker(timeout)
  repeat {
    info <- cl$info(package_id)
    if (is.null(info)) {
      if (times_up()) {
        log <- try(cat(cl$log(package_id)), silent = TRUE)
        msg <- "Package not created in time"
        if (inherits(log, "try-error")) {
          msg <- paste(msg, "(and error getting log)")
        }
        stop(msg)
      }
      if (verbose) {
        message(".", appendLF = FALSE)
      }
      Sys.sleep(poll)
    } else if (is.null(info$filename_binary)) {
      if (log_on_failure) {
        log <- cl$log(package_id)
        message(paste(log, collapse = "\n"))
        stop(sprintf("Build failed; see above for details (id: %s)",
                     package_id))
      } else {
        stop(sprintf("Build failed; see '$log(\"%s\")' for details",
                     package_id))
      }
    } else {
      if (verbose) {
        message("done")
      }
      return(cl$download(package_id, dest))
    }
  }
}

client_wait_batch <- function(cl, package_id,
                              dest = tempfile(), poll = 1, timeout = 600,
                              verbose = TRUE, log_on_failure = TRUE) {
  package_ids <- strsplit(package_id, ",", fixed = TRUE)[[1L]]
  times_up <- time_checker(timeout)
  ok <- rep(FALSE, length(package_ids))
  repeat {
    status <- cl$status(package_id)
    done <- status %in% c("COMPLETE", "ERROR")
    if (verbose) {
      for (i in which(done & !ok)) {
        ok[i] <- TRUE
        nm <- cl$source_info(package_ids[[i]])$filename_source
        message(sprintf("built %s [%s] (%d / %d done)",
                        nm, status[[i]], sum(done), length(status)))
      }
    }
    if (all(done)) {
      break
    } else if (times_up()) {
      stop("Packages not created in time")
    } else {
      if (verbose) {
        message(".", appendLF = FALSE)
      }
      Sys.sleep(poll)
    }
  }

  err <- status == "ERROR"
  if (any(err)) {
    if (log_on_failure) {
      log <- lapply(package_ids[err],
                    function(x) tryCatch(cl$log(x), error = function(e) NULL))
      log <- lapply(package_ids[err], cl$log, missing_ok = TRUE)
      log <- log[lengths(log) > 0]
      if (length(log) == 0) {
        ## not sure if this will ever happen, but in case getting all
        ## the logs fails, then fall back on the overall build-log
        log <- cl$log(package_id)
      }
      message(paste(log, collapse = "\n\n"))
      stop(sprintf("Build failed; see above for details (id: %s)",
                   paste(package_ids[err], collapse = ", ")))
    } else {
      stop(sprintf("Build failed; see log for details (id: %s)",
                   package_id))
    }
  }

  vcapply(package_ids, cl$download, dest, USE.NAMES = FALSE)
}
