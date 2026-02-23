"""
AWS Credentials Verification Script

Run this script to verify your AWS credentials are properly configured.
"""

import os
import sys
import boto3
from botocore.exceptions import ClientError, NoCredentialsError


def check_aws_credentials():
    """Check if AWS credentials are configured."""
    print("🔍 Checking AWS Credentials...\n")

    # Check environment variables
    access_key = os.getenv('AWS_ACCESS_KEY_ID')
    secret_key = os.getenv('AWS_SECRET_ACCESS_KEY')
    region = os.getenv('AWS_REGION')  # reads from ~/.aws/config when not set

    if access_key and secret_key:
        print("✅ AWS credentials found in environment variables")
        print(f"   Access Key: {access_key[:8]}...{access_key[-4:]}")
        print(f"   Region: {region or '(from ~/.aws/config)'}\n")
    else:
        print("⚠️  AWS credentials not in environment variables")
        print("   Checking ~/.aws/credentials...\n")

    # Try to get caller identity
    try:
        sts = boto3.client('sts', region_name=region)
        identity = sts.get_caller_identity()

        print("✅ AWS Authentication Successful!")
        print(f"   Account ID: {identity['Account']}")
        print(f"   User ARN: {identity['Arn']}")
        print(f"   User ID: {identity['UserId']}\n")
        return True

    except NoCredentialsError:
        print("❌ No AWS credentials found!")
        print("\nPlease configure credentials using one of these methods:")
        print("1. Run: aws configure")
        print("2. Set environment variables:")
        print("   $env:AWS_ACCESS_KEY_ID='your_key'")
        print("   $env:AWS_SECRET_ACCESS_KEY='your_secret'")
        print("3. Create .env file from .env.template\n")
        return False

    except ClientError as e:
        print(f"❌ AWS Authentication Failed: {e}")
        print("\nPossible issues:")
        print("1. Invalid credentials")
        print("2. Credentials expired")
        print("3. No internet connection\n")
        return False


def check_s3_access(bucket_name=None):
    """Check S3 access."""
    bucket_name = bucket_name or os.getenv('S3_DATA_BUCKET', 'house-forecast')

    print(f"🔍 Checking S3 Access to bucket: {bucket_name}\n")

    try:
        s3 = boto3.client('s3', region_name=os.getenv('AWS_REGION'))

        # List buckets
        response = s3.list_buckets()
        print("✅ S3 Access Granted!")
        print(f"   Found {len(response['Buckets'])} buckets in your account\n")

        # Check if specific bucket exists
        try:
            s3.head_bucket(Bucket=bucket_name)
            print(f"✅ Bucket '{bucket_name}' exists and is accessible\n")

            # List objects in bucket
            try:
                response = s3.list_objects_v2(Bucket=bucket_name, MaxKeys=5)
                if 'Contents' in response:
                    print(f"   Sample objects in bucket:")
                    for obj in response['Contents'][:5]:
                        print(f"   - {obj['Key']} ({obj['Size']} bytes)")
                else:
                    print(f"   Bucket is empty")
                print()

            except ClientError as e:
                print(f"⚠️  Cannot list objects: {e}\n")

        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                print(f"❌ Bucket '{bucket_name}' does not exist")
                print(f"   Create it with: aws s3 mb s3://{bucket_name}\n")
            elif e.response['Error']['Code'] == '403':
                print(f"❌ Access denied to bucket '{bucket_name}'")
                print(f"   Check IAM permissions\n")
            else:
                print(f"❌ Error accessing bucket: {e}\n")

        return True

    except NoCredentialsError:
        print("❌ No AWS credentials found for S3 access\n")
        return False

    except ClientError as e:
        print(f"❌ S3 Access Failed: {e}\n")
        return False


def check_s3_data_file(bucket_name=None, file_key=None):
    """Check if specific data file exists in S3."""
    bucket_name = bucket_name or os.getenv('S3_DATA_BUCKET', 'house-forecast')
    file_key = file_key or os.getenv('S3_DATA_KEY', 'raw/housing_data.csv')

    print(f"🔍 Checking Data File: s3://{bucket_name}/{file_key}\n")

    try:
        s3 = boto3.client('s3', region_name=os.getenv('AWS_REGION'))

        # Check if file exists
        response = s3.head_object(Bucket=bucket_name, Key=file_key)

        print("✅ Data file found!")
        print(f"   Size: {response['ContentLength']} bytes")
        print(f"   Last Modified: {response['LastModified']}")
        print(f"   Content Type: {response.get('ContentType', 'Unknown')}\n")

        return True

    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            print(f"❌ File not found: s3://{bucket_name}/{file_key}")
            print(f"\nUpload your data file with:")
            print(f"   aws s3 cp your_local_file.csv s3://{bucket_name}/{file_key}\n")
        else:
            print(f"❌ Error checking file: {e}\n")
        return False


def print_configuration_summary():
    """Print current configuration."""
    print("=" * 60)
    print("CURRENT CONFIGURATION")
    print("=" * 60)

    print("\nEnvironment Variables:")
    print(f"  USE_S3: {os.getenv('USE_S3', 'false')}")
    print(f"  AWS_REGION: {os.getenv('AWS_REGION', 'us-east-1')}")
    print(f"  S3_DATA_BUCKET: {os.getenv('S3_DATA_BUCKET', 'house-forecast')}")
    print(f"  S3_DATA_KEY: {os.getenv('S3_DATA_KEY', 'raw/housing_data.csv')}")
    print(f"  S3_BUCKET (models): {os.getenv('S3_BUCKET', 'house-forecast')}")

    print("\nTo use S3 for data loading:")
    print("  $env:USE_S3='true'")
    print("  $env:S3_DATA_BUCKET='your-bucket-name'")
    print("  $env:S3_DATA_KEY='path/to/your/data.csv'")
    print()


def main():
    """Main verification flow."""
    print("\n" + "=" * 60)
    print("AWS CREDENTIALS & S3 ACCESS VERIFICATION")
    print("=" * 60 + "\n")

    # Check credentials
    if not check_aws_credentials():
        print("❌ Setup incomplete. Please configure AWS credentials first.\n")
        sys.exit(1)

    # Check S3 access
    if not check_s3_access():
        print("❌ S3 access check failed.\n")
        sys.exit(1)

    # Check data file
    check_s3_data_file()

    # Print configuration
    print_configuration_summary()

    print("=" * 60)
    print("✅ AWS SETUP VERIFICATION COMPLETE!")
    print("=" * 60)
    print("\nYou're ready to use S3 for data loading!")
    print("Run: python src/feature_pipeline/load.py\n")


if __name__ == "__main__":
    main()

