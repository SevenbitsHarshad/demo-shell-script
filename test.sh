#!/bin/bash

sudo apt update
#sudo apt install -y jq lz4 build-essential
sudo apt install -y jq lz4

curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
#sudo apt-get install azure-cli
 
az_version_output=$(az --version)

# Use echo to display the captured output
echo "az_version_output: $az_version_output"

#az login --identity
az login --identity
# Check the exit code of the az login command
if [ $? -eq 0 ]; then
    echo "Azure login with managed identity was successful."
else
    echo "Azure login with managed identity failed."
    while true; do
        az login --identity
        if [ $? -eq 0 ]; then
            echo "Azure login with managed identity was successful. from wait"
            break
        else
            echo "Azure login with managed identity failed. wait 120"
            sleep 120
        fi
    done
    # Add error handling or exit the script if needed
fi

 
sleep 5


# Replace the following with your actual tag key and value
tag_key_snapshot="Name"
tag_value_snapshot="sei-node-snapshot"
tag_value_disk="sei-disk-test"

# Describe snapshots with the given tag key and value, and extract the latest SnapshotId using jq
latest_snapshot_id=$(az snapshot list --query "[?tags.$tag_key_snapshot=='$tag_value_snapshot'] | sort_by(@, &timeCreated) | [-1].id" --output json | jq -r)
echo "Latest Snapshot ID: $latest_snapshot_id"

rgName=$(curl -X GET -H "Metadata:true"  "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01" -s | jq -r .resourceGroupName)
instance_name_res=$(curl -X GET -H "Metadata:true"  "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01" -s | jq -r .name)
vmssName=$(curl -X GET -H "Metadata:true"  "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01" -s | jq -r .vmScaleSetName)
instance_id="${instance_name_res##*_}"

echo "instanceid: $instance_id"
echo "rgName: $rgName"
echo "vmssName: $vmssName"
echo "instance_name_res: $instance_name_res"

#rgName="terrfor_Archival_sei_node"
#instance_name_res="sei-demo-vm"
data_disk_name="$instance_name_res-data-disk"
echo "data_disk_name: $data_disk_name"

# Function to check the provisioning status of a VMSS instance
check_vmss_provisioning_status() {
    local resource_group="$1"
    local vmss_name="$2"
    local instance_number="$3"

    local status
    status=$(az vmss get-instance-view --resource-group "$resource_group" --name "$vmss_name" --instance-id "$instance_number" --query "statuses[?code=='ProvisioningState/succeeded']" --output tsv)

    if [ -n "$status" ]; then
        echo "VMSS instance $instance_number is provisioned and ready."
        return 0  # Success
    else
        echo "VMSS instance $instance_number is still provisioning. Waiting..."
        return 1  # Still provisioning
    fi
}


# Function to attach a data disk to a VMSS instance
attach_data_disk() {
    local resource_group="$1"
    local vmss_name="$2"
    local instance_number="$3"
    local disk_name="$4"

    # Try to attach the data disk
    az vmss disk attach --resource-group "$resource_group" --vmss-name "$vmss_name" --instance-id "$instance_number" --disk "$disk_name"

    if [ $? -eq 0 ]; then
        echo "Data disk attached successfully to VMSS instance $instance_number."
        return 0  # Success
    else
        echo "Failed to attach data disk to VMSS instance $instance_number."
        return 1  # Error
    fi
}


# Check if snapshot ID are null"
if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
then
    # Create new disk volumes with 1024GB size
    while true; do
        vmDiskStatus=$(az disk create  --resource-group $rgName --name $data_disk_name --size-gb 1024 --tags Name=$tag_value_disk)
        echo "vmDiskStatus: $vmDiskStatus"
        if [ "$vmDiskStatus" != "null" ]; then
            echo "Data disk create succeeded."
            break
        else
            echo "Waiting for data disk create to complete..."
            sleep 10
        fi
    done
    
    # Check VMSS provisioning status and wait until it's provisioned
    #while true; do
    #    vmss_provisioning_status=$(check_vmss_provisioning_status "$rgName" "$vmssName" "$instance_id")
    #    echo "vmss_provisioning_status: $vmss_provisioning_status"
    #    if [ "$vmss_provisioning_status" -eq 0 ]; then
    #        echo "vmss_provisioning_status:$vmss_provisioning_status"
    #        break
    #    else
    #        echo "Waiting vmss provisioning status ready..."
    #        sleep 10
    #    fi
    #done

    while check_vmss_provisioning_status "$resource_group" "$vmss_name" "$instance_number"; do
        sleep 10  # Wait for 120 seconds before checking again
    done

    # Wait for disk attachment
    while true; do
        attachmentState=$(az vmss disk attach  -g $rgName --vmss-name $vmssName --instance-id $instance_id --disk $data_disk_name)
        #attachmentState=$(attach_data_disk "$rgName" "$vmssName"  "$instance_id"  "$data_disk_name")
        if [ "$attachmentState" != "null" ]; then
            echo "Data disk attachment succeeded."
            break
        else
            echo "Waiting for data disk attachment to complete..."
            sleep 10
        fi
    done
else
    # Use the existing snapshots   
    # Wait for disk create
    while true; do
        vmDiskStatus=$(az disk create  --resource-group $rgName --name $data_disk_name --source $latest_snapshot_id --tags Name=$tag_value_disk)
        if [ "$vmDiskStatus" != "null" ]; then
            echo "Data disk create succeeded."
            break
        else
            echo "Waiting for data disk create to complete..."
            sleep 10
        fi
    done

    # Wait for disk attachment
    while true; do
        attachmentState=$(az vmss disk attach  -g $rgName --vmss-name $vmssName --instance-id $instance_id --disk $data_disk_name)
        if [ "$attachmentState" != "null" ]; then
            echo "Data disk attachment succeeded."
            break
        else
            echo "Waiting for data disk attachment to complete..."
            sleep 10
        fi
    done
  
fi
exit
device_name_volume_instance="/dev/sdc"
data_dir_name="/home/sei_data"

if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
then
    # Create a mount point directory
    lsblk
    df -h
    sudo mkfs.ext4 $device_name_volume_instance
fi

sudo mkdir $data_dir_name 
sudo mount $device_name_volume_instance $data_dir_name

uuid=$(sudo blkid -o value -s UUID $device_name_volume_instance)
type_attribute=$(sudo blkid -o value -s TYPE $device_name_volume_instance)
echo "uuid $uuid"
echo "type_attribute $type_attribute"
echo "UUID=$uuid /data $type_attribute defaults,nofail 0 0" | sudo tee -a /etc/fstab

 

sudo chown -R sxt-admin:sxt-admin  $data_dir_name
wget https://golang.org/dl/go1.19.3.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.19.3.linux-amd64.tar.gz

echo 'export GOROOT=/usr/local/go' >> /home/sxt-admin/.profile
echo 'export GOPATH=/home/sxt-admin/go' >> /home/sxt-admin/.profile
echo 'export GO111MODULE=on' >> /home/sxt-admin/.profile
echo 'export PATH=$PATH:/usr/local/go/bin:/home/sxt-admin/go/bin' >> /home/sxt-admin/.profile
source /home/sxt-admin/.profile
exit
if command -v go &>/dev/null; then

    if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
    then
        # Install cosmovisor
        go install github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor@v1.0.0    
        cd /home/sei_data
        git clone https://github.com/sei-protocol/sei-chain.git
        sudo chown -R sxt-admin:sxt-admin /home/sei_data/sei-chain
        cd sei-chain
        git checkout v3.0.9
    else
        sudo cp -r /home/sei_data/go /home/sxt-admin
        cd /home/sei_data/sei-chain
    fi
   
    make install
    sleep 10
    source ~/.profile
    source /home/sxt-admin/.profile
    seid start --home "/home/sei_data"

    if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
    then
        sudo cp -r /home/sxt-admin/go /home/sei_data
    fi
fi
