# yw_dmz_lab — DMZ Security Lab

`yw_dmz_lab`는 Containerlab 기반으로 DMZ 보안 아키텍처를 자동 구성하고,  
외부 공격자가 WAF/웹서버를 공격했을 때 방화벽 차단, IDS 탐지, ELK SIEM 수집/시각화까지 실습할 수 있는 보안 연구실입니다.

이 프로젝트는 단순히 컨테이너를 실행하는 것이 아니라, 실제 기업 DMZ 환경에서 자주 사용되는 보안 구성요소를 하나의 Lab으로 재현하는 것을 목표로 합니다.

---

## 1. 프로젝트 목적

이 Lab은 다음과 같은 흐름을 재현합니다.

```text
외부 공격자
   ↓
Internet Router
   ↓
Edge Router
   ↓
External Firewall
   ↓
Proxy WAF
   ↓
Flask Web Server
   ↓
Database

동시에 IDS / Firewall / WAF 로그는 Logstash → Elasticsearch → Kibana로 수집됩니다.

주요 목적은 다음과 같습니다.

DMZ 보안 아키텍처 실습
WAF, 방화벽, IDS, SIEM 연동 구조 이해
SQL Injection, XSS, Directory Traversal 공격 테스트
Suricata 탐지 룰 실습
Logstash 파이프라인 및 Elasticsearch 인덱스 분석
Kibana 기반 보안 이벤트 시각화
Containerlab을 활용한 네트워크 보안 자동화 실습
2. 전체 아키텍처
Attacker (Kali)
      │
      │ 200.168.1.0/24
      ▼
Router Internet
      │
      │ 172.168.2.0/30
      ▼
Router Edge
      │
      │ 172.168.3.0/30
      ▼
External_FW
      │
      ├────────────────────────────┐
      │                            │
      ▼                            ▼
DMZ Zone                      SIEM Zone
10.0.2.0/24                   10.0.3.0/24
      │                            │
      ▼                            ▼
DMZ_Switch                    SIEM_FW
      │                            │
      ├── Proxy_WAF                ├── Logstash
      ├── Flask_Web                ├── Elasticsearch
      ├── Database                 ├── Kibana
      └── DMZ_IDS                  └── siem_pc
3. 구성요소

현재 Lab은 총 12개 컨테이너로 구성됩니다.

구분	컨테이너	역할
Attacker	Attacker	외부 공격자 역할, Kali 기반 공격 테스트
Internet	router-internet	외부 인터넷 라우터
Edge	router-edge	Internet과 DMZ 경계 라우터
Firewall	External_FW	외부 방화벽, NAT, 접근제어, 로그 생성
DMZ	DMZ_Switch	DMZ 내부 L2/L3 연결
WAF	Proxy_WAF	Reverse Proxy 및 WAF 역할
Web	Flask_Web	취약한 Flask Web Application
DB	Database	Web Application Backend Database
IDS	DMZ_IDS	Suricata 기반 DMZ 트래픽 탐지
SIEM	Logstash	Firewall / IDS 로그 수집 및 파싱
SIEM	Elasticsearch	보안 로그 저장 및 검색
SIEM	Kibana	보안 이벤트 시각화
4. 보안 흐름
4.1 정상 트래픽 흐름
Attacker
  → router-internet
  → router-edge
  → External_FW
  → Proxy_WAF
  → Flask_Web
  → Database

정상적인 HTTP 요청은 WAF를 거쳐 Flask Web Application까지 전달됩니다.

4.2 공격 트래픽 흐름
Attacker
  → External_FW
  → Proxy_WAF
  → Flask_Web

공격 트래픽은 다음 보안 장비에서 탐지 또는 차단될 수 있습니다.

보안 장비	탐지/차단 역할
External_FW	허용되지 않은 포트, 비정상 접근 차단
Proxy_WAF	SQL Injection, XSS, Path Traversal 등 웹 공격 탐지/차단
DMZ_IDS	Suricata 룰 기반 네트워크 공격 탐지
Logstash	로그 수집 및 필드 파싱
Elasticsearch	로그 저장
Kibana	이벤트 검색 및 시각화
5. 프로젝트 구조
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
6. 사전 요구사항

테스트 환경은 Ubuntu 또는 Debian 계열 Linux를 권장합니다.

항목	권장 버전	설명
Linux	Ubuntu 22.04+	Lab 실행 OS
Docker	24.0+	컨테이너 런타임
Containerlab	0.48+	네트워크 토폴로지 오케스트레이션
Bash	기본 포함	자동화 스크립트 실행
sudo 권한	필요	네트워크 namespace, bridge, iptables 설정
7. 빠른 시작
git clone https://github.com/RaonL/yw_dmz_lab.git
cd yw_dmz_lab
sudo bash main.sh

배포가 완료되면 다음 서비스를 사용할 수 있습니다.

서비스	URL	설명
Kibana	http://localhost:5601	보안 로그 시각화
Elasticsearch	http://localhost:9200	로그 검색 API
Web App via WAF	http://localhost:8080	WAF를 거친 웹 애플리케이션
8. 주요 실행 명령어
전체 배포
sudo bash main.sh
Lab 중지
sudo bash main.sh --destroy
Lab 완전 삭제
sudo bash main.sh --purge
Containerlab 토폴로지 확인
sudo containerlab inspect --topo topology/DMZ.yml
실행 중인 컨테이너 확인
docker ps
9. 네트워크 대역
구간	Subnet	설명
Internet	200.168.1.0/24	Attacker 구간
Router Link 1	172.168.2.0/30	Internet Router ↔ Edge Router
Router Link 2	172.168.3.0/30	Edge Router ↔ External Firewall
DMZ	10.0.2.0/24	WAF, Web, DB, IDS
SIEM	10.0.3.0/24	Logstash, Elasticsearch, Kibana
10. 공격 테스트
10.1 SQL Injection
bash attacks/attack_sql.sh

예상 흐름:

Attacker → WAF → Flask Web Login Form

예상 결과:

WAF 로그에 SQL Injection 패턴 기록
Suricata 로그에 SQL Injection 탐지 이벤트 기록 가능
Logstash를 통해 Elasticsearch로 이벤트 적재
Kibana에서 관련 이벤트 조회 가능
10.2 XSS
bash attacks/attack_xss.sh

예상 탐지 키워드 예시:

<script>
onerror=
alert(
javascript:
10.3 Directory Traversal
bash attacks/attack_path_traversal.sh

예상 탐지 키워드 예시:

../
../../etc/passwd
%2e%2e%2f
11. 로그 수집 구조
Firewall / IDS / WAF
        ↓
Logstash
        ↓
Elasticsearch
        ↓
Kibana
로그 유형
로그 소스	설명
External_FW	iptables 정책 로그
Proxy_WAF	WAF 탐지/차단 로그
DMZ_IDS	Suricata IDS 이벤트
Flask_Web	Web Application 접근 로그
Database	DB 접근 및 애플리케이션 연동 로그
12. Kibana에서 확인할 내용

Kibana 접속:

http://localhost:5601

확인할 주요 항목:

SQL Injection 이벤트
XSS 이벤트
Directory Traversal 이벤트
Firewall Drop 로그
Suricata alert 로그
공격자 IP 기준 이벤트 필터링
목적지 IP / 목적지 포트 기준 이벤트 필터링
시간대별 공격 이벤트 추이

검색 예시:

event_type: alert
src_ip: 200.168.1.*
alert.signature: *SQL*
http.url: *etc/passwd*
13. 검증 방법
13.1 컨테이너 상태 확인
docker ps

정상적으로 다음 컨테이너들이 실행 중인지 확인합니다.

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
13.2 Web App 접근 확인
curl -I http://localhost:8080

예상 결과:

HTTP/1.1 200 OK

또는 WAF/Reverse Proxy 응답 헤더가 확인되어야 합니다.

13.3 Elasticsearch 확인
curl http://localhost:9200

예상 결과:

{
  "cluster_name": "...",
  "version": {
    "number": "..."
  }
}
13.4 Logstash 포트 확인
docker exec -it clab-yw_dmz_lab-Logstash ss -lntp

또는 호스트에서:

docker ps
docker logs clab-yw_dmz_lab-Logstash
13.5 Suricata 로그 확인
docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json
13.6 Firewall 룰 확인
docker exec -it clab-yw_dmz_lab-External_FW iptables -L -n -v
docker exec -it clab-yw_dmz_lab-External_FW iptables -t nat -L -n -v
14. 트러블슈팅
14.1 Kibana 접속이 안 되는 경우

확인 명령어:

docker ps | grep Kibana
docker logs clab-yw_dmz_lab-Kibana
curl http://localhost:5601

확인 포인트:

Kibana 컨테이너가 실행 중인지
Elasticsearch가 먼저 정상 기동되었는지
포트 5601이 호스트에 바인딩되었는지
메모리 부족으로 Elasticsearch가 죽지 않았는지
14.2 Elasticsearch가 비정상인 경우
docker logs clab-yw_dmz_lab-Elasticsearch
curl http://localhost:9200/_cluster/health?pretty

자주 발생하는 원인:

Docker 메모리 부족
vm.max_map_count 설정 부족
Elasticsearch 초기 기동 시간 부족

필요 시 호스트에서 다음 설정을 적용합니다.

sudo sysctl -w vm.max_map_count=262144

영구 적용:

echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
14.3 공격 로그가 Kibana에 안 보이는 경우

확인 순서:

# 1. 공격 스크립트 실행 여부 확인
bash attacks/attack_sql.sh

# 2. IDS 로그 확인
docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json

# 3. Logstash 로그 확인
docker logs clab-yw_dmz_lab-Logstash

# 4. Elasticsearch 인덱스 확인
curl http://localhost:9200/_cat/indices?v

가능성 높은 원인:

공격 트래픽이 IDS 인터페이스를 지나가지 않음
Suricata 룰이 로드되지 않음
Logstash 파이프라인 파싱 오류
Elasticsearch 인덱스 생성 실패
Kibana Data View가 생성되지 않음
14.4 Web App 접속이 안 되는 경우
curl -v http://localhost:8080
docker logs clab-yw_dmz_lab-Proxy_WAF
docker logs clab-yw_dmz_lab-Flask_Web

확인 포인트:

WAF 컨테이너가 Web Server로 프록시 가능한지
Flask Web Application이 정상 실행 중인지
External_FW NAT/포워딩 설정이 정상인지
Docker 포트 바인딩이 정상인지
15. 실습 시나리오
Scenario 1. 정상 사용자 접근

목표:

WAF를 경유한 웹 접속 확인
정상 HTTP 요청 로그 확인

명령어:

curl http://localhost:8080

확인:

Web App 응답
WAF Access Log
Kibana HTTP Access Event
Scenario 2. SQL Injection 공격 탐지

목표:

로그인 폼 대상 SQL Injection 공격 수행
WAF/IDS/SIEM 탐지 여부 확인

명령어:

bash attacks/attack_sql.sh

확인:

docker exec -it clab-yw_dmz_lab-DMZ_IDS tail -f /var/log/suricata/eve.json
curl http://localhost:9200/_cat/indices?v

Kibana 검색 예시:

SQL
injection
Scenario 3. XSS 공격 탐지

명령어:

bash attacks/attack_xss.sh

Kibana 검색 예시:

script
XSS
Scenario 4. Directory Traversal 공격 탐지

명령어:

bash attacks/attack_path_traversal.sh

Kibana 검색 예시:

etc/passwd
../
16. 이 프로젝트로 보여줄 수 있는 역량

이 프로젝트는 다음 역량을 보여주기 위해 설계되었습니다.

역량	설명
Network Security	DMZ, Firewall, Routing, NAT 구성 이해
WAF	Reverse Proxy 기반 웹 공격 방어 구조 이해
IDS	Suricata 룰 기반 탐지 구조 이해
SIEM	Logstash, Elasticsearch, Kibana 기반 로그 분석
Automation	Bash 기반 One-command Deployment
Container Networking	Containerlab 기반 가상 네트워크 토폴로지 설계
Security Testing	SQLi, XSS, Path Traversal 공격 시뮬레이션
Troubleshooting	네트워크, 로그 파이프라인, 보안장비 연동 문제 분석
17. 향후 개선 계획
Kibana Dashboard 자동 생성
Suricata Custom Rule 추가
ModSecurity CRS 룰셋 튜닝
Filebeat 기반 로그 수집 구조 개선
공격 시나리오 추가
Brute Force
Port Scan
Command Injection
HTTP Flood
Grafana 또는 OpenSearch Dashboard 연동
Terraform/Ansible 기반 배포 자동화 확장
GitHub Actions 기반 문법 검사 및 테스트 자동화
README 내 아키텍처 이미지 추가
18. 삭제 / 초기화

Lab 중지:

sudo bash main.sh --destroy

Lab 완전 삭제:

sudo bash main.sh --purge

Docker 리소스 확인:

docker ps -a
docker images
docker network ls

불필요한 리소스 정리:

docker system prune -f

주의:

--purge 옵션은 관련 Docker 이미지까지 삭제할 수 있으므로 재배포 시간이 길어질 수 있습니다.
19. License

This project is licensed under the MIT License.
