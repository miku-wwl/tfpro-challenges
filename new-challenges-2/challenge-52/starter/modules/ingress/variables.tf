variable "run_id" { type = string }
variable "vpc_id" { type = string }

variable "rules" {
  type = map(object({
    description = string
    protocol    = string
    from_port   = number
    to_port     = number
    cidr        = string
  }))
}
