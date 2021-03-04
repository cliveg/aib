#!/bin/bash -e

# Add banner to MOTD
cat >> /etc/motd << EOF
*******************************************************
**     !!  AZURE VM IMAGE BUILDER Custom Image  !!   **
*******************************************************
EOF

cd /install

cat >> /install/rhel-golden.yml << EOF
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
      size: "20480"
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
      - { directory: '/{{ oracle_folder }}' }
      - { directory: '/{{ oracle_folder }}/app' }
      - { directory: '/{{ oracle_folder }}/app/oraInventory' }
      - { directory: '/{{ oracle_folder }}/app/oracle' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product/19.0.0' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1' }
      - { directory: '/{{ oracle_folder }}/stage' }
      - { directory: '/u02' }
      - { directory: '/u02/oradata' }
      - { directory: '/fra' }
      - { directory: '/dump' }
  - name: Mount the created filesystem.
    mount:
      path: "/{{ oracle_folder }}"
      src: "/dev/mapper/rootvg-u01lv"
      fstype: "xfs"
      opts: defaults
      state: mounted
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
  - name: Keep SSH Session alive longer
    command: "sed -i /etc/ssh/sshd_config -e 's:.ClientAliveInterval 0:ClientAliveInterval 60:'; sed -i /etc/ssh/sshd_config -e 's:.TCPKeepAlive yes:TCPKeepAlive yes:'"
    become_user: root
  - name: Set readline editing to to vi
    command: "set -o vi"
    become_user: root    
  - name: set up swap
    vars:
      waagent:
        ResourceDisk.Format: y                   # Format if unformatted
        ResourceDisk.Filesystem: ext4            # Typically ext3 or ext4
        ResourceDisk.MountPoint: /mnt/resource   #
        ResourceDisk.EnableSwap: y               # Create and use swapfile
        ResourceDisk.SwapSizeMB: 16384            # Size of the swapfile
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
  - name: Check Base Directories Just in case
    become_user: root
    file:
      path: "{{ item.directory }}"
      state: directory
      mode: '0755'
      owner: oracle
      group: oinstall
    loop:
      - { directory: '/{{ oracle_folder }}' }
      - { directory: '/{{ oracle_folder }}/stage' }
      - { directory: '/{{ oracle_folder }}/app' }
      - { directory: '/{{ oracle_folder }}/app/oraInventory' }
      - { directory: '/{{ oracle_folder }}/app/oracle' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product/19.0.0' }
      - { directory: '/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1' }    
      
  - name: Download Installation Files
    become_user: root
    get_url:
      url: "{{ item }}"
      http_agent: Internet Explorer 3.5 for UNIX
      tmp_dest: "/{{ oracle_folder }}"
      dest: "/{{ oracle_folder }}/stage"
    with_items:
      - "https://{{ blob_account }}.blob.core.windows.net/pub/oracle/19c/oracle-database-preinstall-19c-1.0-1.el7.x86_64.rpm"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/rhel/compat-libstdc++-33-3.2.3-72.el7.x86_64.rpm"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/rhel/compat-libcap1-1.10-7.el7.x86_64.rpm"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/oracle/19c/patches/p6880880_121010_Linux-x86-64.zip"
      - "https://{{ blob_account }}.blob.core.windows.net/pub/rhel/RHFiles.tar"
  - name: Download-Software
    shell: wget -P /{{ oracle_folder }}/stage https://{{ blob_account }}.blob.core.windows.net/pub/oracle/19c/LINUX.X64_193000_db_home.zip
    args:
      warn: false
    become_user: root
  - name: Download-Software-Patch
    shell: wget -P /{{ oracle_folder }}/stage https://{{ blob_account }}.blob.core.windows.net/pub/oracle/19c/patches/p31326362_190000_Linux-x86-64.zip
    args:
      warn: false
    become_user: root
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
  - name: Extract Oracle Software
    become_user: root  
    unarchive:
      src: "{{ item }}"
      dest: "/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1"
      mode: 0755
      remote_src: True
    with_items:
      - "/{{ oracle_folder }}/stage/LINUX.X64_193000_db_home.zip"
  - name: Delete directory OPatch
    file:
      path: /{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1/OPatch
      state: absent
    become_user: root
  - name: Extract Oracle Software Updates
    become_user: root  
    unarchive:
      src: "{{ item }}"
      dest: "/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1"
      mode: 0755
      remote_src: True
    with_items:
      - "/{{ oracle_folder }}/stage/p31326362_190000_Linux-x86-64.zip"
      - "/{{ oracle_folder }}/stage/p6880880_121010_Linux-x86-64.zip"
  - name: Generate Response file
    copy:
      dest: /{{ oracle_folder }}/stage/db_install.rsp
      content: "
        oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0\n
        oracle.install.option=INSTALL_DB_SWONLY\n
        UNIX_GROUP_NAME=oinstall\n
        INVENTORY_LOCATION=/{{ oracle_folder }}/app/oraInventory\n
        ORACLE_HOME=/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1\n
        ORACLE_BASE=/{{ oracle_folder }}/app/oracle\n
        oracle.install.db.InstallEdition=EE\n
        oracle.install.db.OSDBA_GROUP=dba\n
        oracle.install.db.OSOPER_GROUP=oper\n
        oracle.install.db.OSBACKUPDBA_GROUP=dba\n
        oracle.install.db.OSDGDBA_GROUP=dba\n
        oracle.install.db.OSKMDBA_GROUP=dba\n
        oracle.install.db.OSRACDBA_GROUP=dba\n
        oracle.install.db.rootconfig.executeRootScript=false\n
        oracle.install.db.rootconfig.configMethod=\n
        oracle.install.db.rootconfig.sudoPath=\n
        oracle.install.db.rootconfig.sudoUserName=\n
#        oracle.install.db.CLUSTER_NODES=\n
        oracle.install.db.config.starterdb.type=GENERAL_PURPOSE\n
        oracle.install.db.config.starterdb.globalDBName=orcl.oradb3.private\n
        oracle.install.db.config.starterdb.SID=orc1\n
        oracle.install.db.ConfigureAsContainerDB=\n
#        oracle.install.db.config.PDBName=\n
        oracle.install.db.config.starterdb.characterSet=AL32UTF8\n
        oracle.install.db.config.starterdb.memoryOption=true\n
        oracle.install.db.config.starterdb.memoryLimit=65024\n
        oracle.install.db.config.starterdb.installExampleSchemas=\n
        oracle.install.db.config.starterdb.password.ALL={{ oraclepass }}\n
#        oracle.install.db.config.starterdb.password.SYS=\n
#        oracle.install.db.config.starterdb.password.SYSTEM=\n
#        oracle.install.db.config.starterdb.password.DBSNMP=\n
#        oracle.install.db.config.starterdb.password.PDBADMIN=\n
        oracle.install.db.config.starterdb.managementOption=DEFAULT\n
#        oracle.install.db.config.starterdb.omsHost=\n
#        oracle.install.db.config.starterdb.omsPort=\n
#        oracle.install.db.config.starterdb.emAdminUser=\n
#        oracle.install.db.config.starterdb.emAdminPassword=\n
        oracle.install.db.config.starterdb.enableRecovery=true\n
        oracle.install.db.config.starterdb.storageType=FILE_SYSTEM_STORAGE\n
        oracle.install.db.config.starterdb.fileSystemStorage.dataLocation=/u02/oradata\n
        oracle.install.db.config.starterdb.fileSystemStorage.recoveryLocation=/dump\n
#        oracle.install.db.config.asm.diskGroup=\n
#        oracle.install.db.config.asm.ASMSNMPPassword=\n"
  - name: Create Response File for dbca
    copy:
      dest: /{{ oracle_folder }}/stage/dbca.rsp
      content: "
        responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v19.0.0\n
        gdbName=orcl.oradb3.private\n
        sid=orc1\n
        templateName=General_Purpose.dbc\n
        sysPassword={{ vmpassword }}\n
        systemPassword={{ vmpassword }}\n
        emConfiguration=DBEXPRESS\n
        emExpressPort=5500\n
        datafileDestination=/u02/oradata\n
        recoveryAreaDestination=/dump\n
        characterSet=US7ASCII\n
        nationalCharacterSet=UTF8\n
        memoryPercentage=80\n
        totalMemory=0\n"
  - name: Extract Management Software
    become_user: root  
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
    become_user: root      
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
      - { pak: /u01/stage/compat-libstdc++-33-3.2.3-72.el7.x86_64.rpm }
      - { pak: /u01/stage/compat-libcap1-1.10-7.el7.x86_64.rpm }
      - { pak: /u01/stage/oracle-database-preinstall-19c-1.0-1.el7.x86_64.rpm }
      - { pak: /var/tmp/falcon-sensor-5.43.0-10807.el7.x86_64.rpm }
      - { pak: /var/tmp/managesoft-12.1.0-1.x86_64.rpm }
      - { pak: /var/tmp/NessusAgent-7.7.0-es7.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-openssl-5.7.0-207-rhel5.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-openldap-5.7.0-207-rhel5.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-curl-5.7.0-207-rhel5.x86_64.rpm }
      - { pak: /var/tmp/centrify/CentrifyDC-5.7.0-207-rhel5.x86_64.rpm }            
EOF

cat >> /install/post.sh << EOF
#!/bin/bash

  menu_option_one() {
    echo "Configuring Storage"
    ansible-playbook /install/post-disk-5drive.yml
  }

  menu_option_two() {
    echo "Configuring Oracle with SampleDB"
    ansible-playbook /install/post-orainstall-sampledb.yml
  }

  press_enter() {
    echo ""
    echo -n "     Press Enter to continue "
    read
    clear
  }

  incorrect_selection() {
    echo "Incorrect selection! Try again."
  }

  until [ "$selection" = "0" ]; do
    clear
    echo "        Server Build Post Steps"
    echo ""
    echo "        1  -  Configure Storage (5 Drive)"
    echo "        2  -  Configure Oracle with SampleDB"
    echo "        0  -  Exit"
    echo ""
    echo -n "  Enter selection: "
    read selection
    echo ""
    case $selection in
      1 ) clear ; menu_option_one ; press_enter ;;
      2 ) clear ; menu_option_two ; press_enter ;;
      0 ) clear ; exit ;;
      * ) clear ; incorrect_selection ; press_enter ;;
    esac
  done

EOF

cat >> /install/post.yml << EOF
- name: Post configure
  hosts: localhost
- name: Setup VM Storage
  import_playbook: post-disk-5drive.yml
- name: Install and Configure Oracle 12c EE
  import_playbook: post-orainstall-sampledb.yml
EOF

cat >> /install/post-disk-5drive.yml << EOF
- name: Configure Disk-5
  hosts: localhost
  become: yes
  become_user: root
  vars_files:
    - vars.yml
  tasks:
  - name: Partition Disks
    parted:
      device: "{{ item.device }}"
      number: "1"
      flags: [ raid ]
      state: present
    become_user: root
    loop:
      - {device: /dev/sdc}
      - {device: /dev/sdd}
      - {device: /dev/sde}
      - {device: /dev/sdf}
      - {device: /dev/sdg}
  - name: Configure Software RAID Volume data
    shell: mdadm --create /dev/md/mdoradata --level=0 --raid-devices=3 /dev/sdc1 /dev/sdd1 /dev/sde1
    become_user: root
  - name: Configure Software RAID Volume archivelog
    shell: mdadm --create /dev/md/mdarch --level=0 --raid-devices=2 /dev/sdf1 /dev/sdg1
    become_user: root
  - name: Format RAID Volumes
    filesystem:
      fstype: xfs
      dev: "{{ item.raid }}"
    become_user: root
    loop:
      - {raid: /dev/md/mdoradata}
      - {raid: /dev/md/mdarch}
  - name: Get md127 UUID
    shell: /sbin/blkid /dev/md127 -s UUID -o value "\$1"
    become_user: root    
    register: md127uuid
  - name: Get md126 UUID
    shell: /sbin/blkid /dev/md126 -s UUID -o value "\$1"
    register: md126uuid
    become_user: root    
  - name: Add to fstab
    mount:
      path: "{{ item.path }}"
      src: UUID="{{ item.uuid }}"
      fstype: xfs
      opts: defaults,nofail
      passno: "2"
      state: mounted
    become_user: root
    loop:
      - { uuid: "{{ md127uuid.stdout }}", path: /u02/oradata }
      - { uuid: "{{ md126uuid.stdout }}", path: /fra }
  - name: Save RAID Config
    shell: mdadm --detail --scan --verbose >> /etc/mdadm.conf
    become_user: root
  - name: Verify Directory Permissions for Oracle Install
    become_user: root
    file:
      path: "{{ item.directory }}"
      state: directory
      recurse: yes
      mode: '0755'
      owner: oracle
      group: oinstall
    loop:
      - { directory: '/{{ oracle_folder }}' }
      - { directory: '/u02' }    
EOF

cat >> /install/post-orainstall-sampledb.yml << EOF
- name: Install Oracle and create sampledb
  hosts: localhost
  become: yes
  become_user: root
  vars_files:
    - vars.yml
  tasks:
  - name: Install Oracle
    command: "/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1/runInstaller -silent -waitforcompletion -responseFile /{{ oracle_folder }}/stage/db_install.rsp"
    become_user: oracle
  - name: Execute Inventory Root Command
    command: "/{{ oracle_folder }}/app/oraInventory/orainstRoot.sh"
    become_user: root
  - name: Execute DB home Root Command
    command: "/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1/root.sh"
    become_user: root
  - name: Create Listener from netca
    command: '/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1/bin/netca -silent -responseFile /{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1/assistants/netca/netca.rsp'
    become_user: oracle    
  - name: Create Database
    command: '/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1/bin/dbca -silent -createDatabase -responseFile /{{ oracle_folder }}/stage/dbca.rsp'
    become_user: oracle    
  - name: Create Oracle Home Variable
    lineinfile: dest='/home/oracle/.bashrc' line='export ORACLE_HOME=/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1'
    become_user: oracle    
  - name: Create Oracle Sid Variable
    lineinfile: dest='/home/oracle/.bashrc' line='export ORACLE_SID=orc1'
    become_user: oracle    
  - name: Add Oracle Home Bin Folder
    lineinfile: dest='/home/oracle/.bashrc' line='export PATH=$PATH:$ORACLE_HOME/bin'
    become_user: oracle    
  - name: Change oratab
    lineinfile: dest='/etc/oratab' regexp='^ora1:/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1:N' line='ora1:/{{ oracle_folder }}/app/oracle/product/19.0.0/dbhome_1:Y'
    become_user: root    
EOF

# Register the Microsoft RedHat repository
curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo

# Install PowerShell
#sudo yum install -y powershell

# Install OMI
#sudo wget https://github.com/Microsoft/omi/releases/download/v1.1.0-0/omi-1.1.0.ssl_100.x64.rpm
#sudo wget https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/download/v1.1.1-294/dsc-1.1.1-294.ssl_100.x64.rpm

#sudo rpm -Uvh omi-1.1.0.ssl_100.x64.rpm dsc-1.1.1-294.ssl_100.x64.rpm

sudo mkdir -p /u01/stage

sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm
sudo yum -y install python-pip
sudo yum -y install ansible
sudo ansible-playbook rhel-golden.yml
sudo yum -y install libaio-devel
# Start PowerShell
# pwsh

# install-module nx
