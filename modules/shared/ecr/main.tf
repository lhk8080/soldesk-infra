resource "aws_ecr_repository" "ticketing_was" {
  name                 = "ticketing/ticketing-was"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "ecr-ticketing-was", Environment = var.env }
}

resource "aws_ecr_repository" "worker_svc" {
  name                 = "ticketing/worker-svc"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "ecr-worker-svc", Environment = var.env }
}
