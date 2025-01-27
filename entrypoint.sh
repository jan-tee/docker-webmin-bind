#!/bin/bash
# shellcheck disable=SC2174,SC2086
set -e

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

file_env 'ROOT_PASSWORD'

BIND_USER=${BIND_USER:-bind}
BIND_GROUP=${BIND_GROUP:-bind}
DHCP_USER=${DHCP_USER:-dhcpd}
DHCP_GROUP=${DHCP_GROUP:-dhcpd}
ROOT_PASSWORD=${ROOT_PASSWORD:-password}
BIND_EXTRA_FLAGS=${BIND_EXTRA_FLAGS:--g}
WEBMIN_ENABLED=${WEBMIN_ENABLED:-true}
WEBMIN_INIT_SSL_ENABLED=${WEBMIN_INIT_SSL_ENABLED:-true}
WEBMIN_INIT_REDIRECT_PORT=${WEBMIN_INIT_REDIRECT_PORT:-10000}
WEBMIN_INIT_REFERERS=${WEBMIN_INIT_REFERERS:-NONE}
WEBMIN_INIT_REDIRECT_SSL=${WEBMIN_INIT_REDIRECT_SSL:-false}

DATA_DIR=${DATA_DIR:-/data}
BIND_DATA_DIR=${DATA_DIR}/bind
DHCP_DATA_DIR=${DATA_DIR}/dhcp
WEBMIN_DATA_DIR=${DATA_DIR}/webmin

create_bind_data_dir() {
  mkdir -p "${BIND_DATA_DIR}"

  # populate default bind configuration if it does not exist
  if [ ! -d "${BIND_DATA_DIR}"/etc ]; then
    mv /etc/bind "${BIND_DATA_DIR}"/etc
  fi
  rm -rf /etc/bind
  ln -sf "${BIND_DATA_DIR}"/etc /etc/bind
  chmod -R 0775 "${BIND_DATA_DIR}"
  chown -R "${BIND_USER}":"${BIND_GROUP}" "${BIND_DATA_DIR}"

  if [ ! -d "${BIND_DATA_DIR}"/lib ]; then
    mkdir -p "${BIND_DATA_DIR}"/lib
    chown "${BIND_USER}":"${BIND_GROUP}" "${BIND_DATA_DIR}"/lib
  fi
  rm -rf /var/lib/bind
  ln -sf "${BIND_DATA_DIR}"/lib /var/lib/bind
  mkdir -p "${BIND_DATA_DIR}"/etc/logs
  touch "${BIND_DATA_DIR}"/etc/logs/named.log

}

create_webmin_data_dir() {
  mkdir -p "${WEBMIN_DATA_DIR}"
  chmod -R 0755 "${WEBMIN_DATA_DIR}"
  chown -R root:root "${WEBMIN_DATA_DIR}"

  # populate the default webmin configuration if it does not exist
  if [ ! -d "${WEBMIN_DATA_DIR}"/etc ]; then
    mv /etc/webmin "${WEBMIN_DATA_DIR}"/etc
  fi
  rm -rf /etc/webmin
  ln -sf "${WEBMIN_DATA_DIR}"/etc /etc/webmin
}

disable_webmin_ssl() {
  sed -i 's/ssl=1/ssl=0/g' /etc/webmin/miniserv.conf
}

enable_webmin_ssl() {
  sed -i 's/ssl=0/ssl=1/g' /etc/webmin/miniserv.conf
}

switch_systemctl_service() {
    sed -i 's/^restart_cmd=systemctl.*/restart_cmd=service named restart/' "$WEBMIN_DATA_DIR"/etc/bind8/config
    sed -i 's/^start_cmd=systemctl.*/start_cmd=service named start/' "$WEBMIN_DATA_DIR"/etc/bind8/config
    sed -i 's/^stop_cmd=systemctl.*/stop_cmd=service named stop/' "$WEBMIN_DATA_DIR"/etc/bind8/config
}

set_webmin_redirect_port() {
  webmin_redirect_port_var_exists=$(grep -q "redirect_port" "/etc/webmin/miniserv.conf" ; echo $?)
  if [ "$webmin_redirect_port_var_exists" == "1" ]
  then
  	echo "redirect_port=$WEBMIN_INIT_REDIRECT_PORT" >> /etc/webmin/miniserv.conf
  else
    sed -i "s/^redirect_port.*/redirect_port=$WEBMIN_INIT_REDIRECT_PORT/" /etc/webmin/miniserv.conf
  fi
}

set_webmin_referers() {
  webmin_referers_var_exists=$(grep -q "referers=" "/etc/webmin/config" ; echo $?)
  if [ "$webmin_referers_var_exists" == "1" ]
  then
    echo "referers=$WEBMIN_INIT_REFERERS" >> /etc/webmin/config
  else
    sed -i "s/^referers=.*/referers=$WEBMIN_INIT_REFERERS/" /etc/webmin/config
  fi
}

set_root_passwd() {
  echo "root:$ROOT_PASSWORD" | chpasswd
}

create_pid_dir() {
  mkdir -m 0775 -p /var/run/named
  chown root:"${BIND_USER}" /var/run/named
}

create_bind_cache_dir() {
  mkdir -m 0775 -p /var/cache/bind
  chown root:"${BIND_USER}" /var/cache/bind
}

disable_webmin_redirect_ssl() {
  sed -i '/webprefixnoredir=1/d' /etc/webmin/config
  sed -i '/relative_redir=0/d' /etc/webmin/config
  sed -i '/redirect_ssl=1/d' /etc/webmin/miniserv.conf
}

enable_webmin_redirect_ssl() {
  webmin_webprefixnoredir_var_exists=$(grep -q "webprefixnoredir=" "/etc/webmin/config" ; echo $?)
  if [ "$webmin_webprefixnoredir_var_exists" == "1" ]
  then
    echo "webprefixnoredir=1" >> /etc/webmin/config
  else
    sed -i "s/^webprefixnoredir=.*/webprefixnoredir=1/" /etc/webmin/config
  fi

  webmin_relative_redir_var_exists=$(grep -q "relative_redir=" "/etc/webmin/config" ; echo $?)
  if [ "$webmin_relative_redir_var_exists" == "1" ]
  then
    echo "relative_redir=0" >> /etc/webmin/config
  else
    sed -i "s/^relative_redir=.*/relative_redir=0/" /etc/webmin/config
  fi

  webmin_redirect_ssl_var_exists=$(grep -q "redirect_ssl=" "/etc/webmin/miniserv.conf" ; echo $?)
  if [ "$webmin_redirect_ssl_var_exists" == "1" ]
  then
    echo "redirect_ssl=1" >> /etc/webmin/miniserv.conf
  else
    sed -i "s/^redirect_ssl=.*/redirect_ssl=1/" /etc/webmin/miniserv.conf
  fi
}

first_init() {
    switch_systemctl_service
    set_webmin_redirect_port
    if [ "${WEBMIN_INIT_SSL_ENABLED}" == "false" ]; then
      disable_webmin_ssl
    elif [ "${WEBMIN_INIT_SSL_ENABLED}" == "true" ]; then
      enable_webmin_ssl
    fi
    if [ "${WEBMIN_INIT_REFERERS}" != "NONE" ]; then
      set_webmin_referers
    fi
    if [ "${WEBMIN_INIT_REFERERS}" == "NONE" ]; then
      webmin_referers_var_exists=$(grep -q "referers=" "/etc/webmin/config" ; echo $?)
      if [ "$webmin_referers_var_exists" != "1" ]
      then
        sed -i "/^referers=.*/d" /etc/webmin/config
      fi
    fi
    # Enable/disable SSL redirect after login
    if [ "${WEBMIN_INIT_REDIRECT_SSL}" == "false" ]; then
      disable_webmin_redirect_ssl
    elif [ "${WEBMIN_INIT_REDIRECT_SSL}" == "true" ]; then
      enable_webmin_redirect_ssl
    fi
}


create_dhcpd_data_dir() {
  if [ "${ENABLE_DHCP}" == "true" ]; then
    # /var/lib/dhcp
    mkdir -p "${DHCP_DATA_DIR}"
    mkdir -p "${DHCP_DATA_DIR}/var"
    chown -R "${DHCP_USER}":"${DHCP_GROUP}" "${DHCP_DATA_DIR}"
    rm -rf /var/lib/dhcp
    ln -sf "${DHCP_DATA_DIR}/var" /var/lib/dhcp

    if [ ! -e "${DHCP_DATA_DIR}/var/dhcpd.leases" ] ; then
      touch "${DHCP_DATA_DIR}/var/dhcpd.leases"
      chown "${DHCP_USER}":"${DHCP_GROUP}" "${DHCP_DATA_DIR}/var/dhcpd.leases"
    fi

    # /etc/dhcp
    if [ ! -d "${DHCP_DATA_DIR}/etc" ]; then
      mv /etc/dhcp "${DHCP_DATA_DIR}/etc"
    fi

    rm -rf /etc/dhcp
    ln -sf "${DHCP_DATA_DIR}/etc" /etc/dhcp
    chmod -R 0775 "${DHCP_DATA_DIR}"
    chown -R "${DHCP_USER}":"${DHCP_GROUP}" "${DHCP_DATA_DIR}"
  fi
}

create_bind_supervisord_conf() {
  cat <<EOF > /etc/supervisor/conf.d/named.conf
[program:named]
command="$(type -p named)" -u ${BIND_USER} ${BIND_EXTRA_FLAGS} -c /etc/bind/named.conf ${EXTRA_ARGS}
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
autorestart=false
EOF
}

create_dhcpd_supervisord_conf() {
  if [ "${ENABLE_DHCP}" == "true" ]; then
    cat <<EOF > /etc/supervisor/conf.d/dhcpd.conf
[program:dhcpd]
command="$(type -p dhcpd)" -user ${DHCP_USER} -group ${DHCP_GROUP} -f -4 -pf /run/dhcp-server/dhcpd.pid -cf /etc/dhcp/dhcpd.conf ${DHCP_INTERFACES-eth0}
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
autorestart=true
EOF
  fi
}

create_pid_dir
create_bind_data_dir
create_bind_cache_dir
create_dhcpd_data_dir

# allow arguments to be passed to named
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_ARGS="$*"
  set --
elif [[ ${1} == named || ${1} == $(type -p named) ]]; then
  EXTRA_ARGS="${*:2}"
  set --
fi

create_dhcpd_supervisord_conf
create_bind_supervisord_conf

# default behaviour is to launch named
if [[ -z ${1} ]]; then
  if [ "${WEBMIN_ENABLED}" == "true" ]; then
    create_webmin_data_dir
    first_init
    set_root_passwd
    echo '---------------------'
    echo '|  Starting Webmin  |'
    echo '---------------------'
    /etc/init.d/webmin start
  fi

  echo
  echo '---------------------'
  echo '|  Starting supervisord   |'
  echo '---------------------'
  echo
  # exec "$(type -p named)" -u ${BIND_USER} ${BIND_EXTRA_FLAGS} -c /etc/bind/named.conf ${EXTRA_ARGS}
  exec "$(type -p supervisord)" -c /etc/supervisor/supervisord.conf
else
  exec "$@"
fi
