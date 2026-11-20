# Principal component analysis of the loading profiles.

#' PCA on the covariance matrix. The 168 columns share one scale (share of
#' docks holding a bike), so they are centred but not standardised.
fit_pca <- function(X, components = 10) {
  fit <- stats::prcomp(X, center = TRUE, scale. = FALSE)
  rotation <- fit$rotation[, seq_len(components), drop = FALSE]
  # Fix the arbitrary sign: PC1 points towards fuller stations, later
  # components towards "fuller at Tuesday noon".
  noon <- match("Tue-12", colnames(X))
  sign <- vapply(seq_len(components), function(j) {
    s <- if (j == 1) sum(rotation[, j]) else rotation[noon, j]
    if (s < 0) -1 else 1
  }, numeric(1))
  rotation <- sweep(rotation, 2, sign, `*`)
  variance <- fit$sdev^2
  list(
    center = fit$center,
    rotation = rotation,
    variance = variance[seq_len(components)],
    explained = (variance / sum(variance))[seq_len(components)],
    total_variance = sum(variance)
  )
}

#' Scores of (new) profiles on the fitted components.
pca_scores <- function(pca, X, components = ncol(pca$rotation)) {
  X <- if (is.null(dim(X))) matrix(X, nrow = 1) else X
  sweep(X, 2, pca$center) %*% pca$rotation[, seq_len(components), drop = FALSE]
}

#' Components needed to reach a share of the total variance.
components_for <- function(X, share = 0.9) {
  v <- stats::prcomp(X)$sdev^2
  which(cumsum(v) / sum(v) >= share)[1]
}
