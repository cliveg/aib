#!/bin/bash -e

# Add banner to MOTD
cat >> /etc/motd << EOF
*******************************************************
**     !!  AZURE VM IMAGE BUILDER Custom Image  !!   **
*******************************************************
EOF

cd /install

cat >> /install/rhel-oracle.yml << EOF
- name: Configure Server
  hosts: localhost
  become: yes
  vars_files:
    - vars.yml
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
  - name: Create U01 Logical Volume
    lvol:
      vg: rootvg
      lv: u01lv
      size: 20480
  - name: Create a filesystem on lvm".
    filesystem:
      fstype: "xfs"
      dev: "/dev/mapper/rootvg-u01lv"
      force: no
  - name: Create Base Directories
    file:
      path: "{{ item.directory }}"
      state: directory
      mode: '0755'
      owner: oracle
      group: oinstall
    loop:
      - { directory: '/u01' }
      - { directory: '/u01/app' }
      - { directory: '/u01/app/oraInventory' }
      - { directory: '/u01/app/oracle' }
      - { directory: '/u01/app/oracle/product' }
      - { directory: '/u01/app/oracle/product/19.0.0' }
      - { directory: '/u01/app/oracle/product/19.0.0/dbhome_1' }
      - { directory: '/u02' }
      - { directory: '/u02/oradata' }
      - { directory: '/fra' }
      - { directory: '/dump' }
      - { directory: '/stage' }
  - name: Mount the created filesystem.
    mount:
      path: "/u01"
      src: "/dev/mapper/rootvg-u01lv"
      fstype: "xfs"
      opts: rw,nosuid,noexec
      state: mounted
  - name: Extend rootlv
    lvol:
      vg: rootvg
      lv: rootlv
      size: "10240"
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
  - name: Download-db_home
    become_user: root
    command: "wget -P /stage/ https://clivegaib.blob.core.windows.net/pub/oracle/19c/LINUX.X64_193000_db_home.zip"
  - name: Download-OraPatch
    become_user: root
    command: "wget -P /stage/ https://clivegaib.blob.core.windows.net/pub/oracle/19c/p31326362_190000_Linux-x86-64.zip"
  - name: Download Install Files
    become_user: root
    get_url:
      url: "{{ item }}"
      http_agent: Internet Explorer 3.5 for UNIX
      tmp_dest: "/{{ oracle_folder }}"
      dest: "/stage"
    with_items:
      - "https://{{ blob_account }}.blob.core.windows.net/pub/oracle/19c/oracle-database-preinstall-19c-1.0-1.el7.x86_64.rpm"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/rhel/compat-libstdc++-33-3.2.3-72.el7.x86_64.rpm"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/rhel/compat-libcap1-1.10-7.el7.x86_64.rpm"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/oracle/19c/patches/p6880880_121010_Linux-x86-64.zip"  
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
      - { pak: /stage/compat-libstdc++-33-3.2.3-72.el7.x86_64.rpm }
      - { pak: /stage/compat-libcap1-1.10-7.el7.x86_64.rpm }
  - name: Check Base Directories
    become_user: root
    file:
      path: "{{ item.directory }}"
      state: directory
      mode: '0755'
      owner: oracle
      group: oinstall
    loop:
      - { directory: '/{{ oracle_folder }}' }
      - { directory: '/{{ oracle_folder }}/app' }
      - { directory: '/{{ oracle_folder }}/app/oraInventory' }
      - { directory: '/{{ oracle_folder }}/app/oracle' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product/19.0.0' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1' }
  - name: Generate Response file
    copy:
      dest: /stage/db_install.rsp
      content: "
        oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0\n
        oracle.install.option=INSTALL_DB_SWONLY\n
        UNIX_GROUP_NAME=oinstall\n
        INVENTORY_LOCATION=/u01/app/oraInventory\n
        ORACLE_HOME=/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1\n
        ORACLE_BASE=/{{ oracle_folder }}/app/oracle\n
        oracle.install.db.InstallEdition=EE\n
        oracle.install.db.OSDBA_GROUP=oinstall\n
        oracle.install.db.OSOPER_GROUP=oinstall\n
        oracle.install.db.OSBACKUPDBA_GROUP=oinstall\n
        oracle.install.db.OSDGDBA_GROUP=oinstall\n
        oracle.install.db.OSKMDBA_GROUP=oinstall\n
        oracle.install.db.OSRACDBA_GROUP=oinstall\n
        oracle.install.db.rootconfig.executeRootScript=false\n
        oracle.install.db.rootconfig.configMethod=\n
        oracle.install.db.rootconfig.sudoPath=\n
        oracle.install.db.rootconfig.sudoUserName=\n
        oracle.install.db.CLUSTER_NODES=\n
        oracle.install.db.config.starterdb.type=\n
        oracle.install.db.config.starterdb.globalDBName=\n
        oracle.install.db.config.starterdb.SID=\n
        oracle.install.db.ConfigureAsContainerDB=\n
        oracle.install.db.config.PDBName=\n
        oracle.install.db.config.starterdb.characterSet=\n
        oracle.install.db.config.starterdb.memoryOption=\n
        oracle.install.db.config.starterdb.memoryLimit=\n
        oracle.install.db.config.starterdb.installExampleSchemas=\n
        oracle.install.db.config.starterdb.password.ALL=\n
        oracle.install.db.config.starterdb.password.SYS=\n
        oracle.install.db.config.starterdb.password.SYSTEM=\n
        oracle.install.db.config.starterdb.password.DBSNMP=\n
        oracle.install.db.config.starterdb.password.PDBADMIN=\n
        oracle.install.db.config.starterdb.managementOption=\n
        oracle.install.db.config.starterdb.omsHost=\n
        oracle.install.db.config.starterdb.omsPort=\n
        oracle.install.db.config.starterdb.emAdminUser=\n
        oracle.install.db.config.starterdb.emAdminPassword=\n
        oracle.install.db.config.starterdb.enableRecovery=\n
        oracle.install.db.config.starterdb.storageType=\n
        oracle.install.db.config.starterdb.fileSystemStorage.dataLocation=\n
        oracle.install.db.config.starterdb.fileSystemStorage.recoveryLocation=\n
        oracle.install.db.config.asm.diskGroup=\n
        oracle.install.db.config.asm.ASMSNMPPassword=\n"
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
sudo ansible-playbook rhel-oracle.yml

# Start PowerShell
# pwsh

# install-module nx
