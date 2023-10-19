from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.compute.models import Snapshot
from datetime import datetime

# Replace these variables with your actual values
subscription_id = "0acb0567-53f9-4062-8e2e-4757e4814cd8"
resource_group_name = "sei_full_node_Archival_sei_node"
location = "Central US"

# get current date and time
current_datetime = datetime.now().strftime("%Y%m%d%H%M%S")
str_current_datetime = str(current_datetime)

snapshot_name = "sei-snapshot_"+str_current_datetime
disk_tag_key = "Name"
disk_tag_value = "sei-disk-test"



# Authenticate using the default Azure credentials
credential = DefaultAzureCredential()

# Create a ComputeManagementClient
compute_client = ComputeManagementClient(credential, subscription_id)

# Find the oldest disk with the specified tag
oldest_disk = None
oldest_creation_time = None

disks = compute_client.disks.list_by_resource_group(resource_group_name)
 
for disk in disks:
      
      if disk.tags and disk.tags.get(disk_tag_key) == disk_tag_value:
        creation_time = disk.time_created
        if oldest_creation_time is None or creation_time < oldest_creation_time:
              oldest_disk = disk
              oldest_creation_time = creation_time

# Check if the oldest disk was found
if oldest_disk:
    print(oldest_disk.id)
    # Create a Snapshot object
    snapshot = Snapshot(
    location="Central US",  # Replace with your desired location
    creation_data=compute_client.snapshots.models.CreationData(
        create_option="Copy", source_resource_id=oldest_disk.id
    ),
    tags={
        "Name": "sei-node-snapshot"
        })

    # Create the snapshot
    compute_client.snapshots.begin_create_or_update(
        resource_group_name, snapshot_name, snapshot
    ).result()

    print("Incremental Snapshot '{snapshot_name}' created successfully.")
else:
    print("No disk with the specified tag found in the resource group.")