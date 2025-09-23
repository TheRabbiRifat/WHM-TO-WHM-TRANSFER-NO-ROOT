# WHM-to-WHM Transfer (No Root)

A **simple Bash script** to scan a source WHM server for all **packages** and **accounts/users** under a reseller, without requiring root access.
This script is fully **self-contained** and does **not require `jq`**.

---

## Features

* Works with **reseller WHM credentials**.
* Lists **all available packages** on the source server.
* Lists **all accounts/users** under the reseller.
* Fully **interactive** and prompts for credentials.
* Single file; can be run directly via **curl/wget one-liner**.

---

## Usage

### 1. Run via one-liner

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/TheRabbiRifat/WHM-TO-WHM-TRANSFER-NO-ROOT/main/installer.sh || wget -qO- https://raw.githubusercontent.com/TheRabbiRifat/WHM-TO-WHM-TRANSFER-NO-ROOT/main/installer.sh)"
```

### 2. Follow the prompts

* Enter **source WHM hostname**, username, and password.
* Optionally enter **destination hostname/FTP** info for future backup support.
* The script will then list all **packages** and **accounts/users**.

---

## Example Output

```
==============================================
   WHM-to-WHM Transfer (No Root) Script
==============================================

[*] Fetching all packages from source.example.com...
[*] Found packages:
 - basic
 - standard
 - premium

[*] Fetching all accounts/users under this reseller...
[*] Found accounts/users:
 - user1
 - user2
 - user3

[*] Done. All packages and users listed successfully.
```

---

## Requirements

* **Bash** (tested on Linux systems)
* **curl** or **wget** (to call WHM API over HTTPS)
* **No `jq` needed**

---

## Notes

* **Reseller-level WHM access is required.**
* This script **does not perform migrations or backups**, it only scans and lists information.
* For full account backup/transfer, an FTP destination is needed and the script can be extended to support it.

---

## License

MIT License — free to use, modify, and distribute.
