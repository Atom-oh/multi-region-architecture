resource "aws_lb" "this" {
  name               = var.name_override != "" ? var.name_override : "${var.environment}-api-nlb-${var.region}"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [var.security_group_id]
  subnets            = var.public_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name        = var.name_override != "" ? var.name_override : "${var.environment}-api-nlb-${var.region}"
    Environment = var.environment
  })
}

resource "aws_lb_target_group" "targets" {
  for_each = var.target_groups

  name        = each.value.name
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = var.health_check_port
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(var.tags, {
    Name        = each.value.name
    Environment = var.environment
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type = "forward"

    forward {
      dynamic "target_group" {
        for_each = var.target_groups
        content {
          arn    = aws_lb_target_group.targets[target_group.key].arn
          weight = target_group.value.weight
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_override != "" ? var.name_override : "${var.environment}-api-nlb-${var.region}"}-listener-http"
  })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type = "forward"

    forward {
      dynamic "target_group" {
        for_each = var.target_groups
        content {
          arn    = aws_lb_target_group.targets[target_group.key].arn
          weight = target_group.value.weight
        }
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name_override != "" ? var.name_override : "${var.environment}-api-nlb-${var.region}"}-listener-https"
  })
}
