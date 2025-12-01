// Security groups
resource "aws_security_group" "ecs_sg" {
  count  = var.create_vpc ? 1 : 0
  name   = "ecs-sg"
  vpc_id = aws_vpc.main[0].id

  ingress {
    description = "Container port from ALB"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb_sg" {
  count  = var.create_alb ? 1 : 0
  name   = "alb-sg"
  vpc_id = aws_vpc.main[0].id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
