#!/bin/bash
sudo apt-get install -y expect
echo "Creating prov"
# NOTE: Currently hardcoded for leaseweb-staging-7
export guest_ip="64.131.85.108/26"
export guest_gw="64.131.85.126"
export subnet_id="2f4638aA289f03B8caACe5BD3b017e75758c461F"
export deployer_wallet_key='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
export coms_sender_key='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
export coms_receiver_key='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
export admin_privkey='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
pwd
./expect/create_prov.exp "$subnet_id" "$deployer_wallet_key" "$admin_privkey" "$guest_ip" "$guest_gw"