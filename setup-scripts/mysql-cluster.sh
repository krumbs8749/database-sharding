#!/bin/bash

# Step 1: Create a Docker network for MySQL cluster
# This network allows the containers to communicate with each other.
# The subnet is specified to provide a defined address range for the containers.
echo "Creating Docker network for MySQL Cluster..."
docker network create mysql-cluster --subnet=192.168.0.0/16

# Step 2: Start the NDB management server
# The management server is responsible for managing the cluster.
# This will be the node that monitors and controls other nodes in the cluster.
echo "Starting MySQL Cluster Management Server..."
docker run -d --net=mysql-cluster --name=mysql-mgm --ip=192.168.0.2 mysql/mysql-cluster:8.0 ndb_mgmd

# Step 3: Start the NDB data nodes
# Data nodes store the actual data in the cluster. You can have multiple data nodes for redundancy and load balancing.
echo "Starting NDB Data Nodes (Shards=2)"
docker run -d --net=mysql-cluster --name=mysql-ndb1 --ip=192.168.0.3 mysql/mysql-cluster:8.0 ndbd
docker run -d --net=mysql-cluster --name=mysql-ndb2 --ip=192.168.0.4 mysql/mysql-cluster:8.0 ndbd

# Step 4: Start the MySQL server node
# The MySQL server is the API layer for the application. It handles SQL queries and interacts with the data nodes.
echo "Starting MySQL Server Node..."
docker run -d --net=mysql-cluster -p 3306:3306 --name=mysql-sql --ip=192.168.0.10 -e MYSQL_ROOT_PASSWORD=root mysql/mysql-cluster:8.0 mysqld

# Step 5: Connect to the management node using the NDB management client
# This command allows you to interact with the management server to monitor and control the cluster.
docker run -it --net=mysql-cluster mysql/mysql-cluster:8.0 ndb_mgm

# Inside the ndb_mgm client, you can run commands like 'show' to display the current cluster status.
# Once inside the management client, run:
# ndb_mgm> show
# T quit interactive shell, run:
# ndb_mgm> quit

# The output will show the cluster configuration, including data nodes and the MySQL server node.

# Cleanup instructions:
# If you need to stop and remove all containers and the network created, you can run:
# docker stop $(docker ps --all -q --filter name=mysql*)
# docker rm $(docker ps --all -q --filter name=mysql*)
# docker network rm mysql-cluster

echo "MySQL Cluster setup complete. Use 'ndb_mgm' to manage the cluster."
