data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "sonde" {
  name   = "${local.prefix}-sg-sonde"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description     = "SSH depuis le bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "ICMP depuis le bastion"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "sonde" {
  ami                          = data.aws_ami.ubuntu.id
  instance_type                = "t3.micro"
  subnet_id                    = data.aws_subnet.public_a.id
  vpc_security_group_ids       = [aws_security_group.sonde.id]
  associate_public_ip_address  = true
  key_name                     = var.key_name

  user_data = <<-EOT
    #!/bin/bash
    add-apt-repository -y ppa:oisf/suricata-stable
    apt-get update && apt-get install -y suricata
    suricata-update
    echo 'alert icmp any any -> $HOME_NET any (msg:"TD2 ICMP detecte"; sid:1000001; rev:1;)' \
      >> /var/lib/suricata/rules/suricata.rules
    # Fix : les AMI Ubuntu 22.04 recentes nomment l'interface ENA "ens5",
    # alors que suricata.yaml est livre configure par defaut sur "eth0".
    # Sans ce correctif, le thread de capture af-packet ne demarre jamais
    # et aucune alerte n'est generee, meme si le service semble "actif".
    sed -i 's/eth0/ens5/g' /etc/suricata/suricata.yaml
    systemctl enable suricata
    systemctl restart suricata
  EOT

  tags = { Name = "${local.prefix}-sonde" }
}

output "sonde_private_ip" {
  value = aws_instance.sonde.private_ip
}
