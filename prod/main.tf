############################################
# --- ECR (מאגרי תמונות) ---
############################################
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.ecr_repo_names)
  name     = each.key
  image_scanning_configuration { scan_on_push = true }
  tags = var.tags
}

output "ecr_urls" {
  value = [for r in aws_ecr_repository.repos : r.repository_url]
}

############################################
# --- VPC (מודול רשמי) ---
############################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "prod-vpc"
  cidr            = var.vpc_cidr
  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = var.tags
}

############################################
# --- SG (מודול מקומי שלך) ---
############################################
module "sg" {
  source = "../modules/sg"
  vpc_id = module.vpc.vpc_id
  name   = "prod-sg"
  tags   = var.tags
}

############################################
# --- EKS (קלאסטר מנוהל + IRSA) ---
############################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets   # במודול הרשמי זה מחזיר IDs

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      instance_types = var.node_instance_types
    }
  }

  tags = var.tags
}

############################################
# --- חיבור פרוביידרים ל-EKS (k8s/helm) ---
############################################
data "aws_eks_cluster" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

############################################
# --- Add-on: EBS CSI (אחסון מתמשך ל-PVC) ---
############################################
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  depends_on   = [module.eks]
}

############################################
# --- ניטור: kube-prometheus-stack (Helm) ---
############################################
resource "helm_release" "kube_prom_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  # version        = "57.2.0"
  namespace        = "monitoring"
  create_namespace = true

  values = [yamlencode({
    grafana = {
      adminPassword = var.grafana_admin_password
      service = {
        type = "LoadBalancer"  # להתחלה; ל-HTTPS עדיף Ingress + ALB
      }
    }
    prometheus = {
      prometheusSpec = {
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes      = ["ReadWriteOnce"]
              storageClassName = var.storage_class_name
              resources = { requests = { storage = var.prometheus_storage_size } }
            }
          }
        }
      }
    }
  })]

  depends_on = [module.eks, aws_eks_addon.ebs_csi]
}

output "grafana_service_hint" {
  value = "Run: kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana"
}

############################################
# --- דוגמת פריסה לאפליקציה (Helm מקומית) ---
############################################
resource "helm_release" "app" {
  name             = "app"
  chart            = "${path.module}/../charts/app"
  namespace        = "apps"
  create_namespace = true
  depends_on       = [module.eks]
}

############################################
# --- אופציונלי: AWS Load Balancer Controller (ALB) ---
############################################
resource "helm_release" "alb_controller" {
  count      = var.enable_alb_controller ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [module.eks]
}
