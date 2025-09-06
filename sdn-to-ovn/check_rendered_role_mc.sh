#!/bin/bash

for role in master worker; do
  # Get the current rendered config for this role from MCP
  # only for paused MCP
  rendered=$(oc describe mcp $role | grep -Po "(?<=will not update to MachineConfig )\S+")
  echo "Processing role: $role, rendered config: $rendered"
  
  # Get short hostnames for nodes in this role
  for hostname in $(oc get nodes -l node-role.kubernetes.io/$role --no-headers -o custom-columns=N:.metadata.name | cut -d. -f1); do
    echo "Processing hostname: $hostname"
    
    # Get the nmstate config file content
    oc get -o yaml mc "$rendered" \
      | yq ".spec.config.storage.files[] | select(.path == \"/etc/nmstate/openshift/$hostname.yml\") | .contents.source" \
      | python3 -c 'import sys; from urllib.request import urlopen; content = sys.stdin.read().strip(); print(f"URL: {content}"); sys.stdout.buffer.write(urlopen(content).read())' 2>/dev/null \
      || echo "No config found for $hostname"
  done
done
