#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "${BASE_DIR}/config/variables.sh"

TOPO_DIR="${BASE_DIR}/topology"

TOPO_FILE="${TOPO_DIR}/DMZ.yml"

cat > "$TOPO_FILE" << YAML

name: ${LAB_NAME}

mgmt:
  network: mgmt-net
  ipv4-subnet: 172.20.20.0/24

topology:
  nodes:
    # === Internet Zone ===
    Attacker:
      kind: linux
      image: ${IMG_KALI}
      group: internet

    router-internet:
      kind: linux
      image: ${IMG_FRR}
      group: internet

    router-edge:
      kind: linux
      image: ${IMG_FRR}
      group: edge

    # === DMZ Zone ===
    External_FW:
      kind: linux
      image: ${IMG_UBUNTU}
      group: dmz
      cap-add:
        - NET_ADMIN

    DMZ_Switch:
      kind: linux
      image: ${IMG_FRR}
      group: dmz

    Proxy_WAF:
      kind: linux
      image: ${IMG_MODSEC}
      group: dmz
      startup-delay: 10
      ports:
        - "8080:8080"
      cap-add:
        - NET_ADMIN

    Flask_Webserver:
      kind: linux
      image: ${IMG_UBUNTU}
      group: dmz

    Database:
      kind: linux
      image: ${IMG_POSTGRES}
      group: dmz
      ports:
        - "3636:5432"
      env:
        POSTGRES_PASSWORD: admin123
        POSTGRES_DB: webapp

    DMZ_IDS:
      kind: linux
      image: ${IMG_SURICATA}
      group: dmz
      startup-delay: 15
      binds:
        - ${BASE_DIR}/config/suricata/rules:/etc/suricata/rules:ro
      cap-add:
        - NET_ADMIN
        - SYS_NICE

    # === SIEM Zone ===
    SIEM_FW:
      kind: linux
      image: ${IMG_UBUNTU}
      group: siem
      cap-add:
        - NET_ADMIN

    elasticsearch:
      kind: linux
      image: ${IMG_ELASTIC}
      group: siem
      startup-delay: 15
      env:
        discovery.type: single-node
        ES_JAVA_OPTS: "-Xms512m -Xmx512m"
        xpack.security.enabled: "false"
      ports:
        - "9200:9200"
      cap-add:
        - NET_ADMIN

    logstash:
      kind: linux
      image: ${IMG_LOGSTASH}
      group: siem
      startup-delay: 10
      cmd: tail -f /dev/null
      binds:
        - ${BASE_DIR}/config/logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml:rw
        - ${BASE_DIR}/config/logstash/pipeline:/usr/share/logstash/pipeline:ro
      env:
        XPACK_MONITORING_ENABLED: "false"
        LS_JAVA_OPTS: "-Xmx512m -Xms512m"
      cap-add:
        - NET_ADMIN

    kibana:
      kind: linux
      image: ${IMG_KIBANA}
      group: siem
      startup-delay: 20
      env:
        ELASTICSEARCH_HOSTS: "http://elasticsearch:9200"
      ports:
        - "5601:5601"
      binds:
        - ${BASE_DIR}/config/kibana/kibana.yml:/usr/share/kibana/config/kibana.yml:rw
      cap-add:
        - NET_ADMIN

    siem_pc:
      kind: linux
      image: ${IMG_ALPINE}
      group: siem

  links:
    # Internet path
    - endpoints: ["router-internet:eth1", "Attacker:eth1"]
    - endpoints: ["router-edge:eth1", "router-internet:eth2"]
    - endpoints: ["External_FW:eth2", "router-edge:eth2"]

    # DMZ connections
    - endpoints: ["DMZ_Switch:eth1", "External_FW:eth1"]
    - endpoints: ["DMZ_Switch:eth2", "Proxy_WAF:eth1"]
    - endpoints: ["Proxy_WAF:eth2", "Flask_Webserver:eth1"]
    - endpoints: ["Flask_Webserver:eth2", "Database:eth1"]
    - endpoints: ["DMZ_Switch:eth3", "DMZ_IDS:eth1"]

    # SIEM connections
    - endpoints: ["External_FW:eth3", "SIEM_FW:eth2"]
    - endpoints: ["SIEM_FW:eth3", "logstash:eth1"]
    - endpoints: ["SIEM_FW:eth4", "elasticsearch:eth3"]
    - endpoints: ["SIEM_FW:eth5", "kibana:eth2"]
    - endpoints: ["SIEM_FW:eth6", "siem_pc:eth1"]
    - endpoints: ["SIEM_FW:eth7", "DMZ_IDS:eth2"]
    - endpoints: ["SIEM_FW:eth9", "Proxy_WAF:eth3"]
    - endpoints: ["logstash:eth2", "elasticsearch:eth1"]
    - endpoints: ["elasticsearch:eth2", "kibana:eth1"]

YAML

echo "Topology file generated: $TOPO_FILE"
