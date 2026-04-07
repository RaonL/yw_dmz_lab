#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log_info()    { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ ${BLUE}INFO${NC} ] $1"; }
log_ok()      { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [  ${GREEN}OK${NC}  ] $1"; }
log_warn()    { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [ ${YELLOW}WARN${NC} ] $1"; }
log_error()   { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [${RED}ERROR${NC} ] $1"; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "  $1"; echo -e "${BLUE}========================================${NC}\n"; }
