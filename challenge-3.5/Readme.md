## Challenge 3.5 — LocalStack Community edition

This is a LocalStack-compatible version of Challenge 3. It preserves the same
module, shared-credential, multi-provider, targeted-apply, and lifecycle
exercises. LocalStack Community does not include Auto Scaling, so the ASG is
replaced by a `terraform_data` desired-capacity controller.

### Base infrastructure

Before Task 1, run the following from `base-folder`:

```powershell
terraform init
terraform apply -auto-approve
```

This creates three LocalStack IAM roles, two users, and their access keys:

- `EC2FullAccessChallenge35`
- `IAMFullAccessChallenge35`
- `ReadOnlyRoleChallenge35`
- `kplabs-challenge35-user`
- `ro-user-challenge35`

### Tasks

#### 1. Split resources into child modules

Move resources from `challenge-3.5.tf` (not `base-folder`) into child modules
under `modules`.

| Resource type | Module directory |
| :--- | :---: |
| `aws_launch_template` | `compute` |
| `terraform_data` | `compute` |
| `aws_iam_user` | `iam` |
| `aws_iam_user_policy` | `iam` |

Configure the module sources in the root `challenge-3.5.tf` file.

#### 2. Create shared config and credentials files

Create `.aws/conf` and `.aws/credentials` in this directory.

- `conf` may contain only the `compute` and `iam` profiles.
- Both profiles use `us-east-1`.
- `compute` assumes `EC2FullAccessChallenge35`.
- `iam` assumes `IAMFullAccessChallenge35`.
- Both use the credentials of `kplabs-challenge35-user` as their source
  credentials.

#### 3. Add provider configurations

- The compute module uses the `compute` profile.
- The IAM module uses the `iam` profile.
- `data.aws_caller_identity.local` assumes `ReadOnlyRoleChallenge35`, using
  credentials for `ro-user-challenge35`.
- Every AWS provider configuration must use the LocalStack endpoint
  `http://localhost:4566`.

#### 4. Deploy resources

First create only the local file:

```powershell
terraform apply -target=local_file.this
```

Verify that `account-number.txt` contains LocalStack account ID `000000000000`.
Then deploy the remaining resources:

```powershell
terraform apply -auto-approve
```

#### 5. Ignore desired-capacity changes

Change the capacity-controller value from `1` to `2`.
Add a lifecycle rule that ignores changes to that value. A subsequent plan must
not update the resource, and its state must retain the initial value `1`.

This replaces the original ASG `desired_capacity` exercise while retaining the
same Terraform lifecycle concept.

### Cleanup

Destroy both the root configuration and `base-folder` resources when finished.

```powershell
terraform destroy -auto-approve
Set-Location .\base-folder
terraform destroy -auto-approve
```
