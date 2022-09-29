#!/bin/bash
set -e
trap "cleanup $? $LINENO" EXIT

## Deployment Variables
# <UDF name="cluster_name" label="Domain Name" example="linode.com" default="linode.com" />
# <UDF name="token_password" label="Your Linode API token" />
# <UDF name="add_ssh_keys" label="Add Account SSH Keys to All Nodes?" oneof="yes,no"  default="yes" />
# <UDF name="domain_name" label="Details for self-signed SSL certificates: Country or Region" example="US" default="US" />
# <UDF name="state_or_province_name" label="State or Province" example="Pennsylvania" default="Pennsylvania" />
# <UDF name="locality_name" label="Locality" example="Philadelphia" default="Philadelphia" />
# <UDF name="organization_name" label="Organization" example="Linode LLC" default="Linode LLC"  />
# <UDF name="email_address" label="Email Address" example="user@linode.com" default="user@linode.com"  />
# <UDF name="ca_common_name" label="CA Common Name" example="Mongo CA" default="Mongo CA"  />
# <UDF name="common_name" label="Common Name" example="Mongo Server" default="Mongo Server"  />

## Linode/SSH Security Settings
#<UDF name="sudo_username" label="The limited sudo user to be created in the cluster" />

# git repo
 export GIT_REPO="https://github.com/linode-solutions/mongodb-occ.git"

# enable logging
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1
# source script libraries
source <ssinclude StackScriptID=1>
function cleanup {
  if [ "$?" != "0" ] || [ "$SUCCESS" == "true" ]; then
    #deactivate
    cd ${HOME}
    if [ -d "/tmp/mongodb-cluster" ]; then
      rm -rf /tmp/mongodb-cluster
    fi
    if [ -d "/usr/local/bin/run" ]; then
      rm /usr/local/bin/run
    fi
    stackscript_cleanup && destroy_linode
  fi
}
function destroy_linode {
  curl -H "Authorization: Bearer ${TOKEN_PASSWORD}" \
    -X DELETE \
    https://api.linode.com/v4/linode/instances/${LINODE_ID}
}
function setup {
  # install dependancies
  apt-get update
  apt-get install -y jq git python3 python3-pip python3-dev build-essential
  # write authorized_keys file
  if [ "${ADD_SSH_KEYS}" == "yes" ]; then
    curl -sH "Content-Type: application/json" -H "Authorization: Bearer ${TOKEN_PASSWORD}" https://api.linode.com/v4/profile/sshkeys | jq -r .data[].ssh_key > /root/.ssh/authorized_keys
  fi
  # clone repo and set up ansible environment
  git clone ${GIT_REPO} /tmp/mongodb-cluster
  cd /tmp/mongodb-cluster
  pip3 install virtualenv
  python3 -m virtualenv env
  source env/bin/activate
  pip install pip --upgrade
  pip install -r requirements.txt
  ansible-galaxy install -r collections.yml
  # copy run script to path
  cp scripts/run.sh /usr/local/bin/run
  chmod +x /usr/local/bin/run
}
# main
setup
run ansible:build
run ansible:deploy && export SUCCESS="true"