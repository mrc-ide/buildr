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
  expect_equal(log$message[1:3], c("starting", "queuing", "starting"))
  expect_true("skipping" %in% log$message)
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
  r <- httr::PATCH(file.path(cl$base_url, "reset"))
  expect_true(buildr_http_client_response(r))
  wait_until_finished(cl, 30, 1)
  expect_match(cl$ping(), "^This is buildr")
  expect_equal(cl$packages(), character(0))
})
