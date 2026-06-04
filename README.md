# yw_dmz_lab — DMZ 보안 실습 Lab

`yw_dmz_lab`는 Containerlab과 Docker를 기반으로 DMZ 보안 아키텍처를 자동 구성하는 보안 실습 프로젝트입니다.

외부 공격자가 WAF와 웹 서버를 공격하는 상황을 재현하고, 방화벽 차단, IDS 탐지, ELK 기반 SIEM 수집 및 시각화까지 하나의 Lab에서 실습할 수 있도록 구성했습니다.

이 프로젝트는 단순히 여러 컨테이너를 실행하는 예제가 아니라, 실제 기업 환경에서 자주 사용되는 DMZ, 방화벽, WAF, IDS, SIEM 구조를 작은 규모로 재현하는 것을 목표로 합니다.

---

## 목차

* [프로젝트를 시작한 이유](#프로젝트를-시작한-이유)
* [프로젝트 목표](#프로젝트-목표)
* [전체 아키텍처](#전체-아키텍처)
* [설계 방향](#설계-방향)
* [왜 Containerlab을 사용했는가](#왜-containerlab을-사용했는가)
* [주요 기능](#주요-기능)
* [프로젝트 구조](#프로젝트-구조)
* [사전 요구사항](#사전-요구사항)
* [빠른 시작](#빠른-시작)
* [접속 서비스](#접속-서비스)
* [사용 방법](#사용-방법)
* [네트워크 대역](#네트워크-대역)
* [컨테이너 구성](#컨테이너-구성)
* [보안 트래픽 흐름](#보안-트래픽-흐름)
* [공격 테스트](#공격-테스트)
* [로그 수집 구조](#로그-수집-구조)
* [검증 방법](#검증-방법)
* [트러블슈팅](#트러블슈팅)
* [포트폴리오 관점](#포트폴리오-관점)
* [향후 개선 계획](#향후-개선-계획)
* [Cleanup](#cleanup)
* [License](#license)
* [Author](#author)

---

## 프로젝트를 시작한 이유

네트워크와 보안 인프라를 운영하다 보면 단순히 장비 설정값을 아는 것만으로는 부족한 상황이 많습니다.

실제 장애나 보안 이벤트는 방화벽, WAF, 웹 서버, IDS, 로그 수집 시스템이 서로 연결된 상태에서 발생합니다.

예를 들어 외부에서 SQL Injection 공격이 들어왔을 때 다음과 같은 질문에 답할 수 있어야 합니다.

* 이 트래픽이 방화벽을 통과했는가?
* WAF에서 차단되었는가?
* 웹 서버까지 도달했는가?
* IDS에서 탐지되었는가?
* 최종적으로 SIEM에 로그가 남았는가?
* Kibana에서 해당 이벤트를 검색하고 분석할 수 있는가?

하지만 이런 전체 흐름을 개인 실습 환경에서 재현하기는 쉽지 않습니다.

방화벽, WAF, 웹 서버, 데이터베이스, IDS, SIEM을 각각 따로 구성하면 복잡하고, 매번 수동으로 환경을 만드는 데 시간이 많이 걸립니다.

그래서 이 프로젝트는 실제 기업의 DMZ 보안 구조를 작은 규모로 재현하고, 공격 발생부터 탐지, 차단, 로그 수집, 시각화까지의 흐름을 직접 확인할 수 있는 실습 Lab을 만드는 것을 목표로 시작했습니다.

---

## 프로젝트 목표

이 프로젝트의 목표는 단순히 컨테이너 여러 개를 실행하는 것이 아닙니다.

실제 보안 인프라에서 중요한 다음 흐름을 직접 구성하고 검증하는 것이 핵심입니다.

```text
외부 공격자
  -> 인터넷 라우터
  -> 엣지 라우터
  -> 외부 방화벽
  -> WAF
  -> 웹 서버
  -> 데이터베이스
```

그리고 이 과정에서 발생하는 보안 이벤트를 다음 구조로 수집합니다.

```text
방화벽 로그 / WAF 로그 / IDS 로그
  -> Logstash
  -> Elasticsearch
  -> Kibana
```

최종적으로는 다음 항목을 실습할 수 있는 환경을 만드는 것이 목표입니다.

* DMZ 기반 네트워크 분리
* 외부 방화벽 정책 및 NAT 구성
* WAF를 통한 웹 공격 탐지 및 차단
* Suricata IDS 기반 공격 탐지
* ELK Stack 기반 로그 수집 및 시각화
* SQL Injection, XSS, Directory Traversal 공격 테스트
* Containerlab 기반 보안 인프라 자동 배포

---

## 전체 아키텍처

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

## 설계 방향

처음부터 모든 기능을 복잡하게 넣기보다는, 실제 보안 이벤트 흐름을 이해할 수 있도록 구간을 단순화했습니다.

전체 네트워크는 크게 세 영역으로 나누었습니다.

| 구간            | 목적                                             |
| ------------- | ---------------------------------------------- |
| Internet Zone | 외부 공격자와 인터넷 라우팅 구간                             |
| DMZ Zone      | WAF, 웹 서버, 데이터베이스, IDS가 위치하는 서비스 구간            |
| SIEM Zone     | Logstash, Elasticsearch, Kibana가 위치하는 로그 분석 구간 |

이렇게 구간을 나눈 이유는 실제 기업 환경에서도 외부에 노출되는 서비스는 내부망과 분리된 DMZ에 배치하고, 보안 로그는 별도의 모니터링 구간에서 수집하는 구조가 일반적이기 때문입니다.

이 Lab에서는 내부망까지 포함한 대규모 구조보다는, DMZ 보안 흐름에 집중했습니다.

즉, 외부 공격자가 DMZ 서비스에 접근했을 때 방화벽, WAF, IDS, SIEM이 각각 어떤 역할을 수행하는지 확인하는 데 초점을 맞추었습니다.

---

## 왜 Containerlab을 사용했는가

이 프로젝트에서는 네트워크 토폴로지를 코드로 관리하기 위해 Containerlab을 사용했습니다.

일반적인 Docker Compose만으로도 여러 컨테이너를 실행할 수는 있지만, 네트워크 장비 간 링크, 라우터, 방화벽, IDS 구간을 명확히 표현하기에는 한계가 있습니다.

Containerlab을 사용하면 다음 장점이 있습니다.

* 네트워크 토폴로지를 YAML로 정의할 수 있음
* 라우터, 방화벽, 서버, 공격자 노드를 하나의 Lab으로 구성 가능
* 컨테이너 간 링크 구조를 명확하게 표현 가능
* 실습 환경을 삭제하고 다시 배포하기 쉬움
* 네트워크 보안 아키텍처를 포트폴리오 형태로 설명하기 좋음

이 프로젝트에서는 `topology/DMZ.yml` 파일을 중심으로 전체 보안 Lab의 네트워크 구조를 정의했습니다.

---

## 주요 기능

### 네트워크 보안

* DMZ 기반 네트워크 분리 구조
* 외부 방화벽 기반 접근 제어
* NAT 및 포트 포워딩 구성
* SIEM 전용 구간 분리
* Containerlab 기반 가상 네트워크 토폴로지 구성

### 웹 보안

* Reverse Proxy 기반 WAF 구조
* 취약한 Flask 웹 애플리케이션 구성
* Web Server와 Database 연동
* SQL Injection, XSS, Directory Traversal 공격 테스트

### IDS / SIEM

* Suricata 기반 DMZ 트래픽 탐지
* Logstash 기반 로그 수집 및 파싱
* Elasticsearch 기반 중앙 로그 저장
* Kibana 기반 보안 이벤트 검색 및 시각화

### 자동화

* `main.sh` 기반 원클릭 배포
* 구성요소별 Bash 스크립트 분리
* 배포, 삭제, 초기화 자동화
* 공격 테스트 스크립트 제공

---

## 프로젝트 구조

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

## 사전 요구사항

Ubuntu 또는 Debian 계열 Linux 환경을 권장합니다.

| 항목           |           권장 버전 | 설명                      |
| ------------ | --------------: | ----------------------- |
| Linux        | Ubuntu 22.04 이상 | Lab 실행 OS               |
| Docker       |         24.0 이상 | 컨테이너 런타임                |
| Containerlab |         0.48 이상 | 네트워크 Lab 오케스트레이션        |
| Bash         |           기본 포함 | 자동화 스크립트 실행             |
| sudo 권한      |              필요 | 네트워크 namespace 및 시스템 설정 |

---

## 빠른 시작

```bash
git clone https://github.com/RaonL/yw_dmz_lab.git
cd yw_dmz_lab
sudo bash main.sh
```

배포가 완료되면 Web App, Kibana, Elasticsearch에 접속할 수 있습니다.

---

## 접속 서비스

배포 완료 후 호스트 PC에서 다음 서비스에 접속할 수 있습니다.

| 서비스             | URL                   | 설명                |
| --------------- | --------------------- | ----------------- |
| Kibana          | http://localhost:5601 | SIEM 대시보드         |
| Elasticsearch   | http://localhost:9200 | 로그 검색 및 저장 API    |
| Web App via WAF | http://localhost:8080 | WAF를 경유한 웹 애플리케이션 |

---

## 사용 방법

### 전체 배포

```bash
sudo bash main.sh
```

### Lab 중지

```bash
sudo bash main.sh --destroy
```

### Lab 완전 삭제

```bash
sudo bash main.sh --purge
```

### Containerlab 토폴로지 확인

```bash
sudo containerlab inspect --topo topology/DMZ.yml
```

### 실행 중인 컨테이너 확인

```bash
docker ps
```

---

## 네트워크 대역

| 구간            | Subnet         | 설명                                 |
| ------------- | -------------- | ---------------------------------- |
| Internet      | 200.168.1.0/24 | 공격자 구간                             |
| Router Link 1 | 172.168.2.0/30 | Internet Router와 Edge Router 연결    |
| Router Link 2 | 172.168.3.0/30 | Edge Router와 External Firewall 연결  |
| DMZ           | 10.0.2.0/24    | WAF, Web Server, Database, IDS 구간  |
| SIEM          | 10.0.3.0/24    | Logstash, Elasticsearch, Kibana 구간 |

---

## 컨테이너 구성

이 Lab은 총 12개의 컨테이너로 구성됩니다.

| 구분      | 컨테이너              | 역할                     |
| ------- | ----------------- | ---------------------- |
| 공격자     | `Attacker`        | Kali 기반 외부 공격자 노드      |
| 인터넷 라우터 | `router-internet` | 가상 인터넷 라우터             |
| 엣지 라우터  | `router-edge`     | Edge 구간 라우터            |
| 외부 방화벽  | `External_FW`     | 방화벽, NAT, 접근 제어        |
| DMZ 스위치 | `DMZ_Switch`      | DMZ 내부 연결              |
| WAF     | `Proxy_WAF`       | Reverse Proxy 및 WAF 역할 |
| 웹 서버    | `Flask_Web`       | 취약한 Flask 웹 애플리케이션     |
| 데이터베이스  | `Database`        | 웹 애플리케이션 Backend DB    |
| IDS     | `DMZ_IDS`         | Suricata 기반 침입 탐지      |
| 로그 수집   | `Logstash`        | 로그 수집 및 파싱             |
| 로그 저장   | `Elasticsearch`   | 중앙 로그 저장소              |
| 시각화     | `Kibana`          | 보안 이벤트 시각화             |

---

## 보안 트래픽 흐름

### 정상 트래픽

```text
Attacker
  -> router-internet
  -> router-edge
  -> External_FW
  -> Proxy_WAF
  -> Flask_Web
  -> Database
```

정상 HTTP 요청은 외부 방화벽과 WAF를 거쳐 Flask 웹 애플리케이션으로 전달됩니다.

### 공격 트래픽

```text
Attacker
  -> External_FW
  -> Proxy_WAF
  -> Flask_Web
```

공격 트래픽은 다음 보안 계층에서 탐지 또는 차단될 수 있습니다.

| 보안 계층             | 역할                                                |
| ----------------- | ------------------------------------------------- |
| External Firewall | 허용되지 않은 접근 차단 및 정책 로그 생성                          |
| Proxy WAF         | SQL Injection, XSS, Directory Traversal 등 웹 공격 탐지 |
| DMZ IDS           | Suricata 룰 기반 네트워크 공격 탐지                          |
| Logstash          | 보안 로그 수집 및 파싱                                     |
| Elasticsearch     | 보안 이벤트 저장                                         |
| Kibana            | 보안 이벤트 검색 및 시각화                                   |

---

## 구현하면서 중점적으로 본 부분

이 Lab을 만들면서 가장 중요하게 본 부분은 공격이 실제로 어디에서 탐지되는지 확인하는 것이었습니다.

단순히 공격 스크립트를 실행하는 것보다 중요한 것은 다음 질문에 답할 수 있는 구조를 만드는 것이었습니다.

* 공격 트래픽이 방화벽을 통과했는가?
* WAF에서 차단되었는가?
* 웹 서버까지 도달했는가?
* IDS에서 탐지되었는가?
* Logstash가 로그를 정상적으로 수집했는가?
* Elasticsearch에 인덱스가 생성되었는가?
* Kibana에서 이벤트를 검색할 수 있는가?

이 질문에 답하기 위해 방화벽, WAF, IDS, SIEM을 각각 독립된 컴포넌트로 구성하고, 로그 흐름을 단계별로 확인할 수 있도록 설계했습니다.

---

## 공격 테스트

공격 테스트 스크립트는 `attacks/` 디렉터리에 있습니다.

### SQL Injection

```bash
bash attacks/attack_sql.sh
```

예상 결과:

* SQL Injection 요청이 Web Application으로 전달됨
* WAF에서 공격 패턴을 탐지하거나 차단할 수 있음
* Suricata에서 IDS Alert가 발생할 수 있음
* Logstash를 통해 Elasticsearch에 이벤트가 적재됨
* Kibana에서 관련 이벤트를 검색할 수 있음

Kibana 검색 예시:

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

대표적인 탐지 패턴:

```text
<script>
onerror=
alert(
javascript:
```

Kibana 검색 예시:

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

대표적인 탐지 패턴:

```text
../
../../etc/passwd
%2e%2e%2f
```

Kibana 검색 예시:

```text
etc/passwd
```

```text
../
```

---

## 로그 수집 구조

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

### 로그 소스

| 로그 소스       | 설명                            |
| ----------- | ----------------------------- |
| External_FW | 방화벽 및 NAT 로그                  |
| Proxy_WAF   | WAF Access Log 및 Security Log |
| DMZ_IDS     | Suricata IDS 이벤트              |
| Flask_Web   | 웹 애플리케이션 접근 로그                |
| Database    | 애플리케이션 DB 로그                  |

---

## 검증 방법

### 컨테이너 상태 확인

```bash
docker ps
```

정상적으로 다음 컨테이너들이 실행 중이어야 합니다.

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

### Web Application 확인

```bash
curl -I http://localhost:8080
```

정상 예시:

```text
HTTP/1.1 200 OK
```

### Elasticsearch 확인

```bash
curl http://localhost:9200
```

### Elasticsearch 인덱스 확인

```bash
curl http://localhost:9200/_cat/indices?v
```

### Kibana 접속

브라우저에서 다음 URL에 접속합니다.

```text
http://localhost:5601
```

### Suricata 로그 확인

```bash
docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json
```

### 방화벽 정책 확인

```bash
docker exec -it clab-yw_dmz_lab-External_FW iptables -L -n -v
docker exec -it clab-yw_dmz_lab-External_FW iptables -t nat -L -n -v
```

---

## 트러블슈팅

### Kibana 접속이 안 되는 경우

컨테이너 상태를 확인합니다.

```bash
docker ps | grep Kibana
docker logs clab-yw_dmz_lab-Kibana
```

Elasticsearch 상태를 확인합니다.

```bash
curl http://localhost:9200
```

가능성 높은 원인:

* Kibana가 아직 기동 중임
* Elasticsearch가 정상 기동되지 않음
* 5601 포트가 정상적으로 노출되지 않음
* 호스트 메모리가 부족함

---

### Elasticsearch 상태가 비정상인 경우

로그를 확인합니다.

```bash
docker logs clab-yw_dmz_lab-Elasticsearch
```

Cluster Health를 확인합니다.

```bash
curl http://localhost:9200/_cluster/health?pretty
```

`vm.max_map_count` 관련 오류가 발생하면 호스트에서 다음 명령어를 실행합니다.

```bash
sudo sysctl -w vm.max_map_count=262144
```

영구 적용하려면 다음 명령어를 실행합니다.

```bash
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

### 공격 로그가 Kibana에 보이지 않는 경우

아래 순서대로 확인합니다.

```bash
bash attacks/attack_sql.sh
docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json
docker logs clab-yw_dmz_lab-Logstash
curl http://localhost:9200/_cat/indices?v
```

가능성 높은 원인:

* 공격 트래픽이 IDS 경로를 지나가지 않음
* Suricata 룰이 정상 로드되지 않음
* Logstash 파이프라인 파싱 오류 발생
* Elasticsearch 인덱스가 생성되지 않음
* Kibana Data View가 설정되지 않음

---

### Web App 접속이 안 되는 경우

WAF와 Web Server 로그를 확인합니다.

```bash
curl -v http://localhost:8080
docker logs clab-yw_dmz_lab-Proxy_WAF
docker logs clab-yw_dmz_lab-Flask_Web
```

가능성 높은 원인:

* WAF가 Flask Web Server로 프록시하지 못함
* Flask 애플리케이션이 실행되지 않음
* 방화벽 NAT 또는 포워딩 정책이 잘못됨
* Docker 포트 바인딩이 누락됨

---

### Containerlab 배포가 실패하는 경우

토폴로지 파일과 Docker 상태를 확인합니다.

```bash
sudo containerlab inspect --topo topology/DMZ.yml
docker ps -a
docker network ls
```

기존 Lab 리소스가 남아 있다면 정리 후 다시 배포합니다.

```bash
sudo bash main.sh --destroy
sudo bash main.sh
```

그래도 문제가 지속되면 완전 삭제 후 재배포합니다.

```bash
sudo bash main.sh --purge
sudo bash main.sh
```

---

## 포트폴리오 관점

이 프로젝트는 단순한 보안 툴 설치 예제가 아니라, 네트워크와 보안 인프라가 실제로 어떻게 연결되는지 보여주기 위한 포트폴리오입니다.

특히 다음 역량을 보여주는 데 초점을 두었습니다.

| 역량                   | 설명                                               |
| -------------------- | ------------------------------------------------ |
| DMZ 설계               | 외부, DMZ, SIEM 구간을 분리한 보안 네트워크 구성                 |
| 방화벽 정책               | 접근 제어, NAT, 포트 포워딩 구성                            |
| WAF 이해               | Reverse Proxy 기반 웹 공격 방어 구조                      |
| IDS 이해               | Suricata 기반 네트워크 공격 탐지                           |
| SIEM 구성              | Logstash, Elasticsearch, Kibana 로그 파이프라인         |
| 자동화                  | Bash와 Containerlab 기반 원클릭 배포                     |
| Container Networking | Containerlab 기반 가상 네트워크 구성                       |
| 보안 테스트               | SQL Injection, XSS, Directory Traversal 공격 시뮬레이션 |
| 트러블슈팅                | 네트워크, 보안장비, 로그 파이프라인 문제 분석                       |

---

## 향후 개선 계획

현재는 DMZ 보안 흐름을 중심으로 구성했지만, 이후에는 다음 기능을 추가할 계획입니다.

* Kibana Dashboard 자동 생성
* Suricata Custom Rule 추가
* ModSecurity CRS 룰셋 튜닝
* Brute Force 공격 시나리오 추가
* Port Scan 탐지 시나리오 추가
* Command Injection 공격 시나리오 추가
* HTTP Flood 테스트 추가
* Filebeat 기반 로그 수집 구조 개선
* Ansible 또는 Terraform 기반 배포 자동화
* 테스트 결과 스크린샷과 분석 문서 추가
* `docs/` 디렉터리에 상세 설계 문서 추가
* GitHub Actions 기반 Shell Script 검증 추가

최종적으로는 공격 실행, 탐지, 차단, 로그 분석까지 한 번에 보여줄 수 있는 DMZ 보안 포트폴리오 Lab으로 발전시키는 것이 목표입니다.

---

## Cleanup

Lab 중지:

```bash
sudo bash main.sh --destroy
```

Lab 완전 삭제:

```bash
sudo bash main.sh --purge
```

Docker 리소스 확인:

```bash
docker ps -a
docker images
docker network ls
```

선택적으로 Docker 리소스를 정리할 수 있습니다.

```bash
docker system prune -f
```

> 주의: `--purge` 옵션은 관련 Docker 이미지를 삭제할 수 있습니다. 이 경우 재배포 시간이 길어질 수 있습니다.

---

## Author

Created by [RaonL](https://github.com/RaonL).

이 프로젝트는 DMZ 보안 아키텍처 실습, WAF/IDS/SIEM 테스트, 인프라 자동화 포트폴리오를 목적으로 제작되었습니다.
