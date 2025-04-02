# Spotweb Installation Script

Simple script to install Spotweb on a Debian-based system. This script runs through a SSH connection so you do it from the comfort of your personal Unix-machine (Mac, Linux or Windows).

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
- 🔧 Works on Debian (personally made the script and tested it on and for a Raspberry Pi 4 (8GB RAM))
- 📦 Installs and configures all dependencies
- ⏱️ Sets up automatic hourly spot retrieval
- 🔒 Secure default configuration 

## ⚠️ Precautions

- Make sure you have SSH access to your target machine before running the script
- The script will install and configure Nginx - if you already have a web server running, make sure the selected port is available
- Have your Usenet server details ready (server, username, password)
- The script needs sudo access on the target machine
- Backup any existing web server configurations if you have them
- Initial spot retrieval can take several hours depending on your connection speed
- Since I made this script for my own use, I didn't add any error handling or checks. If something goes wrong, you'll have to figure it out yourself.
