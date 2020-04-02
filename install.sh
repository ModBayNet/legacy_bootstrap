#!/bin/sh

#FIXME: this should be enabled but it makes script exit on EdgeDB loop
#set -e -o pipefail

MODBAY_MANAGER_CONFIG='config/manager.yaml'
MODBAY_WORKER_CONFIG='config/worker.yaml'

EDGEDB_ROLE_NAME='modbay_beta'
EDGEDB_DATABASE_NAME=$EDGEDB_ROLE_NAME

docker-compose down --remove-orphans

#TODO: check if EdgeDB volume exists and initialize if missing

# to remove edgedb volume (THIS WILL WIPE YOUR DATA): docker volume rm modbay-edgedb 
printf "Creating volumes...\n"
docker volume create --name=modbay-redis
docker volume create --name=modbay-edgedb

cleanup () {
	printf "\n"
	printf "Cleaning up...\n"
	docker-compose stop redis
	docker-compose stop edgedb
	exit 0
}

#FIXME: ask password inside docker exec block. currently it is not possible because of the absense of -i flag
# or some other weird TTY issue
getpass()
{
	read -sp "Please, enter password for $1: " password
	printf "$password"
}

trap cleanup 1 2 3 6 EXIT

printf "Setting up redis...\n"
docker-compose up -d redis

REDIS_PASSWORD=$(getpass "Redis database")
printf "\n"

docker-compose exec redis redis-cli config set requirepass "$REDIS_PASSWORD" >/dev/null
docker-compose stop redis

printf "Setting up EdgeDB...\n"
docker-compose up -d edgedb

EDGEDB_PASSWORD=$(getpass "EdgeDB database")
printf "\n"

printf "Waiting for EdgeDB to come online...\n"
printf "If you are seing this for a long time, check EdgDB logs with:\n"
printf "\tdocker-compose logs -f edgedb\n\n"

printf "waiting"

#FIXME: a better way to wait for EdgeDB
#
#this was implemented in edgedb, waiting for new CLI to be merged
#https://github.com/edgedb/edgedb-cli/issues/4
while [ true ]
do
	printf "."
	sleep 3

	cat <<EOF | docker-compose exec -T edgedb sh >/dev/null 2>&1
		set -e
		echo $EDGEDB_PASSWORD | edgedb --admin create-superuser-role --password-from-stdin $EDGEDB_ROLE_NAME
		echo "CREATE DATABASE $EDGEDB_DATABASE_NAME;" | edgedb --admin
EOF
	[ $? -eq 0 ] && break
done

printf "\n"
printf "Done, you can run service with:\n"
printf "\tdocker-compose up\n"
