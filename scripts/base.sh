#!/bin/bash -e

# Add banner to MOTD
cat >> /etc/motd << EOF
*******************************************************
**     !!  AZURE VM IMAGE BUILDER Custom Image  !!   **
*******************************************************
EOF

cd /install

cat >> /install/test.yml << EOF
- name: Configure Users
  hosts: localhost
  become: yes
  vars_files:
    - secrets.yml
  tasks:
  - name: Create Groups
    group:
      name: "{{ item.group }}"
      state: present
    become_user: root
    loop:
      - { group: oinstall }
      - { group: dba }
      - { group: oper }
  - name: Create Oracle User
    user:
      name: oracle
      groups: "{{ item.group }}"
      password: "{{ oraclepass }}"
      state: present
      append: yes
    become_user: root
    loop:
      - { group: oinstall }
      - { group: dba }
      - { group: oper }
  - name: Create Base Directories
    file:
      state: directory
      path: /oracle/app
      owner: oracle
      group: oinstall
EOF

sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
sudo yum -y install python-pip
sudo yum install ansible -y
sudo  ansible-playbook test.yml
