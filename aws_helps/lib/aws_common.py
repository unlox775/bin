#!/usr/bin/env python3

import os
import sys
import boto3
import botocore.exceptions

class AWSCommon:
    """Common AWS utilities and access checking"""
    
    def __init__(self):
        pass
    
    def list_aws_profiles(self):
        """List available AWS profiles in credentials and config files"""
        profiles = set()
        
        # Check ~/.aws/credentials
        cred_path = os.path.expanduser("~/.aws/credentials")
        if os.path.exists(cred_path):
            with open(cred_path, 'r') as f:
                for line in f:
                    if line.strip().startswith('[') and line.strip().endswith(']'):
                        profile = line.strip()[1:-1]
                        if profile != 'default' and not profile.startswith('profile '):
                            profiles.add(profile)
        
        # Check ~/.aws/config
        config_path = os.path.expanduser("~/.aws/config")
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                for line in f:
                    if line.strip().startswith('[') and line.strip().endswith(']'):
                        profile = line.strip()[1:-1]
                        if profile.startswith('profile '):
                            profiles.add(profile[8:])  # Remove 'profile ' prefix
        
        return sorted(list(profiles))
    
    def check_aws_credentials(self):
        """Check if we have valid AWS credentials"""
        # Get the current AWS profile
        profile = os.environ.get('AWS_PROFILE', os.environ.get('AWS_DEFAULT_PROFILE', 'default'))
        
        print(f"Using AWS profile: {profile}")
        
        try:
            # Try to get caller identity - lightweight call to verify credentials
            sts = boto3.client('sts')
            identity = sts.get_caller_identity()
            account_id = identity['Account']
            username = identity['Arn'].split('/')[-1]
            print(f"Authenticated as {username} in account {account_id}")
            return True
            
        except botocore.exceptions.ClientError as e:
            print(f"AWS Access Error: {str(e)}")
            print(f"\nYou may need to switch AWS profiles. Try:")
            print(f"  export AWS_PROFILE=<profile_name>")
            print(f"  # or")
            print(f"  aws sso login --profile <profile_name>")
            
            profiles = self.list_aws_profiles()
            if profiles:
                print("\nAvailable AWS profiles:")
                for p in profiles:
                    print(f"  {p}")
                    
            try:
                if input("\nWould you like to try continuing anyway? (y/N): ").lower() != 'y':
                    sys.exit(1)
            except KeyboardInterrupt:
                print("\nOperation cancelled by user. Exiting.")
                sys.exit(0)
            return False
