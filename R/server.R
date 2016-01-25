## What's not clear is how the http server and the file monitoring
## server should interact.  I want to poll both but it's not clear
## that should really be done.
##
## One option would be to write something that monitors a directory
## and if a file is found to fire off an HTTP request.  I think that's
## the right move.
##
## The server should also launch a number of workers.  Doing this via
## parallel is probably ideal because then we'll always shut them down
## on exit.  The issue is logging, and the fact that parallel is
## terrible.

##' Run a buildr server.  This runs a http server that will listen for
##' requests to build packages.
##' @title Run buildr server
##' @param path Path to store all our files in.  This could get
##'   reasonably large over time.
##' @param n_workers Number of workers to spawn.  This can be zero, in
##'   which case you will have to spawn workers yourself.
##' @param quiet_workers Make the workers quiet?  If FALSE, the
##'   workers will log to the directory \code{file.path(path,
##'   "worker_log")} with one file per worker.  If \code{TRUE} all
##'   worker output will be interleaved in standard output on this
##'   terminal (which might get confusing/annoying).
##' @param host A string that is a valid IPv4 address that is owned by
##'   this server, or \code{"0.0.0.0"} to listen on all IP addresses.
##' @param port The port to listen on.
##' @param loop Run in a loop?  This is generally the right move
##'   unless you plan on handling requests (with
##'   \code{httpuv::service} manually).
##' @export
buildr_server <- function(path, n_workers, quiet_workers=FALSE,
                          host="0.0.0.0", port=8765, loop=TRUE) {
  buildr_server_check_packages()
  ## TODO: Advertise the URL in the directory.
  app <- buildr_server_app(path, n_workers, quiet_workers)
  base_url <- sprintf("http://%s:%d", host, port)
  report_url <- sub("0.0.0.0", "127.0.0.1", base_url, fixed=TRUE)
  buildr_log("Starting server on %s", report_url)
  if (loop) {
    ## Agressively cleanup the workers here, rather than waiting for gc:
    cleanup <- function(e) {
      buildr_workers_cleanup(app$obj)
    }
    withCallingHandlers(
      httpuv::runServer(host, port, app),
      interrupt=cleanup,
      error=cleanup)
  } else {
    httpuv::startServer(host, port, app)
  }
}

## Options here:
##   GET  packages/{source,binary} -> list of packages in source/binary form
##   GET  status/<hash> -> status, by hash
##   GET  log/<hash> -> log of build, by hash
##   GET  binary/<hash> -> get binary by source hash
##   POST submit/filename -> submit package, returning some info
##   GET  queue_status -> queue information
buildr_server_app <- function(path, n_workers, quiet_workers) {
  obj <- buildr(path, n_workers, quiet_workers)

  list(
    obj=obj,
    call=function(req) {
      buildr_log("[httpd] %s %s", req$REQUEST_METHOD, req$PATH_INFO)
      dat <- parse_req(req)

      execute <- switch(
        dat$endpoint,
        "/"=endpoint_root,
        packages=endpoint_packages,
        status=endpoint_status,
        log=endpoint_log,
        filename_binary=endpoint_filename_binary,
        binary=endpoint_binary,
        submit=endpoint_submit,
        queue_status=endpoint_queue_status,
        endpoint_unknown)
      ret <- execute(obj, dat)
      buildr_log("[httpd] \t--> %d", ret$status)
      ret
    })
}

parse_req <- function(req) {
  x <- req$PATH_INFO
  verb <- req$REQUEST_METHOD
  re <- "^/([^/]+)/?(.*)"
  endpoint <- sub(re, "\\1", x)
  path <- sub(re, "\\2", x)
  path_split <- strsplit(path, "/", fixed=TRUE)[[1]]
  if (length(path_split) == 0L) {
    path <- ""
  }

  ret <- list(verb=verb, endpoint=endpoint,
              path=path, path_split=path_split, req=req)
  if (!is.null(req$HTTP_ACCEPT)) {
    ret$accept <- req$HTTP_ACCEPT
  }
  if (!is.null(req$HTTP_CONTENT_TYPE)) {
    ret$content_type <- req$HTTP_CONTENT_TYPE
  }
  if (verb == "POST") {
    con <- req[["rook.input"]]
    if (!is.null(con)) {
      ret$data <- con$read()
    }
  }
  ret
}

endpoint_root <- function(obj, dat) {
  if (dat$verb == "GET") {
    server_response("This is buildr", type="text/plain")
  } else {
    server_error()
  }
}

endpoint_packages <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    server_response(if (path == "binary") obj$binary() else obj$source())
  } else {
    server_error()
  }
}

endpoint_binary <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    filename <- obj$filename_binary(path)
    server_response(readBin(filename, raw(), file.size(filename)))
  } else {
    server_error()
  }
}

endpoint_status <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    server_response(obj$status(path))
  } else {
    server_error()
  }
}

endpoint_log <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    log <- obj$log(path)
    if (is.null(log)) {
      server_error("Not found", 404L)
    } else {
      server_response(log, type="text/plain")
    }
  } else {
    server_error()
  }
}

endpoint_filename_binary <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 1L) {
    filename_binary <- obj$filename_binary(path)
    if (is.null(filename_binary)) {
      server_error("Not found", 404L)
    } else {
      server_response(basename(filename_binary), type="text/plain")
    }
  } else {
    server_error()
  }
}

endpoint_submit <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "POST" && length(path) == 1L) {
    tmp <- file.path(obj$paths$incoming, path)
    writeBin(dat$data, tmp)
    server_response(obj$submit(tmp))
  } else {
    server_error()
  }
}

endpoint_queue_status <- function(obj, dat) {
  path <- dat$path_split
  if (dat$verb == "GET" && length(path) == 0L) {
    ret <- obj$queue_status()
    server_response(ret)
  } else {
    server_error()
  }
}

endpoint_unknown <- function(obj, dat) {
  server_error("Unknown endpoint", 404L)
}

server_response <- function(body, status=200L, type="application/json") {
  if (is.raw(body)) {
    type <- "application/octet-stream"
  } else if (type == "application/json" && !inherits(body, "json")) {
    body <- jsonlite::toJSON(body, auto_unbox=TRUE)
  }
  list(status=status, headers=list("Content-Type"=type), body=body)
}

server_error <- function(message="Invalid request", status=400L,
                         type="text/plain") {
  server_response(message, status, type)
}
