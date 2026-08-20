resource "aws_s3_bucket" "tfstate" {
    bucket = "serverless-todo-api-tfstate-179236281274"
}

resource "aws_s3_bucket_versioning" "tfstate" {
    bucket = aws_s3_bucket.tfstate.id
    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
    bucket = aws_s3_bucket.tfstate.id
    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_dynamodb_table" "tfstate_lock" {
    name         = "serverless-todo-api-tfstate-lock"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "LockID"

    attribute {
        name = "LockID"
        type = "S"
    }
}

resource "aws_dynamodb_table" "todos" {
    name         = "todos-table"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "userId"
    range_key    = "todoId"

    attribute {
        name = "userId"
        type = "S"
    }

    attribute {
        name = "todoId"
        type = "S"
    }
}

data "aws_iam_policy_document" "lambda_trust" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRole"]

        principals {
            type        = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "lambda_exec" {
    name               = "todo-api-lambda-exec-role"
    assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
    role       = aws_iam_role.lambda_exec.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_dynamodb" {
    statement {
        effect = "Allow"
        actions = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Query"
        ]
        resources = [aws_dynamodb_table.todos.arn]
    }
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
    name   = "todo-api-lambda-dynamodb-policy"
    policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
    role       = aws_iam_role.lambda_exec.name
    policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

data "archive_file" "create_todo" {
    type        = "zip"
    source_file = "${path.module}/../src/lambda/create_todo/index.py"
    output_path = "${path.module}/../src/lambda/create_todo.zip"
}

resource "aws_lambda_function" "create_todo" {
    function_name = "todo-api-create-todo"
    role          = aws_iam_role.lambda_exec.arn
    handler       = "index.handler"
    runtime       = "python3.12"

    filename         = data.archive_file.create_todo.output_path
    source_code_hash = data.archive_file.create_todo.output_base64sha256

    environment {
        variables = {
            TABLE_NAME = aws_dynamodb_table.todos.name
        }
    }
}

data "archive_file" "list_todos" {
    type        = "zip"
    source_file = "${path.module}/../src/lambda/list_todos/index.py"
    output_path = "${path.module}/../src/lambda/list_todos.zip"
}

resource "aws_lambda_function" "list_todos" {
    function_name    = "todo-api-list-todos"
    role             = aws_iam_role.lambda_exec.arn
    handler          = "index.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.list_todos.output_path
    source_code_hash = data.archive_file.list_todos.output_base64sha256

    environment {
        variables = { TABLE_NAME = aws_dynamodb_table.todos.name }
    }
}

data "archive_file" "update_todo" {
    type        = "zip"
    source_file = "${path.module}/../src/lambda/update_todo/index.py"
    output_path = "${path.module}/../src/lambda/update_todo.zip"
}

resource "aws_lambda_function" "update_todo" {
    function_name    = "todo-api-update-todo"
    role             = aws_iam_role.lambda_exec.arn
    handler          = "index.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.update_todo.output_path
    source_code_hash = data.archive_file.update_todo.output_base64sha256

    environment {
        variables = { TABLE_NAME = aws_dynamodb_table.todos.name }
    }
}

data "archive_file" "delete_todo" {
    type        = "zip"
    source_file = "${path.module}/../src/lambda/delete_todo/index.py"
    output_path = "${path.module}/../src/lambda/delete_todo.zip"
}

resource "aws_lambda_function" "delete_todo" {
    function_name    = "todo-api-delete-todo"
    role             = aws_iam_role.lambda_exec.arn
    handler          = "index.handler"
    runtime          = "python3.12"
    filename         = data.archive_file.delete_todo.output_path
    source_code_hash = data.archive_file.delete_todo.output_base64sha256

    environment {
        variables = { TABLE_NAME = aws_dynamodb_table.todos.name }
    }
}

resource "aws_cognito_user_pool" "todo_users" {
    name = "todo-api-user-pool"

    password_policy {
        minimum_length    = 8
        require_uppercase = true
        require_numbers   = true
        require_symbols   = false
    }

    auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "todo_client" {
    name         = "todo-api-client"
    user_pool_id = aws_cognito_user_pool.todo_users.id

    explicit_auth_flows = [
        "ALLOW_USER_PASSWORD_AUTH",
        "ALLOW_REFRESH_TOKEN_AUTH"
    ]

    generate_secret = false
}

resource "aws_api_gateway_rest_api" "todo_api" {
    name = "todo-api"
}

resource "aws_api_gateway_authorizer" "cognito" {
    name          = "cognito-authorizer"
    rest_api_id   = aws_api_gateway_rest_api.todo_api.id
    type          = "COGNITO_USER_POOLS"
    provider_arns = [aws_cognito_user_pool.todo_users.arn]
}

resource "aws_api_gateway_resource" "todos" {
    rest_api_id = aws_api_gateway_rest_api.todo_api.id
    parent_id   = aws_api_gateway_rest_api.todo_api.root_resource_id
    path_part   = "todos"
}

resource "aws_api_gateway_resource" "todo_item" {
    rest_api_id = aws_api_gateway_rest_api.todo_api.id
    parent_id   = aws_api_gateway_resource.todos.id
    path_part   = "{todoId}"
}

# POST /todos → create
resource "aws_api_gateway_method" "create_todo" {
    rest_api_id   = aws_api_gateway_rest_api.todo_api.id
    resource_id   = aws_api_gateway_resource.todos.id
    http_method   = "POST"
    authorization = "COGNITO_USER_POOLS"
    authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "create_todo" {
    rest_api_id             = aws_api_gateway_rest_api.todo_api.id
    resource_id             = aws_api_gateway_resource.todos.id
    http_method             = aws_api_gateway_method.create_todo.http_method
    integration_http_method = "POST"
    type                    = "AWS_PROXY"
    uri                     = aws_lambda_function.create_todo.invoke_arn
}

# GET /todos → list
resource "aws_api_gateway_method" "list_todos" {
    rest_api_id   = aws_api_gateway_rest_api.todo_api.id
    resource_id   = aws_api_gateway_resource.todos.id
    http_method   = "GET"
    authorization = "COGNITO_USER_POOLS"
    authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "list_todos" {
    rest_api_id             = aws_api_gateway_rest_api.todo_api.id
    resource_id             = aws_api_gateway_resource.todos.id
    http_method             = aws_api_gateway_method.list_todos.http_method
    integration_http_method = "POST"
    type                    = "AWS_PROXY"
    uri                     = aws_lambda_function.list_todos.invoke_arn
}

# PUT /todos/{todoId} → update
resource "aws_api_gateway_method" "update_todo" {
    rest_api_id   = aws_api_gateway_rest_api.todo_api.id
    resource_id   = aws_api_gateway_resource.todo_item.id
    http_method   = "PUT"
    authorization = "COGNITO_USER_POOLS"
    authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "update_todo" {
    rest_api_id             = aws_api_gateway_rest_api.todo_api.id
    resource_id             = aws_api_gateway_resource.todo_item.id
    http_method             = aws_api_gateway_method.update_todo.http_method
    integration_http_method = "POST"
    type                    = "AWS_PROXY"
    uri                     = aws_lambda_function.update_todo.invoke_arn
}

# DELETE /todos/{todoId} → delete
resource "aws_api_gateway_method" "delete_todo" {
    rest_api_id   = aws_api_gateway_rest_api.todo_api.id
    resource_id   = aws_api_gateway_resource.todo_item.id
    http_method   = "DELETE"
    authorization = "COGNITO_USER_POOLS"
    authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "delete_todo" {
    rest_api_id             = aws_api_gateway_rest_api.todo_api.id
    resource_id             = aws_api_gateway_resource.todo_item.id
    http_method             = aws_api_gateway_method.delete_todo.http_method
    integration_http_method = "POST"
    type                    = "AWS_PROXY"
    uri                     = aws_lambda_function.delete_todo.invoke_arn
}

resource "aws_api_gateway_deployment" "todo_api" {
    rest_api_id = aws_api_gateway_rest_api.todo_api.id

    triggers = {
        redeployment = sha1(jsonencode([
            aws_api_gateway_resource.todos.id,
            aws_api_gateway_resource.todo_item.id,
            aws_api_gateway_method.create_todo.id,
            aws_api_gateway_method.list_todos.id,
            aws_api_gateway_method.update_todo.id,
            aws_api_gateway_method.delete_todo.id,
            aws_api_gateway_integration.create_todo.id,
            aws_api_gateway_integration.list_todos.id,
            aws_api_gateway_integration.update_todo.id,
            aws_api_gateway_integration.delete_todo.id,
        ]))
    }

    lifecycle {
        create_before_destroy = true
    }
}

resource "aws_api_gateway_stage" "prod" {
    deployment_id = aws_api_gateway_deployment.todo_api.id
    rest_api_id   = aws_api_gateway_rest_api.todo_api.id
    stage_name    = "prod"
}

resource "aws_lambda_permission" "create_todo" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.create_todo.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "list_todos" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.list_todos.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "update_todo" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.update_todo.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "delete_todo" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.delete_todo.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "${aws_api_gateway_rest_api.todo_api.execution_arn}/*/*"
}

output "api_url" {
    value = aws_api_gateway_stage.prod.invoke_url
}