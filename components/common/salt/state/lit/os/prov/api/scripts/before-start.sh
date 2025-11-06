#!/bin/bash

mkdir -p /var/lit/os/prov/shared/releases
mkdir -p /var/lit/os/prov/shared/keys

/usr/bin/setfacl -m g:lit-prov:rwx /var/lit/os/prov/shared
/usr/bin/setfacl -m g:lit-prov:rwx /var/lit/os/prov/shared/*