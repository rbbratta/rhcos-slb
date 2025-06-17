#!/usr/bin/env bash

for f in $(oc get pods -n openshift-machine-config-operator \
  -l k8s-app=machine-config-daemon \
  --no-headers \
  -o custom-columns=N:.metadata.name); do

  echo "$f"

  set -x
  oc exec -n openshift-machine-config-operator "$f" -c machine-config-daemon -- \
    chroot /rootfs bash -c "ovs-vsctl --timeout=30 --if-exists del-br br0"
  set +x
done

