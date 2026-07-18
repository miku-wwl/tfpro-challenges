# Challenge 52：临时编写 Terraform 1.6 Tests，再恢复双文件 Starter

Terraform 1.6 正式引入 test framework，但测试必须位于 `.tftest.hcl` 或
`.tftest.json`，无法永久塞进本题唯一的 `.tf`。因此你会在练习过程中临时编写测试，
覆盖有效输入、预期 validation 失败、plan contract 与一次真实 LocalStack apply，完成后删除
测试文件，使目录恢复两文件。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **3c**：Use the Terraform workflow in automation

本题固定使用 Terraform 1.6 已支持的 `run`、`assert`、`variables` 与 `expect_failures`，
不要使用更高版本才有的 mock/override 功能。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-52
terraform init
terraform fmt -check
terraform validate
terraform plan
~~~

Starter 声明一个带 validation 的 bucket name、一个尚未创建的 bucket 和结构化 output。
先不要 apply；test runner 将管理自己的测试 state。

## Task 1：创建第一个 Plan Test

临时创建 `challenge-52.tftest.hcl`。第一个 run：

- 名称清楚表达“valid contract”；
- `command = plan`；
- 传入 `tfpro-c52-test-valid`；
- assert output name 等于输入；
- assert ARN 以 `arn:aws:s3:::` 开头，Challenge tag 为 `52`；
- 每条 assertion 都有能定位业务合同的 `error_message`。

~~~powershell
terraform fmt
terraform test -verbose
~~~

预期 run 通过且 LocalStack 中没有遗留 bucket；plan test 不应用资源。

## Task 2：测试一个预期失败的输入

添加第二个 `command = plan` run，传入含大写字母且缺少前缀的名称。使用
`expect_failures` 精确指向 `var.bucket_name`。

~~~powershell
terraform test
~~~

预期整个 suite 仍通过，因为 validation failure 是合同内的预期结果。不要用宽泛文本匹配
吞掉任意 provider 错误；期望失败必须绑定正确的 checkable object。

## Task 3：增加一次真实 Apply Test

添加第三个 run：

- `command = apply`；
- 使用唯一名称 `tfpro-c52-test-apply`；
- assert resource ID、output name 和 tag 合同；
- 不调用外部脚本创建或删除 bucket。

~~~powershell
terraform test -verbose
aws --endpoint-url=http://localhost:4566 s3api list-buckets --query "Buckets[?starts_with(Name, 'tfpro-c52-test-')].Name"
~~~

Test runner 应在 suite 结束时清理它创建的资源，API 最终返回空列表。若 cleanup 失败，先保留
测试 state 和日志调查，不能直接遗忘远端对象。

## Task 4：证明失败信息能指向合同

临时把第一条 assertion 的期望 name 改成错误值，再运行 `terraform test`。预期只有对应 run
失败，并显示你写的 `error_message`。恢复正确期望并重复执行，suite 必须全部通过。

这一步验证测试不是“只要命令退出 0”，而是对 plan 中的已知值做业务断言。

## Task 5：给资源加入 Custom Condition 并补测试

在 `aws_s3_bucket.under_test` 的 lifecycle 中添加 postcondition，要求 provider 返回的 ARN
包含最终 bucket name。给 test suite 增加一条能覆盖该条件的 assertion。

~~~powershell
terraform fmt
terraform validate
terraform test
~~~

区分两层职责：postcondition 在所有正常 plan/apply workflow 中保护资源合同；test file
负责用多个输入重复验证配置行为。

## Task 6：清理测试产物并恢复 Starter

确保 suite 最后一次通过且 API 没有残留，然后删除临时 `.tftest.hcl`，恢复 starter 中尚未
加入 postcondition 的资源：

~~~powershell
Remove-Item -Force .\challenge-52.tftest.hcl
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

最终只允许 `Readme.md` 与 `challenge-52.tf`。本题没有评分脚本；测试文件本身就是你练习
时临时编写和运行的 Terraform 源码。

## Terraform 1.6 边界

不要添加 `mock_provider`、`override_resource` 或版本更高才出现的测试特性。考试会检查
Terraform 1.6 能执行的配置；LocalStack apply test 验证真实 provider/resource 路径，而不是
替代考试的所有生产经验。
