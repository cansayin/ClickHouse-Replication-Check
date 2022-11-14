# ClickHouse-Replication-Check

Usage: check.sh -m <mode> [-u <user>] [-p <pass>] [-l 0|1] [-w <warning>] [-c <critical>] [-h]                                                                                          

	-s <host>	ClickHouse host address (default 'localhost')
	-u <user>	ClickHouse user (default 'default')
	-p <pass>	ClickHouse password (empty by default)
	-l <0|1>	Disable/Enable query logging (default depends on user's profile settings)
	-m <mode>	Mode to run (see below)
	-w <warning>	Warning threshold (default depends on the mode, see below)
	-c <critical>	Critical threshold (default depends on the mode, see below)
	-h Display this help message

Supported modes:
	replication_log_delay: check difference between entry number in the log of general activity and entry number in the log of general activity that the replica copied to its execution queue for each table
		Default warning threshold: 5
		Default critical threshold: 10
	replication_active_replicas: check number of healthly replicas for each table
		Default warning threshold: N/A
		Default critical threshold: N/A
	replication_is_session_expired: check if any replica has session with ZooKeeper expired
		Default warning threshold: N/A
		Default critical threshold: N/A
	replication_future_parts: check number of data parts that will appear as the result of INSERTs or merges that haven't been done yet for each table
		Default warning threshold: 10
		Default critical threshold: 20
	replication_parts_to_check: check number of data parts in the queue for verification for each table
		Default warning threshold: 5
		Default critical threshold: 10
	replication_is_readonly: check if any replica is in read-only mode
		Default warning threshold: N/A
		Default critical threshold: N/A
	replication_inserts_in_queue: check number of inserts of blocks of data that need to be made for each table
		Default warning threshold: 5
		Default critical threshold: 10
	replication_total_replicas: check total number of replicas known for each table
		Default warning threshold: 2
		Default critical threshold: 2
	replication_queue_size: check queue size for operations waiting to be performed for each table
		Default warning threshold: 10
		Default critical threshold: 20
