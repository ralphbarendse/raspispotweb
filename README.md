# Spotweb Installation Script

Simple script to install Spotweb on any Debian-based system (including Synology DSM).

## How to use

1. Download the script:
```bash
wget https://raw.githubusercontent.com/ralphbarendse/spotweb-installer/main/install_spotweb.sh
chmod +x install_spotweb.sh
```

2. Run it:
```bash
./install_spotweb.sh
```

3. Answer the questions when prompted:
- Hostname of your server
- SSH username
- SSH password
- Timezone (default: Europe/Amsterdam)
- Port for Spotweb (default: 8080)
- Usenet server details

## Features

- 🚀 Fully automated installation
- 🔧 Works on Debian (personally made the script and tested it on a Raspberry Pi 4 (8GB RAM))
- 📦 Installs and configures all dependencies
- ⏱️ Sets up automatic hourly spot retrieval
- 🔒 Secure default configuration 
