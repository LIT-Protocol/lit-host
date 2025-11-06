#!/bin/bash
#
#

set -e

LITOS_GUEST_SRC_PREFIX="litos_guest"
LITOS_GUEST_TRF_PREFIX="trf-litos_guest"

# shellcheck disable=SC2120
init_instance_env() {
	local change_path="$1"

	if [ "${INSTANCE_INIT_CALLED}" == "1" ]; then
		return
	fi
	export INSTANCE_INIT_CALLED="1"

	local build_env="build.env"
	local instance_env="instance.env"

	if [ -z "${INSTANCE_PATH}" ]; then
		die "expected INSTANCE_PATH to be defined"
	fi
	if [ ! -d "${INSTANCE_PATH}" ]; then
		die "Instance directory not found: $INSTANCE_PATH"
	fi
	if [ ! -f "${INSTANCE_PATH}/${instance_env}" ]; then
		die "Instance env file not found: INSTANCE_PATH/$instance_env"
	fi

	if [ "${change_path}" == "true" ]; then
		cd ${INSTANCE_PATH}
	fi

	# load instance.env
	. "${INSTANCE_PATH}/${instance_env}"

	# load build.env
	if [ -e "${INSTANCE_PATH}/build/${build_env}" ]; then
		. "${INSTANCE_PATH}/build/${build_env}"
	elif [ -e "./${build_env}" ]; then
		. "${INSTANCE_PATH}/${build_env}"
	else
		die "Instance build.env file not found: ${INSTANCE_PATH}/build/${build_env} or ${INSTANCE_PATH}/${build_env}"
	fi

	if [ -z "${INSTANCE_NAME}" ]; then
		die "INSTANCE_NAME missing from: ${INSTANCE_PATH}/${instance_env}"
	fi
	if [ -z "${INSTANCE_ID}" ]; then
		die "INSTANCE_ID missing from: ${INSTANCE_PATH}/${instance_env}"
	fi
	if [ -z "${INSTANCE_SERVICE}" ]; then
		die "INSTANCE_SERVICE missing from: ${INSTANCE_PATH}/${instance_env}"
	fi

	# load release.env
	if [ -n "${SUBNET_ID}" ] && [ -e "${INSTANCE_PATH}/releases/${SUBNET_ID}/release.env" ]; then
		. "${INSTANCE_PATH}/releases/${SUBNET_ID}/release.env"
	elif [ -e "${INSTANCE_PATH}/release/release.env" ]; then
		. "${INSTANCE_PATH}/release/release.env"
	fi

  [ -e "$INSTANCE_PATH/cloud-init/network-config" ] || die "Network config not found: $INSTANCE_PATH/cloud-init/network-config"
  command -v yq >/dev/null 2>&1 || die "yq command not found. Please install yq to proceed."
  local extip=$(yq -r '.ethernets.enp0s3.addresses[0]' "$INSTANCE_PATH/cloud-init/network-config")
  [ -n "${extip}" ] && export NET4_IP="${extip}"

  export INSTANCE_SERVICE_FILE="/etc/systemd/system/${INSTANCE_SERVICE}"
  export INSTANCE_LOGS_REF="${INSTANCE_NAME}-services"
  export INSTANCE_LOGS_DIR="$INSTANCE_PATH/logs"
  export INSTANCE_GUEST_OTEL_LOGS_FILE="$INSTANCE_LOGS_DIR/otel.log"
}

create_systemd_service() {
	init_instance_env

	[ -z "${INSTANCE_SERVICE_FILE}" ] && die "INSTANCE_SERVICE_FILE is empty or not set."
	[ -z "${INSTANCE_ID}" ] && die "INSTANCE_ID is empty or not set."
	[ -z "${BUILD_TYPE}" ] && die "BUILD_TYPE is empty or not set."
	[ -z "${BUILD_RELEASE}" ] && die "BUILD_RELEASE is empty or not set."
	[ -z "${INSTANCE_SERVICE_FILE}" ] && die "INSTANCE_SERVICE_FILE is empty or not set."
	[ -z "${LITOS_GUEST_LAUNCH_SCRIPT}" ] && die "LITOS_GUEST_LAUNCH_SCRIPT is empty or not set."
	[ -z "${LITOS_GUEST_MONITOR_SCRIPT}" ] && die "LITOS_GUEST_MONITOR_SCRIPT is empty or not set."

	echo ""
	highlight "Creating service: ${INSTANCE_SERVICE}"

	cat > "${INSTANCE_SERVICE_FILE}" <<-EOF
		[Unit]
		Description=LitOS Guest (id: ${INSTANCE_ID}, type: ${BUILD_TYPE}, env: ${BUILD_RELEASE})
		After=network.target

		[Service]
		Environment="NOCONSOLE=1"
		ExecStart=${LITOS_GUEST_LAUNCH_SCRIPT} -path $(readlink -f ${INSTANCE_PATH})
		ExecStop=${LITOS_GUEST_MONITOR_SCRIPT} -path $(readlink -f ${INSTANCE_PATH}) -shutdown
		Type=exec
		Restart=always
		RestartSec=5
		OOMScoreAdjust=-1000

		[Install]
		WantedBy=default.target
		RequiredBy=network.target
	EOF

	systemctl daemon-reload
	systemctl enable ${INSTANCE_SERVICE}

	if [ -n "$START_INSTANCE" ] && [ "$START_INSTANCE" == "1" ]; then
		echo ""
		highlight "Starting service: ${INSTANCE_SERVICE}"

		systemctl start ${INSTANCE_SERVICE}
	fi
}

# shellcheck disable=SC2120
purge_logging_facilities() {
	local restart="$1"
	init_instance_env

	if [ -e "/etc/logrotate.d/${INSTANCE_LOGS_REF}.conf" ]; then
		rm -f "/etc/logrotate.d/${INSTANCE_LOGS_REF}.conf" || true
	fi

	local otel_override_file="/etc/monitoring/otelcol/docker-compose.override.yml"
	if [ -e "${otel_override_file}" ]; then
		rm -f "${otel_override_file}" || true
	fi
}

init_logging_facilities() {
  if [ -z "${INSTANCE_NAME}" ]; then
    die "expected INSTANCE_NAME to be defined"
  fi
  if [ -z "${INSTANCE_PATH}" ]; then
    die "expected INSTANCE_PATH to be defined"
  fi
  if [ -z "${INSTANCE_ID}" ]; then
    die "expected INSTANCE_ID to be defined"
  fi

	init_instance_env

	local local_subnet_id="$SUBNET_ID"
	if [ -z "$local_subnet_id" ]; then
		local local_subnet_id="LOCAL"
	fi
	local local_release_id="$RELEASE_ID"
	if [ -z "$local_release_id" ]; then
		local local_release_id="LOCAL"
	fi

	echo ""
	highlight "Init logging facility: ${INSTANCE_LOGS_REF}"

	purge_logging_facilities

  [ ! -e "${INSTANCE_LOGS_DIR}" ] && install -o root -g root -d -m 700 "${INSTANCE_LOGS_DIR}"
  [ ! -e "${INSTANCE_GUEST_OTEL_LOGS_FILE}" ] && touch "${INSTANCE_GUEST_OTEL_LOGS_FILE}"
  chown root:root "${INSTANCE_GUEST_OTEL_LOGS_FILE}"

  chmod 600 "${INSTANCE_GUEST_OTEL_LOGS_FILE}"

  # Set up log rotation config for the otel log files specifically.
  {
    echo ""
    echo "$(readlink -f ${INSTANCE_LOGS_DIR})/otel.log {"
    echo "    hourly"
    echo "    rotate 4"
    echo "    copytruncate"
    echo "    size 100M"
    echo "    compress"
    echo "    delaycompress"
    echo "}"
  } >> "/etc/logrotate.d/${INSTANCE_LOGS_REF}.conf"

  # Now that we have the INSTANCE_ID, update the docker-compose file for OTEL Collector and restart it.
  local otel_override_file="/etc/monitoring/otelcol/docker-compose.override.yml"
  cat > "${otel_override_file}" <<-EOF
services:
  otel-collector:
    volumes:
      - ${INSTANCE_LOGS_DIR}:/logs
EOF

  # We also need to update the latest guest / subnet information in the otelcol config file.
  local otel_collector_config_file="/etc/monitoring/otelcol/otel-collector-config.yaml"
  # Extract IP without CIDR notation (remove /XX suffix)
  local ip_no_cidr="${NET4_IP%/*}"
  sed -i "/# This is the domain of the URL that the logs are coming from/{n;s|.*|        value: \"${ip_no_cidr}\"|}" ${otel_collector_config_file}
  sed -i "/# This is the subnet ID of the GCP project/{n;s|.*|        value: \"${local_subnet_id}\"|}" ${otel_collector_config_file}

  systemctl stop otelcol
  systemctl start otelcol
}
