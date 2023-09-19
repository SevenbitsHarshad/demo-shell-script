#!/bin/bash
mkdir -p /home/adminuser/sei-fullnode
sudo chown -R adminuser:adminuser /home/adminuser/sei-fullnode

# Install required packages
sudo apt update
sudo apt install -y jq lz4 make cmake gcc

# Download and install Go
wget https://golang.org/dl/go1.19.3.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.19.3.linux-amd64.tar.gz
rm go1.19.3.linux-amd64.tar.gz

# Configure Go environment variables
echo 'export GOROOT=/usr/local/go' >> /home/adminuser/.profile
echo 'export GOPATH=/home/adminuser/go' >> /home/adminuser/.profile
echo 'export GO111MODULE=on' >> /home/adminuser/.profile
echo 'export PATH=$PATH:/usr/local/go/bin:/home/adminuser/go/bin' >> /home/adminuser/.profile
source /home/adminuser/.profile

# Check if Go is installed
sudo chown -R adminuser:adminuser /home/adminuser/go
# Check the exit status of the chown command
if [ $? -eq 0 ]; then
    echo "Ownership change successful."
    echo "Ownership change successful." + $(date) >> /tmp/ownerif.txt
else
    echo "Ownership change failed."
    echo "Ownership change failed." + $(date) >> /tmp/ownerelse.txt
fi
if command -v go &>/dev/null; then
    sudo chmod -R 600 adminuser:adminuser /home/adminuser/go
    # Check the exit status of the chown command
    if [ $? -eq 0 ]; then
        echo "Ownership change successful."
        echo "chmod change successful." + $(date) >> /tmp/chmodif.txt
    else
        echo "Ownership change failed."
        echo "chmod change failed." + $(date) >> /tmp/chmodelse.txt
    fi
    
    # Install cosmovisor
    go install github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor@v1.0.0

    # Clone sei-chain repository
    cd /home/adminuser/sei-fullnode
    git clone https://github.com/sei-protocol/sei-chain.git
    sudo chown -R adminuser:adminuser /home/adminuser/sei-fullnode/sei-chain
    if [ $? -eq 0 ]; then
       
        echo "sei-chain Ownership change successful." + $(date) >> /tmp/seiownerif.txt
    else
        
        echo "sei-chain Ownership change failed." + $(date) >> /tmp/seiownerelse.txt
    fi
    # Checkout a specific version and build the project
    cd sei-chain
    /usr/bin/git fetch origin
    /usr/bin/git checkout v3.0.9
    if  /usr/bin/git checkout v3.0.9; then
        echo "Git checkout." + $(date) >> /tmp/gitcheckif.txt
    else
        echo "Ownership change failed."
        echo "Git checkout failed." + $(date) >> /tmp/gitcheckelse.txt
    fi
    make install
    sleep 10
    source ~/.profile
    source /home/adminuser/.profile
    sleep 5
    mkdir -p /home/adminuser/.sei
    sudo chown -R adminuser:adminuser /home/adminuser/.sei
    seid init seidevcus01 --chain-id pacific-1
    sleep 5
    wget -O /home/adminuser/.sei/config/genesis.json https://snapshots.polkachu.com/genesis/sei/genesis.json --inet4-only
    sed -i 's/seeds = ""/seeds = "ade4d8bc8cbe014af6ebdf3cb7b1e9ad36f412c0@seeds.polkachu.com:11956"/' /home/adminuser/.sei/config/config.toml
    sed -i -e "s|^bootstrap-peers *=.*|bootstrap-peers = \"33b1526dd09adfe1330ac29d51c89505e6363e8b@3.70.17.165:26656,6e1b407d182f58b0e6e2e519d1fc4d823f006273@35.158.58.99:26656\"|" /home/adminuser/.sei/config/config.toml
    mkdir -p /home/adminuser/.sei/cosmovisor/genesis/bin
    mkdir -p /home/adminuser/.sei/cosmovisor/upgrades
    cp /home/adminuser/go/bin/seid /home/adminuser/.sei/cosmovisor/genesis/bin
fi
#go install github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor@v1.0.00
