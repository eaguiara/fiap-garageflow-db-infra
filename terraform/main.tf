resource "aws_vpc" "garage_flow_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "garage_flow_igw" {
  vpc_id = aws_vpc.garage_flow_vpc.id
}

resource "aws_route_table" "garage_flow_rt" {
  vpc_id = aws_vpc.garage_flow_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.garage_flow_igw.id
  }
}

resource "aws_route_table_association" "garage_flow_rta_az_a" {
  subnet_id      = aws_subnet.garage_flow_subnet_az_a.id
  route_table_id = aws_route_table.garage_flow_rt.id
}

resource "aws_route_table_association" "garage_flow_rta_az_b" {
  subnet_id      = aws_subnet.garage_flow_subnet_az_b.id
  route_table_id = aws_route_table.garage_flow_rt.id
}

resource "aws_subnet" "garage_flow_subnet_az_a" {
  vpc_id                  = aws_vpc.garage_flow_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/elb"                = "1"
  }
}

resource "aws_subnet" "garage_flow_subnet_az_b" {
  vpc_id                  = aws_vpc.garage_flow_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/elb"                = "1"
  }
}

# EIP for NAT Gateway
resource "aws_eip" "garage_flow_nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.garage_flow_igw]
}

# NAT Gateway in public subnet az_a
resource "aws_nat_gateway" "garage_flow_nat" {
  allocation_id = aws_eip.garage_flow_nat_eip.id
  subnet_id     = aws_subnet.garage_flow_subnet_az_a.id
  depends_on    = [aws_internet_gateway.garage_flow_igw]

  tags = {
    Name = "garage_flow_nat"
  }
}

# Private subnets for EKS nodes
resource "aws_subnet" "garage_flow_private_subnet_az_a" {
  vpc_id                  = aws_vpc.garage_flow_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/internal-elb"        = "1"
  }
}

resource "aws_subnet" "garage_flow_private_subnet_az_b" {
  vpc_id                  = aws_vpc.garage_flow_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false

  tags = {
    "kubernetes.io/cluster/garage_flow_eks" = "owned"
    "kubernetes.io/role/internal-elb"        = "1"
  }
}

# Private route table via NAT Gateway
resource "aws_route_table" "garage_flow_private_rt" {
  vpc_id = aws_vpc.garage_flow_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.garage_flow_nat.id
  }
}

resource "aws_route_table_association" "garage_flow_private_rta_az_a" {
  subnet_id      = aws_subnet.garage_flow_private_subnet_az_a.id
  route_table_id = aws_route_table.garage_flow_private_rt.id
}

resource "aws_route_table_association" "garage_flow_private_rta_az_b" {
  subnet_id      = aws_subnet.garage_flow_private_subnet_az_b.id
  route_table_id = aws_route_table.garage_flow_private_rt.id
}