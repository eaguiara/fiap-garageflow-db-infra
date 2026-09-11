resource "aws_vpc" "garage_flow_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_internet_gateway" "garage_flow_igw" {
  vpc_id = try(aws_vpc.garage_flow_vpc.id, null)

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table" "garage_flow_rt" {
  vpc_id = try(aws_vpc.garage_flow_vpc.id, null)

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = try(aws_internet_gateway.garage_flow_igw.id, null)
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_route_table_association" "garage_flow_rta_az_a" {
  subnet_id      = try(aws_subnet.garage_flow_subnet_az_a.id, null)
  route_table_id = try(aws_route_table.garage_flow_rt.id, null)

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_route_table_association" "garage_flow_rta_az_b" {
  subnet_id      = try(aws_subnet.garage_flow_subnet_az_b.id, null)
  route_table_id = try(aws_route_table.garage_flow_rt.id, null)

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_subnet" "garage_flow_subnet_az_a" {
  vpc_id                  = try(aws_vpc.garage_flow_vpc.id, null)
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/elb"                = "1"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "garage_flow_subnet_az_b" {
  vpc_id                  = try(aws_vpc.garage_flow_vpc.id, null)
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/elb"                = "1"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# EIP for NAT Gateway
resource "aws_eip" "garage_flow_nat_eip" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.garage_flow_igw]

  lifecycle {
    ignore_changes = [tags]
  }
}

# NAT Gateway in public subnet az_a
resource "aws_nat_gateway" "garage_flow_nat" {
  allocation_id = try(aws_eip.garage_flow_nat_eip.id, null)
  subnet_id     = try(aws_subnet.garage_flow_subnet_az_a.id, null)

  depends_on = [aws_internet_gateway.garage_flow_igw]

  tags = {
    Name = "garage_flow_nat"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Private subnets for EKS nodes
resource "aws_subnet" "garage_flow_private_subnet_az_a" {
  vpc_id                  = try(aws_vpc.garage_flow_vpc.id, null)
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/internal-elb"        = "1"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "aws_subnet" "garage_flow_private_subnet_az_b" {
  vpc_id                  = try(aws_vpc.garage_flow_vpc.id, null)
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/internal-elb"        = "1"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Private route table via NAT Gateway
resource "aws_route_table" "garage_flow_private_rt" {
  vpc_id = try(aws_vpc.garage_flow_vpc.id, null)

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = try(aws_nat_gateway.garage_flow_nat.id, null)
  }

  lifecycle {
    ignore_changes = [tags, route]
  }
}

resource "aws_route_table_association" "garage_flow_private_rta_az_a" {
  subnet_id      = try(aws_subnet.garage_flow_private_subnet_az_a.id, null)
  route_table_id = try(aws_route_table.garage_flow_private_rt.id, null)

  lifecycle {
    ignore_changes = all
  }
}

resource "aws_route_table_association" "garage_flow_private_rta_az_b" {
  subnet_id      = try(aws_subnet.garage_flow_private_subnet_az_b.id, null)
  route_table_id = try(aws_route_table.garage_flow_private_rt.id, null)

  lifecycle {
    ignore_changes = all
  }
}
