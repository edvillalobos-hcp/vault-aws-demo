resource "aws_kms_key" "vault" {
  description             = "Vault unseal key"
  deletion_window_in_days = 10
  tags = {
     Name = "vault-kms-unseal-${var.prefix}"
    }
}