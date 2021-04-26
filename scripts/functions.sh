#!/usr/bin/env bash

# Check if we need to configure the container timezone
setup_timezone() {
	if [ ! -z "$TZ" ]; then
		TZ_FILE="/usr/share/zoneinfo/$TZ"
		if [ -f "$TZ_FILE" ]; then
			info "Setting container timezone to: ${emphasis}$TZ${reset}"
			ln -snf "$TZ_FILE" /etc/localtime
			echo "$TZ" > /etc/timezone
		else
			warn "Cannot set timezone to: ${emphasis}$TZ${reset} -- this timezone does not exist."
		fi
	else
		info "Not setting any timezone for the container"
	fi
}

# Setup rsyslog output format
rsyslog_log_format() {
	local log_format="${LOG_FORMAT}"
	if [[ -z "${log_format}" ]]; then
		log_format="plain"
	fi
	info "Using ${emphasis}${log_format}${reset} log format for rsyslog."
	sed -i -E "s/<log-format>/${log_format}/" /etc/rsyslog.conf
}

# Make and change owner of the Postfix folder
reown_folders() {
	mkdir -p /var/spool/postfix/pid
	chown root:root -R /var/spool/postfix/
}

# Update aliases database. It's not used, but postfix complains if the .db file is missing
postfix_create_aliases() {
	postalias /etc/postfix/aliases
}

postfix_set_hostname() {
	do_postconf -# myhostname
	if [[ -z "$POSTFIX_MYHOSTNAME" ]]; then
		POSTFIX_MYHOSTNAME="${HOSTNAME}"
	fi
}

postfix_set_relay_tls_level() {
	RELAYHOST_TLS_LEVEL="${RELAYHOST_TLS_LEVEL:-may}"
	info "Setting smtp_tls_security_level: ${RELAYHOST_TLS_LEVEL}"
	do_postconf -e "smtp_tls_security_level=${RELAYHOST_TLS_LEVEL}"

	if [ "${RELAYHOST_TLS_LEVEL}" = "encrypt" ]; then
		do_postconf -e 'smtp_use_tls=yes'
		do_postconf -e 'smtp_tls_note_starttls_offer=yes'
	fi
}

# Set Postfix as a relay host
postfix_setup_relayhost() {
	do_postconf -e 'mydestination=$myhostname, localhost.$mydomain, localhost, $mydomain'
	do_postconf -e 'relay_domains=$mydestination'

	if [ ! -z "$RELAYHOST" ]; then
		infon "Forwarding all emails to ${emphasis}$RELAYHOST${reset}"
		do_postconf -e "relayhost=$RELAYHOST"
		# Alternately, this could be a folder, like this:
		# smtp_tls_CApath=/etc/ssl/certs
		do_postconf -e "smtp_tls_CAfile=/etc/ssl/certs/ca-certificates.crt"

		file_env 'RELAYHOST_PASSWORD'

		if [ -n "$RELAYHOST_USERNAME" ] && [ -n "$RELAYHOST_PASSWORD" ]; then
			echo -e " using username ${emphasis}$RELAYHOST_USERNAME${reset} and password ${emphasis}(redacted)${reset}."
			if [[ -f /etc/postfix/sasl_passwd ]]; then
				if ! grep -F "$RELAYHOST $RELAYHOST_USERNAME:$RELAYHOST_PASSWORD" /etc/postfix/sasl_passwd; then
					sed -i -e "s/^$RELAYHOST .*$/d" /etc/postfix/sasl_passwd
					echo "$RELAYHOST $RELAYHOST_USERNAME:$RELAYHOST_PASSWORD" >> /etc/postfix/sasl_passwd
				fi
			else
				echo "$RELAYHOST $RELAYHOST_USERNAME:$RELAYHOST_PASSWORD" >> /etc/postfix/sasl_passwd
			fi

			postmap lmdb:/etc/postfix/sasl_passwd
			chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.lmdb
			chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.lmdb

			do_postconf -e 'smtp_sasl_auth_enable=yes'
			do_postconf -e 'smtp_sasl_password_maps=lmdb:/etc/postfix/sasl_passwd'
			do_postconf -e 'smtp_sasl_security_options=noanonymous'
			do_postconf -e 'smtp_sasl_tls_security_options=$smtp_sasl_security_options'
		fi
	else
		info "Will try to deliver emails directly to the final server. ${emphasis}Make sure your DNS is setup properly!${reset}"
		do_postconf -# relayhost
		do_postconf -# smtp_sasl_auth_enable
		do_postconf -# smtp_sasl_password_maps
		do_postconf -# smtp_sasl_security_options
	fi
}

# Set MYNETWORKS with CIDR including Kubernetes and Docker networks
postfix_setup_networks() {
	if [ ! -z "$MYNETWORKS" ]; then
		POSTFIX_MYNETWORKS="$MYNETWORKS"
	fi
	
	POSTFIX_MYNETWORKS=${POSTFIX_MYNETWORKS:-"127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"}
	info "Using networks: ${POSTFIX_MYNETWORKS}"
	do_postconf -e "mynetworks = ${POSTFIX_MYNETWORKS}"
}

# Enable detailed logging for debugging when INBOUND_DEBUGGING is defined
postfix_setup_debugging() {
	info "Enabling additional debbuging for: ${emphasis}$POSTFIX_MYNETWORKS${reset}, as INBOUND_DEBUGGING=''${INBOUND_DEBUGGING}''"
	do_postconf -e "debug_peer_list=$POSTFIX_MYNETWORKS"
}

postfix_open_submission_port() {
	# Use Port 587 (submission)
	sed -i -r -e 's/^#submission/submission/' /etc/postfix/master.cf
}

# Execute any custom Docker entrypoint script. Allows to extend the Docker image
# capability without forking and building derivatives.
execute_post_init_scripts() {
	if [ -d /docker-entrypoint.d/ ]; then
		info "Executing custom Docker entrypoint scripts ..."

		for ENTRYPOINT_SCRIPT in /docker-entrypoint.d/*.sh; do
			sh ${ENTRYPOINT_SCRIPT}
		done
	fi
}

# Remove environment variables that contains sensible values (secrets) that are read from conf files
unset_sensible_variables() {
	unset RELAYHOST_PASSWORD
	unset XOAUTH2_CLIENT_ID
	unset XOAUTH2_SECRET
	unset XOAUTH2_INITIAL_ACCESS_TOKEN
	unset XOAUTH2_INITIAL_REFRESH_TOKEN
}
