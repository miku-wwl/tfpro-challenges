## Challenge 7

本挑战考查你对 Terraform 数据类型的理解，以及如何从外部 CSV 文件动态提取和处理数据。

### 任务

所有值都**必须**从 `ec2.csv` 动态获取。不要在 output 中硬编码 CSV 里的任何值。

### 1. 从 CSV 文件获取数据

创建一个 **local value**，读取并获取 `ec2.csv` 中的全部数据。

### 2. 输出 CSV 中的 AMI ID 列表

创建名为 `list_amis` 的 **output value**，动态生成包含 CSV 中所有 AMI ID 的 `list`。

参考最终输出：

```sh
list_amis = [
  "ami-01816d07b1128cd2d",
  "ami-0fd05997b4dff7aac",
  "ami-09b0a86a2c84101e1",
  "ami-0995922d49dc9a17d",
]
```

### 3. 输出 CSV 中唯一的 Team 名称列表

创建名为 `unique_team_names` 的 **output value**，其中包含 CSV 中所有唯一 Team 名称组成的 `list`，不允许重复。

参考最终输出：

```sh
unique_team_names = ["DevOps","SRE","Security"]
```

### 4. 输出 Region 的 List of Lists

创建名为 `regions_list_of_lists` 的 **output value**。它应为一个 list of lists，CSV 中每个 Region 分别放在单独的内层 list 中。

参考最终输出：

```sh
regions_list_of_lists = [
  [
    "us-east-1",
  ],
  [
    "ap-south-1",
  ],
  [
    "us-east-1",
  ],
  [
    "ap-southeast-1",
  ],
]
```

### 5. 根据条件输出过滤后的 List of Lists

创建名为 `list_list_condition` 的 **output value**。结果应为 list of lists，但只包含 `instance_type` 为 `nano` 的行。

参考最终输出：

```sh
list_list_condition = [
  [
    "ap-south-1",
  ],
  [
    "us-east-1",
  ],
]
```

### 6. 包含各实例类型总数的 Map

创建名为 `instance_count_by_type` 的 **output value**，生成一个 map，显示 CSV 中每种 `instance_type` 的数量。

参考最终输出：

```sh
instance_count_by_type = {
  "micro" = 2
  "nano" = 2
}
```

### 7. List of Maps

创建名为 `instance_details` 的 **output value**，生成一个 map 列表，每个 map 包含相应实例的 `team` 和 `type` 属性。

参考最终输出：

```sh
instance_details = [
  {
    "team" = "Security"
    "type" = "micro"
  },
  {
    "team" = "SRE"
    "type" = "nano"
  },
  {
    "team" = "DevOps"
    "type" = "nano"
  },
  {
    "team" = "SRE"
    "type" = "micro"
  },
]
```

### 8. Map of Maps

输出一个 map of maps，其中每个唯一 key 都由 `instance_type`、Region 和 Team Name 组合而成。每个 map 的属性应与参考输出类似。

参考最终输出：

```sh
map_of_maps = {
  "micro_ap-southeast-1_SRE" = {
    "ami_id" = "ami-0995922d49dc9a17d"
    "instance_type" = "micro"
    "region" = "ap-southeast-1"
    "team_name" = "SRE"
  }
  "micro_us-east-1_Security" = {
    "ami_id" = "ami-01816d07b1128cd2d"
    "instance_type" = "micro"
    "region" = "us-east-1"
    "team_name" = "Security"
  }
  "nano_ap-south-1_SRE" = {
    "ami_id" = "ami-0fd05997b4dff7aac"
    "instance_type" = "nano"
    "region" = "ap-south-1"
    "team_name" = "SRE"
  }
  "nano_us-east-1_DevOps" = {
    "ami_id" = "ami-09b0a86a2c84101e1"
    "instance_type" = "nano"
    "region" = "us-east-1"
    "team_name" = "DevOps"
  }
}
```
