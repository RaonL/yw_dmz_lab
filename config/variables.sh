#!/bin/bash
# yw_dmz_lab - Central Variables

export LAB_NAME="yw-dmz"
export TOPO_FILE="DMZ.yml"

# === Docker Images ===
export IMG_ALPINE="alpine:latest"
export IMG_UBUNTU="ubuntu:latest"
export IMG_FRR="frrouting/frr:latest"
export IMG_NGINX="nginx:latest"
export IMG_POSTGRES="postgres:16"
export IMG_SURICATA="jasonish/suricata:latest"
export IMG_KALI="kalilinux/kali-rolling"
export IMG_MODSEC="owasp/modsecurity-crs:nginx"
export IMG_ELASTIC="docker.elastic.co/elasticsearch/elasticsearch:9.2.1"
export IMG_LOGSTASH="docker.elastic.co/logstash/logstash:9.2.1"
export IMG_KIBANA="docker.elastic.co/kibana/kibana:9.2.1"

# === Network Subnets ===
export INTERNET_SUBNET="200.168.1.0/24"
export EDGE1_SUBNET="172.168.2.0/30"
export EDGE2_SUBNET="172.168.3.0/30"
export DMZ_SUBNET="10.0.2.0/24"
export SIEM_SUBNET="10.0.3.0/24"

# === Internet Zone ===
export INTERNET_ATTACKER_ETH1_IP="200.168.1.100/24"
export ROUTER_INTERNET_ETH1_IP="200.168.1.1/24"
export ROUTER_INTERNET_ETH2_IP="172.168.2.1/30"
export ROUTER_EDGE_ETH1_IP="172.168.2.2/30"
export ROUTER_EDGE_ETH2_IP="172.168.3.1/30"

# === External Firewall ===
export EXT_FW_ETH1_IP="10.0.2.1/24"         # DMZ side
export EXT_FW_ETH2_IP="172.168.3.2/30"      # Edge side
export EXT_FW_ETH3_IP="10.0.3.5/30"         # SIEM side

# === DMZ Zone ===
export DMZ_SWITCH_ETH1_IP="10.0.2.2/24"
export DMZ_WAF_ETH1_IP="10.0.2.30/24"
export DMZ_WAF_ETH2_IP="10.0.2.31/24"       # to Flask
export DMZ_WAF_ETH3_IP="10.0.3.34/30"       # to SIEM
export DMZ_WEBSERVER_ETH1_IP="10.0.2.10/24"
export DMZ_WEBSERVER_ETH2_IP="10.0.2.11/24"  # to DB
export DMZ_DB_ETH1_IP="10.0.2.20/24"
export DMZ_IDS_ETH1_IP="10.0.2.40/24"       # mirror port
export DMZ_IDS_ETH2_IP="10.0.3.38/30"       # to SIEM

# === SIEM Zone ===
export SIEM_FW_ETH1_IP="10.0.3.1/30"        # from External_FW (not used in DMZ-only)
export SIEM_FW_ETH2_IP="10.0.3.6/30"        # from External_FW
export SIEM_FW_ETH3_IP="10.0.3.9/30"        # to Logstash
export SIEM_FW_ETH4_IP="10.0.3.13/30"       # to Elasticsearch
export SIEM_FW_ETH5_IP="10.0.3.17/30"       # to Kibana
export SIEM_FW_ETH6_IP="10.0.3.21/30"       # to siem_pc
export SIEM_FW_ETH7_IP="10.0.3.37/30"       # from DMZ_IDS
export SIEM_FW_ETH9_IP="10.0.3.33/30"       # from WAF

export SIEM_LOGSTASH_ETH1_IP="10.0.3.10/30"
export SIEM_LOGSTASH_ETH2_IP="10.0.3.25/30"  # to ES
export SIEM_ELASTIC_ETH1_IP="10.0.3.26/30"   # from Logstash
export SIEM_ELASTIC_ETH2_IP="10.0.3.29/30"   # from Kibana
export SIEM_ELASTIC_ETH3_IP="10.0.3.14/30"   # from SIEM_FW
export SIEM_KIBANA_ETH1_IP="10.0.3.30/30"
export SIEM_KIBANA_ETH2_IP="10.0.3.18/30"
export SIEM_PC_ETH1_IP="10.0.3.22/30"

# === Container Names ===
export CONTAINER_PREFIX="clab-${LAB_NAME}"

# === Missing Variables (DMZ-only compatibility) ===
# Internal zone (not used but referenced by scripts)
export SUBNET_INTERNAL="192.168.10.0/24"
export SUBNET_BETWEEN_FW="192.168.20.0/24"
export SUBNET_BACKEND="10.0.2.0/24"
export SUBNET_EDGE_1="172.168.2.0/30"
export SUBNET_EDGE_2="172.168.3.0/30"
export SUBNET_INTERNET="200.168.1.0/24"
export SUBNET_NAT="172.168.3.0/30"

# Internal FW (dummy - not present in DMZ lab)
export INT_FW_ETH2_IP="10.0.2.1/24"
export INT_FW_ETH3_IP="192.168.20.1/24"
export INT_FW_ETH4_IP="10.0.3.2/30"

# External FW additional
export EXT_FW_ETH4_IP="192.168.20.2/24"
export EXT_FW_NAT_IP="172.168.3.2"

# DMZ Web
export DMZ_WEB_CONTAINER="clab-${LAB_NAME}-Flask_Webserver"
export DMZ_WEB_ETH1_IP="10.0.2.10/24"
export DMZ_WEB_ETH2_IP="10.0.2.11/24"

# IDS
export IDS_DMZ_ETH2_IP="10.0.3.38/30"

# SIEM FW additional
export SIEM_FW_ETH8_IP="10.0.3.29/30"

# Container names
export EXTERNAL_FW_CONTAINER="clab-${LAB_NAME}-External_FW"
export SIEM_FW_CONTAINER="clab-${LAB_NAME}-SIEM_FW"
export ROUTER_EDGE_CONTAINER="clab-${LAB_NAME}-router-edge"
export ROUTER_INTERNET_CONTAINER="clab-${LAB_NAME}-router-internet"
export SUBNET_DMZ="10.0.2.0/24"
