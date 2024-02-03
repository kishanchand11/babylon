#!/bin/bash

# Update and upgrade system packagess
sudo apt update && sudo apt upgrade -y

# Set your node moniker provide your input here
MONIKER="YOUR_MONIKER_IS_HERE"   

# Install build tools
sudo apt -qy install curl git jq lz4 build-essential

# Install Go
sudo rm -rf /usr/local/go
curl -Ls https://go.dev/dl/go1.20.12.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
eval "$(echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee /etc/profile.d/golang.sh)"
eval "$(echo 'export PATH=$PATH:$HOME/go/bin' | tee -a $HOME/.profile)"

# Download and build binaries
cd $HOME
rm -rf babylon
git clone https://github.com/babylonchain/babylon.git
cd babylon
git checkout v0.7.2
make build

# Prepare binaries for Cosmovisor
mkdir -p $HOME/.babylond/cosmovisor/genesis/bin
mv build/babylond $HOME/.babylond/cosmovisor/genesis/bin/
rm -rf build

# Create application symlinks
sudo ln -s $HOME/.babylond/cosmovisor/genesis $HOME/.babylond/cosmovisor/current -f
sudo ln -s $HOME/.babylond/cosmovisor/current/bin/babylond /usr/local/bin/babylond -f

# Set up Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest

# Create and start service
cat << EOF | sudo tee /etc/systemd/system/babylon.service
[Unit]
Description=babylon node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.babylond"
Environment="DAEMON_NAME=babylond"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.babylond/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable babylon.service

# Initialize the node
babylond init $MONIKER --chain-id bbn-test-2
curl -Ls https://snapshots.kjnodes.com/babylon-testnet/genesis.json > $HOME/.babylond/config/genesis.json
curl -Ls https://snapshots.kjnodes.com/babylon-testnet/addrbook.json > $HOME/.babylond/config/addrbook.json

# Set seeds and gas prices
sed -i.bak -e "s|^seeds =.*|seeds = \"3f472746f46493309650e5a033076689996c8881@babylon-testnet.rpc.kjnodes.com:16459\"|" \
-e "s|^minimum-gas-prices =.*|minimum-gas-prices = \"0.00001ubbn\"|" $HOME/.babylond/config/config.toml

sed -i.bak -e 's|^pruning =.*|pruning = "custom"|' \
-e 's|^pruning-keep-recent =.*|pruning-keep-recent = "100"|' \
-e 's|^pruning-keep-every =.*|pruning-keep-every = "0"|' \
-e 's|^pruning-interval =.*|pruning-interval = "10"|' $HOME/.babylond/config/app.toml

# Download the latest chain snapshot
curl -L https://snapshots.kjnodes.com/babylon-testnet/snapshot_latest.tar.lz4 | tar -I lz4 -xf - -C $HOME/.babylond/

# Ensure permissions for cosmovisor updates and start the service
[[ -f $HOME/.babylond/data/upgrade-info.json ]] && cp $HOME/.babylond/data/upgrade-info.json $HOME/.babylond/cosmovisor/genesis/upgrade-info.json

sudo systemctl start babylon.service
sudo journalctl -u babylon.service -f --no-hostname -o cat
