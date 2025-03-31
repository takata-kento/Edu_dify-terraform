data "aws_caller_identity" "current" {}
data "aws_vpc" "current" {
  id = var.vpc_id
}

####################################################################################################
# S3 Bucket for Dify Storage

resource "aws_s3_bucket" "main" {
  bucket = var.dify_storage_bucket
}

####################################################################################################
# redis resources

module "sg_for_redis" {
  source = "./modules/securitygroup"

  name        = "dify-redis"
  description = "Security group for Dify Redis"
  vpc_id      = var.vpc_id
  rules = [
    {
      description              = "API to Redis"
      type                     = "ingress"
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = module.sg_for_api.security_group_id
    },
    {
      description              = "Worker to Redis"
      type                     = "ingress"
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      source_security_group_id = module.sg_for_worker.security_group_id
    }
  ]
}

resource "random_password" "redis_for_dify" {
  length  = 24
  special = false
}

module "secret_redis_password" {
  source = "./modules/secrets"

  name         = "dify-redis-password"
  secret_value = random_password.redis_for_dify.result
}

module "redis_for_dify" {
  source = "./modules/redis"

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.sg_for_redis.security_group_id]
  redis_password     = random_password.redis_for_dify.result
}

module "secret_broker_url" {
  source = "./modules/secrets"

  name         = "dify-redis-broker-url"
  secret_value = "redis://${resource.random_password.redis_for_dify.result}@${module.redis_for_dify.primary_endpoint_address}:6379/0"
}

####################################################################################################
# rds resources

module "sg_for_postgres" {
  source = "./modules/securitygroup"

  name        = "dify-db"
  description = "Security group for Dify DB"
  vpc_id      = var.vpc_id
  rules = [
    {
      description = "Internet"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "all"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description              = "API to DB"
      type                     = "ingress"
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = module.sg_for_api.security_group_id
    },
    {
      description              = "Worker to DB"
      type                     = "ingress"
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      source_security_group_id = module.sg_for_worker.security_group_id
    }
  ]
}

resource "random_password" "postgres_for_dify" {
  length  = 24
  special = false
}

module "secret_db_password" {
  source = "./modules/secrets"

  name         = "dify-db-password-1"
  secret_value = random_password.postgres_for_dify.result
}

module "postgres_for_dify" {
  source = "./modules/rds"

  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.sg_for_postgres.security_group_id]
  db_master_password = random_password.postgres_for_dify.result
}

####################################################################################################
# alb

module "sg_for_alb" {
  source = "./modules/securitygroup"

  vpc_id      = var.vpc_id
  name        = "dify-alb"
  description = "Security group for Dify ALB"
  rules = [
    {
      description = "ALB to TargetGroup"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "all"
      cidr_blocks = [data.aws_vpc.current.cidr_block]
    },
    {
      description = "HTTP from Internet"
      type        = "ingress"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  ]
}

resource "aws_lb" "main" {
  name               = "dify-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [module.sg_for_alb.security_group_id]
}

resource "aws_lb_target_group" "web" {
  name        = "dify-web"
  vpc_id      = var.vpc_id
  protocol    = "HTTP"
  port        = 3000
  target_type = "ip"

  slow_start           = 0
  deregistration_delay = 65

  health_check {
    path     = "/apps"
    interval = 10
  }
}

resource "aws_lb_target_group" "api" {
  name        = "dify-api"
  vpc_id      = var.vpc_id
  protocol    = "HTTP"
  port        = 5001
  target_type = "ip"

  slow_start           = 0
  deregistration_delay = 65

  health_check {
    path     = "/health"
    interval = 10
  }
}

module "dify_alb_listener" {
  source = "./modules/alb_listener"

  alb_arn                  = aws_lb.main.arn
  default_target_group_arn = aws_lb_target_group.web.arn
  forwarding_settings = [
    {
      priority         = 10
      path_patterns    = ["/console/api", "/api", "/v1", "/files"]
      target_group_arn = aws_lb_target_group.api.arn
    },
    {
      priority         = 11
      path_patterns    = ["/console/api/*", "/api/*", "/v1/*", "/files/*"]
      target_group_arn = aws_lb_target_group.api.arn
    }
  ]
}

####################################################################################################
# ecs cluster

resource "aws_ecs_cluster" "main" {
  name = "dify-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

####################################################################################################
# common ecs execution role

module "ecs_execution_role" {
  source = "./modules/service_role"

  role_name        = "dify-ecs-execution-role"
  role_description = "IAM role for ECS task execution"
  identifiers      = ["ecs-tasks.amazonaws.com"]
  policy_map = [
    {
      policy_name = "get-ssm-parameter"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      resources = ["arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/*"]
    },
    {
      policy_name = "get-secret"
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      resources = ["arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:*"]
    },
    {
      policy_name = "task-execution"
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = ["*"]
    }
  ]
}

####################################################################################################
# ecs api task resources

resource "random_password" "sandbox_key" {
  length           = 42
  special          = true
  override_special = "%&-_=+:/"
}

resource "random_password" "session_secret_key" {
  length           = 42
  special          = true
  override_special = "-_=+/"
}

module "secret_sandbox_key" {
  source = "./modules/secrets"

  name         = "dify-sandbox-key"
  secret_value = random_password.sandbox_key.result
}

module "secret_session_key" {
  source = "./modules/secrets"

  name         = "dify-session-key"
  secret_value = random_password.session_secret_key.result
}

module "ecs_api_task_role" {
  source = "./modules/service_role"

  role_name        = "dify-ecs-api-task-role"
  role_description = "IAM role for ECS api task"
  identifiers      = ["ecs-tasks.amazonaws.com"]
  policy_map = [
    {
      policy_name = "s3-listbucket"
      actions = [
        "s3:ListBucket"
      ]
      resources = [aws_s3_bucket.main.arn]
    },
    {
      policy_name = "s3-updateobject"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ]
      resources = ["${aws_s3_bucket.main.arn}/*"]
    },
    {
      policy_name = "invoke-bedrock"
      actions = [
        "bedrock:InvokeModel"
      ]
      resources = ["arn:aws:bedrock:*::foundation-model/*"]
    },
    {
      policy_name = "api-logs"
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:PutLogEvents",
        "xray:PutTelemetryRecords",
        "xray:PutTraceSegments",
      ]
      resources = ["*"]
    }
  ]
}

module "dify_api" {
  source = "./modules/ecs"

  family_name        = "dify-api"
  execution_role_arn = module.ecs_execution_role.role_arn
  task_role_arn      = module.ecs_api_task_role.role_arn
  volume_name        = "dependencies"
  container_definitions = [
    {
      name      = "dify-api"
      image     = "langgenius/dify-api:${var.dify_api_version}"
      essential = true
      portMappings = [
        {
          hostPort      = 5001
          protocol      = "tcp"
          containerPort = 5001
        }
      ]
      environment = [
        for name, value in {
          # Startup mode, 'api' starts the API server.
          MODE = "api"
          # The log level for the application. Supported values are `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`
          LOG_LEVEL = "INFO"
          # enable DEBUG mode to output more logs
          # DEBUG  = "true"
          # The base URL of console application web frontend, refers to the Console base URL of WEB service if console domain is
          # different from api or web app domain.
          # example: http://cloud.dify.ai
          CONSOLE_WEB_URL = "http://${aws_lb.main.dns_name}"
          # The base URL of console application api server, refers to the Console base URL of WEB service if console domain is different from api or web app domain.
          # example: http://cloud.dify.ai
          CONSOLE_API_URL = "http://${aws_lb.main.dns_name}"
          # The URL prefix for Service API endpoints, refers to the base URL of the current API service if api domain is different from console domain.
          # example: http://api.dify.ai
          SERVICE_API_URL = "http://${aws_lb.main.dns_name}"
          # The URL prefix for Web APP frontend, refers to the Web App base URL of WEB service if web app domain is different from console or api domain.
          # example: http://udify.app
          APP_WEB_URL = "http://${aws_lb.main.dns_name}"
          # When enabled, migrations will be executed prior to application startup and the application will start after the migrations have completed.
          MIGRATION_ENABLED = false
          # The configurations of postgres database connection.
          # It is consistent with the configuration in the 'db' service below.
          DB_USERNAME = "dify_user"
          DB_HOST     = module.postgres_for_dify.endpoint
          DB_PORT     = module.postgres_for_dify.port
          DB_DATABASE = "dify_db"
          # The configurations of redis connection.
          # It is consistent with the configuration in the 'redis' service below.
          REDIS_HOST    = module.redis_for_dify.primary_endpoint_address
          REDIS_PORT    = module.redis_for_dify.port
          REDIS_USE_SSL = true
          # use redis db 0 for redis cache
          REDIS_DB = 0
          # Specifies the allowed origins for cross-origin requests to the Web API, e.g. https://dify.app or * for all origins.
          WEB_API_CORS_ALLOW_ORIGINS = "*"
          # Specifies the allowed origins for cross-origin requests to the console API, e.g. https://cloud.dify.ai or * for all origins.
          CONSOLE_CORS_ALLOW_ORIGINS = "*"
          # CSRF Cookie settings
          # Controls whether a cookie is sent with cross-site requests,
          # providing some protection against cross-site request forgery attacks
          #
          # Default = `SameSite=Lax, Secure=false, HttpOnly=true`
          # This default configuration supports same-origin requests using either HTTP or HTTPS,
          # but does not support cross-origin requests. It is suitable for local debugging purposes.
          #
          # If you want to enable cross-origin support,
          # you must use the HTTPS protocol and set the configuration to `SameSite=None, Secure=true, HttpOnly=true`.
          #
          # The type of storage to use for storing user files. Supported values are `local` and `s3` and `azure-blob` and `google-storage`, Default = `local`
          STORAGE_TYPE = "s3"
          # The S3 storage configurations, only available when STORAGE_TYPE is `s3`.
          S3_USE_AWS_MANAGED_IAM = true
          S3_BUCKET_NAME         = aws_s3_bucket.main.bucket
          S3_REGION              = "ap-northeast-1"
          # The type of vector store to use. Supported values are `weaviate`, `qdrant`, `milvus`, `relyt`.
          VECTOR_STORE = "pgvector"
          # pgvector configurations
          PGVECTOR_HOST     = module.postgres_for_dify.endpoint
          PGVECTOR_PORT     = module.postgres_for_dify.port
          PGVECTOR_USER     = "dify_user"
          PGVECTOR_DATABASE = "dify_db"
          # # Mail configuration, support = resend, smtp
          # MAIL_TYPE = ''
          # # default send from email address, if not specified
          # MAIL_DEFAULT_SEND_FROM = 'YOUR EMAIL FROM (eg = no-reply <no-reply@dify.ai>)'
          # SMTP_SERVER = ''
          # SMTP_PORT = 587
          # SMTP_USERNAME = ''
          # SMTP_PASSWORD = ''
          # SMTP_USE_TLS = 'true'
          # The sandbox service endpoint.
          CODE_EXECUTION_ENDPOINT       = "http://localhost:8194" # Fargate の task 内通信は localhost 宛
          CODE_MAX_NUMBER               = "9223372036854775807"
          CODE_MIN_NUMBER               = "-9223372036854775808"
          CODE_MAX_STRING_LENGTH        = 80000
          TEMPLATE_TRANSFORM_MAX_LENGTH = 80000
          CODE_MAX_STRING_ARRAY_LENGTH  = 30
          CODE_MAX_OBJECT_ARRAY_LENGTH  = 30
          CODE_MAX_NUMBER_ARRAY_LENGTH  = 1000
          # Indexing configuration
          INDEXING_MAX_SEGMENTATION_TOKENS_LENGTH = 1000
        } : { name = name, value = tostring(value) }
      ]
      secrets = [
        {
          name      = "SECRET_KEY"
          valueFrom = module.secret_session_key.secret_arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = module.secret_db_password.secret_arn
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = module.secret_redis_password.secret_arn
        },
        # The configurations of celery broker.
        # Use redis as the broker, and redis db 1 for celery broker.
        {
          name      = "CELERY_BROKER_URL"
          valueFrom = module.secret_broker_url.secret_arn
        },
        {
          name      = "PGVECTOR_PASSWORD"
          valueFrom = module.secret_db_password.secret_arn
        },
        {
          name      = "CODE_EXECUTION_API_KEY"
          valueFrom = module.secret_sandbox_key.secret_arn
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5001/health || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      cpu         = 0
      volumesFrom = []
      mountPoints = []
    },
    // `dify-sandbox:0.2.6` では `/dependencies/python-requirements.txt` が存在しないと起動時エラーになる。
    // そのため、簡易的ではあるが volume を利用して sandbox から見れるファイルを作成する。
    {
      name      = "dify-sandbox-dependencies"
      image     = "busybox:latest" # dify-sandbox イメージより軽量ならなんでもいい
      essential = false
      cpu       = 0
      mountPoints = [
        {
          sourceVolume  = "dependencies"
          containerPath = "/dependencies"
        }
      ]
      entryPoint = ["sh", "-c"]
      command    = ["touch /dependencies/python-requirements.txt && chmod 755 /dependencies/python-requirements.txt"]
    },
    {
      name      = "dify-sandbox"
      image     = "langgenius/dify-sandbox:${var.dify_sandbox_version}"
      essential = true
      mountPoints = [
        {
          sourceVolume  = "dependencies"
          containerPath = "/dependencies"
        }
      ]
      portMappings = [
        {
          hostPort      = 8194
          protocol      = "tcp"
          containerPort = 8194
        }
      ]
      environment = [
        for name, value in {
          GIN_MODE       = "release"
          WORKER_TIMEOUT = 15
          ENABLE_NETWORK = true
          SANDBOX_PORT   = 8194
        } : { name = name, value = tostring(value) }
      ]
      secrets = [
        {
          name      = "API_KEY"
          valueFrom = module.secret_sandbox_key.secret_arn
        }
      ]
      cpu         = 0
      volumesFrom = []
    }
  ]
  ecs_cluster_name   = aws_ecs_cluster.main.name
  desired_count      = 1
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.sg_for_api.security_group_id]
  load_balancer_setting = {
    target_group_arn = aws_lb_target_group.api.arn
    container_port   = 5001
  }
}

module "sg_for_api" {
  source = "./modules/securitygroup"

  name        = "dify-api"
  description = "Security group for Dify API"
  vpc_id      = var.vpc_id
  rules = [
    {
      description = "Internet"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "all"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description              = "ALB to API"
      type                     = "ingress"
      from_port                = 5001
      to_port                  = 5001
      protocol                 = "tcp"
      source_security_group_id = module.sg_for_alb.security_group_id
    }
  ]
}

####################################################################################################
# ecs worker task resources

module "dify_worker" {
  source = "./modules/ecs"

  family_name        = "dify-worker"
  execution_role_arn = module.ecs_execution_role.role_arn
  task_role_arn      = module.ecs_api_task_role.role_arn
  container_definitions = [
    {
      name      = "dify-worker"
      image     = "langgenius/dify-api:${var.dify_api_version}"
      essential = true
      environment = [
        for name, value in {
          # Startup mode, 'worker' starts the Celery worker for processing the queue.
          MODE = "worker"

          # --- All the configurations below are the same as those in the 'api' service. ---

          # The log level for the application. Supported values are `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`
          LOG_LEVEL = "INFO"
          # The configurations of postgres database connection.
          # It is consistent with the configuration in the 'db' service below.
          DB_USERNAME = "dify_user"
          DB_HOST     = module.postgres_for_dify.endpoint
          DB_PORT     = module.postgres_for_dify.port
          DB_DATABASE = "dify_db"
          # The configurations of redis cache connection.
          REDIS_HOST    = module.redis_for_dify.primary_endpoint_address
          REDIS_PORT    = module.redis_for_dify.port
          REDIS_DB      = "0"
          REDIS_USE_SSL = "true"
          # The type of storage to use for storing user files. Supported values are `local` and `s3` and `azure-blob` and `google-storage`, Default = `local`
          STORAGE_TYPE = "s3"
          # The S3 storage configurations, only available when STORAGE_TYPE is `s3`.
          S3_USE_AWS_MANAGED_IAM = true
          S3_BUCKET_NAME         = aws_s3_bucket.main.bucket
          S3_REGION              = "ap-northeast-1"
          # The type of vector store to use. Supported values are `weaviate`, `qdrant`, `milvus`, `relyt`, `pgvector`.
          VECTOR_STORE = "pgvector"
          # pgvector configurations
          PGVECTOR_HOST     = module.postgres_for_dify.endpoint
          PGVECTOR_PORT     = module.postgres_for_dify.port
          PGVECTOR_USER     = "dify_user"
          PGVECTOR_DATABASE = "dify_db"
          # Mail configuration, support = resend
          # MAIL_TYPE = ''
          # # default send from email address, if not specified
          # MAIL_DEFAULT_SEND_FROM = 'YOUR EMAIL FROM (eg = no-reply <no-reply@dify.ai>)'
          # SMTP_SERVER = ''
          # SMTP_PORT = 587
          # SMTP_USERNAME = ''
          # SMTP_PASSWORD = ''
          # SMTP_USE_TLS = 'true'
          # Indexing configuration
          INDEXING_MAX_SEGMENTATION_TOKENS_LENGTH = "1000"
        } : { name = name, value = tostring(value) }
      ]
      secrets = [
        {
          name      = "SECRET_KEY"
          valueFrom = module.secret_session_key.secret_arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = module.secret_db_password.secret_arn
        },
        {
          name      = "REDIS_PASSWORD"
          valueFrom = module.secret_redis_password.secret_arn
        },
        # The configurations of celery broker.
        # Use redis as the broker, and redis db 1 for celery broker.
        {
          name      = "CELERY_BROKER_URL"
          valueFrom = module.secret_broker_url.secret_arn
        },
        {
          name      = "PGVECTOR_PASSWORD"
          valueFrom = module.secret_db_password.secret_arn
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:5001/health || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }
      cpu         = 0
      volumesFrom = []
      mountPoints = []
    }
  ]
  ecs_cluster_name   = aws_ecs_cluster.main.name
  desired_count      = 1
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.sg_for_worker.security_group_id]
}

module "sg_for_worker" {
  source = "./modules/securitygroup"

  name        = "dify-worker"
  description = "Security group for Dify Worker"
  vpc_id      = var.vpc_id
  rules = [
    {
      description = "Internet"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "all"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

####################################################################################################
# ecs web task resources

module "ecs_web_task_role" {
  source = "./modules/service_role"

  role_name        = "dify-ecs-web-task-role"
  role_description = "IAM role for ECS web task"
  identifiers      = ["ecs-tasks.amazonaws.com"]
  policy_map = [
    {
      policy_name = "api-logs"
      actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:PutLogEvents",
        "xray:PutTelemetryRecords",
        "xray:PutTraceSegments",
      ]
      resources = ["*"]
    }
  ]
}

module "dify_web" {
  source = "./modules/ecs"

  family_name        = "dify-web"
  execution_role_arn = module.ecs_execution_role.role_arn
  task_role_arn      = module.ecs_web_task_role.role_arn
  container_definitions = [
    {
      name      = "dify-web"
      image     = "langgenius/dify-web:${var.dify_web_version}"
      essential = true
      environment = [
        for name, value in {
          # The base URL of console application api server, refers to the Console base URL of WEB service if console domain is
          # different from api or web app domain.
          # example: http://cloud.dify.ai
          CONSOLE_API_URL = "http://${aws_lb.main.dns_name}"
          # # The URL for Web APP api server, refers to the Web App base URL of WEB service if web app domain is different from
          # # console or api domain.
          # # example: http://udify.app
          APP_API_URL             = "http://${aws_lb.main.dns_name}"
          NEXT_TELEMETRY_DISABLED = "0"
        } : { name = name, value = tostring(value) }
      ]
      portMappings = [
        {
          hostPort      = 3000
          protocol      = "tcp"
          containerPort = 3000
        }
      ]
      cpu         = 0
      volumesFrom = []
      mountPoints = []
    }
  ]
  ecs_cluster_name   = aws_ecs_cluster.main.name
  desired_count      = 1
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.sg_for_web.security_group_id]
  load_balancer_setting = {
    target_group_arn = aws_lb_target_group.web.arn
    container_port   = 3000
  }
}

module "sg_for_web" {
  source = "./modules/securitygroup"

  name        = "dify-web"
  description = "Security group for Dify Web"
  vpc_id      = var.vpc_id
  rules = [
    {
      description = "Internet"
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "all"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description              = "ALB to Web"
      type                     = "ingress"
      from_port                = 3000
      to_port                  = 3000
      protocol                 = "tcp"
      source_security_group_id = module.sg_for_alb.security_group_id
    }
  ]
}
