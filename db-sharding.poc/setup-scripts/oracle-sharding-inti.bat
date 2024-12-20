@echo off
rem ==================================================
rem Setup Script for Oracle Sharding using Docker in CMD
rem ==================================================

rem Set Variables (customize as needed)
set NETWORK_NAME=shard_pub1_nw
set NETWORK_SUBNET=10.0.20.0/24
set NETWORK_GATEWAY=10.0.20.1
set VOLUME_BASE="C:\Users\darw\IdeaProjects\db-sharding-poc\db-sharding.poc\setup-scripts\scratch\oracle\oradata"
set CATALOG_VOLUME=%VOLUME_BASE%/CATALOG
set SHARD1_VOLUME=%VOLUME_BASE%/ORCL1CDB
set SHARD2_VOLUME=%VOLUME_BASE%/ORCL2CDB
set GSM1_VOLUME=%VOLUME_BASE%/GSMDATA
set GSM2_VOLUME=%VOLUME_BASE%/GSM2DATA
set SECRETS_DIR="C:/Program Files/Git/opt/.secrets"
set HOST_FILE="C:/Program Files/Git/opt/containers/shard_host_file"
set CATALOG_CONTAINER=oracle-catalog
set SHARD1_CONTAINER=oracle-shard1
set SHARD2_CONTAINER=oracle-shard2
set GSM1_CONTAINER=oracle-gsm1
set GSM2_CONTAINER=oracle-gsm2
set CATALOG_IP=10.0.20.102
set SHARD1_IP=10.0.20.103
set SHARD2_IP=10.0.20.104
set GSM1_IP=10.0.20.100
set GSM2_IP=10.0.20.101
set DOMAIN=example.com
set PASSWORD_FILE=%SECRETS_DIR%/pwdfile.enc
set KEY_FILE=%SECRETS_DIR%/key.pem


rem Create Docker network
echo Creating Docker network %NETWORK_NAME% ...
docker network create --driver=bridge --subnet=%NETWORK_SUBNET% --gateway=%NETWORK_GATEWAY% %NETWORK_NAME%

rem Create directories for Catalog and Shards
echo Creating directories for Catalog and Shards ...
mkdir "%CATALOG_VOLUME%"
mkdir "%SHARD1_VOLUME%"
mkdir "%SHARD2_VOLUME%"
mkdir "%GSM1_VOLUME%"
mkdir "%GSM2_VOLUME%"

rem Deploy Catalog Container
echo Deploying Catalog Container ...
docker run -d --hostname oshard-catalog-0 ^
  --dns-search=%DOMAIN% ^
  --network=%NETWORK_NAME% ^
  --ip=%CATALOG_IP% ^
  -p 1521:1521 ^
  -e DOMAIN=%DOMAIN% ^
  -e ORACLE_SID=CATCDB ^
  -e ORACLE_PDB=CAT1PDB ^
  -e OP_TYPE=catalog ^
  -e COMMON_OS_PWD_FILE=%PASSWORD_FILE% ^
  -e PWD_KEY=%KEY_FILE% ^
  -e ORACLE_PWD=oracle ^
  -e SHARD_SETUP=true ^
  -e ENABLE_ARCHIVELOG=true ^
  -v %CATALOG_VOLUME%:/opt/oracle/oradata ^
  -v %HOST_FILE%:/etc/hosts ^
  --volume %SECRETS_DIR%:/run/secrets:ro ^
  --privileged=false ^
  --name %CATALOG_CONTAINER% oracle/database-sharding:21.3.0-ee-modified


rem Deploy Shard1 Container
echo Deploying Shard1 Container ...
docker run -d --hostname oshard1-0 ^
  --dns-search=%DOMAIN% ^
  --network=%NETWORK_NAME% ^
  --ip=%SHARD1_IP% ^
  -e DOMAIN=%DOMAIN% ^
  -e ORACLE_SID=ORCL1CDB ^
  -e ORACLE_PDB=ORCL1PDB ^
  -e OP_TYPE=primaryshard ^
  -e COMMON_OS_PWD_FILE=%PASSWORD_FILE% ^
  -e PWD_KEY=%KEY_FILE% ^
  -e ORACLE_PWD=oracle ^
  -e SHARD_SETUP=true ^
  -e ENABLE_ARCHIVELOG=true ^
  -v %SHARD1_VOLUME%:/opt/oracle/oradata ^
  -v %HOST_FILE%:/etc/hosts ^
  --volume %SECRETS_DIR%:/run/secrets:ro ^
  --privileged=false ^
  --name %SHARD1_CONTAINER% oracle/database-sharding:21.3.0-ee-modified


rem Deploy Shard2 Container
echo Deploying Shard2 Container ...
docker run -d --hostname oshard2-0 ^
  --dns-search=%DOMAIN% ^
  --network=%NETWORK_NAME% ^
  --ip=%SHARD2_IP% ^
  -e DOMAIN=%DOMAIN% ^
  -e ORACLE_SID=ORCL2CDB ^
  -e ORACLE_PDB=ORCL2PDB ^
  -e OP_TYPE=primaryshard ^
  -e COMMON_OS_PWD_FILE=%PASSWORD_FILE% ^
  -e PWD_KEY=%KEY_FILE% ^
  -e ORACLE_PWD=oracle ^
  -e SHARD_SETUP=true ^
  -e ENABLE_ARCHIVELOG=true ^
  -v %SHARD2_VOLUME%:/opt/oracle/oradata ^
  -v %HOST_FILE%:/etc/hosts ^
  --volume %SECRETS_DIR%:/run/secrets:ro ^
  --privileged=false ^
  --name %SHARD2_CONTAINER% oracle/database-sharding:21.3.0-ee-modified

rem ocker logs -f oracle-shard2

rem Wait for the catalog container to complete the GSM catalog setup
echo Waiting for the catalog setup to complete...
:WaitForCatalogSetup
docker logs %CATALOG_CONTAINER% | findstr /i "GSM Catalog Setup Is Completed" >nul 2>&1
if errorlevel 1 (
  timeout /t 10 >nul
  goto :WaitForCatalogSetup
)
echo GSM Catalog setup completed.
pause

rem Deploy Master GSM Container
echo Deploying Master GSM Container ...
docker run --hostname oshard-gsm1 ^
  --dns-search=%DOMAIN% ^
  --network=%NETWORK_NAME% ^
  --ip=%GSM1_IP% ^
  -p 1522:1522 ^
  -e DOMAIN=%DOMAIN% ^
  -e SHARD_DIRECTOR_PARAMS="director_name=sharddirector1;director_region=region1;director_port=1522" ^
  -e SHARD1_GROUP_PARAMS="group_name=shardgroup1;deploy_as=primary;group_region=region1" ^
  -e CATALOG_PARAMS="catalog_host=oshard-catalog-0;catalog_db=CATCDB;catalog_pdb=CAT1PDB;catalog_port=1521;catalog_name=shardcatalog1;catalog_region=region1" ^
  -e SHARD1_PARAMS="shard_host=oshard1-0;shard_db=ORCL1CDB;shard_pdb=ORCL1PDB;shard_port=1521;shard_group=shardgroup1" ^
  -e SHARD2_PARAMS="shard_host=oshard2-0;shard_db=ORCL2CDB;shard_pdb=ORCL2PDB;shard_port=1521;shard_group=shardgroup1" ^
  -e SERVICE1_PARAMS="service_name=oltp_rw_svc;service_role=primary" ^
  -e SERVICE2_PARAMS="service_name=oltp_ro_svc;service_role=primary" ^
  -e COMMON_OS_PWD_FILE=%PASSWORD_FILE% ^
  -e PWD_KEY=%KEY_FILE% ^
  -e ORACLE_PWD=oracle ^
  -e SHARD_SETUP=true ^
  -e OP_TYPE=gsm ^
  -e MASTER_GSM=true ^
  -v %GSM1_VOLUME%:/opt/oracle/gsmdata ^
  -v %HOST_FILE%:/etc/hosts ^
  --volume %SECRETS_DIR%:/run/secrets:ro ^
  --name %GSM1_CONTAINER% oracle/gsm:21.3.0


docker logs oracle-gsm1

rem Final Message
echo Oracle Sharding setup completed.
pause