locals {
  curated_bus_name = "autospotting-run-instances"
}

resource "aws_cloudwatch_event_bus" "filtered_bus" {
  name = local.curated_bus_name
}

resource "aws_iam_role" "bus_forwarder" {
  name = "${local.curated_bus_name}-forwarder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "bus_forwarder_putevents" {
  name = "${local.curated_bus_name}-putevents"
  role = aws_iam_role.bus_forwarder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["events:PutEvents"]
      Resource = aws_cloudwatch_event_bus.filtered_bus.arn
    }]
  })
}

#########################################################
# 3) Receiver bus resource policy (allow this role to send)
#########################################################
data "aws_iam_policy_document" "curated_bus_policy" {
  statement {
    sid     = "AllowPutEventsFromForwarderRole"
    effect  = "Allow"
    actions = ["events:PutEvents"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.bus_forwarder.arn]
    }

    resources = [aws_cloudwatch_event_bus.filtered_bus.arn]
  }
}

resource "aws_cloudwatch_event_bus_policy" "curated" {
  event_bus_name = aws_cloudwatch_event_bus.filtered_bus.name
  policy         = data.aws_iam_policy_document.curated_bus_policy.json
}

#########################################################
# 4) Rule on DEFAULT bus to match an AWS event and forward
#########################################################
resource "aws_cloudwatch_event_rule" "filter_on_default" {
  name           = "${local.curated_bus_name}-filter"
  description    = "Filter AWS events from default bus -> curated bus"
  event_bus_name = "default"

  # EC2 instance creation API call (RunInstances) via CloudTrail.
  event_pattern = <<EOF
{
  "source": ["aws.ec2"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["ec2.amazonaws.com"],
    "eventName": ["RunInstances"]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "to_curated_bus" {
  rule           = aws_cloudwatch_event_rule.filter_on_default.name
  event_bus_name = "default"

  arn      = aws_cloudwatch_event_bus.filtered_bus.arn
  role_arn = aws_iam_role.bus_forwarder.arn
}

data "aws_region" "current" {}
