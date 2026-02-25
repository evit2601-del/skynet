#!/bin/bash
set -e
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
systemctl restart xray-skynet || true
