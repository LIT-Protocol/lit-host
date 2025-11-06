#!/bin/bash

set -e

hostnamectl set-hostname $(cat /etc/hostname)
