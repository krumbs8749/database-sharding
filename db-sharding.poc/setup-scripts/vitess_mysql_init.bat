@echo off

REM Step 1: Create Docker network for Vitess components
docker network create vitess-network

REM Step 2: Start Zookeeper for topology management
echo Starting Zookeeper...
docker run -d --name vit-zookeeper --network vitess-network -p 2181:2181 zookeeper:3.5

REM Step 3: Start MySQL on a different port (if 3306 is in use)
echo Starting MySQL server...
docker run -d --name vit-mysql --network vitess-network -e MYSQL_ROOT_PASSWORD=root -p 3307:3306 vitess-image /usr/sbin/mysqld

REM Step 4: Start Vitess control service (vtctld)
echo Starting vit-vtctld...
docker run -d --name vit-vtctld --network vitess-network -p 15000:15000 vitess-image \
    /vt/vitess/bin/vtctld \
    --topo_implementation=zookeeper \
    --topo_global_server_address=vit-zookeeper:2181 \
    --topo_global_root=/vitess/global

REM Step 5: Start Vitess tablet (vttablet0 - primary for shard 0)
echo Starting vit-vttablet0 (primary for shard 0)...
docker run -d --name vit-vttablet0 --network vitess-network -p 15100:15100 vitess-image \
    /vt/vitess/bin/vttablet \
    --tablet_hostname=vit-vttablet0 \
    --init_keyspace=test_keyspace \
    --init_shard=0 \
    --init_tablet_type=primary \
    --port=15100 \
    --topo_implementation=zookeeper \
    --topo_global_server_address=vit-zookeeper:2181 \
    --topo_global_root=/vitess/global

REM Step 6: Start Vitess tablet (vttablet1 - primary for shard 1)
echo Starting vit-vttablet1 (primary for shard 1)...
docker run -d --name vit-vttablet1 --network vitess-network -p 15101:15101 vitess-image \
    /vt/vitess/bin/vttablet \
    --tablet_hostname=vit-vttablet1 \
    --init_keyspace=test_keyspace \
    --init_shard=1 \
    --init_tablet_type=primary \
    --port=15101 \
    --topo_implementation=zookeeper \
    --topo_global_server_address=vit-zookeeper:2181 \
    --topo_global_root=/vitess/global

REM Step 7: Start Vitess query router (vtgate)
echo Starting vtgate...
docker run -d --name vit-vtgate --network vitess-network -p 15306:15306 vitess-image \
    /vt/vitess/bin/vtgate \
    --topo_implementation=zookeeper \
    --topo_global_server_address=vit-zookeeper:2181 \
    --topo_global_root=/vitess/global \
    --logtostderr=true

REM Step 8: Initialize keyspace and VSchema for sharding
echo Initializing keyspace and VSchema...
docker exec -t vit-vtctld vtctlclient \
    --server=localhost:15000 \
    CreateKeyspace --sharding_column_name=head_id --sharding_column_type=hash test_keyspace

docker exec -t vit-vtctld vtctlclient \
    --server=localhost:15000 \
    ApplyVSchema --vschema '{
        "tables": {
          "tb_head": {
            "column_vindexes": [
              {
                "column": "head_id",
                "name": "hash"
              }
            ]
          }
        }
      }' test_keyspace

echo Vitess and MySQL setup complete. Vitess routing is available at localhost:15306.
