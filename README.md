# diepxuan-repositories

DiepXuan PPA - Microsoft APT Repository Setup

## Overview

Package `diepxuan-repositories` adds Microsoft APT repository to the system.
It enables installation of:
- **msodbcsql18** - Microsoft ODBC Driver for SQL Server
- **unixodbc-dev** - ODBC development files
- Other Microsoft packages

## Installation

```bash
apt install diepxuan-repositories
```

This will:
1. Import Microsoft GPG key to `/usr/share/keyrings/microsoft-prod.gpg`
2. Add Microsoft APT repository to `/etc/apt/sources.list.d/microsoft-prod.list`
3. Run `apt-get update`

## Usage

After installation, you can install Microsoft packages:

```bash
apt install msodbcsql18
apt install unixodbc-dev
```

## Dependencies

- curl
- gnupg
- lsb-release
- apt-transport-https

## License

MIT - See LICENSE file for details.

## Author

Tran Ngoc Duc <ductn@diepxuan.com>
DiepXuan Co., Ltd
