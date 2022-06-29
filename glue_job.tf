resource "aws_s3_object" "glue_script_upload" {
  count = var.glue_job_enable ? 1 : 0

  bucket = var.glue_job_s3_bucket
  key    = "${local.full_name}.py"
  source = "${path.module}/../../../glue_job/job.py"
  etag   = "${filemd5("${path.module}/../../../glue_job/job.py")}"
}

resource "aws_glue_job" "glue_job" {
  count = var.glue_job_enable ? 1 : 0

  name     = local.full_name
  role_arn = var.glue_job.role_arn

  description            = var.glue_job.description
  connections            = var.glue_job.connections
#  default_arguments      = var.glue_job.default_arguments
  glue_version           = var.glue_job.version != null ? var.glue_job.version : "3.0"
  max_capacity           = var.glue_job.max_capacity
  max_retries            = var.glue_job.max_retries
  timeout                = var.glue_job.timeout
  security_configuration = var.glue_job.security_configuration
  worker_type            = var.glue_job.worker_type
  number_of_workers      = var.glue_job.number_of_workers
  
  default_arguments = {
    # ... potentially other arguments ...
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://aws-glue-assets-313555887466-eu-north-1/temporary/" 
    "--extra-py-files"                   = "s3://technodom-prod-data-lake-s3-glue-libs/delta-core_2.12-1.0.0.jar"
    "--extra-jars"                       = "s3://technodom-prod-data-lake-s3-glue-libs/delta-core_2.12-1.0.0.jar"
    "--spark-event-logs-path"            = "s3://aws-glue-assets-313555887466-eu-north-1/sparkHistoryLogs/"
    "--user-jars-first"                  = "true"
    "--enable-spark-ui"                  = "true"
    "--enable-glue-datacatalog"          = "true"  
    "--job-bookmark-option"              = "job-bookmark-disable"
  }


  dynamic "command" {
    iterator = command
    for_each = var.glue_job.command != null ? var.glue_job.command : [
      {
        name            = "glueetl",
        script_location = "s3://${var.glue_job_s3_bucket}/${local.full_name}.py",
        python_version  = "3"
      }
    ]

    content {
      script_location = lookup(command.value, "script_location", null)
      name            = lookup(command.value, "name", null)
      python_version  = lookup(command.value, "python_version", null)
    }
  }

  dynamic "execution_property" {
    iterator = execution_property
    for_each = var.glue_job.execution_property != null ? var.glue_job.execution_property : []

    content {
      max_concurrent_runs = lookup(execution_property.value, "max_concurrent_runs", 1)
    }
  }

  dynamic "notification_property" {
    iterator = notification_property
    for_each = var.glue_job.notification_property != null ? var.glue_job.notification_property : []

    content {
      notify_delay_after = lookup(notification_property.value, "notify_delay_after", null)
    }
  }

  tags = merge(
    {
      App = "glue"
    },
    local.base_tags,
    var.tags
  )

  lifecycle {
    create_before_destroy = true
    ignore_changes        = []
  }

  depends_on = [aws_s3_object.glue_script_upload]
}

// TODO multiple triggers
resource "aws_glue_trigger" "glue_job_trigger" {
  count = var.glue_job_trigger_enable && var.glue_job_enable ? 1 : 0

  name = local.full_name
  type = upper(var.glue_job_trigger.type)

  description   = var.glue_job_trigger.description
  enabled       = var.glue_job_trigger.enabled != null ? var.glue_job_trigger.enabled : true
  schedule      = var.glue_job_trigger.schedule
  workflow_name = var.glue_job_trigger.workflow_name

  dynamic "actions" {
    iterator = actions
    for_each = var.glue_job_trigger.actions != null ? var.glue_job_trigger.actions : [{"arguments": {}, "job_name": element(concat(aws_glue_job.glue_job.*.id, [""]), 0)}]

    content {
      arguments = lookup(actions.value, "arguments", null)
      job_name  = lookup(actions.value, "job_name", null)
      timeout   = lookup(actions.value, "timeout", null)
    }
  }

  dynamic "predicate" {
    iterator = predicate
    for_each = var.glue_job_trigger.predicate != null ? var.glue_job_trigger.predicate : []

    content {
      logical = lookup(predicate.value, "logical", null)

      dynamic "conditions" {
        iterator = conditions
        for_each = lookup(predicate.value, "conditions", [])

        content {
          job_name         = lookup(conditions.value, "job_name", null)
          state            = lookup(conditions.value, "state", null)
          crawler_name     = lookup(conditions.value, "crawler_name", null)
          crawl_state      = lookup(conditions.value, "crawl_state", null)
          logical_operator = lookup(conditions.value, "logical_operator", null)
        }
      }
    }
  }

  dynamic "timeouts" {
    iterator = timeouts
    for_each = var.glue_job_trigger.timeouts != null ? var.glue_job_trigger.timeouts : []

    content {
      create = lookup(timeouts.value, "create", null)
      delete = lookup(timeouts.value, "delete", null)
    }
  }

  tags = merge(
    {
      App = "glue"
    },
    local.base_tags,
    var.tags
  )

  lifecycle {
    create_before_destroy = true
    ignore_changes        = []
  }

  depends_on = [
    aws_glue_job.glue_job,
    aws_s3_object.glue_script_upload
  ]
}
