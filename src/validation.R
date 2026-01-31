# ============================================================================
# DATA VALIDATION AND QUALITY CHECKS
# Functions to ensure data integrity and model validity
# ============================================================================

# ----------------------------------------------------------------------------
# DATA VALIDATION FUNCTIONS
# ----------------------------------------------------------------------------

#' Validate raw CAS Schedule P data
#' @param data Raw data frame from CAS
#' @return List with validation results and messages
validate_raw_data <- function(data) {
  results <- list(
    valid = TRUE,
    errors = character(),
    warnings = character(),
    info = list()
  )
  
  # Check required columns exist
  required_cols <- c("GRCODE", "AccidentYear", "DevelopmentLag", 
                     "IncurLoss_B", "EarnedPremDIR_B")
  missing_cols <- setdiff(required_cols, names(data))
  
  if (length(missing_cols) > 0) {
    results$valid <- FALSE
    results$errors <- c(results$errors, 
                       paste("Missing required columns:", 
                             paste(missing_cols, collapse = ", ")))
  }
  
  # Check for NA values in critical columns
  if (any(is.na(data$IncurLoss_B))) {
    results$warnings <- c(results$warnings, 
                         "NA values found in IncurLoss_B")
  }
  
  if (any(is.na(data$EarnedPremDIR_B))) {
    results$warnings <- c(results$warnings, 
                         "NA values found in EarnedPremDIR_B")
  }
  
  # Check for negative values
  if (any(data$IncurLoss_B < 0, na.rm = TRUE)) {
    results$errors <- c(results$errors, 
                       "Negative values found in IncurLoss_B")
    results$valid <- FALSE
  }
  
  if (any(data$EarnedPremDIR_B < 0, na.rm = TRUE)) {
    results$errors <- c(results$errors, 
                       "Negative values found in EarnedPremDIR_B")
    results$valid <- FALSE
  }
  
  # Check data ranges
  results$info$n_rows <- nrow(data)
  results$info$n_companies <- length(unique(data$GRCODE))
  results$info$year_range <- range(data$AccidentYear)
  results$info$loss_range <- range(data$IncurLoss_B, na.rm = TRUE)
  results$info$premium_range <- range(data$EarnedPremDIR_B, na.rm = TRUE)
  
  return(results)
}

#' Validate prepared modeling data
#' @param data Prepared data frame for modeling
#' @return List with validation results
validate_model_data <- function(data) {
  results <- list(
    valid = TRUE,
    errors = character(),
    warnings = character(),
    checks = list()
  )
  
  # Check required columns
  required_cols <- c("Loss", "Premium", "AccidentYear")
  missing_cols <- setdiff(required_cols, names(data))
  
  if (length(missing_cols) > 0) {
    results$valid <- FALSE
    results$errors <- c(results$errors, 
                       paste("Missing columns:", 
                             paste(missing_cols, collapse = ", ")))
    return(results)
  }
  
  # Check for zeros and negatives
  if (any(data$Loss <= 0, na.rm = TRUE)) {
    n_zero <- sum(data$Loss <= 0, na.rm = TRUE)
    results$warnings <- c(results$warnings, 
                         paste(n_zero, "zero or negative Loss values"))
  }
  
  if (any(data$Premium <= 0, na.rm = TRUE)) {
    n_zero <- sum(data$Premium <= 0, na.rm = TRUE)
    results$errors <- c(results$errors, 
                       paste(n_zero, "zero or negative Premium values"))
    results$valid <- FALSE
  }
  
  # Check loss ratio bounds (should be reasonable)
  loss_ratio <- data$Loss / data$Premium
  if (any(loss_ratio > 10, na.rm = TRUE)) {
    n_extreme <- sum(loss_ratio > 10, na.rm = TRUE)
    results$warnings <- c(results$warnings, 
                         paste(n_extreme, "observations with loss ratio > 10"))
  }
  
  # Statistical checks
  results$checks$n_obs <- nrow(data)
  results$checks$complete_cases <- sum(complete.cases(data))
  results$checks$loss_ratio_mean <- mean(loss_ratio, na.rm = TRUE)
  results$checks$loss_ratio_median <- median(loss_ratio, na.rm = TRUE)
  results$checks$loss_cv <- sd(data$Loss, na.rm = TRUE) / mean(data$Loss, na.rm = TRUE)
  
  return(results)
}

# ----------------------------------------------------------------------------
# MODEL VALIDATION FUNCTIONS
# ----------------------------------------------------------------------------

#' Validate Tweedie model results
#' @param model Fitted Tweedie GLM object
#' @param p Power parameter
#' @return List with validation results
validate_tweedie_model <- function(model, p) {
  results <- list(
    valid = TRUE,
    errors = character(),
    warnings = character(),
    diagnostics = list()
  )
  
  # Check convergence
  if (!model$converged) {
    results$errors <- c(results$errors, "Model did not converge")
    results$valid <- FALSE
  }
  
  # Check power parameter bounds
  if (p <= 1 || p >= 2) {
    results$errors <- c(results$errors, 
                       paste("Power parameter out of bounds (1, 2):", p))
    results$valid <- FALSE
  }
  
  # Check coefficient significance
  model_summary <- summary(model)
  p_values <- model_summary$coefficients[, "Pr(>|t|)"]
  
  if (any(p_values > 0.05)) {
    insig_vars <- names(p_values)[p_values > 0.05]
    results$warnings <- c(results$warnings, 
                         paste("Insignificant coefficients:", 
                               paste(insig_vars, collapse = ", ")))
  }
  
  # Check for extreme predictions
  fitted_vals <- fitted(model)
  if (any(fitted_vals <= 0)) {
    results$errors <- c(results$errors, 
                       "Model produces non-positive fitted values")
    results$valid <- FALSE
  }
  
  # Diagnostic statistics
  results$diagnostics$deviance <- model$deviance
  results$diagnostics$null_deviance <- model$null.deviance
  results$diagnostics$pseudo_r2 <- 1 - (model$deviance / model$null.deviance)
  results$diagnostics$aic <- AIC(model)
  results$diagnostics$n_coef <- length(coef(model))
  
  # Check residuals
  resids <- residuals(model, type = "deviance")
  results$diagnostics$resid_mean <- mean(resids)
  results$diagnostics$resid_sd <- sd(resids)
  
  if (abs(results$diagnostics$resid_mean) > 0.1) {
    results$warnings <- c(results$warnings, 
                         paste("Large mean residual:", 
                               round(results$diagnostics$resid_mean, 3)))
  }
  
  return(results)
}

#' Validate EVT model results
#' @param gev_fit GEV fitted object
#' @param gpd_fit GPD fitted object
#' @return List with validation results
validate_evt_models <- function(gev_fit, gpd_fit) {
  results <- list(
    valid = TRUE,
    errors = character(),
    warnings = character(),
    checks = list()
  )
  
  # GEV checks
  gev_params <- gev_fit$estimate
  
  # Check for reasonable scale parameter
  if (gev_params["scale"] <= 0) {
    results$errors <- c(results$errors, "GEV scale parameter must be positive")
    results$valid <- FALSE
  }
  
  # Warn about extreme shape parameters
  if (abs(gev_params["shape"]) > 1) {
    results$warnings <- c(results$warnings, 
                         paste("GEV shape parameter is extreme:", 
                               round(gev_params["shape"], 3)))
  }
  
  # GPD checks
  gpd_params <- gpd_fit$estimate
  
  if (gpd_params["scale"] <= 0) {
    results$errors <- c(results$errors, "GPD scale parameter must be positive")
    results$valid <- FALSE
  }
  
  # Check for upper bound violations (Weibull case)
  if (gpd_params["shape"] < 0) {
    upper_bound <- -gpd_params["scale"] / gpd_params["shape"]
    results$checks$gpd_upper_bound <- upper_bound
  }
  
  # Store parameter estimates
  results$checks$gev_shape <- gev_params["shape"]
  results$checks$gpd_shape <- gpd_params["shape"]
  results$checks$gev_scale <- gev_params["scale"]
  results$checks$gpd_scale <- gpd_params["scale"]
  
  return(results)
}

# ----------------------------------------------------------------------------
# PREDICTION VALIDATION
# ----------------------------------------------------------------------------

#' Validate model predictions
#' @param actual Actual values
#' @param predicted Predicted values
#' @param tolerance_pct Acceptable percentage error (default 20%)
#' @return List with validation results
validate_predictions <- function(actual, predicted, tolerance_pct = 20) {
  results <- list(
    valid = TRUE,
    errors = character(),
    warnings = character(),
    metrics = list()
  )
  
  # Check for same length
  if (length(actual) != length(predicted)) {
    results$errors <- c(results$errors, 
                       "Actual and predicted have different lengths")
    results$valid <- FALSE
    return(results)
  }
  
  # Check for NA values
  if (any(is.na(predicted))) {
    n_na <- sum(is.na(predicted))
    results$errors <- c(results$errors, 
                       paste(n_na, "NA predictions"))
    results$valid <- FALSE
  }
  
  # Calculate error metrics
  pct_errors <- abs((predicted - actual) / actual) * 100
  
  results$metrics$mae_pct <- mean(pct_errors, na.rm = TRUE)
  results$metrics$median_ae_pct <- median(pct_errors, na.rm = TRUE)
  results$metrics$max_ae_pct <- max(pct_errors, na.rm = TRUE)
  results$metrics$n_exceed_tolerance <- sum(pct_errors > tolerance_pct, na.rm = TRUE)
  
  # Check if predictions are reasonable
  if (results$metrics$mae_pct > tolerance_pct) {
    results$warnings <- c(results$warnings, 
                         paste("Mean absolute error exceeds tolerance:", 
                               round(results$metrics$mae_pct, 2), "%"))
  }
  
  # Check for systematic bias
  bias <- mean(predicted - actual, na.rm = TRUE)
  results$metrics$bias <- bias
  results$metrics$bias_pct <- mean((predicted - actual) / actual * 100, na.rm = TRUE)
  
  if (abs(results$metrics$bias_pct) > 5) {
    results$warnings <- c(results$warnings, 
                         paste("Systematic bias detected:", 
                               round(results$metrics$bias_pct, 2), "%"))
  }
  
  return(results)
}

# ----------------------------------------------------------------------------
# VALIDATION REPORT GENERATOR
# ----------------------------------------------------------------------------

#' Generate comprehensive validation report
#' @param validation_results List of validation results from different checks
#' @return Character vector with formatted report
generate_validation_report <- function(validation_results) {
  report <- character()
  
  report <- c(report, rep("=", 80))
  report <- c(report, "VALIDATION REPORT")
  report <- c(report, rep("=", 80))
  report <- c(report, "")
  
  for (check_name in names(validation_results)) {
    result <- validation_results[[check_name]]
    
    report <- c(report, paste0("--- ", toupper(check_name), " ---"))
    
    if (result$valid) {
      report <- c(report, "✅ PASSED")
    } else {
      report <- c(report, "❌ FAILED")
    }
    
    if (length(result$errors) > 0) {
      report <- c(report, "")
      report <- c(report, "Errors:")
      for (err in result$errors) {
        report <- c(report, paste0("  ❌ ", err))
      }
    }
    
    if (length(result$warnings) > 0) {
      report <- c(report, "")
      report <- c(report, "Warnings:")
      for (warn in result$warnings) {
        report <- c(report, paste0("  ⚠️  ", warn))
      }
    }
    
    if (!is.null(result$metrics)) {
      report <- c(report, "")
      report <- c(report, "Metrics:")
      for (metric_name in names(result$metrics)) {
        report <- c(report, paste0("  ", metric_name, ": ", 
                                   round(result$metrics[[metric_name]], 4)))
      }
    }
    
    if (!is.null(result$diagnostics)) {
      report <- c(report, "")
      report <- c(report, "Diagnostics:")
      for (diag_name in names(result$diagnostics)) {
        report <- c(report, paste0("  ", diag_name, ": ", 
                                   round(result$diagnostics[[diag_name]], 4)))
      }
    }
    
    report <- c(report, "")
  }
  
  # Overall summary
  all_valid <- all(sapply(validation_results, function(x) x$valid))
  
  report <- c(report, rep("=", 80))
  if (all_valid) {
    report <- c(report, "✅ ALL CHECKS PASSED")
  } else {
    report <- c(report, "❌ SOME CHECKS FAILED - REVIEW ERRORS ABOVE")
  }
  report <- c(report, rep("=", 80))
  
  return(report)
}

#' Print validation report to console
#' @param report Character vector with report lines
print_validation_report <- function(report) {
  for (line in report) {
    cat(line, "\n")
  }
}

#' Save validation report to file
#' @param report Character vector with report lines
#' @param filepath Path to save report
save_validation_report <- function(report, filepath = "results/validation_report.txt") {
  dir.create(dirname(filepath), recursive = TRUE, showWarnings = FALSE)
  writeLines(report, filepath)
  cat("Validation report saved to:", filepath, "\n")
}
