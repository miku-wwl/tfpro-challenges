# Challenge 51：用 TF_LOG 定位 Provider 的运行期 Endpoint 故障

`terraform validate` 能验证 HCL 与 provider schema，却不会证明 endpoint 可连接。Starter
故意把 S3/STS 指向本机未监听的端口；你要先准确复现失败，再收集最小日志证据、区分 Core
与 provider 信息，最后只修复一处配置并完成部署。

## 官方考试目标

- **1a**：Initialize a configuration using `terraform init` and its options
- **5d**：Troubleshoot provider errors

本题错误完全留在 loopback，不会访问真实 AWS。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-51
terraform init
terraform fmt -check
terraform validate
~~~

三条命令应成功。不要因为 validate 成功就提前修改 endpoint；先保留故障现场。

## Task 1：复现第一条运行期失败

~~~powershell
terraform plan
~~~

预期 caller identity 刷新时出现连接、重试或 endpoint 错误，且不会创建 bucket。记录：

- 失败对象是 data source 还是 resource；
- 请求试图连接的 host/port；
- 错误发生在 configuration validation 之后还是之前。

不要把 `skip_*` flags 当成“跳过全部网络调用”；它们只跳过特定验证。

## Task 2：把 Debug 日志写到明确文件

~~~powershell
$env:TF_LOG = "DEBUG"
$env:TF_LOG_PATH = (Join-Path (Get-Location) "c51-debug.log")
terraform plan
Select-String -Path .\c51-debug.log -Pattern '4567','provider','GetCallerIdentity'
~~~

日志应包含 provider plugin 启动和对错误端口的请求证据。不要把整份日志提交、粘贴到公开
issue 或交给不可信系统；真实日志可能含请求头、路径和敏感值。

## Task 3：缩小到 Provider 日志

如果当前 Terraform 1.6 patch 支持 `TF_LOG_PROVIDER`，清除通用 `TF_LOG`，设置
`TF_LOG_PROVIDER=DEBUG` 后重试并比较两份日志；如果不支持，就保留 `TF_LOG=DEBUG` 并只
筛选 `provider.terraform-provider-aws` 行。目标是减少噪声，不是获得更多无关文本。

回答：为什么 `terraform providers schema -json` 可以成功，而 caller identity 失败？
前者需要已安装的插件与 schema，后者还必须调用 STS API。

## Task 4：做唯一必要的配置修复

只把 S3/STS endpoint 的端口从 `4567` 改为 `4566`；不要删除 data source、skip flags 或把
结果写死。

~~~powershell
terraform fmt
terraform validate
terraform plan '-out=c51-fixed.tfplan'
terraform show c51-fixed.tfplan
terraform apply c51-fixed.tfplan
terraform output diagnostic_contract
~~~

预期 account ID 来自 LocalStack，且只创建一个 bucket。

## Task 5：从 State 与 API 验收

~~~powershell
terraform state show aws_s3_bucket.diagnostic
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket tfpro-c51-provider-diagnostic
terraform plan
~~~

最终 plan 必须 `No changes`。再比较修复前后的日志：能说明根因的最小证据应是错误端口与
连接失败，不需要依赖重试堆栈的每一行。

## Task 6：先销毁，再清除日志环境

~~~powershell
terraform destroy -auto-approve
Remove-Item Env:TF_LOG -ErrorAction SilentlyContinue
Remove-Item Env:TF_LOG_PROVIDER -ErrorAction SilentlyContinue
Remove-Item Env:TF_LOG_PATH -ErrorAction SilentlyContinue
Remove-Item -Force .\c51-debug.log, .\c51-fixed.tfplan -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

把 endpoint 恢复为故障 starter 的 `4567`，供下次练习复现。最终目录只剩两份源文件。

## 考试边界

考试重视从首个有意义错误定位 provider 问题。不要用无限重试、删除全部缓存或关闭 TLS
验证来掩盖根因；先区分版本安装、schema、认证、endpoint 与远端 API 五个层次。
