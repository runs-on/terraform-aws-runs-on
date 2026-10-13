variable "base_url" {
  description = "Raw GitHub web or API URL as configured by the customer. Leave empty for github.com."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.base_url) == "" || startswith(lower(trimspace(var.base_url)), "https://")
    error_message = "The GitHub URL must be empty or use https://."
  }
}
