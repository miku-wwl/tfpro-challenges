variable "role" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "peer_topic_arn" {
  type     = string
  nullable = true
}

variable "expected_peer_role" {
  type     = string
  nullable = true
}

