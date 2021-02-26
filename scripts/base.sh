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
  - name: Install packages
    yum:
      name: "{{ item.pak }}"
      state: latest
    become_user: root
    loop:
      - { pak: facter }
      - { pak: net-snmp }
      - { pak: net-snmp-utils }
      - { pak: crash }
      - { pak: dstat }
      - { pak: cifs-utils }
      - { pak: mdadm}
      - { pak: binutils }
      - { pak: compat-libcap1 }
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
      - { pak: libXtst }
      - { pak: make }
      - { pak: sysstat }
      - { pak: java-1.8.0-openjdk }
      - { pak: java-1.8.0-openjdk-devel }
      - { pak: elfutils-libelf-devel }
      - { pak: fontconfig-devel }
      - { pak: librdmacm-devel }
      - { pak: libstdc++-devel }
      - { pak: nfs-utils }
      - { pak: targetcli }
      - { pak: cloud-utils-growpart }
      - { pak: gdisk }
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
  - name: set up swap
    vars:
      waagent:
        ResourceDisk.Format: y                   # Format if unformatted
        ResourceDisk.Filesystem: ext4            # Typically ext3 or ext4
        ResourceDisk.MountPoint: /mnt/resource   #
        ResourceDisk.EnableSwap: y               # Create and use swapfile
        ResourceDisk.SwapSizeMB: 2048            # Size of the swapfile
    become_user: root
    lineinfile: dest=/etc/waagent.conf line="{{ item.key }}={{ item.value }}"
    with_dict: "{{ waagent }}"
    tags:
      - setup

  - name: unmount device
    mount: 
      path: /mnt
      state: unmounted
    tags:
      - setup

  - name: restart agent
    service:
      name: waagent.service
      state: restarted
    become_user: root
    tags:
      - setup
EOF

# Register the Microsoft RedHat repository
curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
 
# Install PowerShell
#sudo yum install -y powershell

# Install OMI
#sudo wget https://github.com/Microsoft/omi/releases/download/v1.1.0-0/omi-1.1.0.ssl_100.x64.rpm
#sudo wget https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/download/v1.1.1-294/dsc-1.1.1-294.ssl_100.x64.rpm

#sudo rpm -Uvh omi-1.1.0.ssl_100.x64.rpm dsc-1.1.1-294.ssl_100.x64.rpm

sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
sudo yum -y install python-pip
sudo yum install ansible -y
sudo ansible-playbook test.yml

# Start PowerShell
# pwsh

# install-module nx
