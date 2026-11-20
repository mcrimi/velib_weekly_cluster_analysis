pca <- fit_pca(X)

test_that("components are orthonormal and ordered", {
  expect_equal(unname(crossprod(pca$rotation)), diag(10), tolerance = 1e-10)
  expect_true(all(diff(pca$variance) <= 0))
  expect_lt(sum(pca$explained), 1)
})

test_that("scores reproduce prcomp up to sign", {
  ref <- stats::prcomp(X)
  ours <- pca_scores(pca, X, 3)
  expect_equal(unname(abs(ours)), unname(abs(ref$x[, 1:3])), tolerance = 1e-10)
  expect_equal(unname(pca_scores(pca, X[5, ], 2)), unname(ours[5, 1:2, drop = FALSE]))
})

test_that("the first component is the fill level and the second the working day", {
  scores <- pca_scores(pca, X, 2)
  expect_gt(stats::cor(scores[, 1], rowMeans(X)), 0.95)
  expect_true(all(pca$rotation[, 1] > 0))
  t <- velib$time
  loading <- pca$rotation[, 2]
  expect_gt(mean(loading[!t$weekend & t$hour %in% 10:16]), 0.1)
  expect_lt(mean(loading[!t$weekend & t$hour %in% 1:6]), -0.04)
})

test_that("two components carry most of the variance but not ninety percent", {
  expect_gt(sum(pca$explained[1:2]), 0.6)
  expect_gt(components_for(X, 0.9), 10)
})
