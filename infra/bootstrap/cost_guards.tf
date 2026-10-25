# AWS has no hard spending cap. These alert early. Budgets without actions and
# Cost Anomaly Detection do not add cost. They are created here, not by hand,
# so they are tagged and removed by the same destroy as everything else.

# The alert email is personal data and must not be stored in GitHub, so CI plans
# this root with a placeholder address. `ignore_changes` keeps that placeholder
# from showing up as a change. To change the email or the thresholds, replace:
#   tofu apply -replace=aws_budgets_budget.monthly -replace=aws_ce_anomaly_subscription.daily
# (both are free and recreated in seconds).

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly-${var.budget_limit_usd}usd"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  lifecycle {
    ignore_changes = [notification]
  }
}

# A test of the alert path (task 18). The real Budget stays untouched. This one is far below the
# month's spend, so AWS sends an email at its next evaluation. It is off by default and has no
# `ignore_changes`: it exists only while the test runs. Budgets without actions are free.
resource "aws_budgets_budget" "alert_test" {
  count = var.budget_alert_test ? 1 : 0

  name         = "${var.name_prefix}-alert-test"
  budget_type  = "COST"
  limit_amount = "0.01"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

resource "aws_ce_anomaly_monitor" "services" {
  name              = "${var.name_prefix}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "daily" {
  name      = "${var.name_prefix}-anomalies-daily"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  subscriber {
    type    = "EMAIL"
    address = var.budget_alert_email
  }

  # Alert on any anomaly that adds at least $1.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"]
    }
  }

  lifecycle {
    ignore_changes = [subscriber]
  }
}
