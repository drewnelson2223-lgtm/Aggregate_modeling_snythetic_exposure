# ============================================================================
# UNIT TESTS: VALIDATION FUNCTIONS
# Tests for data and model validation in validation.R
# ============================================================================

library(testthat)

# Load validation functions - try multiple paths to handle different working directories
if (file.exists("src/validation.R")) {
  source("src/validation.R")
} else if (file.exists("../../src/validation.R")) {
  source("../../src/validation.R")
} else {
  stop("Cannot find validation.R - make sure you're running from project root")
}

# ----------------------------------------------------------------------------
# Test: validate_raw_data
# ----------------------------------------------------------------------------

test_that("validate_raw_data detects missing columns", {
  # Valid data
  valid_data <- data.frame(
    GRCODE = c(1, 1, 2, 2),
    AccidentYear = c(1990, 1991, 1990, 1991),
    DevelopmentLag = c(10, 10, 10, 10),
    IncurLoss_B = c(1000, 1100, 2000, 2100),
    EarnedPremDIR_B = c(500, 550, 1000, 1050)
  )
  
  result <- validate_raw_data(valid_data)
  expect_true(result$valid)
  expect_equal(length(result$errors), 0)
  
  # Missing column
  invalid_data <- valid_data[, -which(names(valid_data) == "AccidentYear")]
  result <- validate_raw_data(invalid_data)
  expect_false(result$valid)
  expect_true(any(grepl("AccidentYear", result$errors)))
})

test_that("validate_raw_data detects negative values", {
  data <- data.frame(
    GRCODE = c(1, 1),
    AccidentYear = c(1990, 1991),
    DevelopmentLag = c(10, 10),
    IncurLoss_B = c(1000, -100),  # Negative!
    EarnedPremDIR_B = c(500, 550)
  )
  
  result <- validate_raw_data(data)
  expect_false(result$valid)
  expect_true(any(grepl("Negative", result$errors)))
})

test_that("validate_raw_data reports data info", {
  data <- data.frame(
    GRCODE = c(1, 1, 2, 2, 3, 3),
    AccidentYear = c(1990, 1991, 1990, 1991, 1990, 1991),
    DevelopmentLag = c(10, 10, 10, 10, 10, 10),
    IncurLoss_B = c(1000, 1100, 2000, 2100, 1500, 1600),
    EarnedPremDIR_B = c(500, 550, 1000, 1050, 750, 800)
  )
  
  result <- validate_raw_data(data)
  expect_equal(result$info$n_rows, 6)
  expect_equal(result$info$n_companies, 3)
  expect_equal(result$info$year_range, c(1990, 1991))
})

# ----------------------------------------------------------------------------
# Test: validate_model_data
# ----------------------------------------------------------------------------

test_that("validate_model_data checks for required columns", {
  valid_data <- data.frame(
    Loss = c(1000, 1100, 1200),
    Premium = c(500, 550, 600),
    AccidentYear = c(1990, 1991, 1992)
  )
  
  result <- validate_model_data(valid_data)
  expect_true(result$valid)
  
  # Missing column
  invalid_data <- valid_data[, -which(names(valid_data) == "Premium")]
  result <- validate_model_data(invalid_data)
  expect_false(result$valid)
})

test_that("validate_model_data detects zero/negative values", {
  data <- data.frame(
    Loss = c(1000, 0, 1200),  # Zero loss
    Premium = c(500, 550, 0),  # Zero premium
    AccidentYear = c(1990, 1991, 1992)
  )
  
  result <- validate_model_data(data)
  expect_false(result$valid)  # Should fail due to zero premium
  expect_true(length(result$warnings) > 0)  # Should warn about zero loss
})

test_that("validate_model_data warns about extreme loss ratios", {
  data <- data.frame(
    Loss = c(1000, 11000),  # Second has 11x loss ratio
    Premium = c(1000, 1000),
    AccidentYear = c(1990, 1991)
  )
  
  result <- validate_model_data(data)
  expect_true(any(grepl("loss ratio > 10", result$warnings)))
})

# ----------------------------------------------------------------------------
# Test: validate_predictions
# ----------------------------------------------------------------------------

test_that("validate_predictions calculates error metrics", {
  actual <- c(100, 200, 300, 400)
  predicted <- c(110, 190, 310, 390)
  
  result <- validate_predictions(actual, predicted)
  expect_true(result$valid)
  expect_true(!is.null(result$metrics$mae_pct))
  expect_true(!is.null(result$metrics$bias))
})

test_that("validate_predictions detects length mismatch", {
  actual <- c(100, 200, 300)
  predicted <- c(110, 190)
  
  result <- validate_predictions(actual, predicted)
  expect_false(result$valid)
  expect_true(any(grepl("different lengths", result$errors)))
})

test_that("validate_predictions warns about high errors", {
  actual <- c(100, 100, 100, 100)
  predicted <- c(150, 150, 150, 150)  # 50% error
  
  result <- validate_predictions(actual, predicted, tolerance_pct = 20)
  expect_true(length(result$warnings) > 0)
})

test_that("validate_predictions detects systematic bias", {
  actual <- c(100, 200, 300, 400)
  predicted <- actual * 1.1  # Consistent 10% overestimate
  
  result <- validate_predictions(actual, predicted)
  expect_true(result$metrics$bias_pct > 5)
  expect_true(any(grepl("bias", result$warnings)))
})

# ----------------------------------------------------------------------------
# Test: generate_validation_report
# ----------------------------------------------------------------------------

test_that("generate_validation_report creates formatted output", {
  validation_results <- list(
    test1 = list(
      valid = TRUE,
      errors = character(),
      warnings = c("Minor warning"),
      metrics = list(mae = 5.2)
    ),
    test2 = list(
      valid = FALSE,
      errors = c("Critical error"),
      warnings = character()
    )
  )
  
  report <- generate_validation_report(validation_results)
  
  expect_true(is.character(report))
  expect_true(length(report) > 0)
  expect_true(any(grepl("VALIDATION REPORT", report)))
  expect_true(any(grepl("PASSED", report)))
  expect_true(any(grepl("FAILED", report)))
})

# ----------------------------------------------------------------------------
# Test: Integration test for full validation workflow
# ----------------------------------------------------------------------------

test_that("Full validation workflow completes", {
  # Create test data
  test_data <- data.frame(
    Loss = c(1000, 1100, 1200, 1300),
    Premium = c(500, 550, 600, 650),
    AccidentYear = c(1990, 1991, 1992, 1993)
  )
  
  # Run validation
  result <- validate_model_data(test_data)
  
  # Generate report
  report <- generate_validation_report(list(model_data = result))
  
  expect_true(is.character(report))
  expect_true(result$valid)
})
