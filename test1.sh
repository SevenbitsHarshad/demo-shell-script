#!/bin/bash
git clone https://github.com/sei-protocol/sei-chain/ sei
sudo chown -R sxt-admin:sxt-admin /home/sxt-admin/demo-shell-script
sudo chmod -R 775 /home/sxt-admin/demo-shell-script
sudo chown -R sxt-admin:sxt-admin /home/sxt-admin/demo-shell-script/sei
sudo chmod -R 775 /home/sxt-admin/demo-shell-script/sei
git config --global --add safe.directory /home/sxt-admin/demo-shell-script/sei
cd /home/sxt-admin/demo-shell-script/sei
git checkout v3.1.1
