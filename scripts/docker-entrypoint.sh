#!/usr/bin/env bash

set -e

. /common.sh
. /functions.sh

info "Starting Postfix ..."

setup_timezone
rsyslog_log_format
reown_folders

postfix_create_aliases
postfix_set_hostname
postfix_set_relay_tls_level
postfix_setup_relayhost
postfix_setup_networks
postfix_open_submission_port

[[ -n "$INBOUND_DEBUGGING" ]] && postfix_setup_debugging

execute_post_init_scripts
unset_sensible_variables

info "Starting: ${emphasis}rsyslog${reset}, ${emphasis}postfix${reset}$DKIM_ENABLED"

exec supervisord -c /etc/supervisord.conf
