variable "team_name" {
  description = "Short lowercase team name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.team_name))
    error_message = "Use 3-31 lowercase letters, numbers, or hyphens."
  }
}

variable "enable_kv" {
  description = "Create the team's KV v2 secrets engine."
  type        = bool
  default     = true
}