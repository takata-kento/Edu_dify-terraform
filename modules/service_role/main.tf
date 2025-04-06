data "aws_iam_policy_document" "trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = var.identifiers
    }
  }
}

data "aws_iam_policy_document" "policy" {
  count = length(var.policy_map)

  statement {
    actions   = var.policy_map[count.index].actions
    resources = var.policy_map[count.index].resources
  }
}

resource "aws_iam_role" "main" {
  name               = var.role_name
  description        = var.role_description
  assume_role_policy = data.aws_iam_policy_document.trust_policy.json
}

resource "aws_iam_role_policy" "main" {
  count = length(var.policy_map)

  role   = aws_iam_role.main.id
  name   = var.policy_map[count.index].policy_name
  policy = data.aws_iam_policy_document.policy[count.index].json
}
