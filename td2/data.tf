data "aws_vpc" "default" {
  default = true # le VPC par defaut (172.31.0.0/16)
}

data "aws_subnet" "public_a" {
  # Les sous-reseaux "par defaut" (default_for_az) ont ete supprimes dans ce
  # VPC partage : on cible donc directement le sous-reseau public restant,
  # confirme public car sa route table associee a une route 0.0.0.0/0 -> IGW.
  id = "subnet-095c2c562da7511cc"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

locals {
  prefix = "td2-${var.student_id}"
}
