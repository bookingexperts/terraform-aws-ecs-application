resource "aws_lb_listener_rule" "wildcard" {
  listener_arn = var.load_balancers.listener.arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  condition {
    host_header {
      values = [local.hostname, local.wildcard]
    }
  }
}
