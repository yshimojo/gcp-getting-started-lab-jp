#!/bin/sh
set -eu

cmdname=$( basename "$0" )

usage() {
  echo "Usage: ${cmdname} [-c config]" 1>&2
  echo "  -c : config file (default: lustre.yaml)" 1>&2
  exit 1
}

config="lustre.yaml"

while getopts c:h opt
do
  case $opt in
    "c" ) config="${OPTARG}" ;;
    "h" ) usage ;;
      * ) usage ;;
  esac
done

if [ ! -e "${config}" ]; then
  echo "Config file (${config}) is not found." 1>&2
  usage
fi

trimmed_config=$(sed -e 's| ||g' "${config}")
cluster=$(echo "${trimmed_config}" | grep cluster_name | sed -e 's|cluster_name:||g')
if [ "${cluster}" = "" ]; then
  echo "The cluster name is invalid."
  usage
fi
zone=$(echo "${trimmed_config}" | grep zone | sed -e 's|zone:||g')
if [ "${zone}" = "" ]; then
  echo "The zone is invalid."
  usage
fi

mds=$( gcloud deployment-manager deployments describe "${cluster}" --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep mds)
for id in ${mds}; do
    gcloud compute instances start "${id}" --zone "${zone}"
done

while :
do
  if gcloud compute ssh "${cluster}-mds1" --zone "${zone}" --tunnel-through-iap \
        --command "sudo journalctl -u google-startup-scripts.service" 2>/dev/null \
        | grep -q -m 1 'Started Google Compute Engine Startup Scripts'; then
    echo "MDSs are ready."
    break
  else
    sleep 5
  fi
done

oss=$( gcloud deployment-manager deployments describe "${cluster}" --format json \
    | jq -r '.resources[]|select(.type=="compute.v1.instance")|.name' \
    | grep oss)
for id in ${oss}; do
    gcloud compute instances start "${id}" --zone "${zone}"
done

while :
do
  if gcloud compute ssh "${cluster}-oss1" --zone "${zone}" --tunnel-through-iap \
        --command "sudo journalctl -u google-startup-scripts.service" 2>/dev/null \
        | grep -q -m 1 'Started Google Compute Engine Startup Scripts'; then
    echo "OSSs are ready."
    break
  else
    sleep 5
  fi
done
