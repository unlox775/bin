#!/usr/bin/env python3

import os
import sys
import signal
import subprocess
import boto3
import botocore.exceptions
import inquirer

class EC2Proxy:
    """EC2 instance proxy for SSM port forwarding and tunneling"""
    
    def __init__(self):
        self.ssm = boto3.client('ssm')
        self.ec2 = boto3.client('ec2')
    
    def get_default_ec2_instance(self):
        """Get default EC2 instance from environment variables"""
        # First check for instance ID
        instance_id = os.environ.get('AWS_SSM_DEFAULT_EC2_INSTANCE')
        if instance_id:
            return instance_id
        
        # Then check for name/stack name
        instance_name = os.environ.get('AWS_SSM_DEFAULT_EC2_NAME')
        if instance_name:
            return instance_name
        
        return None
    
    def get_ec2_instances_with_ssm(self):
        """Get list of EC2 instances with SSM agent running"""
        try:
            # Get instances with SSM agent - increase limit to get more instances
            ssm_response = self.ssm.describe_instance_information(MaxResults=50)
            
            if not ssm_response['InstanceInformationList']:
                return []
            
            # Get instance IDs
            instance_ids = [info['InstanceId'] for info in ssm_response['InstanceInformationList']]
            
            # Get detailed instance information including tags
            ec2_response = self.ec2.describe_instances(InstanceIds=instance_ids)
            
            instances = []
            for reservation in ec2_response['Reservations']:
                for instance in reservation['Instances']:
                    # Extract tags
                    tags = {}
                    instance_name = "Unknown"
                    stack_name = None
                    for tag in instance.get('Tags', []):
                        tags[tag['Key']] = tag['Value']
                        if tag['Key'] == 'Name':
                            instance_name = tag['Value']
                        elif tag['Key'] == 'aws:cloudformation:stack-name':
                            stack_name = tag['Value']
                    
                    # Use stack name as fallback for sorting if no name
                    sort_name = instance_name if instance_name != "Unknown" else (stack_name or instance['InstanceId'])
                    
                    # Find most useful tag for display (prefer stack, then first alphabetical)
                    useful_tag = None
                    if stack_name:
                        useful_tag = f"stack:{stack_name}"
                    else:
                        # Find first alphabetical tag that's not Name or aws:cloudformation:stack-name
                        other_tags = [(k, v) for k, v in tags.items() 
                                     if k not in ['Name', 'aws:cloudformation:stack-name']]
                        if other_tags:
                            other_tags.sort(key=lambda x: x[0])  # Sort by key
                            useful_tag = f"{other_tags[0][0]}:{other_tags[0][1]}"
                    
                    # Create instance info
                    instance_info = {
                        'id': instance['InstanceId'],
                        'name': instance_name,
                        'sort_name': sort_name,
                        'type': instance['InstanceType'],
                        'state': instance['State']['Name'],
                        'tags': tags,
                        'useful_tag': useful_tag,
                        'launch_time': instance['LaunchTime']
                    }
                    instances.append(instance_info)
            
            # Sort by sort_name (name, then stack name, then instance ID)
            instances.sort(key=lambda x: x['sort_name'].lower())
            return instances
            
        except Exception as e:
            print(f"Error getting EC2 instances: {str(e)}")
            return []
    
    def select_ec2_instance(self, instances, exclude_instance_id=None):
        """Present a menu to select an EC2 instance"""
        if not instances:
            print("No EC2 instances with SSM agent found.")
            sys.exit(1)
        
        # Filter out the failed instance if specified
        if exclude_instance_id:
            instances = [inst for inst in instances if inst['id'] != exclude_instance_id]
            if not instances:
                print("No other EC2 instances available.")
                sys.exit(1)
        
        # Don't show default instance info if we're excluding it (it failed)
        if exclude_instance_id:
            default_instance = None
        else:
            default_instance = self.get_default_ec2_instance()
        
        # Always show environment variable info to help users optimize
        print("\nTo avoid EC2 instance selection in the future, set one of these environment variables:")
        print("  export AWS_SSM_DEFAULT_EC2_INSTANCE=<instance-id>")
        print("  export AWS_SSM_DEFAULT_EC2_NAME=<instance-name-or-stack-name>")
        
        # Create choices with useful information
        choices = []
        for instance in instances:
            # Create a descriptive choice string
            name_display = instance['name'][:30] if len(instance['name']) > 30 else instance['name']
            
            # Build the choice string with useful tag info
            choice_parts = [f"{instance['id']} - {name_display}"]
            
            # Add useful tag if available
            if instance['useful_tag']:
                choice_parts.append(f"({instance['useful_tag']})")
            
            choice = " ".join(choice_parts)
            choices.append(choice)
        
        # Add option to use default if available
        if default_instance:
            print(f"\nDefault EC2 instance available: {default_instance}")
        
        questions = [
            inquirer.List('selected_instance',
                          message="Which EC2 instance do you want to use for port forwarding?",
                          choices=choices)
        ]
        
        try:
            answers = inquirer.prompt(questions)
            if answers is None:
                print("\nSelection cancelled. Exiting.")
                sys.exit(0)
            selected_index = choices.index(answers['selected_instance'])
            return instances[selected_index]
        except KeyboardInterrupt:
            print("\nOperation cancelled. Exiting.")
            sys.exit(0)
    
    def find_available_ec2(self, region=None):
        """Find an available EC2 instance with SSM for tunneling"""
        # Get all instances with SSM
        instances = self.get_ec2_instances_with_ssm()
        
        if not instances:
            print("No EC2 instances with SSM agent found. Unable to create tunnel.")
            sys.exit(1)
        
        # Check if we have a default instance from environment
        default_instance = self.get_default_ec2_instance()
        if default_instance:
            print(f"Looking for default EC2 instance: {default_instance}")
            
            # Check if it looks like an instance ID or a name
            if default_instance.startswith('i-'):
                # It's an instance ID, try to match directly
                for instance in instances:
                    if instance['id'] == default_instance:
                        print(f"Found default EC2 instance by ID: {instance['id']} ({instance['name']})")
                        return instance['id']
                print(f"Warning: Default instance ID {default_instance} not found in available instances")
            else:
                # It's a name, try to look it up
                instance_id = self._find_instance_id_by_name(default_instance)
                if instance_id:
                    # Find the instance details for display
                    for instance in instances:
                        if instance['id'] == instance_id:
                            print(f"Found default EC2 instance by name: {instance['id']} ({instance['name']})")
                            return instance['id']
                else:
                    print(f"Warning: Default instance name '{default_instance}' not found in available instances")
        
        # Auto-select the first instance (sorted by name/stack)
        instance = instances[0]
        print(f"Using EC2 instance {instance['id']} ({instance['name']}) as tunnel endpoint")
        return instance['id']
    
    def check_ssm_permissions(self, instance_id):
        """Check if we have SSM permissions for a specific instance"""
        try:
            # Try to execute a command that will fail for valid reasons other than permissions
            self.ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={'commands': ['echo "test"']},
                TimeoutSeconds=30,
                MaxConcurrency='1',
                MaxErrors='0'
            )
            return True
        except botocore.exceptions.ClientError as e:
            error_msg = str(e)
            if 'AccessDenied' in error_msg:
                return False
            elif 'InvalidInstanceId' in error_msg:
                # Instance might not have SSM agent, but we have permission
                return True
            else:
                # Other errors - assume we have permission
                return True
    
    def _find_instance_id_by_name(self, instance_name):
        """Find instance ID by name (case-insensitive)"""
        instances = self.get_ec2_instances_with_ssm()
        
        # First try exact match (case-insensitive)
        for instance in instances:
            if instance['name'].lower() == instance_name.lower():
                return instance['id']
        
        # Then try stack name match
        for instance in instances:
            stack_name = instance['tags'].get('aws:cloudformation:stack-name')
            if stack_name and stack_name.lower() == instance_name.lower():
                return instance['id']
        
        return None
    
    def setup_port_forwarding(self, target_host, target_port, local_port=None, service_name="service"):
        """Setup port forwarding using an EC2 instance with SSM"""
        # If no local port is specified, use a default
        if local_port is None:
            local_port = 13306  # Default for MySQL, can be overridden
        
        # Find an available EC2 instance for tunneling
        import boto3
        region = boto3.session.Session().region_name
        instance_id = self.find_available_ec2(region)
        
        print(f"\nSetting up {service_name} port forwarding through SSM:")
        print(f"  Local port:     {local_port}")
        print(f"  Target host:    {target_host}")
        print(f"  Target port:    {target_port}")
        print(f"\nConnect using:")
        print(f"  <client> -h 127.0.0.1 -P {local_port} [connection-options]")
        print("\nPort forwarding active. Press Ctrl+C to quit.\n")
        
        # Define the SSM port forwarding command
        cmd = [
            "aws", "ssm", "start-session",
            "--target", instance_id,
            "--document-name", "AWS-StartPortForwardingSessionToRemoteHost",
            "--parameters", f"localPortNumber={local_port},host={target_host},portNumber={target_port}"
        ]
        
        # Handle Ctrl+C gracefully
        def signal_handler(sig, frame):
            print("\nPort forwarding stopped.")
            sys.exit(0)
        
        signal.signal(signal.SIGINT, signal_handler)
        
        # Start port forwarding with retry logic
        max_retries = 3
        failed_instances = []
        
        for attempt in range(max_retries):
            try:
                print(f"Attempting connection with command: {' '.join(cmd)}")
                print("Starting port forwarding session...")
                
                # Run the command and capture stderr to detect errors, but let stdout show in real-time
                result = subprocess.run(cmd, check=True, stderr=subprocess.PIPE, text=True)
                break
                
            except subprocess.CalledProcessError as e:
                error_output = e.stderr if e.stderr else ""
                
                # Check if it's a TargetNotConnected error
                if "TargetNotConnected" in error_output:
                    print(f"\nError: Instance {instance_id} is not connected to SSM.")
                    failed_instances.append(instance_id)
                    
                    if attempt < max_retries - 1:
                        print("Connection failed. Please choose a different EC2 instance:")
                        # Get a new instance, excluding failed ones
                        instances = self.get_ec2_instances_with_ssm()
                        if len(instances) > len(failed_instances):
                            selected_instance = self.select_ec2_instance(instances, exclude_instance_id=instance_id)
                            instance_id = selected_instance['id']
                            print(f"Trying EC2 instance {instance_id} ({selected_instance['name']})...")
                            # Rebuild the command with new instance
                            cmd = [
                                "aws", "ssm", "start-session",
                                "--target", instance_id,
                                "--document-name", "AWS-StartPortForwardingSessionToRemoteHost",
                                "--parameters", f"localPortNumber={local_port},host={target_host},portNumber={target_port}"
                            ]
                        else:
                            print("No other EC2 instances available.")
                            sys.exit(1)
                    else:
                        print("Maximum retries reached. Please check your EC2 instances and try again.")
                        sys.exit(1)
                else:
                    # Re-raise if it's not a TargetNotConnected error
                    raise
    
    def check_aws_ssm_access(self):
        """Check if we have valid AWS credentials and permissions for SSM sessions"""
        from .aws_common import AWSCommon
        
        aws_common = AWSCommon()
        
        # First check basic AWS credentials
        if not aws_common.check_aws_credentials():
            return False
        
        # Now check SSM access
        ssm = boto3.client('ssm')
        ec2 = boto3.client('ec2')
        
        print("Checking SSM session permissions...")
        
        # Check if we have a default EC2 instance from environment variable
        default_instance = self.get_default_ec2_instance()
        if default_instance:
            print(f"Using default EC2 instance from environment: {default_instance}")
            
            # Check if it looks like an instance ID or a name
            if default_instance.startswith('i-'):
                # It's an instance ID, use it directly
                instance_id = default_instance
            else:
                # It's a name, try to look it up
                print(f"Looking up instance ID for name: {default_instance}")
                instance_id = self._find_instance_id_by_name(default_instance)
                if not instance_id:
                    print(f"Warning: Could not find instance with name '{default_instance}'")
                    print("Please choose an EC2 instance:")
                    instances = self.get_ec2_instances_with_ssm()
                    if instances:
                        selected_instance = self.select_ec2_instance(instances)
                        instance_id = selected_instance['id']
                        print(f"Using selected instance: {instance_id} ({selected_instance['name']})")
                    else:
                        print("No EC2 instances with SSM agent found.")
                        return False
        else:
            # Find any running instance ID to test against
            try:
                ec2_response = ec2.describe_instances(
                    Filters=[{'Name': 'instance-state-name', 'Values': ['running']}],
                    MaxResults=50
                )
                
                if not ec2_response.get('Reservations') or len(ec2_response['Reservations']) == 0:
                    print("Warning: No running EC2 instances found. Cannot verify SSM permissions.")
                    print("You may encounter issues when trying to establish port forwarding.")
                    return True  # Continue anyway
                    
                instance_id = ec2_response['Reservations'][0]['Instances'][0]['InstanceId']
            
            except botocore.exceptions.ClientError as e:
                print(f"Warning: Could not list EC2 instances: {str(e)}")
                print("You may encounter issues when trying to establish port forwarding.")
                try:
                    if input("\nWould you like to try continuing anyway? (y/N): ").lower() != 'y':
                        sys.exit(1)
                except KeyboardInterrupt:
                    print("\nOperation cancelled by user. Exiting.")
                    sys.exit(0)
                return False
        
        # Check if we have ssm:StartSession permission
        print(f"Testing SSM permission with instance: {instance_id}")
        
        try:
            # Try to execute a command that will fail for valid reasons other than permissions
            self.ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunShellScript',
                Parameters={'commands': ['echo "test"']},
                TimeoutSeconds=30,
                MaxConcurrency='1',
                MaxErrors='0'
            )
            
            # If we get here, we have the permissions for SSM commands
            print("✓ You appear to have SSM permissions.")
            return True
            
        except botocore.exceptions.ClientError as e:
            error_code = e.response.get('Error', {}).get('Code')
            error_msg = str(e)
            
            if 'AccessDenied' in error_msg or error_code == 'AccessDeniedException':
                print("✗ You don't have permission to use SSM.")
                print(f"\nYou need ssm:StartSession permission to use port forwarding.")
                print(f"Error message: {error_msg}")
                print(f"\nYou may need to switch to a profile with more permissions. Try:")
                print(f"  export AWS_PROFILE=<profile_name>")
                print(f"  # or")
                print(f"  aws sso login --profile <profile_name>")
                
                profiles = aws_common.list_aws_profiles()
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
            elif 'InvalidInstanceId' in error_msg or 'ValidationException' in error_msg:
                # Instance might not have SSM agent, but we have permission
                print("✓ You appear to have SSM permissions (but instance might not be SSM-enabled).")
                return True
            else:
                print(f"Warning: Unexpected error checking SSM permissions: {error_msg}")
                return True  # Continue anyway
        
        except Exception as e:
            print(f"Warning: Could not check IAM permissions: {str(e)}")
            print("You may encounter issues when trying to establish port forwarding.")
            try:
                if input("\nWould you like to try continuing anyway? (y/N): ").lower() != 'y':
                    sys.exit(1)
            except KeyboardInterrupt:
                print("\nOperation cancelled by user. Exiting.")
                sys.exit(0)
            return False
