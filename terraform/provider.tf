provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "ai-incident-intelligence"
      ManagedBy   = "Terraform"
      Environment = "portfolio"
    }
  }
}
