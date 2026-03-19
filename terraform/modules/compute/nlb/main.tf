resource "aws_lb" "this" {
  name               = "${var.environment}-api-nlb-${var.region}"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [var.security_group_id]
  subnets            = var.public_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = merge(var.tags, {
    Name        = "${var.environment}-api-nlb-${var.region}"
    Environment = var.environment
  })
}

resource "aws_lb_target_group" "this" {
  name        = "${var.environment}-api-tg-${var.region}"
  port        = 80
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-api-tg-${var.region}"
    Environment = var.environment
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-api-listener-http-${var.region}"
  })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-api-listener-https-${var.region}"
  })
}
