#!/bin/bash -e

# Add banner to MOTD
cat >> /etc/motd << EOF
*******************************************************
**     !!  AZURE VM IMAGE BUILDER Custom Image  !!   **
*******************************************************
EOF

cd /install

cat >> /install/test.yml << EOF
- name: Configure Server
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
  - name: Add Oracle User Limits
    lineinfile: dest=/etc/security/limits.conf line='oracle {{ item.limit }} {{ item.type}} {{ item.value }}'
    become_user: root
    loop:
      - { limit: 'soft', type: nofile, value: 4096 }
      - { limit: 'hard', type: nofile, value: 65536 }
      - { limit: 'soft', type: nproc, value: 2047 }
      - { limit: 'hard', type: nproc, value: 16384 }
      - { limit: 'soft', type: stack, value: 10240 }
      - { limit: 'hard', type: stack, value: 32768 }
      - { limit: 'soft', type: memlock, value: 60397978 }
      - { limit: 'hard', type: memlock, value: 60397978 }
  - name: Create Base Directories
    file:
      state: directory
      path: /oracle/app
      owner: oracle
      group: oinstall
  - name: Create Disable Transparent Huge Pages script
    copy:
      dest: ~/disable_trans_hugepages.sh
      mode: 755
      content: "
        cat << EOF >> /etc/rc.local\n
        if test -f /sys/kernel/mm/transparent_hugepage/enabled; then\n
        \techo never > /sys/kernel/mm/transparent_hugepage/enabled\n
        fi\n
        if test -f /sys/kernel/mm/transparent_hugepage/defrag; then\n
        \techo never > /sys/kernel/mm/transparent_hugepage/defrag\n
        fi\n
        EOF\n
        if test -f /sys/kernel/mm/transparent_hugepage/enabled; then\n
        \techo never > /sys/kernel/mm/transparent_hugepage/enabled\n
        fi\n
        if test -f /sys/kernel/mm/transparent_hugepage/defrag; then\n
        \techo never > /sys/kernel/mm/transparent_hugepage/defrag\n
        fi\n"
  - name: Run Disable Transparent Hugepages script
    shell: ~/disable_trans_hugepages.sh
    become_user: root
EOF

# Register the Microsoft RedHat repository
curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
#sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
sudo yum install -y code
 
# Install PowerShell
sudo yum install -y powershell

# Optional installation method
# sudo yum install https://github.com/PowerShell/PowerShell/releases/download/v7.0.3/powershell-lts-7.0.3-1.rhel.7.x86_64.rpm

# Install OMI
sudo wget https://github.com/Microsoft/omi/releases/download/v1.1.0-0/omi-1.1.0.ssl_100.x64.rpm
sudo wget https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/download/v1.1.1-294/dsc-1.1.1-294.ssl_100.x64.rpm

sudo rpm -Uvh omi-1.1.0.ssl_100.x64.rpm dsc-1.1.1-294.ssl_100.x64.rpm

sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
sudo yum -y install python-pip
sudo yum install ansible -y
sudo  ansible-playbook test.yml

# Start PowerShell
# pwsh

# install-module nx
