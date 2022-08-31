resource "aws_api_gateway_api_key" "MyDemoApiKey" {
  name = "webhook"
}

resource "aws_iam_role" "role" {
  name = "webhook-apigateway"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "apigateway.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
  tags = merge({
    "Name" = "webhook-apigateway",
    }
  )
}


resource "aws_iam_role_policy_attachment" "cloudwatch_apigateway" {
  role       = aws_iam_role.role.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}


resource "aws_iam_role_policy" "ping_data_allow_access" {
  name = "webhook-apigateway"
  role = aws_iam_role.role.id
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "VisualEditor0",
          "Effect" : "Allow",
          "Action" : [
            "s3:ListStorageLensConfigurations",
            "s3:ListAccessPointsForObjectLambda",
            "s3:GetAccessPoint",
            "s3:PutAccountPublicAccessBlock",
            "s3:GetAccountPublicAccessBlock",
            "s3:ListAllMyBuckets",
            "s3:ListAccessPoints",
            "s3:PutAccessPointPublicAccessBlock",
            "s3:ListJobs",
            "s3:PutStorageLensConfiguration",
            "s3:ListMultiRegionAccessPoints",
            "s3:CreateJob"
          ],
          "Resource" : "*"
        },
        {
          "Sid" : "VisualEditor1",
          "Effect" : "Allow",
          "Action" : "s3:*",
          "Resource" : [
            "arn:aws:s3:::webhook-apigateway*",
            "arn:aws:s3:::webhook-apigateway/*"
          ]
        }
      ]
    }
  )
}

# S3 bucket to store the required software
resource "aws_s3_bucket" "ping-data" {
  bucket = "webhook-apigateway"
  tags = merge({
    "Name" = "webhook-apigateway",
    }
  )
}

resource "aws_s3_bucket_public_access_block" "ping-data" {
  bucket                  = "webhook-apigateway"
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



resource "aws_api_gateway_rest_api" "api" {
  name        = "api-gateway-webhook"
  description = "enable webhook for S3 bucket"
  endpoint_configuration {
  types = ["REGIONAL"]
}
}


resource "aws_api_gateway_resource" "resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{folder}"
}


resource "aws_api_gateway_method" "get_method" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.resource.id
  http_method      = "GET"
  authorization    = "NONE"
  api_key_required = "true"
  request_parameters = {
    "method.request.path.folder" = true
  }
}


resource "aws_api_gateway_method" "post_method" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.resource.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = "true"
  request_parameters = {
    "method.request.path.folder" = true
  }
}


resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "GET"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:ap-southeast-2:s3:path/{bucket}"
  credentials             = aws_iam_role.role.arn

  request_parameters = {
    "integration.request.path.bucket" = "method.request.path.folder"
  }
}

resource "aws_api_gateway_integration" "post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "PUT"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:ap-southeast-2:s3:path/{bucket}/{fileName}"
  credentials             = aws_iam_role.role.arn
  request_templates       = {
    "application/json" = "#set($context.requestOverride.path.fileName = $context.requestId + '.json')\n$input.json('$')"
  }
  request_parameters = {
    "integration.request.path.bucket" = "method.request.path.folder"
  }
}


resource "aws_api_gateway_method_response" "get" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  resource_id = "${aws_api_gateway_resource.resource.id}"
  http_method = "${aws_api_gateway_method.get_method.http_method}"
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "get" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.get_method.http_method
  status_code = aws_api_gateway_method_response.get.status_code
  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.integration
]
}

resource "aws_api_gateway_method_response" "post" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "post" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = aws_api_gateway_method_response.post.status_code
  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.integration
]
}


resource "aws_api_gateway_deployment" "S3APIDeployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on = [
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.integration,
    aws_api_gateway_rest_api.api
  ]
  triggers = {
  redeployment = sha1(jsonencode([
    aws_api_gateway_rest_api.api.body,
    aws_api_gateway_integration.post_integration.id,
    aws_api_gateway_integration.integration.id
    ]))
}
  lifecycle {
  create_before_destroy = true
}
}

resource "aws_api_gateway_stage" "S3API" {
  deployment_id = aws_api_gateway_deployment.S3APIDeployment.id
  cache_cluster_size = "0.5"
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "s3api"
}

resource "aws_api_gateway_usage_plan" "example" {
  name         = "usage-plan"
  description  = "webhook-apigateway"

  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_stage.S3API.stage_name
  }

  quota_settings {
    limit  = 20
    offset = 2
    period = "WEEK"
  }

  throttle_settings {
    burst_limit = 5
    rate_limit  = 10
  }
}

resource "aws_api_gateway_usage_plan_key" "main" {
  key_id        = aws_api_gateway_api_key.MyDemoApiKey.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.example.id
}
