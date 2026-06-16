resource "aws_security_group" "yokozuna_sg" {
  name        = "yokozuna_sg"
  description = "Security group yokozuna"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "yokozuna_sg"
  }
}

resource "aws_subnet" "yokozuna_subnet" {
  vpc_id     = var.vpc_id
  cidr_block = "172.31.10.0/24"

  tags = {
    Name = "yokozuna_subnet"
  }
}

resource "aws_key_pair" "yokozuna_key" {
  key_name   = "yokozuna_key"
  public_key = file(pathexpand("~/.ssh/yokozuna_key.pub"))
}

resource "aws_instance" "yokozuna_serverweb" {
  ami                         = var.vm_image
  instance_type               = var.vm_instance_type
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.yokozuna_subnet.id
  vpc_security_group_ids      = [aws_security_group.yokozuna_sg.id]
  key_name                    = aws_key_pair.yokozuna_key.key_name

  tags = {
    Name = "yokozuna_serverweb"
  }
}
