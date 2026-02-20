# @summary Defines the valid database installation modes for Kea DHCP
#
# - instance: Create a new dedicated PostgreSQL instance for Kea DHCP
# - database: Add the Kea database to the existing default PostgreSQL instance
# - none: Skip database installation (database is managed externally)
type Kea_Dhcp::Db_install_mode = Enum['instance', 'database', 'none']
