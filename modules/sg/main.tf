resource "aws_security_group" "this" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  # ⚠️ זה פותח את כל התעבורה פנימה מכל העולם — לא מומלץ לפרוד!
  ingress {
    description = "All inbound (NOT SAFE for prod)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # כל התעבורה החוצה
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    { Name = var.name },
    try(var.tags, {})  # אם var.tags לא הוגדר – נופל חזרה ל-{}
  )
}
