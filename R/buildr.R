buildr_server_check_packages <- function() {
  required <- c("context", "devtools", "httpuv", "parallel", "queuer")
  missing <- setdiff(required, .packages(TRUE))
  if (length(missing) > 0L) {
    stop(sprintf("missing required packages: %s",
                 paste(missing, collapse=", ")))
  }
  for (i in required) {
    loadNamespace(i)
  }
}

buildr <- R6::R6Class(
  "buildr",
  public=list(
    paths=NULL,
    queue=NULL,
    db=NULL,
    workers=NULL,

    initialize=function(path, n_workers=0L) {
      buildr_server_check_packages()
      self$paths <- buildr_paths(path, TRUE)
      ## TODO: this could be much nicer in context...
      id <- tryCatch(
        suppressWarnings(context::contexts_list(self$paths$context)),
        error=function(e) character(0))
      if (length(id) == 0L) {
        ctx <- context::context_save(self$paths$context, packages="buildr")
      } else if (length(id) == 1L) {
        ctx <- context::context_handle(self$paths$context, id)
      } else {
        stop("Mo contexts mo problems")
      }
      self$queue <- queuer:::queue_local(ctx)
      self$db <- context::context_db(ctx)

      self$workers <- buildr_workers_spawn(n_workers, self$paths, ctx$id)
      reg.finalizer(self, buildr_workers_cleanup, TRUE)
    },

    submit=function(filename) {
      buildr_enqueue(filename, self$paths, self$db, self$queue)
    },

    ## State of the whole queue.  In theory this could take a while to
    ## hit because of the 'times' call and the large number of things
    ## that might accumulate.
    queue_status=function() {
      status <- self$queue$tasks_status()
      task_ids <- names(status)
      hash <- vcapply(task_ids, self$db$get, "buildr__id_hash")
      filename <- vcapply(hash, self$db$get, "buildr__filename")
      times <- self$queue$tasks_times(task_ids)
      cbind(data.frame(hash=hash, filename=filename,
                       task=task_ids, status=status,
                       stringsAsFactors=FALSE, row.names=NULL),
            times[-1])
    },

    ## List source files:
    source=function() {
      hash <- dir(self$paths$source)
      filename_source <- vcapply(hash, self$db$get, "buildr__filename")
      data.frame(hash=hash, filename_source=filename_source,
                 stringsAsFactors=FALSE, row.names=NULL)
    },

    ## List binary files:
    binary=function() {
      hash <- dir(self$paths$binary)
      filename_source <- vcapply(hash, self$db$get, "buildr__filename")
      filename_binary <- vcapply(hash, function(x)
        dir(file.path(self$paths$binary, x)))
      data.frame(hash=hash, filename_source=filename_source,
                 filename_binary=filename_binary,
                 stringsAsFactors=FALSE, row.names=NULL)
    },

    ## Detailed information on a single source:
    status=function(hash) {
      known <- self$db$exists(hash, "buildr__filename")
      if (known) {
        filename <- self$db$get(hash, "buildr__filename")
        task_id <- self$db$get(hash, "buildr__hash_id")
        status <- self$queue$tasks_status(task_id)
        info <- tryCatch(
          self$db$get(hash, "buildr__binary_info"),
          error=function(e) list())
        c(list(hash=hash, task_id=task_id), info)
      } else {
        list(hash=hash, task_id=NULL)
      }
    },

    log=function(hash) {
      logfile <- file.path(self$paths$log, paste0(hash, ".log"))
      if (file.exists(logfile)) {
        read_text(logfile)
      } else {
        NULL
      }
    },

    ## Full path to binary (throws if not complete)
    binary_filename=function(hash) {
      info <- tryCatch(self$db$get(hash, "buildr__binary_info"),
                       error=function(e) NULL)
      if (is.null(info)) {
        NULL
      } else if (is.null(info$filename_binary)) {
        ""
      } else {
        file.path(self$paths$binary, hash, info$filename_binary)
      }
    }
  ))

buildr_enqueue <- function(filename, paths, db, obj) {
  if (!file.exists(filename)) {
    stop("No such file: ", filename)
  }
  hash <- hash_file(filename)
  buildr_log("Queueing: %s", filename)
  buildr_log(" -- hash: %s", hash)
  build <- package_needs_building(filename, paths, db)
  if (isTRUE(build)) {
    db$set(hash, basename(filename), "buildr__filename")
    if (!file.copy(filename, file.path(paths$source, hash), overwrite=TRUE)) {
      stop("Error copying file")
    }

    root <- paths$root
    t <- obj$enqueue(build_package(hash, root))

    db$set(hash, t$id, "buildr__hash_id")
    db$set(t$id, hash, "buildr__id_hash")
    buildr_log(" -- task: %s", t$id)
    ret <- list(hash=hash, build=TRUE, id=t$id)
  } else {
    reason <- attr(build, "reason", exact=TRUE)
    buildr_log("Skipping: %s", reason)
    ret <- list(hash=hash, build=FALSE, reason=reason)
  }
  file.remove(filename)
  ret
}


## This is the main entrypoint that the queue hits.  There needs to be
## a shell out here to capture all output unless devtools can get
## patched to redirect correctly.  This does mean we have a _lot_ of R
## processes running at once;
## - master
## - worker
##   - the system call here
##     - the R CMD system call spawned by devtools
##
## Unfortunately because of the (current) design of queuer, this needs
## to be exported as ::: will be parsed as a compound call.
##
##' @export
##' @noRd
build_package <- function(file, root) {
  paths <- buildr_paths(root, FALSE)
  db <- context::context_db(paths$context)
  file <- file.path(paths$source, file)
  stopifnot(file.exists(file))
  hash <- hash_file(file)
  log <- file.path(paths$log, paste0(hash, ".log"))
  dest <- file.path(paths$binary, hash_file(file))
  ok <- system2(system.file("build.R", package="buildr"),
                c(file, dest), stdout=log, stderr=log)

  if (ok == 0L) {
    file_bin <- dir(dest)
    info <- list(success=TRUE,
                 filename_source=basename(file),
                 filename_binary=file_bin,
                 hash_source=hash,
                 hash_binary=buildr:::hash_file(file.path(dest, file_bin)))
    db$set(hash, info, "buildr__binary_info")
    info
  } else {
    log_contents <- read_text(log)
    info <- list(success=FALSE,
                 filename_source=basename(file),
                 hash_source=hash,
                 log=log_contents)
    db$set(hash, info, "buildr__binary_info")
    err <- list(message="Build failed", call=NULL, log_contents=log_contents)
    class(err) <- c("build_error", "error", "condition")
    stop(err)
  }
}

## This is the main entry point that the script will use.
devtools_build <- function(filename, dest) {
  tmp <- tempfile()
  untar(filename, exdir=tmp)
  pkg <- file.path(tmp, dir(tmp))
  dir.create(dest, FALSE, TRUE)
  devtools::install_deps(pkg, upgrade=FALSE)
  devtools::build(pkg, path=dest, binary=TRUE)
}

package_needs_building <- function(filename, paths, db) {
  no <- function(reason) {
    structure(FALSE, reason=reason)
  }
  if (!file.exists(filename)) {
    return(no("file_not_found"))
  }

  hash <- hash_file(filename)

  if (db$exists(hash, "buildr__hash_id")) {
    task_id <- db$get(hash, "buildr__hash_id")
    status <- context::task_status(context::task_handle(db, task_id, FALSE))
    if (status == "PENDING") {
      return(no("already queued"))
    }
  }

  if (!db$exists(hash, "buildr__binary_info")) {
    return(TRUE)
  }
  info <- db$get(hash, "buildr__binary_info")
  filename_binary <- file.path(paths$binary, hash, info$filename_binary)
  if (length(filename_binary) == 0L || !file.exists(filename_binary)) {
    return(TRUE)
  }
  if (hash_file(filename_binary) == info$hash_binary) {
    return(no("up_to_date"))
  } else {
    return(TRUE)
  }
}

buildr_paths <- function(root, create=FALSE) {
  paths <- c(root=root,
             context=file.path(root, "context"),
             db=file.path(root, "context/db"),
             incoming=file.path(root, "incoming"),
             source=file.path(root, "source"),
             binary=file.path(root, "binary"),
             log=file.path(root, "log"),
             worker_log=file.path(root, "worker_log"))
  if (create) {
    dir_create(paths, FALSE, TRUE)
  } else {
    if (!all(file.exists(paths))) {
      stop("Paths do not exist")
    }
  }
  setNames(as.list(normalizePath(paths, mustWork=TRUE)),
           names(paths))
}

buildr_log <- function(fmt, ...) {
  message(sprintf(paste0("[%s] ", fmt), Sys.time(), ...))
}

buildr_workers_spawn <- function(n, paths, context_id) {
  if (n == 0L) {
    dir <- sub(paste0(getwd(), "/"), "", paths$context)
    cmd <- sprintf('queue:::queue_local_worker("%s", "%s")', dir, context_id)
    message("Start workers with:\n\t", cmd)
    return(NULL)
  }
  logfiles <- file.path(paths$worker_log,
                        sprintf("%d.%d.log", Sys.getpid(), seq_len(n)))
  cl <- vector("list", n)
  pid <- integer(n)
  for (i in seq_len(n)) {
    message("Creating worker...", appendLF=FALSE)
    tmp <- parallel::makeCluster(1L, "PSOCK", outfile=logfiles[[i]])
    pid[[i]] <- parallel::clusterCall(tmp, Sys.getpid)[[1]]
    message(pid[[i]])
    cl[[i]] <- tmp[[1L]]
  }
  class(cl) <- c("SOCKcluster", "cluster")
  attr(cl, "pid") <- as.integer(parallel::clusterCall(cl, Sys.getpid))

  args <- list(paths$context, context_id)
  for (i in seq_len(n)) {
    parallel:::sendCall(cl[[i]], queuer:::queue_local_worker, args)
  }

  cl
}

buildr_workers_cleanup <- function(object) {
  if (!is.null(object$workers)) {
    message("Shutting down workers")
    tools::pskill(attr(object$workers, "pid"))
    for (i in seq_along(object$workers)) {
      try(close(object$workers[[i]]$con), silent=TRUE)
    }
  }
}
