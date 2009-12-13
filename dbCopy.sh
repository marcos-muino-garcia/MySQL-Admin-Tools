#!/bin/sh

TMP_DIR="/tmp"
#mkdir -p $TMP_DIR
#chmod a+w $TMP_DIR

function usage {
    echo 'Usage: '$0' sourceHost sourcePort sourceUser sourcePassword targetHost targetPort targetUser targetPassword database1 database2 ...'
    exit
}

MYSQL="$(which mysql) --protocol=tcp"
MYSQLDUMP="$(which mysqldump) --protocol=tcp"

if [ $# -lt 9 ]; then
    usage
fi

sourceHost=$1
shift
sourcePort=$1
shift
sourceUser=$1
shift
sourcePassword=$1
shift
targetHost=$1
shift
targetPort=$1
shift
targetUser=$1
shift
targetPassword=$1
shift

echo 'Replicating '$#' databases: '$@

INIT=`date +%s`

for db in $@; do

    echo "Replicating database $db"

    echo "drop database if exists $db;" | $MYSQL -h $targetHost -P $targetPort -u $targetUser -p$targetPassword
    echo "create database $db;" | $MYSQL -h $targetHost -P $targetPort -u $targetUser -p$targetPassword

    $MYSQLDUMP -h $sourceHost -P $sourcePort -u $sourceUser -p$sourcePassword --no-data $db | $MYSQL -h $targetHost -P $targetPort -u $targetUser -p$targetPassword $db

    echo "    DDL executed"

    TABLES=$($MYSQL -h $sourceHost -P $sourcePort -u $sourceUser -p$sourcePassword -Bse 'show full tables from '$db | grep 'BASE TABLE' | awk '{print $1}')

    for table in $TABLES; do
        echo "Disabling keys for table $db.$table"

        echo "alter table $db.$table disable keys;" | $MYSQL -h $targetHost -P $targetPort -u $targetUser -p$targetPassword
    done

    for table in $TABLES; do
        echo "Replicating table $db.$table"

        DATA_TABLE_FILE="$TMP_DIR/$db.$table.pipe"

        mkfifo $DATA_TABLE_FILE
        chmod 666 $DATA_TABLE_FILE

        $MYSQL -h $sourceHost -P $sourcePort -u $sourceUser -p$sourcePassword -qBse "select /*!40001 SQL_NO_CACHE */ * from $db.$table" >> $DATA_TABLE_FILE &
        $MYSQL -h $targetHost -P $targetPort -u $targetUser -p$targetPassword -e "LOAD DATA LOCAL INFILE '$DATA_TABLE_FILE' INTO TABLE $db.$table"

        rm -f $DATA_TABLE_FILE
    done

    for table in $TABLES; do

        echo "Enabling keys for table $db.$table"

        echo "alter table $db.$table enable keys;" | $MYSQL -h $targetHost -P $targetPort -u $targetUser -p$targetPassword
    done

done

END_EXPORT=`date +%s`
EXECUTION_TIME=`echo "($END_EXPORT-$INIT)"|bc`
echo 'Databases successfully replicated in '$EXECUTION_TIME' seconds'
