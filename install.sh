#!/bin/bash

clear
echo "Please wait..."
sudo apt update -y > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1
mkdir -p /etc/autobackup
clear

echo "==============================================="
echo "   AutoBackup Script - Automatic Installer"
echo "       Created by Odidak | Indonesia"
echo "              Version 1.0.0"
echo "==============================================="
echo "Choose an option:"
echo "1) Install Backup Data"
echo "2) Install Backup Database"
echo "3) Uninstall Backup Data"
echo "4) Uninstall Backup Database"
read -p "Enter your choice (1/2/3/4): " BACKUP_CHOICE

if [ "$BACKUP_CHOICE" -eq 1 ]; then
    echo "Installing dependencies required for data backup..."
    sleep 2
    sudo apt install cron curl zip tar rclone -y > /dev/null 2>&1
    echo "Dependencies for data backup installed."

    read -p "Enter the name of the Rclone remote (e.g., myremote): " RCLONE_REMOTE_NAME
    read -p "Enter the path to the directory on Google Drive for backup (e.g., backups): " GDRIVE_DIR
    read -p "Enter the base directory to store backup (e.g., /path/to/backup): " BASE_DIR
    read -p "Enter the Webhook URL for notifications (or leave blank for no notifications): " WEBHOOK_URL

    echo "Choose backup format:"
    echo "1) zip"
    echo "2) tar.gz"
    read -p "Enter your choice (1/2): " FORMAT_CHOICE

    if [ "$FORMAT_CHOICE" -eq 1 ]; then
        BACKUP_FORMAT="zip"
    elif [ "$FORMAT_CHOICE" -eq 2 ]; then
        BACKUP_FORMAT="tar.gz"
    else
        echo "Invalid format choice!"
        exit 1
    fi

    cat <<EOL > /etc/autobackup/backupdata.sh
#!/bin/bash

set -euo pipefail
IFS=\$'\n\t'

RCLONE_REMOTE_NAME="${RCLONE_REMOTE_NAME}"
GDRIVE_DIR="${GDRIVE_DIR}"
WEBHOOK_URL="${WEBHOOK_URL}"
TITLE_STATUS="Backup Data Status"
TITLE_START="Backup Data Status"
DESCRIPTION_START="Data backup process has started."
DESCRIPTION_STATUS="Data backup process completed."
DESCRIPTION_FAIL_ALL="Backup failed - all folders failed."
COLOR_START=3447003
COLOR_STATUS=3066993
COLOR_FAIL_ALL=15158332
BACKUP_FORMAT="${BACKUP_FORMAT}"
BASE_DIR="${BASE_DIR}"
TEMP_DIR="\$(mktemp -d)"
trap 'rm -rf "\${TEMP_DIR}"' EXIT

DATE_DIR="\$(date +"%Y-%m-%d_%H-%M-%S")"
GDRIVE_DATE_DIR="\${GDRIVE_DIR}/\${DATE_DIR}"

# Create necessary directories
mkdir -p "\${TEMP_DIR}" || { echo "Failed to create temp directory"; exit 1; }
rclone mkdir "\${RCLONE_REMOTE_NAME}:\${GDRIVE_DATE_DIR}" || { echo "Failed to create remote directory"; exit 1; }

# Function to automatically format size
format_size() {
    local size=\$1
    local size_kb=\$(echo "scale=2; \$size / 1024" | bc)
    local size_mb=\$(echo "scale=2; \$size / 1024 / 1024" | bc)
    local size_gb=\$(echo "scale=2; \$size / 1024 / 1024 / 1024" | bc)
    
    local size_kb_int=\$(echo "\$size_kb * 100" | bc | cut -d'.' -f1)
    local size_mb_int=\$(echo "\$size_mb * 100" | bc | cut -d'.' -f1)
    local size_gb_int=\$(echo "\$size_gb * 100" | bc | cut -d'.' -f1)
    
    if [ \$size_gb_int -ge 100 ]; then
        echo "\$size_gb GB"
    elif [ \$size_mb_int -ge 100 ]; then
        echo "\$size_mb MB"
    else
        echo "\$size_kb KB"
    fi
}

# Send start notification
if [[ -n "\${WEBHOOK_URL}" ]]; then
    curl -H "Content-Type: application/json" \
         -X POST \
         -d "{
               \"embeds\": [
                 {
                   \"title\": \"\${TITLE_START}\",
                   \"description\": \"**[⚒️] | Status :** \${DESCRIPTION_START}\",
                   \"color\": \${COLOR_START}
                 }
               ]
             }" \
         "\${WEBHOOK_URL}"
fi

backup_folder() {
    local folder="\$1"
    local backup_file="\$2"
    case "\${BACKUP_FORMAT}" in
        zip) zip -r "\${backup_file}" "\${folder}" ;;
        tar.gz) tar -czf "\${backup_file}" "\${folder}" ;;
        *) echo "Invalid backup format!"; return 1 ;;
    esac
}

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_FOLDERS=""
TOTAL_SIZE=0

for folder in "\${BASE_DIR}"/*; do
    if [ -d "\${folder}" ]; then
        FOLDER_NAME=\$(basename "\${folder}")
        BACKUP_FILE="\${TEMP_DIR}/\${FOLDER_NAME}.\${BACKUP_FORMAT}"
        
        if backup_folder "\${folder}" "\${BACKUP_FILE}"; then
            FILE_SIZE=\$(stat -c%s "\${BACKUP_FILE}")
            TOTAL_SIZE=\$((TOTAL_SIZE + FILE_SIZE))
            
            if rclone copy "\${BACKUP_FILE}" "\${RCLONE_REMOTE_NAME}:\${GDRIVE_DATE_DIR}/\${FOLDER_NAME}.\${BACKUP_FORMAT}"; then
                echo "Backup folder \${FOLDER_NAME} successfully saved to \${GDRIVE_DATE_DIR}/\${FOLDER_NAME}.\${BACKUP_FORMAT}"
                SUCCESS_COUNT=\$((SUCCESS_COUNT + 1))
            else
                echo "Backup folder \${FOLDER_NAME} failed when copying to Google Drive."
                FAIL_COUNT=\$((FAIL_COUNT + 1))
                FAILED_FOLDERS+="\${FOLDER_NAME} "
            fi
        else
            echo "Backup folder \${FOLDER_NAME} failed!"
            FAIL_COUNT=\$((FAIL_COUNT + 1))
            FAILED_FOLDERS+="\${FOLDER_NAME} "
        fi
    fi
done

# Format the total size automatically
FORMATTED_SIZE=\$(format_size \${TOTAL_SIZE})

if [[ -n "\${WEBHOOK_URL}" ]]; then
    if [[ \${FAIL_COUNT} -gt 0 ]]; then
        curl -H "Content-Type: application/json" \
             -X POST \
             -d "{
                   \"embeds\": [
                     {
                       \"title\": \"\${TITLE_STATUS}\",
                       \"description\": \"**[❌] | Status :** \${DESCRIPTION_FAIL_ALL}\n**Failed Folders:** \${FAILED_FOLDERS}\",
                       \"color\": \${COLOR_FAIL_ALL}
                     }
                   ]
                 }" \
             "\${WEBHOOK_URL}"
    else
        curl -H "Content-Type: application/json" \
             -X POST \
             -d "{
                   \"embeds\": [
                     {
                       \"title\": \"\${TITLE_STATUS}\",
                       \"description\": \"**[✅] | Status :** \${DESCRIPTION_STATUS}\n**Total Size:** \${FORMATTED_SIZE}\n**Total Successful Backups:** \${SUCCESS_COUNT}\n**Total Failed Backups:** \${FAIL_COUNT}\",
                       \"color\": \${COLOR_STATUS}
                     }
                   ]
                 }" \
             "\${WEBHOOK_URL}"
    fi
fi

if [[ \${TOTAL_SIZE} -gt 0 ]]; then
    echo "Total backup size: \${FORMATTED_SIZE}"
else
    echo "No data was successfully backed up."
fi

rm -rf "\${TEMP_DIR}"
EOL

    chmod +x /etc/autobackup/backupdata.sh

    if ! crontab -l | grep -q '/etc/autobackup/backupdata.sh'; then
        (crontab -l 2>/dev/null; echo "0 0 * * * /etc/autobackup/backupdata.sh") | crontab -
        echo "Daily data backup schedule has been added."
    else
        echo "Data backup cron job already exists."
    fi

elif [ "$BACKUP_CHOICE" -eq 2 ]; then
    echo "Installing dependencies required for database backup..."
    sleep 2
    sudo apt install cron curl rclone -y > /dev/null 2>&1
    echo "Dependencies for database backup installed."

    read -p "Enter the name of the Rclone remote (e.g., myremote): " RCLONE_REMOTE_NAME
    read -p "Enter the database name to backup: " DB_NAME
    read -p "Enter the database host (default: localhost): " DB_HOST
    read -p "Enter the database user (default: root): " DB_USER
    read -sp "Enter the database password: " DB_PASS
    echo ""
    read -p "Enter the path to the directory on Google Drive for backup (e.g., backups): " GDRIVE_DIR
    read -p "Enter the Webhook URL for notifications (or leave blank for no notifications): " WEBHOOK_URL

    cat <<EOL > /etc/autobackup/backupdb.sh
#!/bin/bash

RCLONE_REMOTE_NAME="$RCLONE_REMOTE_NAME"
DB_NAME="$DB_NAME"
DB_HOST="$DB_HOST"
DB_USER="$DB_USER"
DB_PASS="$DB_PASS"
GDRIVE_DIR="$GDRIVE_DIR"
WEBHOOK_URL="$WEBHOOK_URL"
TITLE_STATUS="Database Backup Status"
TITLE_START="Database Backup Status"
DESCRIPTION_START="Database backup process has started."
DESCRIPTION_STATUS="Database backup process completed."
DESCRIPTION_FAIL="Database backup process failed."
COLOR_START=3447003
COLOR_STATUS=3066993
COLOR_FAIL=15158332
TEMP_DIR="/tmp/BackupDB"
DATE_DIR=\$(date +"%Y-%m-%d_%H-%M-%S")
GDRIVE_DATE_DIR="\$GDRIVE_DIR/\$DATE_DIR"

mkdir -p "\$TEMP_DIR" || { echo "Failed to create directory \$TEMP_DIR"; exit 1; }
rclone mkdir "\$RCLONE_REMOTE_NAME:\$GDRIVE_DATE_DIR" || { echo "Failed to create folder \$GDRIVE_DATE_DIR in Google Drive"; exit 1; }

if [[ -n "\$WEBHOOK_URL" ]]; then
    curl -H "Content-Type: application/json" \
         -X POST \
         -d "{
               \"embeds\": [
                 {
                   \"title\": \"\$TITLE_START\",
                   \"description\": \"**[⚒️] | Status :** \$DESCRIPTION_START\",
                   \"color\": \$COLOR_START
                 }
               ]
             }" \
         "\$WEBHOOK_URL"
fi

BACKUP_FILE="\$TEMP_DIR/\$DB_NAME.sql"

if mysqldump -u "\$DB_USER" -p"\$DB_PASS" -h "\$DB_HOST" "\$DB_NAME" > "\$BACKUP_FILE"; then
    echo "Database backup successful."
    
    if rclone copy "\$BACKUP_FILE" "\$RCLONE_REMOTE_NAME:\$GDRIVE_DATE_DIR/\$DB_NAME.sql"; then
        echo "Database backup successfully saved to \$GDRIVE_DATE_DIR/\$DB_NAME.sql"
        
        if [[ -n "\$WEBHOOK_URL" ]]; then
            curl -H "Content-Type: application/json" \
                 -X POST \
                 -d "{
                       \"embeds\": [
                         {
                           \"title\": \"\$TITLE_STATUS\",
                           \"description\": \"**[✅] | Status :** \$DESCRIPTION_STATUS\",
                           \"color\": \$COLOR_STATUS
                         }
                       ]
                     }" \
                 "\$WEBHOOK_URL"
        fi
    else
        echo "Failed to upload backup to Google Drive."
        
        if [[ -n "\$WEBHOOK_URL" ]]; then
            curl -H "Content-Type: application/json" \
                 -X POST \
                 -d "{
                       \"embeds\": [
                         {
                           \"title\": \"\$TITLE_STATUS\",
                           \"description\": \"**[❌] | Status :** \$DESCRIPTION_FAIL\nFailed to upload to Google Drive\",
                           \"color\": \$COLOR_FAIL
                         }
                       ]
                     }" \
                 "\$WEBHOOK_URL"
        fi
    fi
else
    echo "Database backup failed!"
    
    if [[ -n "\$WEBHOOK_URL" ]]; then
        curl -H "Content-Type: application/json" \
             -X POST \
             -d "{
                   \"embeds\": [
                     {
                       \"title\": \"\$TITLE_STATUS\",
                       \"description\": \"**[❌] | Status :** \$DESCRIPTION_FAIL\nBackup creation failed\",
                       \"color\": \$COLOR_FAIL
                     }
                   ]
                 }" \
             "\$WEBHOOK_URL"
    fi
fi

rm -rf "\$TEMP_DIR"
EOL

    chmod +x /etc/autobackup/backupdb.sh

    if ! crontab -l | grep -q '/etc/autobackup/backupdb.sh'; then
        (crontab -l 2>/dev/null; echo "0 0 * * * /etc/autobackup/backupdb.sh") | crontab -
        echo "Daily database backup schedule has been added."
    else
        echo "Database backup cron job already exists."
    fi

elif [ "$BACKUP_CHOICE" -eq 3 ]; then
    if crontab -l | grep -q '/etc/autobackup/backupdata.sh'; then
        crontab -l | grep -v '/etc/autobackup/backupdata.sh' | crontab -
        echo "Daily data backup schedule has been removed."
    else
        echo "Data backup cron job not found."
    fi
    rm -rf /etc/autobackup/backupdata.sh
    echo "Data backup script has been removed."

elif [ "$BACKUP_CHOICE" -eq 4 ]; then
    if crontab -l | grep -q '/etc/autobackup/backupdb.sh'; then
        crontab -l | grep -v '/etc/autobackup/backupdb.sh' | crontab -
        echo "Daily database backup schedule has been removed."
    else
        echo "Database backup cron job not found."
    fi
    rm -rf /etc/autobackup/backupdb.sh
    echo "Database backup script has been removed."

else
    echo "Invalid option. Exiting."
    exit 1
fi

if [ "$BACKUP_CHOICE" -eq 1 ] || [ "$BACKUP_CHOICE" -eq 2 ]; then
    echo -e "\n============================================="
    echo "          Installation Complete!"
    echo "============================================="
    echo -e "\nImportant Information:"
    echo "-------------------------------------------"
    echo "1. Backup Schedule:"
    echo "   - Default: Every day at 00:00 (Midnight)" 
    echo "   - To change schedule: "
    echo "     1. Type: crontab -e"
    echo "     2. Find line: 0 0 * * * /etc/autobackup/backup*.sh"
    echo "     3. Edit time using format: minute hour day month weekday"
    echo "   - Schedule examples:"
    echo "     * Every 6 hours: 0 */6 * * *"
    echo "     * Every day 2 AM: 0 2 * * *"
    echo "     * Every Sunday 3 AM: 0 3 * * 0"
    echo "     * Every 1st monthly: 0 0 1 * *"

    echo -e "\n2. Manual Backup:"
    if [ "$BACKUP_CHOICE" -eq 1 ]; then
        echo "   Run command: bash /etc/autobackup/backupdata.sh"
        echo "   Backup location: ${GDRIVE_DIR} (Google Drive)"
    elif [ "$BACKUP_CHOICE" -eq 2 ]; then
        echo "   Run command: bash /etc/autobackup/backupdb.sh"
        echo "   Backup location: ${GDRIVE_DIR} (Google Drive)"
    fi

    echo -e "\n3. Useful Commands:"
    echo "   - View cron schedule: crontab -l"
    echo "   - Test rclone: rclone ls ${RCLONE_REMOTE_NAME}:${GDRIVE_DIR}"

    echo -e "\n4. Webhook Status:"
    if [ -n "$WEBHOOK_URL" ]; then
        echo "   Notifications: Enabled"
    else
        echo "   Notifications: Disabled"
    fi

    echo -e "\nNext backup: $(date -d "$(date -d 'tomorrow 00:00')" '+%Y-%m-%d %H:%M:%S')"

elif [ "$BACKUP_CHOICE" -eq 3 ] || [ "$BACKUP_CHOICE" -eq 4 ]; then
    echo -e "\n============================================="
    echo "          Uninstallation Complete!"
    echo "============================================="
    echo -e "\nAll backup scripts and schedules have been removed"
fi

echo "============================================="
echo -e "\nNeed Support?"
echo "============================================="
echo "- Email support: raditm100308@gmail.com"
echo "- WhatsApp support: +62 851-5096-0915"
echo "============================================="
