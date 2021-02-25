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
  - name: Install packages
    yum:
      name: "{{ item.pak }}"
      state: latest
    become_user: root
    loop:
      - { pak: mdadm}
      - { pak: binutils }
      - { pak: compat-libcap1 }
      - { pak: compat-libstdc++-33-3.2.3-72.el7.i686 }
      - { pak: compat-libstdc++-33-3.2.3-72.el7.x86_64 }
      - { pak: gcc }
      - { pak: gcc-c++ }
      - { pak: glibc.i686 }
      - { pak: glibc }
      - { pak: glibc-devel.i686 }
      - { pak: glibc-devel }
      - { pak: ksh }
      - { pak: libaio.i686 }
      - { pak: libaio }
      - { pak: libaio-devel.i686 }
      - { pak: libaio-devel }
      - { pak: libgcc.i686 }
      - { pak: libgcc }
      - { pak: libstdc++.i686 }
      - { pak: libstdc++ }
      - { pak: libstdc++-devel.i686 }
      - { pak: libstdc++-devel }
      - { pak: libXi.i686 }
      - { pak: libXi }
      - { pak: libXtst.i686 }
      - { pak: libXtst}
      - { pak: make }
      - { pak: sysstat }
  - name: Disable SELinux
    selinux:
      state: disabled
    become_user: root
  - name: Disable Firewall daemon
    service: 
      name: firewalld 
      state: stopped 
      enabled: no
    become_user: root
  - name: Adjust Kernel Parameters
    sysctl:
      name: "{{ item.key }}"
      value: "{{ item.value }}"
      state: present
    become_user: root
    loop:
      - { key: fs.file-max, value: 6815744 }
      - { key: kernel.sem, value: 250 32000 100 128 }
      - { key: kernel.shmmni, value: 4096 }
      - { key: kernel.shmall, value: 4294967296 }
      - { key: kernel.shmmax, value: 4398046511104 }
      - { key: kernel.panic_on_oops, value: 1 }
      - { key: net.core.rmem_default, value: 262144 }
      - { key: net.core.rmem_max, value: 4194304 }
      - { key: net.core.wmem_default, value: 262144 }
      - { key: net.core.wmem_max, value: 1048576 }
      - { key: net.ipv4.conf.all.rp_filter, value: 2 }
      - { key: net.ipv4.conf.default.rp_filter, value: 2 }
      - { key: fs.aio-max-nr, value: 1048576 }
      - { key: net.ipv4.ip_local_port_range, value: 9000 65500 }
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

# Register the Microsoft RedHat repository
curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
#sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'

# Install PowerShell
sudo yum install -y powershell

# Optional installation method
# sudo yum install https://github.com/PowerShell/PowerShell/releases/download/v7.0.3/powershell-lts-7.0.3-1.rhel.7.x86_64.rpm

# Install OMI
wget https://github.com/Microsoft/omi/releases/download/v1.1.0-0/omi-1.1.0.ssl_100.x64.rpm
wget https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/download/v1.1.1-294/dsc-1.1.1-294.ssl_100.x64.rpm

sudo rpm -Uvh omi-1.1.0.ssl_100.x64.rpm dsc-1.1.1-294.ssl_100.x64.rpm

sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
sudo yum -y install python-pip
sudo yum install ansible -y
sudo  ansible-playbook test.yml

# Start PowerShell
# pwsh

# install-module nx
