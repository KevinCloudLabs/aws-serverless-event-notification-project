variable "aws_region" {
  default = "us-west-1"
}

variable "project_name" {
  default = "events-system"
}

variable "subscriber_email" {
  description = "Email address to receive event notifications"
  type        = string
}
