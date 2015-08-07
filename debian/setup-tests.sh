#!/bin/bash
set -x -e

clean_exit () {
    local error_code="$?"
    # Shutdown PGSQL
    ${PGSQL_PATH}/pg_ctl -w -D ${PGSQL_DATA} -o "-p $PGSQL_PORT" stop
    rm -rf ${PGSQL_DATA}

    # Shutdown MySQL
    kill $(jobs -p)
    rm -rf ${MYSQL_DATA}
    return $error_code

    # Shutdown of memcached
    kill $MEMCACHED_PID

    # Shutdown of redis
#    kill $REDIS_SERVER_PID
}

wait_for_line () {
    while read line
    do
        echo "$line" | grep -q "$1" && break
    done < "$2"
    # Read the fifo for ever otherwise process would block
    cat "$2" >/dev/null &
}

wait_for_mysql_ping () {
	echo -n pinging mysqld.
	attempts=0
	while ! /usr/bin/mysqladmin --socket=${MYSQL_DATA}/mysql.socket ping ; do
		sleep 3
		attempts=$((attempts+1))
		if [ ${attempts} -gt 3 ] ; then
			echo "skipping test, mysql server could not be contacted after 30 seconds"
			exit 1
		fi
	done
}

get_random_port () {
	PORT=13306
	while netstat -atwn | grep "^.*:${PORT}.*:\*\s*LISTEN\s*$"
	do
		PORT=$(( ${PORT} + 1 ))
	done
}


trap "clean_exit" EXIT

PGSQL_DATA=`mktemp -d /tmp/tooz-pgsql-XXXXX`
PGSQL_PORT=9825
PGSQL_PATH=`pg_config --bindir`

# Start MySQL process for tests
get_random_port

MYSQL_DATA=`mktemp -d /tmp/tooz-mysql-XXXXX`
mkfifo ${MYSQL_DATA}/out
/usr/sbin/mysqld --datadir=${MYSQL_DATA} --port=${PORT} --pid-file=${MYSQL_DATA}/mysql.pid --socket=${MYSQL_DATA}/mysql.socket --slow-query-log-file=${MYSQL_DATA}/mysql-slow.log --skip-grant-tables &
# Wait for MySQL to start listening to connections
wait_for_mysql_ping
#wait_for_line "mysqld: ready for connections." ${MYSQL_DATA}/out
mysql -S ${MYSQL_DATA}/mysql.socket -e 'CREATE DATABASE test;'
export TOOZ_TEST_MYSQL_URL="mysql://root@localhost:${PORT}/test"

# Start PostgreSQL process for tests
${PGSQL_PATH}/initdb ${PGSQL_DATA}
${PGSQL_PATH}/pg_ctl -w -D ${PGSQL_DATA} -o "-k ${PGSQL_DATA} -p ${PGSQL_PORT}" start
# Wait for PostgreSQL to start listening to connections
export TOOZ_TEST_PGSQL_URL="postgresql:///?host=${PGSQL_DATA}&port=${PGSQL_PORT}&dbname=template1"

# Start memcached
memcached -p 11212 & MEMCACHED_PID=$!
export TOOZ_TEST_MEMCACHED_URL="memcached://localhost:11212?timeout=5"

# Start redis
#redis-server --port 6380 & REDIS_SERVER_PID=$!
#export TOOZ_TEST_REDIS_URL="redis://localhost:6380?timeout=5"

# Yield execution to venv command
$*
