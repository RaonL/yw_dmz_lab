# yw_dmz_lab — DMZ Security Lab

`yw_dmz_lab`는 Containerlab 기반으로 DMZ 보안 아키텍처를 자동 구성하고, 외부 공격자가 WAF/웹서버를 공격했을 때 방화벽 차단, IDS 탐지, ELK SIEM 수집/시각화까지 실습할 수 있는 보안 연구실입니다.

이 프로젝트는 단순히 컨테이너를 실행하는 것이 아니라, 실제 기업 DMZ 환경에서 자주 사용되는 보안 구성요소를 하나의 Lab으로 재현하는 것을 목표로 합니다.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Services](#services)
- [Usage](#usage)
- [Network Topology](#network-topology)
- [Components](#components)
- [Security Flow](#security-flow)
- [Attack Scenarios](#attack-scenarios)
- [Log Pipeline](#log-pipeline)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

`yw_dmz_lab` simulates a practical DMZ security environment.

The lab reproduces the following security flow:

```text
Attacker
  -> Internet Router
  -> Edge Router
  -> External Firewall
  -> Proxy WAF
  -> Flask Web Server
  -> Database
```

At the same time, security logs from firewall, WAF, and IDS components are collected into the ELK stack.

```text
Firewall / WAF / IDS Logs
  -> Logstash
  -> Elasticsearch
  -> Kibana
```

This lab is designed for:

- DMZ network security practice
- WAF, firewall, IDS, and SIEM integration testing
- Web attack simulation
- Suricata rule testing
- Logstash pipeline analysis
- Kibana-based security event visualization
- Containerlab-based infrastructure automation

---

## Architecture

```text
Attacker (Kali)
      |
      | 200.168.1.0/24
      v
Router Internet
      |
      | 172.168.2.0/30
      v
Router Edge
      |
      | 172.168.3.0/30
      v
External_FW
      |
      +-----------------------------+
      |                             |
      v                             v
DMZ Zone                       SIEM Zone
10.0.2.0/24                    10.0.3.0/24
      |                             |
      v                             v
DMZ_Switch                     SIEM_FW
      |                             |
      +-- Proxy_WAF                 +-- Logstash
      +-- Flask_Web                 +-- Elasticsearch
      +-- Database                  +-- Kibana
      +-- DMZ_IDS                   +-- siem_pc
```

---

## Features

### Network Security

- DMZ-based segmented network architecture
- External firewall with packet filtering and NAT
- Dedicated SIEM zone
- Isolated WAF, Web, Database, and IDS components
- Containerlab-based virtual network topology

### Web Security

- Reverse proxy based WAF structure
- Flask-based vulnerable web application
- Database-backed application flow
- SQL Injection, XSS, and Directory Traversal testing

### IDS / SIEM

- Suricata IDS for DMZ traffic inspection
- Logstash pipeline for log ingestion and parsing
- Elasticsearch for centralized log storage
- Kibana for security event visualization

### Automation

- One-command deployment
- Modular Bash scripts
- Component-based configuration structure
- Easy destroy and purge workflow

---

## Project Structure

```text
yw_dmz_lab/
├── main.sh
├── topology/
│   ├── DMZ.yml
│   └── topology-generator.sh
├── config/
│   ├── variables.sh
│   ├── webserver-details/
│   │   └── app.py
│   ├── logstash/
│   │   └── pipeline/
│   │       └── logstash.conf
│   ├── kibana/
│   │   └── kibana.yml
│   └── suricata/
│       └── rules/
├── scripts/
│   └── configure/
│       ├── dmz/
│       │   ├── webserver.sh
│       │   ├── waf.sh
│       │   └── db.sh
│       ├── firewalls/
│       ├── ids/
│       ├── network/
│       └── siem/
│           ├── logstash.sh
│           ├── kibana.sh
│           └── elasticsearch.sh
├── attacks/
│   ├── attack_sql.sh
│   ├── attack_xss.sh
│   └── attack_path_traversal.sh
└── LICENSE
```

---

## Prerequisites

The lab is recommended for Ubuntu or Debian-based Linux environments.

| Requirement | Recommended Version | Description |
|---|---:|---|
| Linux | Ubuntu 22.04+ | Host OS |
| Docker | 24.0+ | Container runtime |
| Containerlab | 0.48+ | Network lab orchestration |
| Bash | Default | Automation script execution |
| sudo | Required | Network namespace and system configuration |

---

## Quick Start

```bash
git clone https://github.com/RaonL/yw_dmz_lab.git
cd yw_dmz_lab
sudo bash main.sh
```

---

## Services

After deployment, the following services are available from the host.

| Service | URL | Description |
|---|---|---|
| Kibana | http://localhost:5601 | SIEM dashboard |
| Elasticsearch | http://localhost:9200 | Search and log storage API |
| Web App via WAF | http://localhost:8080 | Web application through WAF |

---

## Usage

### Full Deployment

```bash
sudo bash main.sh
```

### Destroy Lab

```bash
sudo bash main.sh --destroy
```

### Destroy Lab and Remove Related Images

```bash
sudo bash main.sh --purge
```

### Inspect Containerlab Topology

```bash
sudo containerlab inspect --topo topology/DMZ.yml
```

### Check Running Containers

```bash
docker ps
```

---

## Network Topology

| Segment | Subnet | Description |
|---|---|---|
| Internet | 200.168.1.0/24 | Attacker network |
| Router Link 1 | 172.168.2.0/30 | Internet Router to Edge Router |
| Router Link 2 | 172.168.3.0/30 | Edge Router to External Firewall |
| DMZ | 10.0.2.0/24 | WAF, Web Server, Database, IDS |
| SIEM | 10.0.3.0/24 | Logstash, Elasticsearch, Kibana |

---

## Components

The lab consists of 12 containers.

| Component | Container | Role |
|---|---|---|
| Attacker | `Attacker` | Kali-based attacker node |
| Internet Router | `router-internet` | Simulated internet router |
| Edge Router | `router-edge` | Edge routing node |
| External Firewall | `External_FW` | Firewall, NAT, and access control |
| DMZ Switch | `DMZ_Switch` | DMZ network switching |
| WAF | `Proxy_WAF` | Reverse proxy and WAF |
| Web Server | `Flask_Web` | Vulnerable Flask application |
| Database | `Database` | Backend database |
| IDS | `DMZ_IDS` | Suricata-based intrusion detection |
| Log Collector | `Logstash` | Log ingestion and parsing |
| Log Storage | `Elasticsearch` | Centralized log storage |
| Dashboard | `Kibana` | Security event visualization |

---

## Security Flow

### Normal Traffic

```text
Attacker
  -> router-internet
  -> router-edge
  -> External_FW
  -> Proxy_WAF
  -> Flask_Web
  -> Database
```

Normal HTTP traffic is forwarded through the firewall and WAF before reaching the Flask web application.

### Attack Traffic

```text
Attacker
  -> External_FW
  -> Proxy_WAF
  -> Flask_Web
```

Attack traffic can be detected or blocked by multiple security layers.

| Security Layer | Role |
|---|---|
| External Firewall | Blocks unauthorized access and logs policy hits |
| Proxy WAF | Detects and blocks web attacks |
| DMZ IDS | Detects suspicious network traffic |
| Logstash | Parses and forwards logs |
| Elasticsearch | Stores security events |
| Kibana | Visualizes and searches security events |

---

## Attack Scenarios

Preconfigured attack scripts are stored in the `attacks/` directory.

### SQL Injection

```bash
bash attacks/attack_sql.sh
```

Expected behavior:

- SQL Injection request is sent to the web application
- WAF may detect or block the payload
- Suricata may generate an alert
- Security logs are ingested into Elasticsearch
- Events can be searched from Kibana

Example search keywords in Kibana:

```text
SQL
```

```text
injection
```

---

### XSS

```bash
bash attacks/attack_xss.sh
```

Typical payload patterns:

```text
<script>
onerror=
alert(
javascript:
```

Example search keywords in Kibana:

```text
XSS
```

```text
script
```

---

### Directory Traversal

```bash
bash attacks/attack_path_traversal.sh
```

Typical payload patterns:

```text
../
../../etc/passwd
%2e%2e%2f
```

Example search keywords in Kibana:

```text
etc/passwd
```

```text
../
```

---

## Log Pipeline

```text
External_FW / Proxy_WAF / DMZ_IDS
        |
        v
     Logstash
        |
        v
  Elasticsearch
        |
        v
      Kibana
```

### Log Sources

| Source | Description |
|---|---|
| External_FW | Firewall and NAT logs |
| Proxy_WAF | WAF access and security logs |
| DMZ_IDS | Suricata IDS events |
| Flask_Web | Web access logs |
| Database | Application database logs |

---

## Verification

### Check Containers

```bash
docker ps
```

Expected containers:

```text
Attacker
router-internet
router-edge
External_FW
DMZ_Switch
Proxy_WAF
Flask_Web
Database
DMZ_IDS
Logstash
Elasticsearch
Kibana
```

### Check Web Application

```bash
curl -I http://localhost:8080
```

Expected result:

```text
HTTP/1.1 200 OK
```

### Check Elasticsearch

```bash
curl http://localhost:9200
```

### Check Elasticsearch Indices

```bash
curl http://localhost:9200/_cat/indices?v
```

### Check Kibana

Open the following URL in your browser:

```text
http://localhost:5601
```

### Check Suricata Logs

```bash
docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json
```

### Check Firewall Rules

```bash
docker exec -it clab-yw_dmz_lab-External_FW iptables -L -n -v
docker exec -it clab-yw_dmz_lab-External_FW iptables -t nat -L -n -v
```

---

## Troubleshooting

### Kibana Is Not Accessible

Check container status:

```bash
docker ps | grep Kibana
docker logs clab-yw_dmz_lab-Kibana
```

Check whether Elasticsearch is running:

```bash
curl http://localhost:9200
```

Common causes:

- Kibana is still starting
- Elasticsearch is not ready
- Port `5601` is not exposed correctly
- Host memory is insufficient

---

### Elasticsearch Is Not Healthy

Check logs:

```bash
docker logs clab-yw_dmz_lab-Elasticsearch
```

Check cluster health:

```bash
curl http://localhost:9200/_cluster/health?pretty
```

If Elasticsearch fails due to `vm.max_map_count`, apply the following setting on the host:

```bash
sudo sysctl -w vm.max_map_count=262144
```

To make it persistent:

```bash
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

### Attack Logs Do Not Appear in Kibana

Check the flow in order:

```bash
bash attacks/attack_sql.sh
docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json
docker logs clab-yw_dmz_lab-Logstash
curl http://localhost:9200/_cat/indices?v
```

Possible causes:

- Attack traffic is not passing through the IDS path
- Suricata rules are not loaded
- Logstash pipeline has a parsing error
- Elasticsearch index was not created
- Kibana Data View is not configured

---

### Web App Is Not Accessible

Check WAF and Web Server logs:

```bash
curl -v http://localhost:8080
docker logs clab-yw_dmz_lab-Proxy_WAF
docker logs clab-yw_dmz_lab-Flask_Web
```

Possible causes:

- WAF cannot reach the Flask web server
- Flask application is not running
- Firewall NAT or forwarding rule is incorrect
- Docker port binding is missing or incorrect

---

## Roadmap

Planned improvements:

- Add automatic Kibana dashboard import
- Add more Suricata custom rules
- Add ModSecurity CRS tuning examples
- Add Filebeat-based log collection
- Add more attack scenarios
  - Brute Force
  - Port Scan
  - Command Injection
  - HTTP Flood
- Add screenshots under `docs/screenshots/`
- Add architecture diagram under `docs/`
- Add GitHub Actions for basic shell script validation
- Add Ansible or Terraform-based deployment workflow

---

## Portfolio Value

This project demonstrates hands-on experience in:

- DMZ network design
- Firewall policy and NAT control
- WAF deployment and testing
- IDS rule-based detection
- SIEM log pipeline construction
- ELK-based security monitoring
- Containerlab-based network automation
- Security attack simulation and analysis

---

## Cleanup

Destroy the lab:

```bash
sudo bash main.sh --destroy
```

Completely remove the lab and related images:

```bash
sudo bash main.sh --purge
```

Check remaining Docker resources:

```bash
docker ps -a
docker images
docker network ls
```

Optional Docker cleanup:

```bash
docker system prune -f
```

> Warning: `--purge` may remove related Docker images. Re-deployment can take longer after purge.

---

## License

This project is licensed under the MIT License.

---

## Author

Created by [RaonL](https://github.com/RaonL).

This project is designed for DMZ security architecture practice, WAF/IDS/SIEM testing, and infrastructure automation portfolio.
