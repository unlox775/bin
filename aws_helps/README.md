# AWS Helper Scripts

This directory contains various AWS command-line helper scripts organized by service. Below is a summary of each script and its primary purpose:

## IAM & Security

- `aws_check_access`: Check AWS IAM user or role permissions for specific actions.
    - Usage: `aws_check_access --profile myprofile --user myuser --action s3:GetObject`
- `aws_iam_role_ls`: List IAM roles and associated AWS resources (EC2, Lambda, ECS, CloudFormation, etc.).
    - Usage: `aws_iam_role_ls --profile myprofile --region us-east-1`
- `aws_iam_policy_ls`: List IAM policies and their entity attachments (users, roles, groups), distinguishing between permissions policies and permission boundaries.
    - Usage: `aws_iam_policy_ls --profile myprofile --region us-east-1`
- `aws_role_usage`: Summarize usage of IAM roles across services.
    - Usage: `aws_role_usage --profile myprofile --region us-east-1`
- `aws_secrets_ls`: List AWS Secrets Manager secrets.
    - Usage: `aws_secrets_ls --profile myprofile --region us-east-1`
- `aws_secrets_sharing_report`: Report on shared secrets across accounts.
    - Usage: `aws_secrets_sharing_report --profile myprofile --region us-east-1`
- `aws_security_group_ls`: List security groups and their inbound/outbound rules.
    - Usage: `aws_security_group_ls --profile myprofile --region us-east-1`

## EC2 & Compute

- `aws_ec2_ami_ls`: List Amazon Machine Images (AMIs) in your AWS account.
    - Usage: `aws_ec2_ami_ls --profile myprofile --region us-east-1`
- `aws_ec2_ssm_connect`: Connect to EC2 instances via AWS SSM Session Manager.
    - Usage: `aws_ec2_ssm_connect --profile myprofile --region us-east-1 --instance i-1234567890abcdef0`
- `aws_eni_ls`: List network interfaces (ENIs) and their details.
    - Usage: `aws_eni_ls --profile myprofile --region us-east-1`
- `aws_public_ip_ls`: List public IP addresses allocated in the account.
    - Usage: `aws_public_ip_ls --profile myprofile --region us-east-1`

## S3 & Storage

- `aws_bucket_cross_account_access`: Report cross-account access for S3 buckets.
    - Usage: `aws_bucket_cross_account_access --profile myprofile --region us-east-1`
- `aws_s3_download_files_to_zip`: Download S3 bucket files and compress them into a ZIP archive.
    - Usage: `aws_s3_download_files_to_zip --profile myprofile --bucket mybucket --prefix myprefix`
- `aws_s3_list_all_filenames`: List all object keys in an S3 bucket.
    - Usage: `aws_s3_list_all_filenames --profile myprofile --bucket mybucket`
- `aws_s3_public_bucket_list_objects`: List objects in public S3 buckets.
    - Usage: `aws_s3_public_bucket_list_objects --bucket mybucket`
- `aws_s3_public_bucket_put_object`: Upload a test object to public S3 buckets.
    - Usage: `aws_s3_public_bucket_put_object --bucket mybucket --key test.txt`

## Database & Analytics

- `aws_athena_run_query`: Run SQL queries on AWS Athena and output results.
    - Usage: `aws_athena_run_query --profile myprofile --region us-east-1 --query "SELECT * FROM table"`
- `aws_rds_mysql_ssm_port_forward`: Set up SSM port forwarding to RDS MySQL instances.
    - Usage: `aws_rds_mysql_ssm_port_forward --profile myprofile --region us-east-1 --cluster mycluster`
- `aws_redshift_inspect_user`: Inspect usage and ownership details for a given Redshift user, including role memberships, active sessions, stored procs, and more.
    - Usage: `aws_redshift_inspect_user --profile myprofile --region us-east-1 --cluster mycluster --user myuser`
- `aws_redshift_ssm_port_forward`: Set up SSM port forwarding to Redshift clusters.
    - Usage: `aws_redshift_ssm_port_forward --profile myprofile --region us-east-1 --cluster mycluster`

## Memcached & Caching

- `aws_memcache_ssm_port_forward`: Set up SSM port forwarding to ElastiCache Memcached clusters.
    - Usage: `aws_memcache_ssm_port_forward --profile myprofile --region us-east-1 --cluster mycluster`
- `aws_memcache_dump_all_keys`: Dump all Memcached keys to a compressed file.
    - Usage: `aws_memcache_dump_all_keys -H localhost -p 11211 -o keys.txt.gz`
- `aws_memcache_extract_keys`: Extract specific keys from Memcached and save to files with appropriate extensions (JSON, YAML, images, etc.).
    - Usage: `aws_memcache_extract_keys -H localhost -p 11211 -o output.txt --keys mykey`

## Application Services

- `aws_codebuild_ls`: List AWS CodeBuild projects.
    - Usage: `aws_codebuild_ls --profile myprofile --region us-east-1`
- `aws_cognito_ls`: List AWS Cognito user pools and associated resources.
    - Usage: `aws_cognito_ls --profile myprofile --region us-east-1`
- `aws_log_export`: Export AWS CloudWatch logs to local files.
    - Usage: `aws_log_export --profile myprofile --region us-east-1 --log-group /aws/lambda/myfunction`

## Standards and Conventions

- Scripts are named with the `aws_` prefix followed by a descriptive action.
- All scripts expect AWS credentials via `--profile` or `AWS_PROFILE` env var.
- Use `--help` to view usage instructions for each script.

For more details on each script, run:
```bash
./<script_name> --help
```
