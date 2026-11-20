grid <- expand.grid(x = 1:10, y = 1:10)
nb <- nearest_neighbours(grid, k = 4)

test_that("neighbours are the nearest other stations", {
  expect_equal(dim(nb), c(100, 4))
  expect_false(any(nb == row(nb)))
  centre <- which(grid$x == 5 & grid$y == 5)
  expect_setequal(nb[centre, ], which(abs(grid$x - 5) + abs(grid$y - 5) == 1))
})

test_that("two halves of a grid are spatially coherent and a random split is not", {
  halves <- as.integer(grid$x > 5) + 1L
  coherent <- join_count_test(halves, nb, permutations = 199)
  expect_gt(coherent$observed, 0.9)
  expect_equal(coherent$p, 1 / 200)
  expect_gt(coherent$z, 5)
  shuffled <- withr::with_seed(5, sample(halves))
  expect_gt(join_count_test(shuffled, nb, permutations = 199)$p, 0.05)
})

test_that("Moran's I separates a gradient from noise", {
  expect_gt(morans_i(grid$x, nb, permutations = 99)$observed, 0.8)
  noise <- withr::with_seed(6, stats::rnorm(100))
  expect_lt(abs(morans_i(noise, nb, permutations = 99)$observed), 0.2)
})

test_that("Vélib clusters, formed without coordinates, are neighbourhoods", {
  fit <- fit_kmeans(X, 4)
  velib_nb <- nearest_neighbours(velib$stations[c("x", "y")], k = 6)
  test <- join_count_test(fit$cluster, velib_nb, permutations = 199)
  expect_gt(test$observed, 2 * test$expected)
  expect_gt(test$observed, test$null_max)
})

test_that("bonus stations are the empty ones", {
  fit <- fit_kmeans(X, 4)
  b <- bonus_table(velib, station_summary(velib), fit$cluster)
  expect_lt(b$mean_fill_bonus, b$mean_fill_other / 2)
  expect_gt(b$prob_emptier, 0.8)
  expect_gt(b$emptiest_cluster_share, 0.9)
  expect_equal(sum(b$by_cluster$bonus), 127)
})
