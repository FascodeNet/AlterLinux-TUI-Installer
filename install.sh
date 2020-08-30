#!/usr/bin/env bash
dev_array=()
for dev_t in `lsblk -pl -o NAME`
do
 if [[ ${dev_t} =~ ^/dev/[hmnsv][dmv][0-9a-z]* ]]; then
    dev_array+=(${dev_t})
 fi
done
echo ${dev_array[@]}
