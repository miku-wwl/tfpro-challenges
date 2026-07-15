import {
  to = module.ec2.aws_instance.instances["subnet-574a3f4c574e443f8"]
  id = "i-7bb36512d5f125faa"
}

import {
  to = module.ec2.aws_instance.instances["subnet-7b27cc06cea54afce"]
  id = "i-2629ae63073cfe39d"
}

import {
  to = module.sg.aws_security_group.sg["app-1-sg"]
  id = "sg-5fd742d4304b7860a"
}

import {
  to = module.sg.aws_security_group.sg["app-2-sg"]
  id = "sg-4216d6e48b15cac9e"
}

import {
  to = module.sg.aws_vpc_security_group_egress_rule.app_2_sg_egress["0"]
  id = "sgr-a2ba1144f6980b23f"
}

import {
  to = module.sg.aws_vpc_security_group_egress_rule.app_2_sg_egress["1"]
  id = "sgr-6949f8c7f08e1523b"
}

import {
  to = module.sg.aws_vpc_security_group_ingress_rule.app_1_sg_ingress["0"]
  id = "sgr-b9800307676251483"
}

import {
  to = module.sg.aws_vpc_security_group_ingress_rule.app_1_sg_ingress["1"]
  id = "sgr-951834742ad763827"
}
