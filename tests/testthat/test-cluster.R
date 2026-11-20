test_that("k-means finds groups that are really there", {
  fit <- fit_kmeans(toy$X, 3)
  expect_equal(adjusted_rand(fit$cluster, toy$truth), 1)
  # Cluster 1 is the fullest, cluster 3 the emptiest.
  expect_equal(fit$cluster, rep(3:1, each = 40))
  expect_equal(unname(rowMeans(fit$centres)), c(0.9, 0.5, 0.1), tolerance = 0.02)
  expect_gt(fit$r2, 0.99)
})

test_that("results do not depend on the random start", {
  expect_identical(fit_kmeans(X, 4)$cluster, fit_kmeans(X, 4)$cluster)
  expect_identical(fit_kmeans(X, 4, seed = 1)$cluster, fit_kmeans(X, 4, seed = 99)$cluster)
})

test_that("every station is nearest to its own cluster centre", {
  fit <- fit_kmeans(X, 4)
  expect_equal(nearest_centre(X, fit$centres), fit$cluster)
  expect_equal(unname(sq_dist(X[1:3, ], X[1:3, ])), unname(as.matrix(stats::dist(X[1:3, ]))^2),
               tolerance = 1e-10)
})

test_that("Ward and mixtures recover the toy groups too", {
  expect_equal(adjusted_rand(fit_ward(toy$X, 3)[["3"]], toy$truth), 1)
  mix <- fit_mixtures(stats::prcomp(toy$X)$x[, 1:2], ks = 2:4)
  expect_equal(adjusted_rand(mix$cluster[["3"]], toy$truth), 1)
  expect_equal(mix$bic$k[which.max(mix$bic$bic)], 3)
})

test_that("the adjusted Rand index behaves at its landmarks", {
  a <- rep(1:3, each = 10)
  expect_equal(adjusted_rand(a, a), 1)
  expect_equal(adjusted_rand(a, c(3, 1, 2)[a]), 1)  # labels do not matter
  expect_lt(abs(adjusted_rand(a, rep(1:3, 10))), 0.1)
  expect_equal(adjusted_rand(a, a), mclust::adjustedRandIndex(a, a))
  b <- withr::with_seed(3, sample(1:4, 200, TRUE))
  c <- withr::with_seed(4, sample(1:3, 200, TRUE))
  expect_equal(adjusted_rand(b, c), mclust::adjustedRandIndex(b, c))
})

test_that("Jaccard matching finds each cluster's best counterpart", {
  expect_equal(unname(jaccard_match(c(1, 1, 2, 2), c(5, 5, 9, 9))), c(1, 1))
  expect_equal(unname(jaccard_match(c(1, 1, 1, 2), c(1, 1, 2, 2))), c(2 / 3, 1 / 2))
})

test_that("stability is high for real groups and lower when there are none", {
  real <- bootstrap_stability(toy$X, toy$truth, B = 10)
  expect_equal(mean(real$ari), 1)
  expect_equal(dim(real$jaccard), c(10, 3))
  noise <- withr::with_seed(2, matrix(stats::rnorm(120 * 12), 120))
  split <- stats::kmeans(noise, 3)$cluster
  expect_lt(mean(bootstrap_stability(noise, split, B = 10)$ari), 0.8)
})

test_that("the gap statistic picks three for three groups", {
  expect_equal(gap_statistic(toy$X, k_max = 5, B = 10)$chosen, 3)
})

test_that("cluster names are distinct at every resolution shown on the page", {
  summary <- station_summary(velib)
  for (k in PAGE_KS) {
    labels <- vapply(describe_clusters(velib, summary, fit_kmeans(X, k)$cluster),
                     function(d) d$label, character(1))
    expect_false(anyDuplicated(labels) > 0, info = paste("K =", k))
  }
  expect_equal(cluster_label(0.7, 0), "Full, steady")
  expect_equal(cluster_label(0.4, 0.5), "Half full, fills sharply by day")
  expect_equal(cluster_label(0.1, -0.3), "Empty, empties by day")
})
