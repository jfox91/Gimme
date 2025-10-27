# GIMME - Infrastructure Swiss Army Knife 🔧

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/bash-4.0+-green.svg)](https://www.gnu.org/software/bash/)
[![Python](https://img.shields.io/badge/python-3.6+-blue.svg)](https://www.python.org/)

**GIMME** is a powerful CLI tool for managing and querying your infrastructure metadata, Kubernetes clusters, and Nautobot DCIM.

## Features

- 🔍 **Query node metadata** - MAC addresses, IPs, hostnames, clusters, racks, and more
- 🔎 **Reverse lookups** - Find nodes by IP, MAC, or any field
- 🏷️ **Label-based search** - Filter nodes by labels
- ☸️ **Kubernetes integration** - Check node status, versions, find offline nodes
- 📊 **Cluster analytics** - Find oldest nodes, version mismatches
- 🖥️ **Hardware info** - SSH to nodes and get hardware details
- 📦 **Nautobot integration** - Query DCIM data, rack locations, notes
- 🐿️ **Easter egg** - `gimme nut`

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/jfox91/Gimme.git
cd Gimme

# Run the interactive setup wizard
./install.sh

# Reload your shell
source ~/.bashrc
