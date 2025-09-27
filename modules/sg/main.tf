resource "aws_security_group" "this" {
  name   = var.name
  vpc_id = var.vpc_id
  description = "Allow inbound traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # חוקים... (ingress/egress)

  tags = merge(
    { Name = var.name },
    var.tags
  )
}
}


