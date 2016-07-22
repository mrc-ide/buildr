## To be called from the python server script; this is designed to
## make very few assumptions about how the python version is
## structured in terms of directories, but of course there is still a
## bunch of information that has to match up nicely.
build_binary_main <- function(package_id, path_source, path_binary, path_info) {
  path_source <- normalizePath(path_source, "/", TRUE)
  path_binary <- normalizePath(path_binary, "/", TRUE)
  path_info   <- normalizePath(path_info,   "/", TRUE)

  res <- do_build_binary(file.path(path_source, package_id), path_binary)

  info <- jsonlite::toJSON(list(hash_source=package_id,
                                hash_binary=tools::md5sum(res),
                                filename_binary=basename(res),
                                filename_source=package_id),
                           auto_unbox=TRUE)
  writeLines(info, file.path(path_info, package_id))

  file.rename(res, file.path(path_binary, package_id))
  invisible()
}

## To run this properly, buildr must be installed somewhere accessible
## from the commandline.
bootstrap <- function(lib) {
  dir.create(lib, FALSE, TRUE)
  r <- getOption("repos")
  r[["CRAN"]] <- "https://cran.rstudio.com"
  oo <- options(repos=r)
  on.exit(options(oo))
  desc <- read.dcf(system.file("DESCRIPTION", package=.packageName))
  deps <- get_deps(desc, FALSE)
  existing <- .packages(TRUE, lib)
  needed <- setdiff(deps, existing)
  if (length(needed)) {
    message("Installing dependencies: ", paste(needed, collapse=", "))
    install.packages(deps, lib=lib)
  }
  if (!(.packageName %in% existing)) {
    path <- system.file(package=.packageName)
    file.copy(path, lib, recursive=TRUE)
  }
}
