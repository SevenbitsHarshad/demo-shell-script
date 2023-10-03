#!/bin/bash

sudo apt update
sudo apt install -y jq lz4 build-essential

curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
#sudo apt-get install azure-cli
 
az_version_output=$(az --version)

# Use echo to display the captured output
echo "az_version_output: $az_version_output"

az login --identity
# Check the exit code of the az login command
if [ $? -eq 0 ]; then
    echo "Azure login with managed identity was successful."
else
    echo "Azure login with managed identity failed."
    # Add error handling or exit the script if needed
fi

sudo chown -R sxt-admin:sxt-admin /home/sxt-admin/go
sudo chmod -R 0775 /home/sxt-admin/go

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

data_disk_name="$instance_name_res-data-disk"
echo "data_disk_name: $data_disk_name"


#check disk attach or not
has_disks=$(az vmss show --resource-group "$rgName" --name "$vmssName" --instance-id "$instance_id" --query 'storageProfile.dataDisks' --output json)
echo "has_disks: $has_disks"
if [ "$(echo "$has_disks" | jq '. | length')" -ne 0 ]; then
    echo "The disk $data_disk_name exists in resource group $rgName."
else
    # Check if the disk exists or not
    if az disk show --name "$data_disk_name" --resource-group "$rgName" &> /dev/null; then
        echo "The disk $data_disk_name exists in resource group $rgName."
    else

        # Check if snapshot ID are null"
        if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
        then
            # Create new disk volumes with 1024GB size
            while true; do
                vmDiskStatus=$(az disk create  --resource-group $rgName --name $data_disk_name --size-gb 1024 --tags Name=$tag_value_disk)
                echo "vmDiskStatus: $vmDiskStatus"
                if [ "$vmDiskStatus" != "null" ]; then
                    echo "Data disk create succeeded from snapshot id."
                    break
                else
                    echo "Waiting for data disk create to complete..."
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
        fi
    fi

    status=$(az vmss get-instance-view --resource-group "$rgName" --name "$vmssName" --instance-id "$instance_id" --query 'statuses[?code==`ProvisioningState/succeeded`]' --output tsv)
    if [ ! -z "$status" ]; then
        echo "VMSS instance $instance_id is provisioned and ready."
        while true; do
            attachment_state=$(az vmss disk attach -g "$rgName" --vmss-name "$vmssName" --instance-id "$instance_id" --disk "$data_disk_name")
            if [ ! -z "$attachment_state" ]; then
                echo "Data disk attachment succeeded."
                break
            else
                echo "Waiting for data disk attachment to complete..."
                sleep 10
            fi
        done
    fi
     
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
     
    if command -v go &>/dev/null; then

        if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
        then
            # Install cosmovisor
            go install github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor@v1.0.0    
            if [ $? -eq 0 ]; then
                echo "cosmos install sucess" + $(date) >> /tmp/cosmosinstall.txt
            else
                echo "cosmos install fail" + $(date) >> /tmp/cosmosinstall.txt
            fi

            mkdir -p /home/sei_data/sei-chain
            sudo chown -R sxt-admin:sxt-admin /home/sei_data/sei-chain
            sudo chmod -R 0775 /home/sei_data/sei-chain

            sudo cp -r /home/sxt-admin/sei-fullnode/demo-shell-script/sei-chain-dir/ /home/sei_data/sei-chain
            cd /home/sei_data/sei-chain/sei-chain-dir
            #git clone https://github.com/sei-protocol/sei-chain.git
            #sudo chown -R sxt-admin:sxt-admin /home/sei_data/sei-chain
            #cd sei-chain
            #git checkout v3.0.9
            #if [ $? -eq 0 ]; then
            #    echo "git checkout sucess" + $(date) >> /tmp/gitcheckout.txt
            #else
            #    echo "git checkout fail" + $(date) >> /tmp/gitcheckout.txt
            #fi
        else
            sudo cp -r /home/sei_data/go /home/sxt-admin
            cd /home/sei_data/sei-chain
        fi
    
        make install
        if [ $? -eq 0 ]; then
            echo "make install sucess" + $(date) >> /tmp/makeinstall.txt
        else
            echo "make install fail" + $(date) >> /tmp/makeinstall.txt
        fi
        sleep 10
        source ~/.profile
        if [ $? -eq 0 ]; then
            echo "source update sucess" + $(date) >> /tmp/sourceupdate.txt
        else
            echo "source update fail" + $(date) >> /tmp/sourceupdate.txt
        fi

        source /home/sxt-admin/.profile
        if [ $? -eq 0 ]; then
            echo "source update sucess" + $(date) >> /tmp/sourceupdate.txt
        else
            echo "source update fail" + $(date) >> /tmp/sourceupdate.txt
        fi
        sleep 10
        seid init seidevcus01 --chain-id pacific-1 --home "/home/sei_data"
        if [ $? -eq 0 ]; then
            echo "seid  version sucess" + $(date) >> /tmp/seidversion.txt
        else
            echo "seid  version fail" + $(date) >> /tmp/seidversion.txt
        fi
        
        wget -O /home/sei_data/config/genesis.json https://snapshots.polkachu.com/genesis/sei/genesis.json --inet4-only
        sed -i 's/seeds = ""/seeds = "ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:11956"/' /home/sei_data/config/config.toml
        sed -i -e "s|^bootstrap-peers *=.*|bootstrap-peers = \"33b1526dd09adfe1330ac29d51c89505e6363e8b@3.70.17.165:26656,6e1b407d182f58b0e6e2e519d1fc4d823f006273@35.158.58.99:26656\"|" /home/sei_data/config/config.toml

        # Create Cosmovisor Folders
        mkdir -p /home/sei_data/cosmovisor/genesis/bin
        mkdir -p /home/sei_data/cosmovisor/upgrades

        # Load Node Binary into Cosmovisor Folder
        cp $HOME/go/bin/seid /home/sei_data/cosmovisor/genesis/bin
        #seid start --home "/home/sei_data"

        if { [ -z "$latest_snapshot_id" ] || [ "$latest_snapshot_id" == "null" ] ; }
        then
            sudo cp -r /home/sxt-admin/go /home/sei_data
        fi
    fi
fi
