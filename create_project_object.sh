#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' 

echo "================================================================="
echo -e "${BLUE} Data Engineering Project Setup${NC}"
echo "================================================================="

echo -e "${YELLOW} Creating All Required Folder"
mkdir -p config logs \
src/{database,logging,extract,transform,load,quality,utils} \
data/{raw,processed,archive} \
tests
echo -e "${GREEN} =================================================="
echo -e "${GREEN} All required folder clreated successfully"
echo -e "${GREEN} =================================================="

# Create folder structure
touch config/{config.yaml,database.yaml}
touch logs/{app.log,etl.log,error.log}
touch src/database/{connection.py,engine.py,session.py,models.py}
touch src/logging/{logger.py,custom_formatter.py}
touch src/extract/{csv_reader.py,json_reader.py,sql_reader.py}
touch src/transform/{cleaning.py,validation.py,business_rules.py}
touch src/load/{sql_loader.py,bulk_loader.py}
touch src/quality/{null_checks.py,duplicate_checks.py,schema_checks.py}
touch src/utils/{helpers.py,file_utils.py,date_utils.py}
touch src/main.py
touch tests/{test_connection.py,test_etl.py,test_validation.py}
touch requirements.txt .env 

echo -e "${GREEN} =================================================="
echo -e "${GREEN} All required file clreated successfully"
echo -e "${GREEN} =================================================="