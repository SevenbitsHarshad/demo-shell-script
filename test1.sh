#!/bin/bash
git clone https://github.com/sei-protocol/sei-chain/ sei
sudo chown -R sxt-admin:sxt-admin /home/sxt-admin/sei
sudo chmod -R 775 /home/sxt-admin/sei
cd /home/sxt-admin/sei
git checkout v3.1.1
