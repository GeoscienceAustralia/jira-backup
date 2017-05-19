#!/bin/bash

echo "Running jira backup script"

# Set this to your Atlassian instance's timezone.
# See this for a list of possible values:
# https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TIMEZONE=Australia/Sydney

# Grabs cookies and generates the backup on the UI.
TODAY=$(TZ=$TIMEZONE date +%Y%m%d)
COOKIE_FILE_LOCATION=jiracookie

echo 'Initiating backup'

curl --silent --cookie-jar $COOKIE_FILE_LOCATION -X POST "https://${INSTANCE}/rest/auth/1/session" -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}" -H 'Content-Type: application/json' --output /dev/null
#The $BKPMSG variable will print the error message, you can use it if you're planning on sending an email
BKPMSG=$(curl -s --cookie $COOKIE_FILE_LOCATION --header "X-Atlassian-Token: no-check" -H "X-Requested-With: XMLHttpRequest" -H "Content-Type: application/json"  -X POST https://${INSTANCE}/rest/obm/1.0/runbackup -d '{"cbAttachments":"true" }' )

#Checks if the backup procedure has failed
if [ "$(echo "$BKPMSG" | grep -ic backup)" -ne 0 ]; then
    echo 'Unable to make backup at this time'
    echo $BKPMSG
    echo 'Emailing Cloud Enablement...'
    ./send-email.sh
fi

#Checks if the backup exists every 10 seconds, 60 times. If you have a bigger instance with a larger backup file you'll probably want to increase that.
for (( c=1; c<=60; c++ ))
    do
    echo 'Checking backup progress...'
    PROGRESS_JSON=$(curl -s --cookie $COOKIE_FILE_LOCATION https://${INSTANCE}/rest/obm/1.0/getprogress.json)
    FILE_NAME=$(echo "$PROGRESS_JSON" | sed -n 's/.*"fileName"[ ]*:[ ]*"\([^"]*\).*/\1/p')

    if [[ $PROGRESS_JSON == *"error"* ]]; then
    break
    fi

    if [ ! -z "$FILE_NAME" ]; then
    break
    fi
    sleep 10
done

echo $PROGRESS_JSON

#If after 60 attempts it still fails it ends the script.
if [ -z "$FILE_NAME" ];
then
        rm $COOKIE_FILE_LOCATION
        echo 'Timeout - exiting'
        exit
else

    #If it's confirmed that the backup exists the file gets copied to the current directory.
    if [[ $FILE_NAME == *"ondemandbackupmanager/download"* ]]; then
        #Download the new way, starting Nov 2016
        #wget --load-cookies=$COOKIE_FILE_LOCATION -t 0 --retry-connrefused "https://${INSTANCE}/$FILE_NAME" -O "JIRA-backup-${TODAY}.zip" >/dev/null 2>/dev/null
        curl --silent --show-error --location --cookie $COOKIE_FILE_LOCATION --request GET --url https://${INSTANCE}/$FILE_NAME --output jira-backup-${TODAY}.zip
        else
        #Deprecated download from WEBDAV
        echo "Attempted to download from WEBDAV directory, which is no longer supported"
    fi

fi

rm $COOKIE_FILE_LOCATION

echo 'Uploading to S3 bucket...'
aws s3 cp jira-backup-${TODAY}.zip s3://${S3_BUCKET}/
