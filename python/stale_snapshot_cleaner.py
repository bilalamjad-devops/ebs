import boto3
import botocore

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    print("--- Starting Automated EBS Snapshot Optimization Routine ---")
    
    # Fetch all snapshots owned by this current AWS account
    try:
        snapshots_response = ec2.describe_snapshots(OwnerIds=['self'])
        snapshots = snapshots_response.get('Snapshots', [])
    except Exception as e:
        print(f"Error fetching snapshots: {str(e)}")
        return {'statusCode': 500, 'body': 'Failed to fetch snapshots.'}
        
    print(f"Total snapshots discovered in this region: {len(snapshots)}")
    deleted_count = 0
    
    for snapshot in snapshots:
        snapshot_id = snapshot['SnapshotId']
        volume_id = snapshot.get('VolumeId')
        
        # Skip if snapshot doesn't have an associated volume metadata mapping
        if not volume_id:
            continue
            
        try:
            # Check if the baseline volume still exists in AWS
            ec2.describe_volumes(VolumeIds=[volume_id])
            print(f"Snapshot {snapshot_id} is active. Associated volume {volume_id} is live.")
            
        except botocore.exceptions.ClientError as e:
            # If the error code matches NotFound, the parent asset is gone
            if e.response['Error']['Code'] == 'InvalidVolume.NotFound':
                print(f"Orphaned Snapshot Detected: {snapshot_id} (Reason: Volume {volume_id} no longer exists).")
                try:
                    ec2.delete_snapshot(SnapshotId=snapshot_id)
                    print(f"Successfully purged stale snapshot: {snapshot_id}")
                    deleted_count += 1
                except Exception as del_err:
                    print(f"Failed to delete snapshot {snapshot_id}: {str(del_err)}")
            else:
                print(f"AWS API Error processing validation on volume {volume_id}: {str(e)}")
                
    print(f"--- Optimization Routine Finished. Total Stale Snapshots Purged: {deleted_count} ---")
    return {
        'statusCode': 200,
        'body': f'Optimization complete. Purged {deleted_count} stale snapshots.'
    }
