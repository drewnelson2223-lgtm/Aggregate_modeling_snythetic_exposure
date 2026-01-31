# ============================================================================
# UNIT TESTS: EXTREME VALUE THEORY
# Tests for GEV and GPD modeling functions
# ============================================================================

library(testthat)
library(evd)

# ----------------------------------------------------------------------------
# Test: GEV (Generalized Extreme Value) fitting
# ----------------------------------------------------------------------------

test_that("GEV fits block maxima successfully", {
  skip_if_not_installed("evd")
  
  # Generate synthetic maxima
  set.seed(123)
  maxima <- rgev(20, loc = 1000, scale = 200, shape = 0.1)
  
  # Fit GEV
  gev_fit <- fgev(maxima)
  
  expect_s3_class(gev_fit, "uvevd")
  expect_true(!is.null(gev_fit$estimate))
  expect_equal(length(gev_fit$estimate), 3)  # loc, scale, shape
  expect_true(names(gev_fit$estimate)[1] == "loc")
})

test_that("GEV parameter estimates are reasonable", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  true_loc <- 5000
  true_scale <- 1000
  true_shape <- -0.2
  
  maxima <- rgev(50, loc = true_loc, scale = true_scale, shape = true_shape)
  
  gev_fit <- fgev(maxima)
  estimates <- gev_fit$estimate
  
  # Scale should be positive
  expect_true(estimates["scale"] > 0)
  
  # Estimates should be in reasonable range (generous bounds for random data)
  expect_true(estimates["loc"] > 0)
  expect_true(abs(estimates["shape"]) < 1)
})

test_that("GEV return levels are calculated correctly", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  maxima <- rgev(30, loc = 1000, scale = 200, shape = 0)
  
  gev_fit <- fgev(maxima)
  params <- gev_fit$estimate
  
  # Calculate return level for 100-year return period
  return_level_100 <- qgev(1 - 1/100, 
                           loc = params["loc"],
                           scale = params["scale"],
                           shape = params["shape"])
  
  expect_true(is.finite(return_level_100))
  expect_true(return_level_100 > max(maxima))  # Should exceed observed max
})

test_that("GEV handles different shape parameter regimes", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  
  # Gumbel (shape ≈ 0)
  gumbel_data <- rgev(30, loc = 1000, scale = 200, shape = 0)
  gumbel_fit <- fgev(gumbel_data)
  expect_true(abs(gumbel_fit$estimate["shape"]) < 0.5)
  
  # Fréchet (shape > 0)
  frechet_data <- rgev(30, loc = 1000, scale = 200, shape = 0.3)
  frechet_fit <- fgev(frechet_data)
  expect_s3_class(frechet_fit, "uvevd")
  
  # Weibull (shape < 0)
  weibull_data <- rgev(30, loc = 1000, scale = 200, shape = -0.3)
  weibull_fit <- fgev(weibull_data)
  expect_s3_class(weibull_fit, "uvevd")
})

# ----------------------------------------------------------------------------
# Test: GPD (Generalized Pareto Distribution) fitting
# ----------------------------------------------------------------------------

test_that("GPD fits threshold exceedances successfully", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  data <- rexp(500, rate = 0.001)  # Exponential data
  threshold <- quantile(data, 0.9)
  
  # Fit GPD
  gpd_fit <- fpot(data, threshold)
  
  expect_s3_class(gpd_fit, "pot")
  expect_true(!is.null(gpd_fit$estimate))
  expect_equal(length(gpd_fit$estimate), 2)  # scale, shape
})

test_that("GPD parameter estimates are valid", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  data <- rgamma(500, shape = 2, scale = 500)
  threshold <- quantile(data, 0.85)
  
  gpd_fit <- fpot(data, threshold)
  estimates <- gpd_fit$estimate
  
  # Scale must be positive
  expect_true(estimates["scale"] > 0)
  
  # Shape should be finite
  expect_true(is.finite(estimates["shape"]))
})

test_that("GPD return levels increase with return period", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  data <- rgamma(500, shape = 2, scale = 500)
  threshold <- quantile(data, 0.85)
  
  gpd_fit <- fpot(data, threshold, std.err = FALSE)
  params <- gpd_fit$estimate
  
  # Calculate return levels for different periods
  exceedance_prob <- sum(data > threshold) / length(data)
  
  return_level_10 <- ifelse(abs(params["shape"]) < 1e-6,
                            threshold + params["scale"] * log(10 * exceedance_prob),
                            threshold + (params["scale"] / params["shape"]) * 
                              ((10 * exceedance_prob)^params["shape"] - 1))
  
  return_level_100 <- ifelse(abs(params["shape"]) < 1e-6,
                             threshold + params["scale"] * log(100 * exceedance_prob),
                             threshold + (params["scale"] / params["shape"]) * 
                               ((100 * exceedance_prob)^params["shape"] - 1))
  
  # 100-year return level should exceed 10-year
  expect_true(return_level_100 > return_level_10)
})

test_that("GPD threshold selection affects fit", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  data <- rgamma(500, shape = 2, scale = 500)
  
  # Fit with different thresholds
  threshold_low <- quantile(data, 0.70)
  threshold_high <- quantile(data, 0.95)
  
  gpd_fit_low <- fpot(data, threshold_low, std.err = FALSE)
  gpd_fit_high <- fpot(data, threshold_high, std.err = FALSE)
  
  # Both should fit successfully
  expect_s3_class(gpd_fit_low, "pot")
  expect_s3_class(gpd_fit_high, "pot")
  
  # Parameter estimates will differ
  expect_false(identical(gpd_fit_low$estimate, gpd_fit_high$estimate))
})

# ----------------------------------------------------------------------------
# Test: EVT validation functions (if validation.R available)
# ----------------------------------------------------------------------------

test_that("EVT models can be validated", {
  skip_if_not_installed("evd")
  
  # Try to load validation functions - skip if not available
  skip_if_not(file.exists("src/validation.R"), "validation.R not found")
  
  source("src/validation.R")
  
  set.seed(123)
  
  # Fit GEV
  maxima <- rgev(30, loc = 1000, scale = 200, shape = 0.1)
  gev_fit <- fgev(maxima)
  
  # Fit GPD
  data <- rgamma(500, shape = 2, scale = 500)
  threshold <- quantile(data, 0.85)
  gpd_fit <- fpot(data, threshold, std.err = FALSE)
  
  # Validate
  validation <- validate_evt_models(gev_fit, gpd_fit)
  
  expect_true(!is.null(validation$valid))
  expect_true(is.logical(validation$valid))
  expect_true(!is.null(validation$checks))
})

# ----------------------------------------------------------------------------
# Test: Edge cases and error handling
# ----------------------------------------------------------------------------

test_that("EVT handles small sample sizes", {
  skip_if_not_installed("evd")
  
  # Very small sample
  small_maxima <- c(100, 150, 120, 180, 160)
  
  # Should still fit (though not reliable)
  gev_fit <- fgev(small_maxima)
  
  expect_s3_class(gev_fit, "uvevd")
})

test_that("GPD handles cases with few exceedances", {
  skip_if_not_installed("evd")
  
  set.seed(123)
  data <- rexp(100, rate = 0.01)
  threshold <- quantile(data, 0.98)  # Only 2 exceedances
  
  # May fit but with warnings
  gpd_fit <- fpot(data, threshold, std.err = FALSE)
  
  expect_s3_class(gpd_fit, "pot")
})
