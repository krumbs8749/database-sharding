#!/bin/bash

# Step 1: Create a Docker network for Citus
docker network create citus-network

# Step 2: Run the Citus coordinator
docker run -d \
  --name citus-coordinator \
  --network citus-network \
  -e POSTGRES_PASSWORD=postgres \
  -p 5442:5432 \
  citusdata/citus:12.1

# Wait for the coordinator to start
until docker exec citus-coordinator pg_isready -U postgres; do
  sleep 2
done

# Step 3: Run the Citus worker nodes
docker run -d \
  --name citus-worker-1 \
  --network citus-network \
  -e POSTGRES_PASSWORD=postgres \
  citusdata/citus:12.1

docker run -d \
  --name citus-worker-2 \
  --network citus-network \
  -e POSTGRES_PASSWORD=postgres \
  citusdata/citus:12.1

# Wait for the workers to start
echo "Waiting for the Citus worker nodes to start..."
sleep 10

# Step 4: Add worker nodes to the coordinator with password authentication
echo "Adding worker nodes to the coordinator..."
docker exec -t citus-coordinator psql -U postgres -P pager=off -c "SELECT * FROM master_add_node('citus-worker-1', 5432);"
sleep 2
docker exec -t citus-coordinator psql -U postgres -P pager=off -c "SELECT * FROM master_add_node('citus-worker-2', 5432);"
sleep 2

# Optional: Confirm worker nodes are added
echo "Active worker nodes:"
docker exec -t citus-coordinator psql -U postgres -P pager=off -c "SELECT * FROM citus_get_active_worker_nodes();"

# Step 5: Create the /scripts directory inside the container
echo "Creating /scripts directory in the coordinator..."
docker exec citus-coordinator mkdir -p /scripts
sleep 2

echo "Citus cluster setup complete!"

# Pause at the end of the script
echo "Press any key to exit..."
read -n 1 -s
