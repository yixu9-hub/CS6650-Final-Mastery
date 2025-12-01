data "aws_availability_zones" "available" {
  count = var.create_vpc ? 1 : 0
  state = "available"
}

resource "aws_vpc" "main" {
  count      = var.create_vpc ? 1 : 0
  cidr_block = var.vpc_cidr
  tags = { Name = "ordersystem-vpc" }
}

resource "aws_internet_gateway" "igw" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  tags   = { Name = "ordersystem-igw" }
}

resource "aws_subnet" "public_a" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.public_subnets[0]
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available[0].names[0]
  tags = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.public_subnets[1]
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available[0].names[1]
  tags = { Name = "public-b" }
}

resource "aws_subnet" "private_a" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.private_subnets[0]
  availability_zone = data.aws_availability_zones.available[0].names[0]
  tags = { Name = "private-a" }
}

resource "aws_subnet" "private_b" {
  count             = var.create_vpc ? 1 : 0
  vpc_id            = aws_vpc.main[0].id
  cidr_block        = var.private_subnets[1]
  availability_zone = data.aws_availability_zones.available[0].names[1]
  tags = { Name = "private-b" }
}

resource "aws_eip" "nat" {
  count  = var.create_vpc ? 1 : 0
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  count         = var.create_vpc ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public_a[0].id
  tags = { Name = "ordersystem-nat" }
}

resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public_a" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.public_a[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public_b" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.public_b[0].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[0].id
  }
  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "private_a" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.private_a[0].id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_route_table_association" "private_b" {
  count          = var.create_vpc ? 1 : 0
  subnet_id      = aws_subnet.private_b[0].id
  route_table_id = aws_route_table.private[0].id
}
