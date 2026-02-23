import json
import boto3
import os

ec2 = boto3.client('ec2')
ssm = boto3.client('ssm')

def handler(event, context):
    """
    Lambda function to trigger model training on EC2 instance.
    This is invoked by EventBridge on a monthly schedule.
    """

    instance_id = os.environ['INSTANCE_ID']
    s3_bucket = os.environ['S3_BUCKET']
    aws_region = os.environ['AWS_REGION']  # set automatically by Lambda runtime

    print(f"🚀 Triggering training on EC2 instance: {instance_id}")

    try:
        # Check if instance is running
        response = ec2.describe_instances(InstanceIds=[instance_id])
        state = response['Reservations'][0]['Instances'][0]['State']['Name']

        if state != 'running':
            print(f"⚠️ Instance is not running (state: {state}). Starting instance...")
            ec2.start_instances(InstanceIds=[instance_id])

            # Wait for instance to be running
            waiter = ec2.get_waiter('instance_running')
            waiter.wait(InstanceIds=[instance_id])
            print("✅ Instance is now running")

        # Send command to run training script
        command = f"""
        export USE_S3=true
        export S3_BUCKET={s3_bucket}
        export AWS_REGION={aws_region}
        /opt/housing-ml/run_training.sh
        """

        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={
                'commands': [command]
            },
            Comment='Trigger monthly model training'
        )

        command_id = response['Command']['CommandId']
        print(f"✅ Training command sent successfully. Command ID: {command_id}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Training triggered successfully',
                'instance_id': instance_id,
                'command_id': command_id
            })
        }

    except Exception as e:
        print(f"❌ Error triggering training: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error triggering training',
                'error': str(e)
            })
        }

