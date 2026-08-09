locals {
  use_fargate = var.compute_mode == "fargate" && local.deploy_app
  fargate_n   = local.use_fargate ? 1 : 0
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  count = local.fargate_n

  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc-${var.environment}" }
}

resource "aws_internet_gateway" "main" {
  count = local.fargate_n

  vpc_id = aws_vpc.main[0].id
  tags   = { Name = "${var.project}-igw-${var.environment}" }
}

resource "aws_subnet" "public" {
  count = local.use_fargate ? 2 : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  count = local.fargate_n

  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = { Name = "${var.project}-public-${var.environment}" }
}

resource "aws_route_table_association" "public" {
  count = local.use_fargate ? 2 : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_security_group" "service" {
  count = local.fargate_n

  name   = "${var.project}-service-${var.environment}"
  vpc_id = aws_vpc.main[0].id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "main" {
  count = local.fargate_n

  name = "${var.project}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_iam_role" "task_execution" {
  count = local.fargate_n

  name = "${var.project}-task-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  count = local.fargate_n

  role       = aws_iam_role.task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "fargate" {
  count = local.fargate_n

  name              = "/aws/ecs/${var.project}-portfolio-ms-${var.environment}"
  retention_in_days = var.app_log_retention_days
}

resource "aws_ecs_task_definition" "api" {
  count = local.fargate_n

  family                   = "${var.project}-portfolio-ms-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = aws_iam_role.task_execution[0].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "api"
    image     = "${local.persistent.ecr_repository_url}:${var.app_image_tag}"
    essential = true

    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]

    environment = [for k, v in local.app_environment : { name = k, value = v }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.fargate[0].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "api"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:3000/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
  }])
}

resource "aws_lb" "api" {
  count = local.fargate_n

  name               = "${var.project}-api-${var.environment}"
  internal           = true
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.service[0].id]
}

resource "aws_lb_target_group" "api" {
  count = local.fargate_n

  name        = "${var.project}-api-${var.environment}"
  port        = 3000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main[0].id

  health_check {
    path                = "/api/v1/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "api" {
  count = local.fargate_n

  load_balancer_arn = aws_lb.api[0].arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api[0].arn
  }
}

resource "aws_ecs_service" "api" {
  count = local.fargate_n

  name            = "${var.project}-portfolio-ms-${var.environment}"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.api[0].arn
  desired_count   = var.fargate_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.service[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api[0].arn
    container_name   = "api"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.api]
}

resource "aws_apigatewayv2_vpc_link" "fargate" {
  count = local.fargate_n

  name               = "${var.project}-fargate-${var.environment}"
  subnet_ids         = aws_subnet.public[*].id
  security_group_ids = [aws_security_group.service[0].id]
}
