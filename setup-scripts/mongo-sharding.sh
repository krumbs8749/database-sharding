#!/bin/bash

# Pulling MongoDB image from Docker Hub (only once if not already pulled)
# The image 'mongo:latest' will be used for MongoDB config servers, shards, and the mongos router.
# 'mongo:latest' is pulled from Docker Hub, which is the official MongoDB Docker image repository.
echo "Creating custom Docker network..."
docker network create mongo-shard-network

# Step 2: Start MongoDB Config Server Replica Set
# The config server manages metadata and settings for the sharded cluster.
# Data will be stored in the C:\Users\darw\IdeaProjects\db-sharding-poc\src\main\resources\db\mongo\volumes/configsvr folder in the host machine, mapped to /data/db in the container.
echo "Starting Config Server Replica Set..."
docker run -d \
  --name mongo-configsvr \
  --net mongo-shard-network \
  -p 27019:27019 \
  -v "C:\Users\darw\IdeaProjects\db-sharding-poc\src\main\resources\db\mongo\volumes/configsvr:/data/db" \
  mongo:latest mongod --configsvr --replSet rs0 --port 27019

# Sleep to allow the config server to fully initialize
sleep 1

# Step 3: Initiate the Config Server Replica Set using mongosh
# 'mongo:latest' image is used to run mongosh, which is the MongoDB shell used to initiate the replica set.
# Initiate replica set for the config server using mongosh.
echo "Initiating the Config Server Replica Set using mongosh..."
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-configsvr --port 27019 --eval 'rs.initiate({
  _id: "rs0",
  configsvr: true,
  members: [{ _id: 0, host: "mongo-configsvr:27019" }]
})'

# Step 4: Start Shard 1 Replica Set
# Shard 1 stores part of the data in the sharded cluster.
# Data for shard 1 will be stored in C:\Users\darw\IdeaProjects\db-sharding-poc\src\main\resources\db\mongo\volumes/shard1 folder on the host machine.
echo "Starting Shard 1 Replica Set..."
docker run -d \
  --name mongo-shard1 \
  --net mongo-shard-network \
  -p 27018:27018 \
  -v "C:\Users\darw\IdeaProjects\db-sharding-poc\src\main\resources\db\mongo\volumes/shard1:/data/db" \
  mongo:latest mongod --shardsvr --replSet shard1 --port 27018

# Sleep to allow shard 1 to initialize
sleep 1

# Step 5: Initiate Shard 1 Replica Set using mongosh
# Initiate shard 1 as a replica set using mongosh.
echo "Initiating Shard 1 Replica Set using mongosh..."
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-shard1 --port 27018 --eval 'rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "mongo-shard1:27018" }]
})'

# Step 6: Start Shard 2 Replica Set
# Shard 2 stores another portion of the sharded data.
# Data for shard 2 will be stored in C:\Users\darw\IdeaProjects\db-sharding-poc\src\main\resources\db\mongo\volumes/shard2 folder on the host machine.
echo "Starting Shard 2 Replica Set..."
docker run -d \
  --name mongo-shard2 \
  --net mongo-shard-network \
  -p 27028:27018 \
  -v "C:\Users\darw\IdeaProjects\db-sharding-poc\src\main\resources\db\mongo\volumes/shard2:/data/db" \
  mongo:latest mongod --shardsvr --replSet shard2 --port 27018

# Sleep to allow shard 2 to initialize
sleep 1

# Step 7: Initiate Shard 2 Replica Set using mongosh
# Initiate shard 2 as a replica set using mongosh.
echo "Initiating Shard 2 Replica Set using mongosh..."
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-shard2 --port 27018 --eval 'rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "mongo-shard2:27018" }]
})'

# Step 8: Start Mongos Router
# Mongos router routes queries to the correct shard based on the sharding key.
echo "Starting Mongos Router..."
docker run -d \
  --name mongo-mongos \
  --net mongo-shard-network \
  -p 27017:27017 \
  mongo:latest mongos --configdb rs0/mongo-configsvr:27019 --bind_ip_all

# Sleep to allow mongos to initialize
sleep 1

# Step 9: Add Shards to the Cluster using mongosh
# Add shard 1 and shard 2 to the cluster using mongosh.
echo "Adding shards to the cluster using mongosh..."
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-mongos --port 27017 --eval '
  sh.addShard("shard1/mongo-shard1:27018");
  sh.addShard("shard2/mongo-shard2:27018");
'

echo "Sharded MongoDB cluster setup completed successfully!"

# Pause at the end of the script
echo "Press any key to exit..."
read -n 1 -s
