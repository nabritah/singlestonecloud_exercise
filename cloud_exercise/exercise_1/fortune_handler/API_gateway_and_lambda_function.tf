#configuration
provider "aws" {
   region = "us-east-1" #need to define this as variables
}

#creating IAM role
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
resource "aws_iam_role_policy_attachment" "AWSLambdaVPCAccessExecutionRole" {
    role       = aws_iam_role.lambda_role.id
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#defining local variable just in case zip location ever changes
locals {
    lambda_zip_location = "outputs/app.zip"
}

#Creating zip of app file.
data "archive_file" "app" {
  type        = "zip"
  source_file = "app.py"
  output_path = "${local.lambda_zip_location}"
}

#creating Lambda function
resource "aws_lambda_function" "lambda_function" {
  filename      = "${local.lambda_zip_location}"
  function_name = "app"
  role          = aws_iam_role.lambda_role.arn
  handler       = "app.lambda_handler"

  #source_code_hash = filebase64sha256("${local.lambda_zip_location}")

  runtime = "python3.7"

}

# Creating API gateway
resource "aws_api_gateway_rest_api" "lambda_api" {
  name        = "Serverless_lambda_api"
  description = "Terraform Serverless Application"
}

resource "aws_api_gateway_resource" "lambda_proxy" {
   rest_api_id = aws_api_gateway_rest_api.lambda_api.id
   parent_id   = aws_api_gateway_rest_api.lambda_api.root_resource_id
   path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
   rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
   resource_id   = aws_api_gateway_resource.lambda_proxy.id
   http_method   = "ANY"
   authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
   rest_api_id = aws_api_gateway_rest_api.lambda_api.id
   resource_id = aws_api_gateway_method.proxy.resource_id
   http_method = aws_api_gateway_method.proxy.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.lambda_function.invoke_arn
}

resource "aws_api_gateway_method" "proxy_root" {
   rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
   resource_id   = aws_api_gateway_rest_api.lambda_api.root_resource_id
   http_method   = "ANY"
   authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
   rest_api_id = aws_api_gateway_rest_api.lambda_api.id
   resource_id = aws_api_gateway_method.proxy_root.resource_id
   http_method = aws_api_gateway_method.proxy_root.http_method

   integration_http_method = "POST"
   type                    = "AWS_PROXY"
   uri                     = aws_lambda_function.lambda_function.invoke_arn
}

resource "aws_api_gateway_deployment" "apideploy" {
   depends_on = [
     aws_api_gateway_integration.lambda,
     aws_api_gateway_integration.lambda_root,
   ]

   rest_api_id = aws_api_gateway_rest_api.lambda_api.id
   stage_name  = "test"
}

resource "aws_lambda_permission" "apigw" {
   statement_id  = "AllowAPIGatewayInvoke"
   action        = "lambda:InvokeFunction"
   function_name = aws_lambda_function.lambda_function.function_name
   principal     = "apigateway.amazonaws.com"

   # The "/*/*" portion grants access from any method on any resource
   # within the API Gateway REST API.
   source_arn = "${aws_api_gateway_rest_api.lambda_api.execution_arn}/*/*"
}

output "base_url" {
  value = aws_api_gateway_deployment.apideploy.invoke_url
}