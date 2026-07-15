# TODO 1: csvdecode 六字段 fleet catalog，并建立独立 checks 与 blocking output precondition。
# TODO 2: 用 grader 注入的 subnet_ids 构造 data.aws_subnet.selected，禁止 managed VPC/subnet。
# TODO 3: 查询 data.aws_ami.selected，并以 fleet_id 创建 SG、launch template、EC2 instance。
# TODO 4: CSV 重排必须保持三类资源地址不变，instance tags 必须引用真实 launch-template ID。
