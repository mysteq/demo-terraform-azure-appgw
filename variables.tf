variable "storage_account_count" {
  description = "Number of storage accounts to create"
  type        = number
  default     = 10
}

variable "domain" {
  description = "Domain name to use"
  type        = string
  default     = "azure.demo.techie.cloud"
}

variable "domain_rg" {
  description = "Resource group that domain resides in"
  type        = string
  default     = "bad-p-rg-techie.cloud-01"
}

variable "name" {
  description = "Name to use as prefix"
  type        = string
  default     = "demoazureappgw"
}
