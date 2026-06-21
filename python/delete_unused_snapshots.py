import boto3

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    print("--- Unused EBS Snapshot Cleanup Process Started ---")

    # Step 1: Get all active AMIs owned by 'self' (your current account)
    try:
        amis = ec2.describe_images(Owners=['self'])
        ami_snapshot_ids = set()
        
        # Extract snapshot IDs that are mapped to active cloud images
        for ami in amis['Images']:
            for bdm in ami.get('BlockDeviceMappings', []):
                if 'Ebs' in bdm and 'SnapshotId' in bdm['Ebs']:
                    ami_snapshot_ids.add(bdm['Ebs']['SnapshotId'])
        
        print(f"Found {len(ami_snapshot_ids)} snapshots linked to active AMIs. These are safe.")

    except Exception as e:
        print(f"Error fetching active AMIs: {e}")
        return {'statusCode': 500, 'body': 'Failed to fetch AMIs'}

    # Step 2: Fetch all block snapshots owned by your account profile
    try:
        snapshots = ec2.describe_snapshots(OwnerIds=['self'])
        deleted_count = 0

        for snapshot in snapshots['Snapshots']:
            snapshot_id = snapshot['SnapshotId']
            description = snapshot.get('Description', '')

            # Check if target snapshot identifier matches active AMI lists
            if snapshot_id not in ami_snapshot_ids:
                
                # Filter out orphaned items generated from older deleted images
                if "Created by CreateImage" in description:
                    try:
                        print(f"Found orphaned AMI snapshot: {snapshot_id}. Deleting...")
                        ec2.delete_snapshot(SnapshotId=snapshot_id)
                        deleted_count += 1
                    except Exception as delete_error:
                        # Catch dynamic locks safely if resources are currently bounded
                        print(f"Could not delete resource {snapshot_id}: {delete_error}")
                        continue

        print(f"Cleanup completed. Total unused snapshots removed: {deleted_count}")
        return {
            'statusCode': 200,
            'body': f"Process finished successfully. Deleted {deleted_count} snapshots."
        }

    except Exception as e:
        print(f"Error scanning snapshots metadata arrays: {e}")
        return {'statusCode': 500, 'body': 'Process failed during snapshot scan'}
