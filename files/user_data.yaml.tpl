#cloud-config
%{ if admin_user_password != "" ~}
chpasswd:
  list: |
     ${ssh_admin_user}:${admin_user_password}
  expire: False
%{ endif ~}
users:
  - default
  - name: node-exporter
    system: true
    lock_passwd: true
  - name: coredns
    system: true
    lock_passwd: true
  - name: ${ssh_admin_user}
    ssh_authorized_keys:
      - "${ssh_admin_public_key}"
write_files:
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
  #coredns corefile
  - path: /opt/coredns/Corefile
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, corefile)}
  #Coredns systemd configuration
  - path: /etc/systemd/system/coredns.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="DNS Service"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=root
      Group=root
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/coredns -conf /opt/coredns/Corefile

      [Install]
      WantedBy=multi-user.target
  - path: /opt/etcd/ca.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, etcd_ca_certificate)}
  - path: /opt/etcd/client.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, etcd_client_certificate)}
  - path: /opt/etcd/client.key
    owner: root:root
    permissions: "0440"
    content: |
      ${indent(6, etcd_client_key)}
  #Coredns auto updater systemd configuration
  - path: /etc/systemd/system/coredns-auto-updater.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Coredns Zonefiles Updating Service"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      Environment=CONNECTION_TIMEOUT=10
      Environment=REQUEST_TIMEOUT=10
      Environment=REQUEST_RETRIES=0
      Environment=ZONEFILE_PATH=/opt/coredns/zonefiles
      Environment=ETCD_ENDPOINTS=${join(",", etcd_endpoints)}
      Environment=CA_CERT_PATH=/opt/etcd/ca.crt
      Environment=USER_CERT_PATH=/opt/etcd/client.crt
      Environment=USER_KEY_PATH=/opt/etcd/client.key
      Environment=ETCD_KEY_PREFIX=${etcd_key_prefix}
      User=root
      Group=root
      Type=simple
      Restart=always
      RestartSec=1
      WorkingDirectory=/opt/coredns/zonefiles
      ExecStart=/usr/local/bin/coredns-auto-updater

      [Install]
      WantedBy=multi-user.target
packages:
  - curl
runcmd:
  #Setup coredns auto updater service
  - curl -L https://github.com/Ferlab-Ste-Justine/coredns-auto-updater/releases/download/v0.1.0/coredns-auto-updater_0.1.0_linux_amd64.tar.gz -o /tmp/coredns-auto-updater_0.1.0_linux_amd64.tar.gz
  - mkdir -p /tmp/coredns-auto-updater
  - tar zxvf /tmp/coredns-auto-updater_0.1.0_linux_amd64.tar.gz -C /tmp/coredns-auto-updater
  - cp /tmp/coredns-auto-updater/coredns-auto-updater /usr/local/bin/coredns-auto-updater
  - rm -rf /tmp/coredns-auto-updater
  - rm -f /tmp/coredns-auto-updater_0.1.0_linux_amd64.tar.gz
  - mkdir - p /opt/coredns/zonefiles
  - systemctl enable coredns-auto-updater
  - systemctl start coredns-auto-updater
  #Setup coredns service
  - curl -L https://github.com/coredns/coredns/releases/download/v${coredns_version}/coredns_${coredns_version}_linux_amd64.tgz -o /tmp/coredns_${coredns_version}_linux_amd64.tgz
  - tar xzvf /tmp/coredns_${coredns_version}_linux_amd64.tgz -C /usr/local/bin
  - rm -f /tmp/coredns_${coredns_version}_linux_amd64.tgz
  - systemctl enable coredns
  - systemctl start coredns
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.3.0/node_exporter-1.3.0.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.3.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter