#!/bin/bash

#linkedin : https://www.linkedin.com/in/can-sayın-b332a157/
#cansayin.com
 
set -eo pipefail
 
PROGNAME=$(basename $0)
PROGPATH=$(echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,')
 
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_DEPENDENT=4
 
fail() {
local msg="$@"
echo "${msg}"
exit ${STATE_CRITICAL}
}
 
# Commands
if ! CHCMD=$(which clickhouse-client 2>/dev/null)
then
fail 'Required clickhouse-client command not found.'
fi
 
# Available modes
# <mode>=<desc>|<default_warning>|<default_critical>
declare -A modes=(
['replication_future_parts']="check number of data parts that will appear as the result of INSERTs or merges that haven't been done yet for each table|10|20"
['replication_inserts_in_queue']="check number of inserts of blocks of data that need to be made for each table|5|10"
['replication_is_readonly']='check if any replica is in read-only mode|N/A|N/A'
['replication_is_session_expired']='check if any replica has session with ZooKeeper expired|N/A|N/A'
['replication_log_delay']='check difference between entry number in the log of general activity and entry number in the log of general activity that the replica copied to its execution queue for each table|5|10'
['replication_parts_to_check']='check number of data parts in the queue for verification for each table|5|10'
['replication_queue_size']='check queue size for operations waiting to be performed for each table|10|20'
['replication_total_replicas']='check total number of replicas known for each table|2|2'
['replication_active_replicas']='check number of healthly replicas for each table|N/A|N/A'
)
 
# Functions
query() {
local sql="$1"
local cmd="${CHCMD} --format_csv_delimiter |"
[ -z "$LOG_QUERIES" ] || cmd="${cmd} --log_queries ${LOG_QUERIES}"
[ -z "$CH_HOST" ] || cmd="${cmd} -h ${CH_HOST}"
[ -z "$CH_USER" ] || cmd="${cmd} -u ${CH_USER}"
[ -z "$CH_PASS" ] || cmd="${cmd} --password ${CH_PASS}"
${cmd} -q "${sql}" 2> /dev/null
}
 
usage() {
tabs 2
echo "Usage: ${PROGNAME} -m <mode> [-u <user>] [-p <pass>] [-l 0|1] [-w <warning>] [-c <critical>] [-h]"
echo
echo -e "\t-s <host>\tClickHouse host address (default 'localhost')"
echo -e "\t-u <user>\tClickHouse user (default 'default')"
echo -e "\t-p <pass>\tClickHouse password (empty by default)"
echo -e "\t-l <0|1>\tDisable/Enable query logging (default depends on user's profile settings)"
echo -e "\t-m <mode>\tMode to run (see below)"
echo -e "\t-w <warning>\tWarning threshold (default depends on the mode, see below)"
echo -e "\t-c <critical>\tCritical threshold (default depends on the mode, see below)"
echo -e "\t-h Display this help message"
 
echo
echo 'Supported modes:'
for mode in "${!modes[@]}"
do
local desc=$(echo ${modes[$mode]} | awk -F\| '{ print $1 }')
local warn=$(echo ${modes[$mode]} | awk -F\| '{ print $2 }')
local crit=$(echo ${modes[$mode]} | awk -F\| '{ print $3 }')
echo -e "\t${mode}: ${desc}"
echo -e "\t\tDefault warning threshold: ${warn}"
echo -e "\t\tDefault critical threshold: ${crit}"
done
exit ${STATE_UNKNOWN}
}
 
check_arguments() {
while getopts ":hm:w:c:u:s:p:l:" opt
do
case $opt in
h )
usage
;;
m )
mode=$OPTARG
;;
w )
warn=$OPTARG
;;
c )
crit=$OPTARG
;;
u )
CH_USER=$OPTARG
;;
s )
CH_HOST=$OPTARG
;;
p )
CH_PASS=$OPTARG
;;
l )
LOG_QUERIES=$OPTARG
;;
\? )
fail "Invalid option: '-${OPTARG}'."
;;
: )
fail "Option '-${OPTARG}' requires an argument."
;;
* )
usage
;;
esac
done
 
[ -z "${mode}" ] && usage
[[ -n "${modes[$mode]}" ]] || fail "Mode '${mode}' isn't supported."
[[ "${LOG_QUERIES}" =~ ^[0|1]?$ ]] || fail "Option log queries (-l) can only be 0 or 1"
 
# Default thresholds
if [ -z $warn ]
then
warn=$(echo ${modes[$mode]} | awk -F\| '{ print $2 }')
fi
if [ -z $crit ]
then
crit=$(echo ${modes[$mode]} | awk -F\| '{ print $3 }')
fi
 
# TODO: sanitize thresholds values
}
 
check_replication() {
local mode=$1
local warn=$2
local crit=$3
 
local query="
SELECT
database,
table,
is_readonly,
is_session_expired,
future_parts,
parts_to_check,
queue_size,
inserts_in_queue,
log_max_index,
log_pointer,
total_replicas,
active_replicas
FROM system.replicas
FORMAT CSV
"
 
# Fields mapping
declare -A mapping=(
['is_readonly']=3
['is_session_expired']=4
['future_parts']=5
['parts_to_check']=6
['queue_size']=7
['inserts_in_queue']=8
['log_max_index']=9
['log_pointer']=10
['total_replicas']=11
['active_replicas']=12
)
 
# Check if any database / table has issue
local state=$STATE_OK
result=$(query "$query")
if [ $? -ne 0 ]
then
state=$STATE_CRITICAL
bad='Unable to reach clickhouse'
fi
for row in $result
do
db=$(echo $row | awk -F\| '{ print $1 }' | sed -s 's/"//g')
table=$(echo $row | awk -F\| '{ print $2 }' | sed -s 's/"//g;s/\.//g')
case "$mode" in
'is_readonly' | 'is_session_expired')
check_value=$(echo $row | awk -v f="${mapping[$mode]}" -F\| '{ print $f }' | sed -s 's/"//g')
ok_message="All tables have ${mode}=${check_value}"
if [ $check_value -ne 0 ]
then
bad="${bad} ${db} ${table} ${mode}=${check_value},"
state=$STATE_CRITICAL
fi
;;
'log_delay')
log_max_index=$(echo $row | awk -v f="${mapping['log_max_index']}" -F\| '{ print $f }' | sed -s 's/"//g')
log_pointer=$(echo $row | awk -v f="${mapping['log_pointer']}" -F\| '{ print $f }' | sed -s 's/"//g')
log_difference=$(($log_max_index - $log_pointer))
ok_message="All tables have ${mode}=${log_difference}"
if [ $log_difference -le $warn ] && [ $log_difference -le $crit ]
then
state=$STATE_OK
elif [ $log_difference -gt $warn ] && [ $log_difference -le $crit ]
then
bad="${bad} ${db} ${table} ${mode}=${log_difference} (> ${warn}),"
state=$STATE_WARNING
else
bad="${bad} ${db} ${table} ${mode}=${log_difference} (> ${crit}),"
state=$STATE_CRITICAL
fi
;;
'total_replicas')
total_replicas=$(echo $row | awk -v f="${mapping['total_replicas']}" -F\| '{ print $f }' | sed -s 's/"//g')
ok_message="All tables have ${mode}=${total_replicas}"
if [ $total_replicas -ge $crit ] && [ $total_replicas -ge $warn ]
then
state=$STATE_OK
elif [ $total_replicas -lt $warn ] && [ $total_replicas -ge $crit ]
then
bad="${bad} ${db} ${table} ${mode}=${total_replicas} (< ${warn}),"
state=$STATE_WARNING
else
bad="${bad} ${db} ${table} ${mode}=${total_replicas} (< ${crit}),"
state=$STATE_CRITICAL
fi
;;
'active_replicas')
total_replicas=$(echo $row | awk -v f="${mapping['total_replicas']}" -F\| '{ print $f }' | sed -s 's/"//g')
active_replicas=$(echo $row | awk -v f="${mapping['active_replicas']}" -F\| '{ print $f }' | sed -s 's/"//g')
ok_message="All tables have ${mode}=${active_replicas}"
if [ $active_replicas -lt $total_replicas ]
then
bad="${bad} ${db} ${table} ${mode}=${active_replicas} (!= ${total_replicas}),"
state=$STATE_CRITICAL
fi
;;
*)
check_value=$(echo $row | awk -v f="${mapping[$mode]}" -F\| '{ print $f }' | sed -s 's/"//g')
ok_message="All tables have ${mode} < ${warn}"
if [ $check_value -le $warn ] && [ $check_value -le $crit ]
then
state=$STATE_OK
elif [ $check_value -gt $warn ] && [ $check_value -le $crit ]
then
bad="${bad} ${db} ${table} ${mode}=${check_value} (> ${warn}),"
state=$STATE_WARNING
else
bad="${bad} ${db} ${table} ${mode}=${check_value} (> ${crit}),"
state=$STATE_CRITICAL
fi
;;
esac
done
 
[ $state -eq $STATE_OK ] && echo "${state}|${ok_message}" || echo "${state}|${bad}"
}
 
main() {
# Perfrom check based on the mode
case "$mode" in
'replication_future_parts')
result=$(check_replication 'future_parts' $warn $crit)
;;
'replication_inserts_in_queue')
result=$(check_replication 'inserts_in_queue' $warn $crit)
;;
'replication_is_readonly')
result=$(check_replication 'is_readonly' $warn $crit)
;;
'replication_is_session_expired')
result=$(check_replication 'is_session_expired' $warn $crit)
;;
'replication_log_delay')
result=$(check_replication 'log_delay' $warn $crit)
;;
'replication_parts_to_check')
result=$(check_replication 'parts_to_check' $warn $crit)
;;
'replication_queue_size')
result=$(check_replication 'queue_size' $warn $crit)
;;
'replication_total_replicas')
result=$(check_replication 'total_replicas' $warn $crit)
;;
'replication_active_replicas')
result=$(check_replication 'active_replicas' $warn $crit)
;;
esac
result=$(echo $result | sed -s 's/,$//')
 
# Check results
state=$(echo $result | awk -F\| '{ print $1 }')
case "$state" in
0)
message="OK: $(echo $result | awk -F\| '{ print $2 }')"
;;
1)
message="WARNING: $(echo $result | awk -F\| '{ print $2 }')"
;;
2)
message="CRITICAL: $(echo $result | awk -F\| '{ print $2 }')"
;;
*)
echo 'Fail'
exit $STATE_UNKNOWN
;;
esac
 
echo "$(echo $mode | awk '{ print toupper($0) }') ${message}"
exit $state
}
 
# Main part starts here
check_arguments $@
main
