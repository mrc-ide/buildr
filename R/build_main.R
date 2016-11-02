## To be called from the python server script; this is designed to
## make very few assumptions about how the python version is
## structured in terms of directories, but of course there is still a
## bunch of information that has to match up nicely.
build_binary_main <- function(package_id, path_source, path_binary, path_info,
                              path_library) {
  desc <- read.dcf(system.file("DESCRIPTION", package = "buildr"))
  for (d in get_deps(desc, FALSE)) {
    loadNamespace(d)
  }
  Sys.unsetenv("R_LIBS_USER")
  path_library <- normalizePath(path_library, "/", TRUE)
  path_source <- normalizePath(path_source, "/", TRUE)
  path_binary <- normalizePath(path_binary, "/", TRUE)
  path_info <- normalizePath(path_info, "/", TRUE)

  .libPaths(path_library)

  build1 <- function(package_id) {
    message(sprintf("BUILDR: %s (%s)", package_id, Sys.time()))
    res <- build_binary(file.path(path_source, package_id), path_binary,
                        path_library)
    info <- jsonlite::toJSON(list(hash_source = package_id,
                                  hash_binary = tools::md5sum(res),
                                  filename_binary = basename(res),
                                  filename_source = package_id),
                             auto_unbox = TRUE)
    writeLines(info, file.path(path_info, package_id))
    file.rename(res, file.path(path_binary, package_id))
  }

  if (grepl(",", package_id)) {
    package_ids <- strsplit(package_id, ",", fixed = TRUE)[[1L]]
    package_ids <- basename(order_packages(file.path(path_source, package_ids)))
    for (id in package_ids) {
      build1(id)
    }
  } else {
    build1(package_id)
  }

  invisible()
}

## To run this properly, buildr must be installed somewhere accessible
## from the commandline.
bootstrap <- function(lib) {
  dir.create(lib, FALSE, TRUE)
  r <- getOption("repos")
  r[["CRAN"]] <- "https://cran.rstudio.com"
  oo <- options(repos = r)
  on.exit(options(oo))
  desc <- read.dcf(system.file("DESCRIPTION", package = "buildr"))
  deps <- get_deps(desc, FALSE)
  existing <- .packages(TRUE, lib)
  needed <- setdiff(deps, existing)
  if (length(needed)) {
    message("Installing dependencies: ", paste(needed, collapse = ", "))
    install.packages(needed, lib = lib)
  }
  if (!("buildr" %in% existing)) {
    path <- system.file(package = "buildr")
    file.copy(path, lib, recursive = TRUE)
  }
}
