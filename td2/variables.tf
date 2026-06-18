variable "student_id" {
  description = "Numero d etudiant (0-99) : noms et CIDR uniques"
  type        = number
}

variable "my_ip" {
  description = "Votre IP publique en /32"
  type        = string
}

variable "key_name" {
  description = "Nom de la paire de cles EC2"
  type        = string
}
