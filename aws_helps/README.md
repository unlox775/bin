# AWS Helper Scripts

This directory contains various AWS command-line helper scripts. Below is a summary of each script and its primary purpose:

- `aws_athena_run_query`: Run SQL queries on AWS Athena and output results.
- `aws_bucket_cross_account_access`: Report cross-account access for S3 buckets.
- `aws_check_access`: Check AWS IAM user or role permissions for specific actions.
- `aws_codebuild_ls`: List AWS CodeBuild projects.
- `aws_cognito_ls`: List AWS Cognito user pools and associated resources.
- `aws_ec2_ami_ls`: List Amazon Machine Images (AMIs) in your AWS account.
- `aws_ec2_ssm_connect`: Connect to EC2 instances via AWS SSM Session Manager.
- `aws_eni_ls`: List network interfaces (ENIs) and their details.
- `aws_iam_role_ls`: List IAM roles and associated AWS resources (EC2, Lambda, ECS, CloudFormation, etc.).
- `aws_iam_policy_ls`: List IAM policies and their entity attachments (users, roles, groups), distinguishing between permissions policies and permission boundaries.
- `aws_log_export`: Export AWS CloudWatch logs to local files.
- `aws_public_ip_ls`: List public IP addresses allocated in the account.
- `aws_rds_mysql_ssm_port_forward`: Set up SSM port forwarding to RDS MySQL instances.
- `aws_role_usage`: Summarize usage of IAM roles across services.
- `aws_s3_download_files_to_zip`: Download S3 bucket files and compress them into a ZIP archive.
- `aws_s3_list_all_filenames`: List all object keys in an S3 bucket.
- `aws_s3_public_bucket_list_objects`: List objects in public S3 buckets.
- `aws_s3_public_bucket_put_object`: Upload a test object to public S3 buckets.
- `aws_secrets_ls`: List AWS Secrets Manager secrets.
- `aws_secrets_sharing_report`: Report on shared secrets across accounts.
- `aws_security_group_ls`: List security groups and their inbound/outbound rules.

## Standards and Conventions

- Scripts are named with the `aws_` prefix followed by a descriptive action.
- All scripts expect AWS credentials via `--profile` or `AWS_PROFILE` env var.
- Use `--help` to view usage instructions for each script.

For more details on each script, run:
```bash
./<script_name> --help
```
