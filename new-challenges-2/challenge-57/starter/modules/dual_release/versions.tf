terraform {
  # TODO 6: add the child Terraform and AWS version boundaries while retaining
  # both explicit configuration aliases.
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.90.0"
      configuration_aliases = [aws.primary, aws.replica]
    }
  }
}
