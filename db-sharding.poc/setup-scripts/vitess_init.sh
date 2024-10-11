#!/bin/bash

# Step 1: Build the Docker image
echo "Building Vitess Docker image..."
docker build -t vitess-image .

# Step 2: Create Docker network for communication between containers (if not exists)
docker network inspect vitess-network >/dev/null 2>&1 || docker network create vitess-network

# Step 3: Run ZooKeeper for topology management
echo "Starting vit-zookeeper..."
docker run -d --name vit-zookeeper --network vitess-network -p 2181:2181 zookeeper:3.5 || docker restart vit-zookeeper

# Step 4: Run MySQL (since vttablet requires MySQL)
echo "Starting vit-mysql-server..."
docker run -d --name vit-mysql-server --network vitess-network -e MYSQL_ROOT_PASSWORD=root -p 3366:3306 mysql:5.7 || docker restart vit-mysql-server

# Step 5: Run Vitess control service (vtctld)
echo "Starting vit-vtctld..."
docker run -d --name vit-vtctld --network vitess-network \
  -p 15000:15000 vitess-image \
  bash /vt/vitess/bin/vtctld \
  --topo_implementation=zookeeper \
  --topo_global_server_address=vit-zookeeper:2181 \
  --topo_global_root=/vitess/global || docker restart vit-vtctld

# Step 6: Run first shard (tablet0 - primary)
echo "Starting vit-vttablet0 (primary for shard 0)..."
docker run -d --name vit-vttablet0 --network vitess-network \
  -p 15100:15100 vitess-image \
  bash /vt/vitess/bin/vttablet \
  --tablet_hostname=vit-vttablet0 \
  --init_keyspace=test_keyspace \
  --init_shard=0 \
  --init_tablet_type=primary \
  --port=15100 \
  --topo_implementation=zookeeper \
  --topo_global_server_address=vit-zookeeper:2181 \
  --topo_global_root=/vitess/global || docker restart vit-vttablet0

# Step 7: Run second shard (tablet1 - primary)
echo "Starting vit-vttablet1 (primary for shard 1)..."
docker run -d --name vit-vttablet1 --network vitess-network \
  -p 15101:15101 vitess-image \
  bash /vt/vitess/bin/vttablet \
  --tablet_hostname=vit-vttablet1 \
  --init_keyspace=test_keyspace \
  --init_shard=1 \
  --init_tablet_type=primary \
  --port=15101 \
  --topo_implementation=zookeeper \
  --topo_global_server_address=vit-zookeeper:2181 \
  --topo_global_root=/vitess/global || docker restart vit-vttablet1

# Step 8: Run vtgate for routing queries
echo "Starting vit-vtgate (MySQL routing proxy)..."
docker run -d --name vit-vtgate --network vitess-network \
  -p 15099:15099 vitess-image \
  bash /vt/vitess/bin/vtgate \
  --topo_implementation=zookeeper \
  --topo_global_server_address=vit-zookeeper:2181 \
  --topo_global_root=/vitess/global \
  --logtostderr=true || docker restart vit-vtgate

# Step 9: Wait for vtctld to be ready (you can replace sleep with a better health check)
echo "Waiting for vit-vtctld to be ready..."
sleep 10  # Replace with a health check

# Step 10: Initialize the keyspace and apply VSchema for sharding
echo "Initializing the keyspace and VSchema..."
docker exec -t vit-vtctld /vt/vitess/bin/vtctlclient \
  --server=localhost:15000 \
  CreateKeyspace --sharding_column_name=head_id --sharding_column_type=hash test_keyspace

docker exec -t vit-vtctld /vt/vitess/bin/vtctlclient \
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

echo "Vitess setup complete. Use vit-vtgate for routing MySQL queries at localhost:15099"

# Pause at the end of the script
echo "Press any key to exit..."
read -n 1 -s
