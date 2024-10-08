#!/bin/bash

# -----------------------
# Network and Directory Setup
# -----------------------

echo "Creating Docker network..."
docker network create shard_pub1_nw || echo "Network already exists, skipping creation."

echo "Creating data directories..."
mkdir -p /opt/oracle/oradata/catalog
mkdir -p /opt/oracle/oradata/shard1
mkdir -p /opt/oracle/oradata/shard2

# -----------------------
# Deploying Containers
# -----------------------

echo "Deploying the shard catalog container..."
docker run --name oracle-shard-catalog --network shard_pub1_nw -v /opt/oracle/oradata/catalog:/opt/oracle/oradata \
  -e ORACLE_SID=CATCDB -d container-registry.oracle.com/database/free:latest

echo "Deploying the first shard container..."
docker run --name oracle-shard1 --network shard_pub1_nw -v /opt/oracle/oradata/shard1:/opt/oracle/oradata \
  -e ORACLE_SID=ORCL1 -d container-registry.oracle.com/database/free:latest

echo "Deploying the second shard container..."
docker run --name oracle-shard2 --network shard_pub1_nw -v /opt/oracle/oradata/shard2:/opt/oracle/oradata \
  -e ORACLE_SID=ORCL2 -d container-registry.oracle.com/database/free:latest

echo "Deploying the GSM container..."
docker run --name oracle-gsm1 --network shard_pub1_nw -d container-registry.oracle.com/database/gsm:latest

echo "Wating for containeres to be initialized"
sleep 0

# -----------------------
# Configuring TNSNAMES.ORA in the GSM Container
# -----------------------

# Define the path to tnsnames.ora in the GSM container
TNSNAMES_PATH="/u01/app/oracle/product/23ai/gsmhome_1/network/admin/tnsnames.ora"

# Define the CATCDB entry
TNS_ENTRY="
CATCDB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = oshard-catalog-0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVICE_NAME = CATCDB)
    )
  )
"

# Add the TNS entry for CATCDB in the GSM container
echo "Configuring tnsnames.ora in GSM container..."
docker exec -t oracle-gsm1 bash -c "echo '$TNS_ENTRY' >> $TNSNAMES_PATH"

# Reload the listener in the GSM container to apply the changes
echo "Reloading listener in GSM container..."
docker exec -t oracle-gsm1 bash -c "lsnrctl reload"

# -----------------------
# Set Up the Shard Catalog
# -----------------------

# Unlock the GSMCATUSER in the Shard Catalog and set the password
echo "Unlocking GSMCATUSER in the shard catalog and setting a password..."
docker exec -t oracle-shard-catalog bash -c "sqlplus / as sysdba <<EOF
ALTER USER GSMCATUSER IDENTIFIED BY new_password ACCOUNT UNLOCK;
exit;
EOF"

# -----------------------
# GDSCTL Commands for Catalog and GSM Setup
# -----------------------

# Create catalog in GDSCTL
echo "Creating catalog in GDSCTL..."
docker exec -t oracle-gsm1 bash -c "gdsctl <<EOF
create catalog -database CATCDB
username: gsmcatuser
password: new_password
EOF"

# Add GSM to the catalog
echo "Adding GSM to the catalog..."
docker exec -t oracle-gsm1 bash -c "gdsctl <<EOF
add gsm -gsm sharddirector1 -listener 1522 -pwd new_password -catalog oshard-catalog-0:1521/CAT1PDB -region region1
EOF"

echo "Setup completed!"

# Pause at the end of the script
echo "Press any key to exit..."
read -n 1 -s
