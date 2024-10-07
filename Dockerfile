# Extend the official Citus image
FROM citusdata/citus:12.1

# Expose the default PostgreSQL port
EXPOSE 5432

# Create a directory for initialization scripts
RUN mkdir -p /docker-entrypoint-initdb.d

# Copy the initialization script to the correct directory
COPY ./src/main/resources/db/postgres/creates_tables_and_shards.sql /docker-entrypoint-initdb.d/

