import json
import os
import textwrap
import boto3

ec2 = boto3.client('ec2')


def handler(event, context):
    """
    Monthly training trigger (EventBridge → Lambda).

    Launches a fresh ephemeral EC2 that:
      1. Pulls the training Docker image from ECR
      2. Runs the full training pipeline inside the container
      3. Uploads the new model to S3
      4. Sends an SSM restart command to the persistent API EC2
      5. Self-terminates via `shutdown -h now`

    The persistent API EC2 is never touched by this Lambda.
    """

    ecr_image_uri         = os.environ['ECR_IMAGE_URI']
    instance_profile_name = os.environ['INSTANCE_PROFILE_NAME']
    security_group_id     = os.environ['SECURITY_GROUP_ID']
    subnet_id             = os.environ['SUBNET_ID']
    ami_id                = os.environ['AMI_ID']
    s3_bucket             = os.environ['S3_BUCKET']
    api_instance_id       = os.environ['API_INSTANCE_ID']

    # ECR registry URL is the image URI without the repo:tag suffix
    # e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com
    ecr_registry = ecr_image_uri.split('/')[0]
    aws_region = os.environ.get('AWS_REGION', 'us-east-1')

    print(f"Launching ephemeral training EC2")
    print(f"  AMI:           {ami_id}")
    print(f"  ECR image:     {ecr_image_uri}")
    print(f"  API instance:  {api_instance_id}")

    # user_data runs as root on first boot; it pulls the image and runs training
    user_data_script = textwrap.dedent(f"""
        #!/bin/bash
        set -e

        exec > /var/log/training-boot.log 2>&1

        echo "=== Ephemeral training EC2 starting at $(date) ==="

        # Install Docker (Amazon Linux 2023 ships without it)
        dnf install -y docker
        systemctl start docker

        # Authenticate with ECR
        aws ecr get-login-password --region {aws_region} | \\
          docker login --username AWS --password-stdin {ecr_registry}

        # Pull and run training container
        docker pull {ecr_image_uri}

        docker run --rm \\
          -e USE_S3=true \\
          -e S3_BUCKET={s3_bucket} \\
          -e API_INSTANCE_ID={api_instance_id} \\
          -e MLFLOW_TRACKING_URI=sqlite:////tmp/mlflow.db \\
          -e MLFLOW_ARTIFACT_ROOT=s3://{s3_bucket}/mlflow/artifacts \\
          -e AWS_DEFAULT_REGION={aws_region} \\
          {ecr_image_uri}

        echo "=== Training container finished at $(date) ==="

        # Self-terminate — ephemeral instance is done
        sudo shutdown -h now
    """).strip()

    try:
        response = ec2.run_instances(
            ImageId=ami_id,
            InstanceType='t2.micro',
            MinCount=1,
            MaxCount=1,
            IamInstanceProfile={'Name': instance_profile_name},
            SecurityGroupIds=[security_group_id],
            SubnetId=subnet_id,
            UserData=user_data_script,
            TagSpecifications=[
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': 'Name',    'Value': 'housing-ml-training-ephemeral'},
                        {'Key': 'Purpose', 'Value': 'training-ephemeral'},
                    ]
                }
            ],
            InstanceInitiatedShutdownBehavior='terminate',
        )

        training_instance_id = response['Instances'][0]['InstanceId']
        print(f"Ephemeral training EC2 launched: {training_instance_id}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Training EC2 launched successfully',
                'training_instance_id': training_instance_id,
                'ecr_image': ecr_image_uri,
            })
        }

    except Exception as e:
        print(f"ERROR launching training EC2: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Failed to launch training EC2',
                'error': str(e)
            })
        }
