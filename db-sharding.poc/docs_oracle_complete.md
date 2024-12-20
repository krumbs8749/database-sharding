### Oracle Sharding Deployment Guide with Custom Images, User Permissions, and Validation

---

This guide details a step-by-step approach for setting up an Oracle Sharding environment, including custom image creation, listener validation, and specific permissions for the `allshardsuser` (all-shards user). For schema design examples, refer to Oracle’s [official schema creation documentation](https://docs.oracle.com/en/database/oracle/oracle-database/21/shard/schema-creation-examples.html).

---

### 1. Building Oracle Database and GSM Images

#### Step 1.1: Build the Oracle Database Image
- **Action**: Build a containerized Oracle Database 21c image with sharding extension.
- **Link**: https://github.com/oracle/db-sharding/blob/master/container-based-sharding-deployment/README.md
- 
- **Commands**:
  ```bash
  ./buildContainerImage.sh -v 21.3.0 -i -e
  ././buildExtensions.sh -x sharding -b oracle/database:23.5.0-ee  -t oracle/database-ext-sharding:23.5.0-ee
  ```
  - Remove problematic code for validation (DBMS_GSM_FIX.validateShard). This line is in `setup` function in orapshard.py that should have been downloaded (z.B. through git) and it 
  should be refactored to this:
  ```python
    def setup_pdb_shard(self):
         """
          This function setup the shard.
         """
         ...
            grant sysdg to GSMUSER;
            grant sysbackup to GSMUSER;
            -- Removed DBMS_GSM_FIX.validateShard for now
            -- execute DBMS_GSM_FIX.validateShard;
            alter system register;
            '''.format(self.ora_env_dict["ORACLE_PDB"])
         ...
  ```
- Then run `docker build -t oracle/database:21.3.0-ee-modified .` with this:
  ```dockerfile
  FROM oracle/database-sharding:21.3.0-ee

  # Modify or copy the file you want to change
  COPY orapshard.py /opt/oracle/scripts/sharding/orapshard.py
  ```
- **Extensions**:
    - The image should include necessary sharding extensions, including `DBMS_GSM_FIX`.
    - Ensure sharding-specific SQL scripts are added to initialize the database with sharding configurations.

#### Step 1.2: Build Oracle GSM Image
- **Action**: Build the Global Service Manager (GSM) image compatible with Oracle Database 21c.
- **Commands**:
  ```bash
  docker build -t oracle/gsm:21c .
  ```
- **Note**: The GSM container must handle routing and connect to the catalog and shard databases using compatible configurations.

---

### 2. Running the Containers

#### Step 2.1: Launch Containers in Sequence
1. **Catalog Container**: Start the catalog container first to ensure metadata coordination.
   ```bash
   docker run -d --name catalog_container -e ORACLE_SID=CATDB -p 1521:1521 oracle/database:21c
   ```
2. **Shard Containers**: Start Shard1 and Shard2 after catalog.
   ```bash
   docker run -d --name shard1_container -e ORACLE_SID=SHARD1DB -p 1522:1521 oracle/database:21c
   docker run -d --name shard2_container -e ORACLE_SID=SHARD2DB -p 1523:1521 oracle/database:21c
   ```
3. **GSM Container**: Initialize GSM last to register and route connections.
   ```bash
   docker run -d --name gsm_container -p 1571:1571 oracle/gsm:21c
   ```

#### Step 2.2: Verify Listeners in Each Container
- **Purpose**: Ensure all listeners are correctly configured for incoming connections.
- **Command**:
  ```bash
  
  docker exec -it <container_name> bash -c "lsnrctl status"
  ```
- **Location**: Run in Catalog, Shard1, and Shard2 containers.

---

### 3. Catalog Container Configuration

#### Step 3.1: Initialize Catalog and Sharding Extensions
- **Command**:
  ```bash
  docker exec -it catalog_container sqlplus sys/oracle@localhost:1521/CATDB as sysdba
  ```
  ```sql
  -- Set up catalog sharding extensions
  exec dbms_gsm_fix.validateShard();
  ```
- **Verification**: Catalog setup should return a `PL/SQL procedure successfully completed.` message.

---

### 4. GSM Container Configuration

#### Step 4.1: GSM Initialization
- **Action**: Configure GSM and connect it to catalog and shard containers.
- **Command**:
  ```bash
  docker exec -it gsm_container gdsctl
  gdsctl> connect sys/oracle@localhost:1521/CATDB as sysdba
  gdsctl> add shardgroup -shardgroup shardgroup1 -region region1
  gdsctl> add shard -connect "connection_string_for_shard1" -shardgroup shardgroup1
  gdsctl> add shard -connect "connection_string_for_shard2" -shardgroup shardgroup1
  ```
- **Verification**: Run `gdsctl config shard` to confirm `OK` status for all shards.

---

### 5. Shard Setup and Permissions for All-Shards User
### Step 5.1 allow gsmuser to execute dbms_gsm_fix.validateShard
- **In each shard container**
```bash
sqlplus / as sysdba
```
```sql
create or replace directory DATA_PUMP_DIR as '/u01/app/oracle/oradata';
```
```sql
alter session set container=orcl[1/2]pdb; 
-- or connect to shard through sqlplus sys/oracle@localhost:1521/orcl1pdb as sysdba
```
```sql
CREATE PUBLIC SYNONYM dbms_gsm_fix FOR sys.dbms_gsm_fix;
grant read, write on directory DATA_PUMP_DIR to gsmadmin_internal;
```
```bash
sqlplus gsmuser/oracle@localhost:1521/orcl1pdb
```


```sql
execute dbms_gsm_fix.validateshard
```

### Step 5.2: Setting db_files so multiple tablspace set can be created

To set or adjust `db_files`, follow these steps:

1. **Set the Parameter in SPFILE**:
   ```sql
   ALTER SYSTEM SET db_files = 1024 SCOPE=SPFILE;
   ```

2. **Restart the Database** to apply changes:
   ```sql
   SHUTDOWN IMMEDIATE;
   STARTUP;
   ```
#### Step 5.3: Create All-Shards User with Necessary Privileges
- **Location**: Catalog Container.
- **Command**:
  ```bash
  sqlplus sys/oracle@localhost:1521/GDS\$CATALOG.oradbcloud as sysdba

  ```
  ```sql
  ALTER SESSION ENABLE SHARD DDL;
  CREATE USER allshardsuser IDENTIFIED BY oracle;
  GRANT ALL PRIVILEGES TO mtsm_timeseries;
  GRANT GSMADMIN_ROLE TO mtsm_timeseries;
  GRANT SELECT_CATALOG_ROLE TO mtsm_timeseries;
  GRANT CONNECT, RESOURCE TO mtsm_timeseries;
  GRANT DBA TO mtsm_timeseries;
  GRANT EXECUTE ON DBMS_CRYPTO TO mtsm_timeseries;
  ```
- **Verification**: Confirm that `allshardsuser` is created on all shards by querying in Shard1 and Shard2 containers:
  ```sql
  SELECT username FROM dba_users WHERE username = 'allshardsuser';
  ```

#### Step 5.4: Check for Shard Validation Issues
- **Action**: Use `gdsctl validate` to verify catalog and shard synchronization.
- **Command**:
  ```bash
  gdsctl validate
  ```
- **Resolution**: If mismatched DDL errors occur, synchronize the DDLs using `gdsctl recover shard -shard <shard_name>`.

---

### 6. Query Execution Across Shards

#### Step 6.1: Execute Queries Using the Query Coordinator (`GDS$CATALOG` Service)
- **Action**: Connect to the query coordinator and run distributed queries.
- **Command**:
  ```bash
  sqlplus allshardsuser/oracle@localhost:1521/GDS\$CATALOG.oradbcloud
  ```
- **Example**:

---

### 7. Tablespace Set and Table Creation for Sharded Tables

#### Step 7.1: Create Tablespace Set
- **Location**: Catalog Container (logged in as `allshardsuser` to `GDS$CATALOG.oradbcloud` server).
- **Command**:
  ```sql
  ALTER SESSION ENABLE SHARD DDL;
  CREATE TABLESPACE SET ts_data_set USING TEMPLATE (
    DATAFILE SIZE 100M AUTOEXTEND ON NEXT 10M MAXSIZE 5G
    EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO
  ) IN SHARDSPACE shardspaceora;
  ```
- **Verification**: Run `gdsctl config shard` to confirm `OK` status and no errors.

#### Step 7.2: Create Table Family with Co-Location
- **Example Commands**:
  ```sql
  CREATE SHARDED TABLE heads (
    head_id NUMBER PRIMARY KEY,
    head_name VARCHAR2(50)
  ) PARTITION BY CONSISTENT HASH (head_id)
  TABLESPACE SET ts_data_set;

  CREATE SHARDED TABLE data_points (
    data_id NUMBER,
    head_id NUMBER,
    data_value NUMBER,
    PRIMARY KEY (head_id, data_id),
    FOREIGN KEY (head_id) REFERENCES heads (head_id)
  )
  PARENT heads
  PARTITION BY CONSISTENT HASH (head_id)
  TABLESPACE SET ts_data_set;
  ```
- **Verification**: Ensure tables are created and validate data co-location by querying each shard.

#### Step 7.2: Insert Data
- Insert into the tables:
  ```sql
  INSERT INTO heads (head_id, head_name) VALUES (3, 'Head 3');
  INSERT INTO data_points (data_id, head_id, data_value) VALUES (101, 2, 500);
  COMMIT;
  ```
#### Step 7.3: Validate Data Distribution
- **Command**:
  ```sql
  SELECT * FROM heads;
  SELECT * FROM data_points;
  ```
    - Ensure data is distributed across shards and co-located within table families.

---

### 8. Troubleshooting with GDSCTL

#### Step 8.1: Validate and Recover Shards
- **Validate Shard Configurations**:
  ```bash
  gdsctl validate
  ```
- **Recover Shard if Necessary**:
  ```bash
  gdsctl recover shard -shard orcl1cdb_orcl1pdb
  ```
    - Use `recover` to resolve DDL synchronization issues and bring shards up to date.
    - Use `recover -h` to use flags for fixing ddl error
---

### Architecture Overview

1. **Catalog Container**: Manages metadata, synchronizes schema, and coordinates queries.
2. **GSM Container**: Manages connections and routes queries to the appropriate shards based on the sharding key.
3. **Shard Containers (Shard1 and Shard2)**: Store the distributed data and handle shard-specific transactions.

In this architecture:
- All-shards queries and DDLs are initiated through the `GDS$CATALOG` service on the catalog.
- The GSM routes client requests to the correct shard based on the sharding key, ensuring efficient query execution.
- The `PARENT` clause and table family concept allow for related data to be co-located within shards for optimized data access patterns.

This setup ensures that all data is distributed and sharded correctly, allowing for horizontal scalability and efficient query execution across multiple shards.

CREATE TABLESPACE SET ts_dataset USING TEMPLATE (
DATAFILE SIZE 100M AUTOEXTEND ON NEXT 10M MAXSIZE 10G
EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO
) IN SHARDSPACE shardspaceora;