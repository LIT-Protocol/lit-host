#!/bin/bash
sudo apt-get install -y expect
echo "Creating node"
# NOTE: Currently hardcoded for leaseweb-staging-7
export guest_ip="64.131.85.108/26"
export guest_gw="64.131.85.126"
# NOTE: Dummy networks and addresses for everything except admin address(no networking is tested)
export subnet_id="2f4638aA289f03B8caACe5BD3b017e75758c461F"
export staker_address='0x2f4638aA289f03B8caACe5BD3b017e75758c461F'
export wallet_key='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
export coms_sender_key='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
export coms_receiver_key='DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF'
export admin_address='0x4C06111c11556284cA3A9660Eae340c6485C2BAD'
pwd
./expect/create_node.exp "$guest_ip" "$guest_gw" "$subnet_id" "$staker_address" "$wallet_key" "$coms_sender_key" "$coms_receiver_key" "$admin_address"