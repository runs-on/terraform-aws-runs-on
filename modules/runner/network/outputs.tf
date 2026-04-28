output "network" {
  description = "Shared runner networking resources"
  value = {
    vpc_id             = var.vpc_id
    private_mode       = var.private_mode
    public_subnet_ids  = var.public_subnet_ids
    private_subnet_ids = var.private_subnet_ids
    security_group_ids = local.effective_security_group_ids
  }
}
