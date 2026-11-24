# Preserve physical resource identity when upgrading the original single-NAT layout.
# These moves have no effect when the source address is absent in newer states.
moved {
  from = aws_subnet.nat
  to   = aws_subnet.nat[0]
}

moved {
  from = aws_eip.main-nat
  to   = aws_eip.nat[0]
}

moved {
  from = aws_nat_gateway.main
  to   = aws_nat_gateway.main[0]
}

moved {
  from = aws_route.main-nat
  to   = aws_route.main-nat[0]
}

moved {
  from = aws_route_table_association.nat-igw
  to   = aws_route_table_association.nat-igw[0]
}
