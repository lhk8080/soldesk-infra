# destroy 순서: cleanup_k8s_resources 먼저 실행(Ingress/SVC 정리) → 노드그룹 → EKS 클러스터
# ALB Controller가 만든 LB·타겟그룹·ENI를 제거해야 VPC destroy가 성공한다.
resource "null_resource" "cleanup_k8s_resources" {
  triggers = {
    cluster_name = var.cluster_name
    region       = var.aws_region
    vpc_id       = var.vpc_id
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.app,
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    when        = destroy
    environment = {
      EKS_CLUSTER_NAME = self.triggers.cluster_name
      EKS_REGION       = self.triggers.region
      EKS_VPC_ID       = self.triggers.vpc_id
      AWS_PAGER        = ""
    }
    command = "tr -d '\\r' < \"${path.module}/scripts/cleanup_k8s_resources_on_destroy.sh\" | bash"
  }
}

# 노드그룹·클러스터 삭제 후 aws-k8s ENI 잔재를 한 번 더 정리.
# subnet 삭제가 ENI 때문에 막히는 상황을 줄이기 위함.
resource "null_resource" "cleanup_vpc_leftovers_post" {
  triggers = {
    region = var.aws_region
    vpc_id = var.vpc_id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    when        = destroy
    environment = {
      EKS_POST_REGION = self.triggers.region
      EKS_POST_VPC_ID = self.triggers.vpc_id
      AWS_PAGER       = ""
    }
    command = "tr -d '\\r' < \"${path.module}/scripts/cleanup_vpc_enis_post_eks_destroy.sh\" | bash"
  }
}
