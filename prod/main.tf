############################################
# --- ECR (מאגרי תמונות) ---
############################################
# יוצר רפוזיטוריז לפי הרשימה var.ecr_repo_names (מוגדרת ב-variables.tf)
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
# --- VPC (מהמודול שלך) ---
############################################
module "vpc" {
  source         = "../modules/vpc"  # עדכני אם שם התיקייה שונה
  cidr           = var.vpc_cidr
  name           = "prod-vpc"
  public_subnets = var.public_subnets
  private_subnets = var.private_subnets   # ← ודאי שהמודול שלך תומך בפרייבט
  azs            = var.azs
  tags           = var.tags
}

############################################
# --- SG (מהמודול שלך) ---
############################################
module "sg" {
  source        = "../modules/sg"
  vpc_id        = module.vpc.vpc_id
  name          = "prod-sg"
  allowed_ports = var.allowed_ports
  tags          = var.tags
}

############################################
# --- (אופציונלי) EC2 (מיותר ל-EKS) ---
############################################
# אם את עוברת ל-EKS אין צורך ב-EC2 הזה. השארתי כאן כהערה לנוחות:
#
# data "aws_ami" "al2023" {
#   most_recent = true
#   owners      = ["amazon"]
#   filter { name = "name"; values = ["al2023-ami-*-x86_64"] }
#   filter { name = "architecture"; values = ["x86_64"] }
# }
#
# module "ec2" {
#   source        = "../modules/ec2"
#   name          = var.name
#   ami           = data.aws_ami.al2023.id
#   instance_type = var.instance_type
#   subnet_id     = module.vpc.public_subnet_ids[0]  # ← ודאי שזה האאוטפוט הנכון
#   sg_id         = module.sg.sg_id
#   depends_on    = [module.vpc, module.sg]
# }

############################################
# --- EKS (קלאסטר מנוהל + IRSA) ---
############################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  # ודאי שלמודול VPC שלך יש אאוטפוט בשם private_subnet_ids:
  subnet_ids = module.vpc.private_subnet_ids   # ← עדכני אם השם שונה אצלך

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      instance_types = var.node_instance_types
      # אפשר להוסיף labels/taints/volume size וכו'
    }
  }

  tags = var.tags
}

############################################
# --- חיבור פרוביידרים ל-EKS (k8s/helm) ---
############################################
# לא נוגעים ב-provider "aws" הקיים אצלך; כאן רק חיבור ל-API של הקלאסטר.
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
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
# מתקין Prometheus Operator + Prometheus + Grafana.
# כאן values inline דרך yamlencode כדי שלא תצטרכי קובץ חיצוני.
resource "helm_release" "kube_prom_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  # version        = "57.2.0"  # אפשר לנעול גרסה
  namespace        = "monitoring"
  create_namespace = true

  values = [yamlencode({
    grafana = {
      adminPassword = var.grafana_admin_password
      service = {
        type = "LoadBalancer"   # להתחלה: NLB פשוט. ל-HTTPS/דומיין העדיפי Ingress+ALB.
      }
    }
    prometheus = {
      prometheusSpec = {
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes      = ["ReadWriteOnce"]
              storageClassName = var.storage_class_name
              resources = {
                requests = { storage = var.prometheus_storage_size }
              }
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
resource "helm_release" "app" {
  name             = "app"
  chart            = "${path.module}/../charts/app"
  namespace        = "apps"
  create_namespace = true

  # אם תרצי לעדכן tag בלי לערוך קבצים, אפשר להעביר values כאן:
  # set {
  #   name  = "image.tag"
  #   value = "a1b2c3d4"  # למשל sha חדש מה-CD
  # }

  depends_on = [module.eks]
}

############################################
# --- אופציונלי: AWS Load Balancer Controller (ALB) ---
############################################
# הפעילי דרך var.enable_alb_controller=true אם תרצי Ingress עם ALB/HTTPS/חוקים.
resource "helm_release" "alb_controller" {
  count      = var.enable_alb_controller ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
name = "clusterName"
value = var.cluster_name
}
  set {
name = "region"
value = var.region 
}
  set { 
name = "vpcId"  
value = module.vpc.vpc_id
}

  depends_on = [module.eks]
}
