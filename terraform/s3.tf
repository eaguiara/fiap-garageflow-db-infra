resource "aws_s3_bucket" "terraform_state" {
  bucket_prefix = "garage-flow-terraform-state-"
}
