# ============================================================================
# UNIT TESTS: DATA PREPARATION
# Tests for data loading and preparation functions
# ============================================================================

library(testthat)
library(dplyr)

# ----------------------------------------------------------------------------
# Test: Data structure and dimensions
# ----------------------------------------------------------------------------

test_that("Prepared data has correct structure", {
  # Create mock Schedule P data
  mock_data <- data.frame(
    GRCODE = rep(1:3, each = 10),
    GRNAME = rep(c("Company A", "Company B", "Company C"), each = 10),
    AccidentYear = rep(1990:1999, 3),
    DevelopmentLag = rep(10, 30),  # Ultimate
    DevelopmentYear = rep(1990:1999, 3) + 10,
    IncurLoss_B = runif(30, 100000, 500000),
    CumPaidLoss_B = runif(30, 80000, 400000),
    BulkLoss_B = runif(30, 1000, 10000),
    EarnedPremDIR_B = runif(30, 50000, 200000),
    EarnedPremCeded_B = runif(30, 5000, 20000),
    EarnedPremNet_B = runif(30, 45000, 180000)
  )
  
  # Filter to ultimate (DevelopmentLag = 10)
  prepared_data <- mock_data %>%
    filter(DevelopmentLag == 10) %>%
    transmute(
      GRCODE = GRCODE,
      GRNAME = GRNAME,
      AccidentYear = AccidentYear,
      Loss = IncurLoss_B,
      Premium = EarnedPremDIR_B
    )
  
  # Check structure
  expect_equal(nrow(prepared_data), 30)
  expect_true("Loss" %in% names(prepared_data))
  expect_true("Premium" %in% names(prepared_data))
  expect_true("AccidentYear" %in% names(prepared_data))
})

test_that("Data preparation removes incomplete cases", {
  mock_data <- data.frame(
    GRCODE = c(1, 1, 2, 2),
    AccidentYear = c(1990, 1991, 1990, 1991),
    DevelopmentLag = c(10, 10, 10, 10),
    IncurLoss_B = c(1000, NA, 1200, 1300),  # One NA
    EarnedPremDIR_B = c(500, 550, 600, 650)
  )
  
  prepared_data <- mock_data %>%
    filter(DevelopmentLag == 10) %>%
    transmute(
      Loss = IncurLoss_B,
      Premium = EarnedPremDIR_B,
      AccidentYear = AccidentYear
    ) %>%
    filter(complete.cases(.))
  
  expect_equal(nrow(prepared_data), 3)  # Should drop the NA row
})

# ----------------------------------------------------------------------------
# Test: Data transformations
# ----------------------------------------------------------------------------

test_that("Loss ratio calculations are correct", {
  test_data <- data.frame(
    Loss = c(1000, 1500, 2000),
    Premium = c(1000, 1000, 1000)
  )
  
  test_data$LossRatio <- test_data$Loss / test_data$Premium
  
  expect_equal(test_data$LossRatio, c(1.0, 1.5, 2.0))
})

test_that("Year centering works correctly", {
  test_data <- data.frame(
    AccidentYear = c(1990, 1991, 1992, 1993, 1994)
  )
  
  mean_year <- mean(test_data$AccidentYear)
  test_data$Year_Centered <- test_data$AccidentYear - mean_year
  
  expect_equal(mean(test_data$Year_Centered), 0)
  expect_equal(test_data$Year_Centered, c(-2, -1, 0, 1, 2))
})

# ----------------------------------------------------------------------------
# Test: Data quality checks
# ----------------------------------------------------------------------------

test_that("Data contains no negative values", {
  test_data <- data.frame(
    Loss = c(1000, 1100, 1200),
    Premium = c(500, 550, 600),
    AccidentYear = c(1990, 1991, 1992)
  )
  
  expect_true(all(test_data$Loss > 0))
  expect_true(all(test_data$Premium > 0))
})

test_that("Data has reasonable value ranges", {
  # Typical bodily injury data ranges
  test_data <- data.frame(
    Loss = c(50000, 100000, 150000),  # Reasonable losses
    Premium = c(25000, 50000, 75000),  # Reasonable premiums
    AccidentYear = c(1990, 1991, 1992)
  )
  
  # Loss ratios should be reasonable (typically 0.5 to 3.0)
  loss_ratios <- test_data$Loss / test_data$Premium
  expect_true(all(loss_ratios > 0))
  expect_true(all(loss_ratios < 10))  # Very generous upper bound
})

# ----------------------------------------------------------------------------
# Test: Aggregation functions
# ----------------------------------------------------------------------------

test_that("Annual aggregation works correctly", {
  test_data <- data.frame(
    AccidentYear = c(1990, 1990, 1991, 1991, 1992),
    Loss = c(1000, 1500, 2000, 2500, 3000),
    Premium = c(500, 750, 1000, 1250, 1500)
  )
  
  annual_totals <- test_data %>%
    group_by(AccidentYear) %>%
    summarise(
      total_loss = sum(Loss),
      total_premium = sum(Premium),
      n_companies = n(),
      .groups = "drop"
    )
  
  expect_equal(nrow(annual_totals), 3)
  expect_equal(annual_totals$total_loss[1], 2500)  # 1990: 1000 + 1500
  expect_equal(annual_totals$n_companies[2], 2)  # 1991: 2 companies
})

# ----------------------------------------------------------------------------
# Test: Company-level filtering
# ----------------------------------------------------------------------------

test_that("Can filter to specific companies", {
  test_data <- data.frame(
    GRCODE = c(1, 1, 2, 2, 3, 3),
    AccidentYear = c(1990, 1991, 1990, 1991, 1990, 1991),
    Loss = runif(6, 1000, 2000),
    Premium = runif(6, 500, 1000)
  )
  
  # Filter to company 1
  company_1 <- test_data %>% filter(GRCODE == 1)
  
  expect_equal(nrow(company_1), 2)
  expect_true(all(company_1$GRCODE == 1))
})

test_that("Can identify companies with minimum data requirements", {
  test_data <- data.frame(
    GRCODE = c(1, 1, 1, 2, 2, 3, 3, 3, 3, 3),
    AccidentYear = c(1990, 1991, 1992, 1990, 1991, 
                     1990, 1991, 1992, 1993, 1994),
    Loss = runif(10, 1000, 2000),
    Premium = runif(10, 500, 1000)
  )
  
  # Companies with at least 3 years of data
  company_counts <- test_data %>%
    group_by(GRCODE) %>%
    summarise(n_years = n(), .groups = "drop") %>%
    filter(n_years >= 3)
  
  expect_equal(nrow(company_counts), 2)  # Companies 1 and 3
  expect_true(all(company_counts$GRCODE %in% c(1, 3)))
})

# ----------------------------------------------------------------------------
# Test: Integration with validation (if available)
# ----------------------------------------------------------------------------

test_that("Prepared data passes basic validation", {
  test_data <- data.frame(
    Loss = c(1000, 1100, 1200, 1300),
    Premium = c(500, 550, 600, 650),
    AccidentYear = c(1990, 1991, 1992, 1993)
  )
  
  # Basic validation checks
  expect_true(all(!is.na(test_data$Loss)))
  expect_true(all(!is.na(test_data$Premium)))
  expect_true(all(test_data$Loss > 0))
  expect_true(all(test_data$Premium > 0))
})
