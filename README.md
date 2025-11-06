# `lit-os`

LitOS is a system which helps Operators administer Lit Nodes.

## Overview

This repository contains a few separate components:

### `components/` 

- `common/bundle` : configuration files for `systemd` and Salt Stack
- `common/salt`: Salt Stack configuration which is shared between Host and Guest layers
- `scripts`: `bash` scripts which are run when Lit OS is installed or updated
- `guest`: `bash` scripts which are used in creation and management of Guest VMs
- `host`: `bash` scripts which are used in creation and management of the Host environment
- `internal`: Salt Stack configuration which can be used as an overlay, containing authorization for Lit team members

## `node/` and `prov/`

The Node and Prov folders contain scripts and Salt Stack configuration which references elements in the `components/` directory, and is used to construct the `node` and `prov` VM environments in Lit OS.

## Developing LitOS 

If you're developing locally and need to upload to your working environment:

```
make
scp user@host.litgateway.com:~/lit-os-prov.tar.gz lit-os-prov.tar.gz
```