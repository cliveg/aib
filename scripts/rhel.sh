#!/bin/bash -e

# Add banner to MOTD
cat >> /etc/motd << EOF
****************************************************************
**     !!  AZURE VM IMAGE BUILDER Custom Image: base.sh  !!   **
****************************************************************
EOF

cd /install

cat >> /install/rhel-golden.yml << EOF
- name: Configure Server
  hosts: localhost
  become: yes
  become_user: root  
  vars_files:
    - vars.yml
  tasks:
  - name: Create U01 Logical Volume
    lvol:
      vg: rootvg
      lv: u01lv
      size: "20480"
  - name: Extend rootlv
    lvol:
      vg: rootvg
      lv: rootlv
      size: "15240"
      force: yes
  - name: Extend varlv
    lvol:
      vg: rootvg
      lv: varlv
      size: "10240"
      force: yes
  - name: Disable SELinux
    selinux:
      state: disabled
  - name: Disable Firewall daemon
    service: 
      name: firewalld 
      state: stopped 
      enabled: no
  - name: Enable TCPKeepAlive
    lineinfile:
      path: /etc/ssh/sshd_config
      regexp: '^#TCPKeepAlive yes'
      line: TCPKeepAlive yes
  - name: Enable ClientAliveInterval
    lineinfile:
      path: /etc/ssh/sshd_config
      regexp: '^#ClientAliveInterval 0'
      line: ClientAliveInterval 60
  - name: Enable ClientAliveInterval
    lineinfile:
      path: /etc/ssh/sshd_config
      regexp: '^#ClientAliveCountMax 0'
      line: ClientAliveCountMax 0
  - name: Set readline editing to to vi
    shell: "set -o vi"
  - name: set up swap
    vars:
      waagent:
        ResourceDisk.Format: y                   # Format if unformatted
        ResourceDisk.Filesystem: ext4            # Typically ext3 or ext4
        ResourceDisk.MountPoint: /mnt/resource   #
        ResourceDisk.EnableSwap: y               # Create and use swapfile
        ResourceDisk.SwapSizeMB: 16384            # Size of the swapfile
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
    tags:
      - setup
  - name: Download Installation Files
    get_url:
      url: "{{ item }}"
      http_agent: Internet Explorer 3.5 for UNIX
      tmp_dest: "/{{ oracle_folder }}"
      dest: "/{{ oracle_folder }}/stage"
    with_items:
      - "https://{{ blob_account }}.blob.core.windows.net/pub/rhel/RHFiles.tar"
  - name: Extract Management Software
    unarchive:
      src: "{{ item }}"
      dest: "/"
      remote_src: True
    with_items:
      - "/{{ oracle_folder }}/stage/RHFiles.tar"
  - name: Delete File from RHFiles.tar
    file:
      path: /etc/NetworkManager/conf.d/90-dns-none.conf
      state: absent
  - name: Install packages
    yum:
      name: "{{ item.pak }}"
      state: latest
      disable_gpg_check: true
    loop:
      - { pak: facter }
      - { pak: net-snmp }
      - { pak: net-snmp-utils }
      - { pak: crash }
      - { pak: dstat }
      - { pak: cifs-utils }
#      - { pak: mdadm}
#      - { pak: binutils }
      - { pak: gcc }
      - { pak: gcc-c++ }
      - { pak: glibc.i686 }
      - { pak: glibc }
      - { pak: glibc-devel.i686 }
      - { pak: glibc-devel }
      - { pak: ksh }
      - { pak: libaio }
      - { pak: libaio.i686 }
      - { pak: libaio-devel }
      - { pak: libaio-devel.i686 }
      - { pak: libgcc.i686 }
      - { pak: libgcc }
      - { pak: libstdc++.i686 }
      - { pak: libstdc++ }
      - { pak: libstdc++-devel }
      - { pak: libstdc++-devel.i686 }
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
#      - { pak: cloud-utils-growpart }
#      - { pak: gdisk }
#      - { pak: "http://mirror.centos.org/centos/7/os/x86_64/Packages/compat-libcap1-1.10-7.el7.x86_64.rpm" }
#      - { pak: "http://mirror.centos.org/centos/7/os/x86_64/Packages/compat-libstdc++-33-3.2.3-72.el7.x86_64.rpm" }
#      - { pak: "http://mirror.centos.org/centos/7/os/x86_64/Packages/libnl-1.1.4-3.el7.x86_64.rpm" }
      - { pak: /var/tmp/falcon-sensor-5.43.0-10807.el7.x86_64.rpm }
      - { pak: /var/tmp/managesoft-12.1.0-1.x86_64.rpm }
      - { pak: /var/tmp/NessusAgent-7.7.0-es7.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-openssl-5.7.0-207-rhel5.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-openldap-5.7.0-207-rhel5.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-curl-5.7.0-207-rhel5.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-5.7.0-207-rhel5.x86_64.rpm }            
EOF
#      - { pak: compat-libcap1 }


cat >> /install/post.yml << EOF
- name: Post configure
  hosts: localhost
  become: yes
  become_user: root
  vars_files:
    - vars.yml
  tasks:
  - name: Replace a localhost entry with our own
    lineinfile:
      path: /etc/hosts
      insertafter: EOF
      line: "127.0.0.1 {{ ansible_hostname }}.{{ domain_suffix }}"
      state: present
      owner: root
      group: root
      mode: '0644'
  - name: dnssearch
    command: "nmcli con mod \"System eth0\" ipv4.dns-search \"{{ dns_search }}\""
  - name: restart network manager
    command: "systemctl restart NetworkManager"
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
sudo yum -y install python3-pip
sudo yum -y install ansible
sudo yum update -y
