#!/bin/bash
set -e
trap "cleanup $? $LINENO" EXIT

function cleanup {
  if [ "$?" != "0" ]; then
    echo "PLAYBOOK FAILED. See /var/log/stackscript.log for details."
    rm ${HOME}/.ssh/id_ansible_ed25519{,.pub}
    destroy
    exit 1
  fi
}

# constants
readonly ROOT_PASS=$(sudo cat /etc/shadow | grep root)
readonly LINODE_PARAMS=($(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .type,.region,.image,.label))
readonly TAGS=$(curl -sH "Authorization: Bearer ${TOKEN_PASSWORD}" "https://api.linode.com/v4/linode/instances/${LINODE_ID}" | jq -r .tags)
readonly VARS_PATH="./group_vars/mongodb/vars"

# utility functions
function destroy {
  if [ -n "${DISTRO}" ] && [ -n "${DATE}" ]; then
    ansible-playbook -i hosts destroy.yml --extra-vars "instance_prefix=${DISTRO}_${DATE}"
  else
    ansible-playbook -i hosts destroy.yml
  fi
}

function secrets {
  #generate secrets
  local SECRET_VARS_PATH="./group_vars/mongodb/secret_vars"
  local VAULT_PASS=$(openssl rand -base64 32)
  local TEMP_ROOT_PASS=$(openssl rand -base64 32)
  local MONGO_ROOT_PASS=$(openssl rand -base64 32)
  local MONGO_ADMIN_PASS=$(openssl rand -base64 32)
  #write secrets
  echo "${VAULT_PASS}" > ./.vault-pass
  cat << EOF > ${SECRET_VARS_PATH}
`ansible-vault encrypt_string "${TEMP_ROOT_PASS}" --name 'root_pass'`
`ansible-vault encrypt_string "${TOKEN_PASSWORD}" --name 'token'`
`ansible-vault encrypt_string "${MONGO_ROOT_PASS}" --name 'mongo_root_pass'`
`ansible-vault encrypt_string "${MONGO_ADMIN_PASS}" --name 'mongo_admin_pass'`
EOF
}

function ssh_key {
    ssh-keygen -o -a 100 -t ed25519 -C "ansible" -f "${HOME}/.ssh/id_ansible_ed25519" -q -N "" <<<y >/dev/null
    export ANSIBLE_SSH_PUB_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519.pub)
    export ANSIBLE_SSH_PRIV_KEY=$(cat ${HOME}/.ssh/id_ansible_ed25519)
    export SSH_KEY_PATH="${HOME}/.ssh/id_ansible_ed25519"
    chmod 700 ${HOME}/.ssh
    chmod 600 ${SSH_KEY_PATH}
    eval $(ssh-agent)
    ssh-add ${SSH_KEY_PATH}
    echo -e "\nprivate_key_file = ${SSH_KEY_PATH}" >> ansible.cfg
}

function lint {
  yamllint .
  ansible-lint
  flake8
}

function verify {
    ansible-playbook -vvv -i hosts verify.yml
    destroy
}

# production
function ansible:build {
  secrets
  ssh_key
  # write vars file
  sed 's/  //g' <<EOF > ${VARS_PATH}
  # linode vars
  ssh_keys: ${ANSIBLE_SSH_PUB_KEY}
  instance_prefix: ${LINODE_PARAMS[3]}
  cluster_name: ${CLUSTER_NAME}
  type: ${LINODE_PARAMS[0]}
  region: ${LINODE_PARAMS[1]}
  image: ${LINODE_PARAMS[2]}
  linode_tags: ${TAGS}
  # ssl/tls vars
  country_name: ${COUNTRY_NAME}
  state_or_province_name: ${STATE_OR_PROVINCE}
  locality_name: ${LOCALITY_NAME}
  organization_name: ${ORGANIZATION_NAME}
  email_address: ${EMAIL_ADDRESS}
  ca_common_name: ${CA_COMMON_NAME}
  common_name: ${COMMON_NAME}
  # sudo user
  sudo_username: ${SUDO_USERNAME}
EOF
}

function ansible:deploy {
  ansible-playbook -vvv provision.yml
  ansible-playbook -vvv -i hosts site.yml --extra-vars "root_password=${ROOT_PASS} add_keys_prompt=${ADD_SSH_KEYS}"
}

# testing
function test:build {

  # write vars file
  sed 's/  //g' <<EOF > ${VARS_PATH}
  # linode vars
  ssh_keys: ssh-rsa AAAA_valid_public_ssh_key_123456785== user@their-computer 
  instance_prefix: mongodb
  cluster_name: linode.com
  type: g6-standard-2
  region: us-southeast
  image: linode/debian11
  linode_tags: occ_test

  # ssl/tls vars
  country_name: US
  state_or_province_name: Pennsylvania
  locality_name: Philadelphia
  organization_name: Linode
  email_address: test@linode.com
  ca_common_name: MongoDB CA
  common_name: linode.com
  # sudo user
  sudo_username: admin
EOF
  cat "./group_vars/mongodb/vars"
  mkdir -p ${HOME}/.ssh
  echo ${ACCOUNT_SSH_KEYS} >> ${HOME}/.ssh/authorized_keys
  secrets
  #dbg
  #cat "./group_vars/mongodb/secret_vars"
  ssh_key
}

function test:deploy {
  export DISTRO="${1}"
  export DATE="$(date '+%Y-%m-%d-%H%M%S')"
  ansible-playbook provision.yml --extra-vars "ssh_keys=${HOME}/.ssh/id_ansible_ed25519.pub instance_prefix=${DISTRO}-${DATE} image=linode/${DISTRO}"
  ansible-playbook -vvv -i hosts site.yml --extra-vars "root_password=${ROOT_PASS}  add_keys_prompt=yes"
  verify
}

# main
case $1 in
    ansible:build) "$@"; exit;;
    ansible:deploy) "$@"; exit;;
    test:build) "$@"; exit;;
    test:deploy) "$@"; exit;;
esac
