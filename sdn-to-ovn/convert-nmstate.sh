#!/usr/bin/env bash

set -eu -o pipefail
set -x

PTH=${0%/*}


ROLE=$1
shift
LOCALNET_NAME=$1
shift
IN=$1

HOSTNAME=$(yq '.hostname.running' "${IN}" | cut -d . -f 1)
MTU=$(yq '.interfaces[] | select(.description == "primary") |  .mtu' "${IN}")
PRIMARY_MAC=$(yq '.interfaces[] | select(.description == "primary") |   .["mac-address"]' "${IN}")
PRIMARY=$(yq '.interfaces[] | select(.description == "primary") | .name' "${IN}")
SECONDARY=$(yq '.interfaces[] | select(.description == "secondary") |  .name' "${IN}")
EXTRA=$(yq '.interfaces[] | select(.ipv4.enabled == false and .type == "ethernet" and .description == null) | .name'  "${IN}")


# don't quote $EXTRA it is multiple interfaces
"${PTH}"/make-br-ex-nmstate.sh "${HOSTNAME}" "${ROLE}" "${MTU}" "${PRIMARY_MAC}" "${PRIMARY}" "${SECONDARY}" "${LOCALNET_NAME}" ${EXTRA}
