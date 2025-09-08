#!/bin/bash

target=$(oc get network.config cluster -o jsonpath='{.spec.networkType}')
for n in $(oc get nodes -o name); do
  mc=$(oc get "$n" -o jsonpath='{.metadata.annotations.machineconfiguration\.openshift\.io/currentConfig}')
  mtu_enabled=$(oc get mc "$mc" -o jsonpath='{.spec.config.systemd.units[?(@.name=="mtu-migration.service")].enabled}' 2>/dev/null)
  ovs_enabled=$(oc get mc "$mc" -o jsonpath='{.spec.config.systemd.units[?(@.name=="ovs-configuration.service")].enabled}' 2>/dev/null)
  # the template changes when the NetworkType changes.
  oc get mc "$mc" -o jsonpath='{.spec.config.systemd.units[?(@.name=="ovs-configuration.service")].contents}' \
  | grep -Fq "ExecStart=/usr/local/bin/configure-ovs.sh ${target}" && ovs_target=yes || ovs_target=no

  if [[ "$mtu_enabled" != *true* && "$ovs_enabled" == *true* && "$ovs_target" == yes ]]; then
    stage="${target} (after 2nd reboot)"
  elif [[ "$mtu_enabled" == *true* ]]; then
    stage="MTU-only (after 1st reboot)"
  else
    stage="pre/unknown"
  fi
  echo -e "$n\t$stage\t$mc"
done