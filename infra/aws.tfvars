# AWS Environment Configuration
environment              = "aws"
region                   = "us-west-2"
visibility_timeout       = 30
message_retention_period = 3600
receive_wait_time        = 20
payment_sim_seconds      = 3
processor_concurrency    = 2
create_alb               = true

# Lab-provided IAM role
lab_role_arn                  = "arn:aws:iam::211125751164:role/LabRole"
ecs_task_execution_role_arn   = "arn:aws:iam::211125751164:role/LabRole"
ecs_task_role_arn             = "arn:aws:iam::211125751164:role/LabRole"
