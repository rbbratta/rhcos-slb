#!/usr/bin/env bash

for f in $(oc get pods -n openshift-machine-config-operator \
  -l k8s-app=machine-config-daemon \
  --no-headers \
  -o custom-columns=N:.metadata.name); do

  echo "$f"

  oc exec -n openshift-machine-config-operator "$f" -c machine-config-daemon -- \
    chroot /rootfs bash -c "mkdir -p /etc/systemd/system/mtu-migration.service.d && \
      printf '%s\n' '[Unit]' 'After=wait-for-primary-ip.service' | \
        tee /etc/systemd/system/mtu-migration.service.d/override.conf && \
      systemctl daemon-reload"
done
