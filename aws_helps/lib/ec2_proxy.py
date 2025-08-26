#!/usr/bin/env python3

import os
import sys
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
            print("You can set to skip this selection:")
            print("  export AWS_SSM_DEFAULT_EC2_INSTANCE=<instance-id>")
            print("  export AWS_SSM_DEFAULT_EC2_NAME=<instance-name-or-stack-name>")
        
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
            
            # First try to match by instance ID
            instance_id = os.environ.get('AWS_SSM_DEFAULT_EC2_INSTANCE')
            if instance_id:
                for instance in instances:
                    if instance['id'] == instance_id:
                        print(f"Found default EC2 instance by ID: {instance['id']} ({instance['name']})")
                        print("To avoid this selection in the future, set:")
                        print("  export AWS_SSM_DEFAULT_EC2_INSTANCE=<instance-id>")
                        print("  export AWS_SSM_DEFAULT_EC2_NAME=<instance-name-or-stack-name>")
                        return instance['id']
                print(f"Warning: Default instance ID {instance_id} not found in available instances")
            
            # Then try to match by name/stack name
            instance_name = os.environ.get('AWS_SSM_DEFAULT_EC2_NAME')
            if instance_name:
                # First try exact name match
                for instance in instances:
                    if instance['name'] == instance_name:
                        print(f"Found default EC2 instance by name: {instance['id']} ({instance['name']})")
                        print("To avoid this selection in the future, set:")
                        print("  export AWS_SSM_DEFAULT_EC2_INSTANCE=<instance-id>")
                        print("  export AWS_SSM_DEFAULT_EC2_NAME=<instance-name-or-stack-name>")
                        return instance['id']
                
                # Then try stack name match
                for instance in instances:
                    stack_name = instance['tags'].get('aws:cloudformation:stack-name')
                    if stack_name == instance_name:
                        print(f"Found default EC2 instance by stack name: {instance['id']} ({instance['name']}) [stack: {stack_name}]")
                        print("To avoid this selection in the future, set:")
                        print("  export AWS_SSM_DEFAULT_EC2_INSTANCE=<instance-id>")
                        print("  export AWS_SSM_DEFAULT_EC2_NAME=<instance-name-or-stack-name>")
                        return instance['id']
                
                print(f"Warning: Default instance name/stack '{instance_name}' not found in available instances")
        
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
