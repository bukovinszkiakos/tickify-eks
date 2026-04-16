resource "aws_subnet" "this" {
  count = length(var.availability_zones)

  vpc_id            = var.vpc_id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-subnet-${count.index}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table_association" "this" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = var.route_table_id
}