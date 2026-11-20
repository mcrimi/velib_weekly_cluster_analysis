# Do clusters found from time profiles alone form neighbourhoods on the map?

#' Indices of each station's k nearest neighbours (rows: stations).
nearest_neighbours <- function(xy, k = 6) {
  d <- as.matrix(stats::dist(xy))
  diag(d) <- Inf
  t(apply(d, 1, function(row) order(row)[seq_len(k)]))
}

#' Share of (station, neighbour) pairs that carry the same label.
same_label_share <- function(label, neighbours) {
  mean(matrix(label[neighbours], nrow = nrow(neighbours)) == label)
}

#' Join-count permutation test: shuffle the labels over the stations and see
#' how often chance alone puts as many like-labelled neighbours together.
join_count_test <- function(label, neighbours, permutations = 999, seed = 2021) {
  observed <- same_label_share(label, neighbours)
  null <- withr::with_seed(seed, vapply(seq_len(permutations), function(i) {
    same_label_share(sample(label), neighbours)
  }, numeric(1)))
  list(observed = observed, expected = mean(null), null_sd = stats::sd(null),
       null_max = max(null), z = (observed - mean(null)) / stats::sd(null),
       p = (1 + sum(null >= observed)) / (permutations + 1), permutations = permutations)
}

#' Moran's I with row-standardised k-nearest-neighbour weights, with a
#' permutation p-value.
morans_i <- function(x, neighbours, permutations = 999, seed = 2021) {
  stat <- function(v) {
    z <- v - mean(v)
    lag <- rowMeans(matrix(z[neighbours], nrow = nrow(neighbours)))
    sum(z * lag) / sum(z^2)
  }
  observed <- stat(x)
  null <- withr::with_seed(seed, vapply(seq_len(permutations), function(i) stat(sample(x)),
                                        numeric(1)))
  list(observed = observed, expected = mean(null),
       p = (1 + sum(null >= observed)) / (permutations + 1))
}

spatial_table <- function(dat, kmeans_fits, neighbours) {
  do.call(rbind, lapply(kmeans_fits, function(f) {
    test <- join_count_test(f$cluster, neighbours)
    data.frame(k = f$k, observed = test$observed, expected = test$expected,
               null_max = test$null_max, z = test$z, p = test$p)
  }))
}

#' The uphill "bonus" stations: how empty are they, and where do they land?
bonus_table <- function(dat, summary, cluster) {
  bonus <- dat$stations$bonus
  test <- stats::wilcox.test(summary$mean_fill[bonus], summary$mean_fill[!bonus])
  share <- tapply(bonus, cluster, mean)
  list(
    n = sum(bonus),
    mean_fill_bonus = mean(summary$mean_fill[bonus]),
    mean_fill_other = mean(summary$mean_fill[!bonus]),
    # Probability that a random bonus station is emptier than a random other one.
    prob_emptier = 1 - unname(test$statistic) / (sum(bonus) * sum(!bonus)),
    p = test$p.value,
    by_cluster = data.frame(cluster = as.integer(names(share)), n = as.vector(table(cluster)),
                            bonus = as.vector(tapply(bonus, cluster, sum)),
                            share = as.vector(share)),
    emptiest_cluster_share = sum(bonus & cluster == which.max(share)) / sum(bonus)
  )
}
