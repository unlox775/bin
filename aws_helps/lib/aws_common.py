#!/usr/bin/env python3

import os
import sys
import boto3
import botocore.exceptions

class AWSCommon:
    """Common AWS utilities and access checking"""
    
    def __init__(self):
        pass
    
    def get_aws_region(self):
        """
        Get AWS region from environment variables or AWS config.
        Returns the region name, or None if not found.
        
        Priority order:
        1. AWS_REGION environment variable
        2. AWS_DEFAULT_REGION environment variable
        3. Region from AWS config file for current profile
        4. Region from boto3 default session
        """
        # First check environment variables (highest priority for explicit user intent)
        region = os.environ.get('AWS_REGION') or os.environ.get('AWS_DEFAULT_REGION')
        if region:
            return region
        
        # Try to get region from AWS config file for current profile
        profile = os.environ.get('AWS_PROFILE', os.environ.get('AWS_DEFAULT_PROFILE', 'default'))
        config_path = os.path.expanduser("~/.aws/config")
        if os.path.exists(config_path):
            current_section = None
            with open(config_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    # Check if this is the profile section we're looking for
                    if line.startswith('[') and line.endswith(']'):
                        section = line[1:-1]
                        if section == profile or section == f'profile {profile}':
                            current_section = section
                        elif section != 'default' and not section.startswith('profile '):
                            # This is a credentials section, not config
                            current_section = None
                        else:
                            current_section = None
                    elif current_section and line.startswith('region'):
                        # Found region setting for this profile
                        parts = line.split('=', 1)
                        if len(parts) == 2:
                            return parts[1].strip()
        
        # Last resort: try to get from boto3 default session
        try:
            session = boto3.Session()
            if session.region_name:
                return session.region_name
        except Exception:
            pass
        
        return None
    
    def get_boto3_client(self, service_name, region_name=None, **kwargs):
        """
        Create a boto3 client for the specified service with proper region handling.
        
        Args:
            service_name: AWS service name (e.g., 'ec2', 'ssm', 'redshift')
            region_name: Optional explicit region. If not provided, uses get_aws_region()
            **kwargs: Additional arguments to pass to boto3.client() (e.g., config)
        
        Returns:
            boto3 client configured with the appropriate region
        """
        if region_name is None:
            region_name = self.get_aws_region()
        
        if region_name:
            return boto3.client(service_name, region_name=region_name, **kwargs)
        else:
            return boto3.client(service_name, **kwargs)
    
    def get_boto3_session(self, profile_name=None, region_name=None):
        """
        Create a boto3 session with proper region handling.
        
        Args:
            profile_name: Optional AWS profile name. If not provided, uses current profile from env
            region_name: Optional explicit region. If not provided, uses get_aws_region()
        
        Returns:
            boto3 Session configured with the appropriate profile and region
        """
        if profile_name is None:
            profile_name = os.environ.get('AWS_PROFILE', os.environ.get('AWS_DEFAULT_PROFILE'))
        
        if region_name is None:
            region_name = self.get_aws_region()
        
        if profile_name and region_name:
            return boto3.Session(profile_name=profile_name, region_name=region_name)
        elif profile_name:
            return boto3.Session(profile_name=profile_name)
        elif region_name:
            return boto3.Session(region_name=region_name)
        else:
            return boto3.Session()
    
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
            sts = self.get_boto3_client('sts')
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
