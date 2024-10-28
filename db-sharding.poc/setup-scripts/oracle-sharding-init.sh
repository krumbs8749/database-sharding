#!/bin/bash

# Variables (customize as needed)
NETWORK_NAME="shard_pub1_nw"
NETWORK_SUBNET="10.0.20.0/24"
NETWORK_GATEWAY="10.0.20.1"
VOLUME_BASE="./scratch/oracle/oradata"
CATALOG_VOLUME="$VOLUME_BASE/CATALOG"
SHARD1_VOLUME="$VOLUME_BASE/ORCL1CDB"
SHARD2_VOLUME="$VOLUME_BASE/ORCL2CDB"
GSM1_VOLUME="$VOLUME_BASE/GSMDATA"
GSM2_VOLUME="$VOLUME_BASE/GSM2DATA"
SECRETS_DIR="/opt/.secrets"
HOST_FILE="/opt/containers/shard_host_file"
CATALOG_CONTAINER="oracle-catalog"
SHARD1_CONTAINER="oracle-shard1"
SHARD2_CONTAINER="oracle-shard2"
GSM1_CONTAINER="oracle-gsm1"
GSM2_CONTAINER="oracle-gsm2"
CATALOG_IP="10.0.20.102"
SHARD1_IP="10.0.20.103"
SHARD2_IP="10.0.20.104"
GSM1_IP="10.0.20.100"
GSM2_IP="10.0.20.101"
DOMAIN="example.com"
PASSWORD_FILE="$SECRETS_DIR/pwdfile.enc"
KEY_FILE="$SECRETS_DIR/key.pem"

# 1. Create Docker network
echo "Creating Docker network $NETWORK_NAME ..."
docker network create --driver=bridge --subnet=$NETWORK_SUBNET --gateway=$NETWORK_GATEWAY $NETWORK_NAME

# 2. Create directories for Catalog and Shards
echo "Creating directories for Catalog and Shards ..."
mkdir -p $CATALOG_VOLUME $SHARD1_VOLUME $SHARD2_VOLUME $GSM1_VOLUME $GSM2_VOLUME

# 3. Set permissions using temporary containers
echo "Setting permissions for Catalog volume..."
docker run --rm -v $CATALOG_VOLUME:/opt/oracle/oradata --user root oracle/database:21.3.0-ee \
  bash -c "chown -R 54321:54321 /opt/oracle/oradata && chmod -R 775 /opt/oracle/oradata"

echo "Setting permissions for Shard1 volume..."
docker run --rm -v $SHARD1_VOLUME:/opt/oracle/oradata --user root oracle/database:21.3.0-ee \
  bash -c "chown -R 54321:54321 /opt/oracle/oradata && chmod -R 775 /opt/oracle/oradata"

echo "Setting permissions for Shard2 volume..."
docker run --rm -v $SHARD2_VOLUME:/opt/oracle/oradata --user root oracle/database:21.3.0-ee \
  bash -c "chown -R 54321:54321 /opt/oracle/oradata && chmod -R 775 /opt/oracle/oradata"

echo "Setting permissions for GSM1 volume..."
docker run --rm -v $GSM1_VOLUME:/opt/oracle/gsmdata --user root oracle/database:21.3.0-ee \
  bash -c "chown -R 54321:54321 /opt/oracle/gsmdata && chmod -R 775 /opt/oracle/gsmdata"

echo "Setting permissions for GSM2 volume..."
docker run --rm -v $GSM2_VOLUME:/opt/oracle/gsmdata --user root oracle/database:21.3.0-ee \
  bash -c "chown -R 54321:54321 /opt/oracle/gsmdata && chmod -R 775 /opt/oracle/gsmdata"



echo "Press any key to exit..."
read -n 1 -s
<<comment

# 3. Deploy Catalog Container
echo "Deploying Catalog Container ..."
docker run -d --hostname oshard-catalog-0 \
  --dns-search=$DOMAIN \
  --network=$NETWORK_NAME \
  --ip=$CATALOG_IP \
  -e DOMAIN=$DOMAIN \
  -e ORACLE_SID=CATCDB \
  -e ORACLE_PDB=CAT1PDB \
  -e OP_TYPE=catalog \
  -e COMMON_OS_PWD_FILE=$PASSWORD_FILE \
  -e PWD_KEY=$KEY_FILE \
  -e ORACLE_PWD=oracle \
  -e SHARD_SETUP="true" \
  -e ENABLE_ARCHIVELOG=true \
  -v /scratch/oradata/dbfiles/CATALOG:/opt/oracle/oradata \
  -v $HOST_FILE:/etc/hosts \
  --volume $SECRETS_DIR:/run/secrets:ro \
  --privileged=false \
  --name $CATALOG_CONTAINER oracle/database-sharding:21.3.0-ee

# Wait for the catalog to be healthy
echo "Waiting for Catalog to be ready ..."
while ! docker exec $CATALOG_CONTAINER sh -c "echo 'SELECT 1;' | sqlplus / as sysdba" > /dev/null 2>&1; do
  sleep 10
done

# 4. Deploy Shard1 Container
echo "Deploying Shard1 Container ..."
docker run -d --hostname oshard1-0 \
  --dns-search=$DOMAIN \
  --network=$NETWORK_NAME \
  --ip=$SHARD1_IP \
  -e DOMAIN=$DOMAIN \
  -e ORACLE_SID=ORCL1CDB \
  -e ORACLE_PDB=ORCL1PDB \
  -e OP_TYPE=primaryshard \
  -e COMMON_OS_PWD_FILE=$PASSWORD_FILE \
  -e PWD_KEY=$KEY_FILE \
  -e ORACLE_PWD=oracle \
  -e SHARD_SETUP="true" \
  -e ENABLE_ARCHIVELOG=true \
  -v /scratch/oradata/dbfiles/ORCL1CDB:/opt/oracle/oradata \
  -v $HOST_FILE:/etc/hosts \
  --volume $SECRETS_DIR:/run/secrets:ro \
  --privileged=false \
  --name $SHARD1_CONTAINER oracle/database-sharding:21.3.0-ee

# 5. Deploy Shard2 Container
echo "Deploying Shard2 Container ..."
docker run -d --hostname oshard2-0 \
  --dns-search=$DOMAIN \
  --network=$NETWORK_NAME \
  --ip=$SHARD2_IP \
  -e DOMAIN=$DOMAIN \
  -e ORACLE_SID=ORCL2CDB \
  -e ORACLE_PDB=ORCL2PDB \
  -e OP_TYPE=primaryshard \
  -e COMMON_OS_PWD_FILE=$PASSWORD_FILE \
  -e PWD_KEY=$KEY_FILE \
  -e ORACLE_PWD=oracle \
  -e SHARD_SETUP="true" \
  -e ENABLE_ARCHIVELOG=true \
  -v /scratch/oradata/dbfiles/ORCL2CDB:/opt/oracle/oradata \
  -v $HOST_FILE:/etc/hosts \
  --volume $SECRETS_DIR:/run/secrets:ro \
  --privileged=false \
  --name $SHARD2_CONTAINER oracle/database-sharding:21.3.0-ee

# 6. Deploy Master GSM Container
echo "Deploying Master GSM Container ..."
docker run -d --hostname oshard-gsm1 \
  --dns-search=$DOMAIN \
  --network=$NETWORK_NAME \
  --ip=$GSM1_IP \
  -p 1522:1522 \
  -e DOMAIN=$DOMAIN \
  -e SHARD_DIRECTOR_PARAMS="director_name=sharddirector1;director_region=region1;director_port=1522" \
  -e SHARD1_GROUP_PARAMS="group_name=shardgroup1;deploy_as=primary;group_region=region1" \
  -e CATALOG_PARAMS="catalog_host=oshard-catalog-0;catalog_db=CATCDB;catalog_pdb=CAT1PDB;catalog_port=1521;catalog_name=shardcatalog1;catalog_region=region1,region2" \
  -e SHARD1_PARAMS="shard_host=oshard1-0;shard_db=ORCL1CDB;shard_pdb=ORCL1PDB;shard_port=1521;shard_group=shardgroup1" \
  -e SHARD2_PARAMS="shard_host=oshard2-0;shard_db=ORCL2CDB;shard_pdb=ORCL2PDB;shard_port=1521;shard_group=shardgroup1" \
  -e SERVICE1_PARAMS="service_name=oltp_rw_svc;service_role=primary" \
  -e SERVICE2_PARAMS="service_name=oltp_ro_svc;service_role=primary" \
  -e COMMON_OS_PWD_FILE=$PASSWORD_FILE \
  -e PWD_KEY=$KEY_FILE \
  -e ORACLE_PWD=oracle \
  -e SHARD_SETUP="True" \
  -e OP_TYPE=gsm \
  -e MASTER_GSM="TRUE" \
  -v $GSM1_VOLUME:/opt/oracle/gsmdata \
  -v $HOST_FILE:/etc/hosts \
  --volume $SECRETS_DIR:/run/secrets:ro \
  --name $GSM1_CONTAINER oracle/gsm:21.3.0

# 7. Deploy Standby GSM Container
echo "Deploying Standby GSM Container ..."
docker run -d --hostname oshard-gsm2 \
  --dns-search=$DOMAIN \
  --network=$NETWORK_NAME \
  --ip=$GSM2_IP \
  -p 1523:1522 \
  -e DOMAIN=$DOMAIN \
  -e SHARD_DIRECTOR_PARAMS="director_name=sharddirector2;director_region=region2;director_port=1522" \
  -e SHARD1_GROUP_PARAMS="group_name=shardgroup1;deploy_as=active_standby;group_region=region2" \
  -e CATALOG_PARAMS="catalog_host=oshard-catalog-0;catalog_db=CATCDB;catalog_pdb=CAT1PDB;catalog_port=1521;catalog_name=shardcatalog1;catalog_region=region1,region2" \
  -e SHARD1_PARAMS="shard_host=oshard1-0;shard_db=ORCL1CDB;shard_pdb=ORCL1PDB;shard_port=1521;shard_group=shardgroup1" \
  -e SHARD2_PARAMS="shard_host=oshard2-0;shard_db=ORCL2CDB;shard_pdb=ORCL2PDB;shard_port=1521;shard_group=shardgroup1" \
  -e SERVICE1_PARAMS="service_name=oltp_rw_svc;service_role=standby" \
  -e SERVICE2_PARAMS="service_name=oltp_ro_svc;service_role=standby" \
  -e COMMON_OS_PWD_FILE=$PASSWORD_FILE \
  -e PWD_KEY=$KEY_FILE \
  -e SHARD_SETUP="True" \
  -e OP_TYPE=gsm \
  -v /c/Program\ Files/Git/scratch/oradata/dbfiles/GSMDATA:/opt/oracle/gsmdata \
  -v $HOST_FILE:/etc/hosts \
  --volume $SECRETS_DIR:/run/secrets:ro \
  --privileged \
  --name $GSM2_CONTAINER oracle/gsm:21.3.0

# Final Message
echo "Oracle Sharding setup completed."

# Pause at the end of the script
echo "Press any key to exit..."
read -n 1 -s
