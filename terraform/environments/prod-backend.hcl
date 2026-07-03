bucket         = "devops-platform-tfstate-prod"
key            = "eks/prod/terraform.tfstate"
region         = "ap-southeast-1"
dynamodb_table = "devops-platform-tfstate-lock-prod"
encrypt        = true
