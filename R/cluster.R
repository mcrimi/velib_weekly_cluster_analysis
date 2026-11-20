# Clustering the stations, and measuring how much to believe the clusters.

K_RANGE <- 2:8

#' Squared Euclidean distances from each row of X to each row of centres.
sq_dist <- function(X, centres) {
  outer(rowSums(X^2), rowSums(centres^2), `+`) - 2 * X %*% t(centres)
}

nearest_centre <- function(X, centres) max.col(-sq_dist(X, centres), ties.method = "first")

#' Renumber clusters so that 1 is the fullest on average and K the emptiest.
#' Without this, labels depend on the random start.
relabel <- function(cluster, X) {
  level <- tapply(rowMeans(X), cluster, mean)
  unname(match(cluster, as.integer(names(sort(level, decreasing = TRUE)))))
}

centres_of <- function(X, cluster) {
  out <- rowsum(X, cluster) / as.vector(table(cluster))
  out[order(as.integer(rownames(out))), , drop = FALSE]
}

fit_kmeans <- function(X, k, nstart = 25, seed = 2021) {
  fit <- withr::with_seed(seed, stats::kmeans(X, centers = k, nstart = nstart, iter.max = 100))
  cluster <- relabel(fit$cluster, X)
  list(k = k, cluster = cluster, centres = centres_of(X, cluster),
       r2 = fit$betweenss / fit$totss)
}

#' Ward's method (minimum variance), the hierarchical counterpart of k-means.
fit_ward <- function(X, ks = K_RANGE) {
  tree <- stats::hclust(stats::dist(X), method = "ward.D2")
  out <- lapply(ks, function(k) relabel(stats::cutree(tree, k), X))
  stats::setNames(out, ks)
}

#' Gaussian mixtures on the leading principal components, for each K.
#' The covariance structure is chosen by BIC separately for each K.
fit_mixtures <- function(scores, ks = K_RANGE, seed = 2021) {
  # mclust looks up its BIC function by name, so the package must be attached.
  suppressPackageStartupMessages(requireNamespace("mclust"))
  mclustBIC <- mclust::mclustBIC
  fits <- withr::with_seed(seed, lapply(c(1, ks), function(k) {
    mclust::Mclust(scores, G = k, verbose = FALSE)
  }))
  list(
    bic = data.frame(k = c(1, ks), bic = vapply(fits, function(f) f$bic, numeric(1)),
                     model = vapply(fits, function(f) f$modelName, character(1))),
    cluster = stats::setNames(lapply(fits[-1], function(f) f$classification), ks),
    uncertainty = stats::setNames(lapply(fits[-1], function(f) f$uncertainty), ks)
  )
}

adjusted_rand <- function(a, b) {
  tab <- table(a, b)
  pairs <- function(n) sum(n * (n - 1) / 2)
  n <- pairs(sum(tab))
  expected <- pairs(rowSums(tab)) * pairs(colSums(tab)) / n
  maximum <- (pairs(rowSums(tab)) + pairs(colSums(tab))) / 2
  if (maximum == expected) return(1)
  (pairs(tab) - expected) / (maximum - expected)
}

#' Best Jaccard overlap of each reference cluster with any cluster in `other`.
jaccard_match <- function(reference, other) {
  tab <- table(reference, other)
  union <- outer(rowSums(tab), colSums(tab), `+`) - tab
  apply(tab / union, 1, max)
}

mean_silhouette <- function(cluster, d) mean(cluster::silhouette(cluster, d)[, "sil_width"])

#' Bootstrap stability: re-cluster resampled stations, assign every station to
#' its nearest new centre, and compare with the reference partition.
bootstrap_stability <- function(X, reference, B = 100, nstart = 5, seed = 2021) {
  k <- max(reference)
  draw <- function() {
    lapply(seq_len(B), function(b) {
      rows <- sample.int(nrow(X), replace = TRUE)
      fit <- stats::kmeans(X[rows, , drop = FALSE], centers = k, nstart = nstart, iter.max = 100)
      other <- nearest_centre(X, fit$centers)
      list(ari = adjusted_rand(reference, other), jaccard = jaccard_match(reference, other))
    })
  }
  # seed = NULL: use the caller's random stream.
  runs <- if (is.null(seed)) draw() else withr::with_seed(seed, draw())
  list(ari = vapply(runs, function(r) r$ari, numeric(1)),
       jaccard = do.call(rbind, lapply(runs, function(r) r$jaccard)))
}

#' Gap statistic (Tibshirani, Walther and Hastie 2001) for k-means.
gap_statistic <- function(X, k_max = max(K_RANGE), B = 50, seed = 2021) {
  cluster_fun <- function(x, k) list(cluster = stats::kmeans(x, k, nstart = 5, iter.max = 100)$cluster)
  gap <- withr::with_seed(seed, cluster::clusGap(X, cluster_fun, K.max = k_max, B = B,
                                                 verbose = FALSE))
  tab <- as.data.frame(gap$Tab)
  list(
    table = data.frame(k = seq_len(k_max), gap = tab$gap, se = tab$SE.sim),
    chosen = cluster::maxSE(tab$gap, tab$SE.sim, method = "Tibs2001SEmax")
  )
}

#' One row per K: every measure of whether K clusters are really there.
validity_table <- function(X, kmeans_fits, ward, mixtures, gap, stability) {
  d <- stats::dist(X)
  ks <- vapply(kmeans_fits, function(f) f$k, numeric(1))
  data.frame(
    k = ks,
    r2 = vapply(kmeans_fits, function(f) f$r2, numeric(1)),
    silhouette = vapply(kmeans_fits, function(f) mean_silhouette(f$cluster, d), numeric(1)),
    gap = gap$table$gap[match(ks, gap$table$k)],
    gap_se = gap$table$se[match(ks, gap$table$k)],
    stability_ari = vapply(stability, function(s) mean(s$ari), numeric(1)),
    stability_ari_lo = vapply(stability, function(s) unname(stats::quantile(s$ari, 0.1)), numeric(1)),
    weakest_jaccard = vapply(stability, function(s) min(colMeans(s$jaccard)), numeric(1)),
    ari_ward = mapply(function(f, w) adjusted_rand(f$cluster, w), kmeans_fits, ward[as.character(ks)]),
    ari_mixture = mapply(function(f, m) adjusted_rand(f$cluster, m), kmeans_fits,
                         mixtures$cluster[as.character(ks)]),
    smallest = vapply(kmeans_fits, function(f) min(table(f$cluster)), numeric(1)),
    row.names = NULL
  )
}

#' The same measures on data with no cluster structure at all: one Gaussian
#' with the covariance of the real profiles. A benchmark for "what would a
#' continuum look like?".
null_benchmark <- function(X, ks = K_RANGE, B = 20, seed = 2021) {
  pca <- stats::prcomp(X)
  n <- nrow(X)
  withr::with_seed(seed, {
    Z <- sweep(matrix(stats::rnorm(n * ncol(X)), n), 2, pca$sdev, `*`) %*% t(pca$rotation)
    d <- stats::dist(Z)
    do.call(rbind, lapply(ks, function(k) {
      fit <- stats::kmeans(Z, k, nstart = 10, iter.max = 100)
      boot <- bootstrap_stability(Z, fit$cluster, B = B, seed = NULL)
      data.frame(k = k, silhouette = mean_silhouette(fit$cluster, d),
                 stability_ari = mean(boot$ari))
    }))
  })
}

#' What each cluster looks like, from descriptors that played no part in forming it.
describe_clusters <- function(dat, summary, cluster) {
  X <- dat$profiles
  weekday <- !dat$time$weekend
  out <- lapply(sort(unique(cluster)), function(g) {
    rows <- cluster == g
    hourly <- function(cols) as.vector(tapply(colMeans(X[rows, cols, drop = FALSE]),
                                              dat$time$hour[cols], mean))
    list(
      cluster = g, n = sum(rows),
      mean_fill = mean(summary$mean_fill[rows]),
      day_night = mean(summary$day_night[rows]),
      bonus_share = mean(dat$stations$bonus[rows]),
      label = cluster_label(mean(summary$mean_fill[rows]), mean(summary$day_night[rows])),
      level = cluster_level(mean(summary$mean_fill[rows])),
      movement = cluster_movement(mean(summary$day_night[rows])),
      weekday = hourly(weekday), weekend = hourly(!weekday),
      centre = colMeans(X[rows, , drop = FALSE])
    )
  })
  out
}

#' A plain-language name from two numbers: how full the stations are, and
#' which way the working day moves them.
cluster_label <- function(mean_fill, day_night) {
  paste0(cluster_level(mean_fill), ", ", cluster_movement(day_night))
}

cluster_level <- function(mean_fill) {
  if (mean_fill >= 0.6) "Full" else if (mean_fill <= 0.25) "Empty" else "Half full"
}

cluster_movement <- function(day_night, swing = 0.2, sharp = 0.45) {
  size <- abs(day_night)
  if (size < swing) return("steady")
  paste0(if (day_night > 0) "fills" else "empties", if (size >= sharp) " sharply" else "",
         " by day")
}
