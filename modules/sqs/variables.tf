variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# How many times SQS will hand a message to a consumer before giving up
# and routing it to the Dead Letter Queue instead. Prevents a single bad
# message (e.g. one that crashes the worker every time) from blocking the
# whole queue forever - after this many failed attempts, it's set aside.
variable "max_receive_count" {
  description = "Number of failed processing attempts before a message goes to the DLQ"
  type        = number
  default     = 5
}

# How long a consumer gets to process a message before SQS assumes it
# failed and makes the message visible to other consumers again. Should
# be longer than your worker's typical processing time - too short and
# a slow-but-successful job gets retried and processed twice.
variable "visibility_timeout_seconds" {
  description = "Time a message is hidden from other consumers while one worker processes it"
  type        = number
  default     = 30
}

# How long SQS retains a message if nothing ever consumes it. After this,
# it's deleted permanently, even from the DLQ.
variable "message_retention_seconds" {
  description = "How long unconsumed messages are kept before permanent deletion"
  type        = number
  default     = 345600 # 4 days
}
