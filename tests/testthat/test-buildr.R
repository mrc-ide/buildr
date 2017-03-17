context("buildr")

test_that("buildr", {
  skip_on_travis()
  skip_if_no_buildr(9999L)

  filename <-
    download_file("https://github.com/richfitz/kitten/archive/master.tar.gz",
                  file.path(tempdir(), "kitten.tar.gz"), TRUE)

  cl <- buildr_client("localhost", 9999L)

  expect_match(cl$ping(), "^This is buildr")

  expect_equal(cl$packages(), character(0))
  expect_equal(cl$packages(TRUE), character(0))
  expect_equal(cl$packages(FALSE, TRUE), character(0))
  expect_equal(cl$packages(TRUE, TRUE), character(0))
  expect_equal(cl$status(), character(0))
  expect_null(cl$active())

  id <- cl$submit(filename)
  id2 <- cl$submit(filename)
  ac <- cl$active()

  expect_equal(id, hash_file(filename))
  expect_identical(id2, id)
  expect_identical(ac, id)

  ans <- cl$wait(id, timeout=3, verbose=FALSE)
  expect_true(file.exists(ans))

  expect_equal(cl$packages(), id)
  expect_equal(cl$packages(TRUE), id)
  expect_equal(cl$packages(translate=TRUE), basename(filename))
  expect_equal(cl$packages(TRUE, translate=TRUE), basename(ans))

  expect_equal(cl$status(id), "COMPLETE")
  expect_equal(cl$status(), character(0))

  log <- cl$log(id)
  expect_is(log, "build_log")
  expect_match(log, "DONE")

  log <- cl$log("queue")
  expect_is(log, "data.frame")
  expect_equal(log$id[1:2], c("Rscript", "R"))
  expect_equal(log$message[3:5], c("starting", "queuing", "starting"))
  expect_true("skipping" %in% log$message[-(1:5)])
})

test_that("batch", {
  path <- tempfile()
  dir.create(path)
  res <- download.packages(c("R6", "crayon"), path)

  ans <- build_binaries(res[, 2], "localhost", 9999L)

  cl <- buildr_client("localhost", 9999L)
  id <- cl$log("queue", 1)$id
  log <- cl$log(id)
  expect_is(log, "build_log")

  expect_equal(sum(grepl("^BUILDR", strsplit(log, "\n")[[1]])), 2L)
  ids <- strsplit(id, ",", fixed = TRUE)[[1]]

  log1 <- cl$log(ids[[1]])
  expect_is(log1, "build_log")
  expect_equal(sum(grepl("^BUILDR", strsplit(log1, "\n")[[1]])), 1L)
})

test_that("upgrade doesn't crash", {
  skip_on_travis()
  skip_if_no_buildr(9999L)

  cl <- buildr_client("localhost", 9999L)
  cl$upgrade()
  wait_until_finished(cl, 10, .25)
  expect_match(cl$ping(), "^This is buildr")
})

test_that("reset works", {
  skip_on_travis()
  skip_if_no_buildr(9999L)

  cl <- buildr_client("localhost", 9999L)
  expect_true(length(cl$packages()) > 0L)
  expect_true(buildr_reset("localhost", 9999L))
  expect_match(cl$ping(), "^This is buildr")
  expect_equal(cl$packages(), character(0))
})

test_that("jeff", {
  if (!file.exists("jeff")) {
    skip("internal test")
  }
  expect_true(buildr_reset("localhost", 9999L))
  cl <- buildr_client("localhost", 9999L)

  expect_match(cl$ping(), "^This is buildr")
  expect_equal(cl$packages(), character(0))

  expect_true(buildr_reset("localhost", 9999L))
  expect_match(cl$ping(), "^This is buildr")
  expect_equal(cl$packages(), character(0))

  filenames <- dir("jeff", full.names = TRUE)

  ids <- vcapply(filenames, cl$submit, build = FALSE)
  expect_equal(sort(cl$packages(FALSE, TRUE)), sort(basename(filenames)))
  expect_equal(cl$packages(TRUE, TRUE), character(0))
  expect_equal(cl$status(), character(0))

  id <- cl$batch(ids)
  ans <- cl$wait(id)
  expect_true(all(file.exists(ans)))

  res <- build_binaries(filenames, "localhost", 9999L)
  expect_equal(basename(res), basename(ans))
})

test_that("broken", {
  skip_on_travis()
  skip_if_no_buildr(9999L)

  cl <- buildr_client("localhost", 9999L)
  system2("R", c("CMD", "build", "broken"))
  filename <- "broken_0.1.0.tar.gz"
  on.exit(file.remove(filename))

  package_id <- cl$submit("broken_0.1.0.tar.gz")
  expect_error(cl$wait(package_id),
               "Build failed; see above for details")
  res <- cl$log(package_id)
  expect_is(res, "build_log")
  expect_match(res, "ERROR", all = FALSE, fixed = TRUE)
})
