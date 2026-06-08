variable "pve_endpoint" {
  type        = string
  description = "Proxmox API URL, e.g. https://pve01:8006/"
}

variable "pve_api_token" {
  type        = string
  description = "API token in the form 'user@realm!tokenid=uuid'"
  sensitive   = true
}

variable "pve_node" {
  type        = string
  description = "Proxmox node name"
  default     = "pve01"
}
