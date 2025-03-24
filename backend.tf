terraform {
  backend "s3" {
    bucket = "edu-dify-terraform"
    key    = "dify-infra/terraform.tfstate"
    region = "ap-northeast-1"
  }
}
