#!/usr/bin/env Rscript
build <- function() {
  'Usage:
build.R <version> [--no-cache]' -> usage

  opts <- docopt::docopt(usage)
  version <- opts$version
  txt <- whisker::whisker.render(readLines("Dockerfile.whisker"),
                                 list(r_version = version))

  tag <- paste0("mrcide/buildr:", version)

  wd <- tempfile()
  dir.create(wd)
  system2("git", c("clone", normalizePath(".."), file.path(wd, "buildr")))
  writeLines(txt, file.path(wd, "Dockerfile"))

  args <- c("build",
            if (opts[["--no-cache"]]) "--no-cache",
            "-t", tag,
            ".")

  owd <- setwd(wd)
  on.exit(setwd(owd))
  code <- system2("docker", args)
  message("Created: ", tag)
}

if (!interactive()) {
  build()
}
