# yw_dmz_lab — DMZ Security Lab

외부 공격자가 WAF/웹서버를 공격 → 방화벽 차단 + IDS 탐지 → ELK SIEM으로 수집/시각화하는 보안 연구실입니다.


## 프로젝트 구조

```text
yw_dmz_lab/
├── main.sh                      # 전체 배포 진입점
├── topology/
│   ├── DMZ.yml                  # ContainerLab 토폴로지 정의
│   └── topology-generator.sh    # 토폴로지 생성 스크립트
├── config/
│   ├── variables.sh             # 전역 환경변수 (IP 등)
│   ├── webserver-details/app.py # Flask 웹앱
│   ├── logstash/pipeline/logstash.conf
│   ├── kibana/kibana.yml
│   └── suricata/rules/
└── scripts/configure/
    ├── dmz/                     (webserver.sh, waf.sh, db.sh ...)
    ├── firewalls/
    ├── ids/
    ├── network/
    └── siem/                    (logstash.sh, kibana.sh, elasticsearch.sh ...)

## 구성 (12개 컨테이너)

```
Attacker (Kali) → Router Internet → Router Edge → External_FW
                                                      │
                                              ┌───────┴───────┐
                                              │               │
                                         DMZ Zone        SIEM Zone
                                        10.0.2.0/24     10.0.3.0/24
                                              │               │
                                         DMZ_Switch      SIEM_FW
                                         Proxy_WAF       Logstash
                                         Flask_Web       Elasticsearch
                                         Database        Kibana
                                         DMZ_IDS         siem_pc
```

## 빠른 시작

```bash
git clone https://github.com/RaonL/yw_dmz_lab.git
cd yw_dmz_lab
sudo bash main.sh
```

## 서비스

| 서비스 | URL |
|--------|-----|
| Kibana | http://localhost:5601 |
| Elasticsearch | http://localhost:9200 |
| Web App (WAF) | http://localhost:8080 |

## 공격 테스트

```bash
bash attacks/attack_sql.sh           # SQL Injection
bash attacks/attack_xss.sh           # XSS
bash attacks/attack_path_traversal.sh # Directory Traversal
```

## 관리

```bash
sudo bash main.sh --destroy  # 중지
sudo bash main.sh --purge    # 완전 삭제
```

## License

MIT License
