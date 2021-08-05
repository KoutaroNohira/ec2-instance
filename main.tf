terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc-cidr-block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    "Name" = "itochu-vpc-tokyo"
  }
}

# Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.my_vpc.id
  count                   = length(var.availability_zones)
  cidr_block              = var.public-cidr-blocks[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    "Name" = "itochu-public-${count.index}"
  }
}

# Security Group for Public
resource "aws_security_group" "public" {
  name   = "itochu-sg-public"
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "itochu-sg-public"
  }
}

resource "aws_security_group_rule" "egress_public" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.public.id
}

resource "aws_security_group_rule" "ingress_public_22" {
  type              = "ingress"
  from_port         = "22"
  to_port           = "22"
  protocol          = "tcp"
  cidr_blocks       = ["${var.ingress-public}"]
  security_group_id = aws_security_group.public.id
}

resource "aws_security_group_rule" "ingress_public_80" {
  type              = "ingress"
  from_port         = "80"
  to_port           = "80"
  protocol          = "tcp"
  cidr_blocks       = ["${var.ingress-public}"]
  security_group_id = aws_security_group.public.id
}

resource "aws_security_group_rule" "ingress_public_443" {
  type              = "ingress"
  from_port         = "443"
  to_port           = "443"
  protocol          = "tcp"
  cidr_blocks       = ["${var.ingress-public}"]
  security_group_id = aws_security_group.public.id
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "itochu-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "ngw_public" {
  vpc = true
  tags = {
    Name = "itochu-ngw-public-a"
  }
}

# Elastic IP for web instances
resource "aws_eip" "web" {
  vpc      = true
  count    = var.instance-count
  instance = aws_instance.web.*.id[count.index]
  tags = {
    Name = "itochu-web-public-${count.index}"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "ngw_public" {
  count         = 1
  allocation_id = aws_eip.ngw_public.id
  subnet_id     = aws_subnet.public.*.id[0]
  tags = {
    Name = "itochu-ngw-public"
  }
}

# Route table for public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.my_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "itochu-route-table-public"
  }
}

# Route table association for public subnets
resource "aws_route_table_association" "public" {
  count          = length(var.public-cidr-blocks)
  subnet_id      = aws_subnet.public.*.id[count.index]
  route_table_id = aws_route_table.public.id
}

# IAM Role
resource "aws_iam_role" "ec2_role" {
  name        = "itochu-ec2-role"
  path        = "/"
  description = "Policy for EC2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "itochu-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# User data for web instances
data "template_file" "web" {
  template = file("${path.module}/nginx.sh")
}

data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Web instances
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amzn2.id
  instance_type          = var.instance-type
  count                  = var.instance-count
  key_name               = "itochu-tfc-keypair"
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  subnet_id              = aws_subnet.public.*.id[count.index]
  vpc_security_group_ids = [aws_security_group.public.id]

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true
  }

  tags = {
    "Name"  = "web-${count.index}",
    "Count" = "web-instance-num-${count.index}"
  }

  user_data = base64encode(data.template_file.web.rendered)
}

# ALB
resource "aws_lb" "alb" {
  name                       = "itochu-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.public.id]
  subnets                    = aws_subnet.public.*.id
  enable_deletion_protection = false
  tags = {
    "Name" = "itochu-web-alb"
  }
}

# ALB target group
resource "aws_lb_target_group" "web" {
  name     = "itochu-target-group-web"
  vpc_id   = aws_vpc.my_vpc.id
  port     = 80
  protocol = "HTTP"

  health_check {
    protocol = "HTTP"
  }
}

resource "aws_lb_target_group_attachment" "web" {
  count            = var.instance-count
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web.*.id[count.index]
  port             = 80
}

# ALB Listener
resource "aws_lb_listener" "alb" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
