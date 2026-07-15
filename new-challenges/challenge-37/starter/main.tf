# TODO 1: csvdecode 并规范化 protocol/ports/CIDR/enabled；全部规则均为 ingress。
# TODO 2: 建立独立的 identity、tuple、字段、端口、CIDR checks 与 SG preconditions。
# TODO 3: 用 data.aws_subnet 查询 grader-owned 网络，禁止创建 VPC/subnet。
# TODO 4: 由规范化复合 key 创建 SG 与 aws_vpc_security_group_ingress_rule resources。
