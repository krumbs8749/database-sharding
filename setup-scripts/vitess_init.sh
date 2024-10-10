#!/bin/bash

# Step 1: Start etcd (Topology Server)
echo "Starting etcd (topology server)..."
docker run -d \
  -p 2379:2379 \
  --name=etcd-topo \
  quay.io/coreos/etcd:v3.3.9 \
  /usr/local/bin/etcd \
  --advertise-client-urls=http://0.0.0.0:2379 \
  --listen-client-urls=http://0.0.0.0:2379

# Step 2: Start MySQL servers for shards
echo "Starting MySQL server for shard 0..."
docker run -d \
  -e MYSQL_ROOT_PASSWORD=my-secret-pw \
  --name=mysql-server-0 \
  -p 3306:3306 \
  mysql:8.0

echo "Starting MySQL server for shard 1..."
docker run -d \
  -e MYSQL_ROOT_PASSWORD=my-secret-pw \
  --name=mysql-server-1 \
  -p 3307:3306 \
  mysql:8.0

# Step 3: Start vtctld (Vitess Control Service)
echo "Starting vtctld..."
docker run -d \
  -p 15000:15000 \
  --name=vtctld \
  vitess/vtctld:latest-bullseye  \
  --topo_global_server_address=etcd-topo:2379 \
  --topo_global_root=/vitess/global \
  --logtostderr=true

# Step 4: Start vttablet for shard 0 (using MySQL server 0)
echo "Starting vttablet for shard 0..."
docker run -d \
  -p 15100:15100 \
  --name=vttablet0 \
  vitess/vttablet:latest-bullseye \
  /vt/bin/vttablet \
  --tablet_hostname=vttablet0 \
  --topo_global_server_address=etcd-topo:2379 \
  --topo_global_root=/vitess/global \
  --init_keyspace=test_keyspace \
  --init_shard=0 \
  --init_tablet_type=master \
  --mysql_server_host=mysql-server-0 \
  --mysql_server_port=3306 \
  --health_check_interval=5s \
  --port=15100 \
  --logtostderr=true

# Step 5: Start vttablet for shard 1 (using MySQL server 1)
echo "Starting vttablet for shard 1..."
docker run -d \
  -p 15101:15101 \
  --name=vttablet1 \
  vitess/vttablet:latest-bullseye \
  /vt/bin/vttablet \
  --tablet_hostname=vttablet1 \
  --topo_implementation=etcd2 \
  --topo_global_server_address=etcd-topo:2379 \
  --topo_global_root=/vitess/global \
  --init_keyspace=test_keyspace \
  --init_shard=1 \
  --init_tablet_type=master \
  --mysql_server_host=mysql-server-1 \
  --mysql_server_port=3307 \
  --health_check_interval=5s \
  --port=15101 \
  --logtostderr=true

# Step 6: Start vtgate (Routing Proxy for MySQL)
echo "Starting vtgate..."
docker run -d \
  -p 15099:15099 \
  --name=vtgate \
  vitess/vtgate \
  /vt/bin/vtgate \
  --topo_implementation=etcd2 \
  --topo_global_server_address=etcd-topo:2379 \
  --topo_global_root=/vitess/global \
  --logtostderr=true

# Step 7: Initialize Vitess Keyspace and Sharding
echo "Initializing Vitess keyspace and sharding..."
docker exec -t vtctld vtctlclient \
  --server=vtctld:15000 \
  CreateKeyspace --sharding_column_name=head_id --sharding_column_type=hash test_keyspace

docker exec -t vtctld vtctlclient \
  --server=vtctld:15000 \
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

# Create two shards: 0 and 1
docker exec -t vtctld vtctlclient \
  --server=vtctld:15000 \
  CreateShard test_keyspace/0

docker exec -t vtctld vtctlclient \
  --server=vtctld:15000 \
  CreateShard test_keyspace/1

# Step 8: Apply schema to the keyspace
echo "Applying schema to the keyspace..."
docker exec -t vtctld vtctlclient \
  --server=vtctld:15000 \
  ApplySchema --sql 'CREATE TABLE tb_head (
  head_id INT PRIMARY KEY,
  head_name VARCHAR(255),
  head_type VARCHAR(255)
)' test_keyspace

# Final instructions
echo "Setup complete. Use vtgate at localhost:15099 for routing queries."

# Pause at the end of the script.
echo "Press any key to exit..."
read -n 1 -s
