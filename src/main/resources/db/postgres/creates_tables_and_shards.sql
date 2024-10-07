DROP TABLE IF EXISTS ts_data_int_ext_ver_curr CASCADE;
DROP TABLE IF EXISTS ts_data_int_ext_ver_archive CASCADE;
DROP TABLE IF EXISTS ts_checkpoint_versioned CASCADE;
DROP TABLE IF EXISTS ts_data_versioned_archive CASCADE;
DROP TABLE IF EXISTS ts_data_versioned_current CASCADE;
DROP TABLE IF EXISTS ts_invalid_interval CASCADE;
DROP TABLE IF EXISTS ts_readonly CASCADE;
DROP TABLE IF EXISTS ts_attribute CASCADE;
DROP TABLE IF EXISTS ts_attr_definition CASCADE;
DROP TABLE IF EXISTS ts_data_normalized CASCADE;
DROP TABLE IF EXISTS ts_data_write_trace CASCADE;
DROP TABLE IF EXISTS ts_formula_placeholder CASCADE;
DROP TABLE IF EXISTS ts_formula_ver CASCADE;
DROP TABLE IF EXISTS ts_formula CASCADE;
DROP TABLE IF EXISTS ts_data CASCADE;
DROP TABLE IF EXISTS ts_head CASCADE;


-- Enable Citus extension if not already enabled
CREATE EXTENSION IF NOT EXISTS citus;

-- Create the ts_head table
CREATE TABLE IF NOT EXISTS ts_head (
                                       head_id VARCHAR(36) PRIMARY KEY,
                                       head_timeseriestype VARCHAR(100) NOT NULL,
                                       head_valueplugin VARCHAR(4000),
                                       head_persistencestrategyid VARCHAR(36) NOT NULL,
                                       head_period VARCHAR(100),
                                       head_valid_from TIMESTAMP,
                                       head_valid_to TIMESTAMP,
                                       head_birth TIMESTAMP NOT NULL,
                                       head_death TIMESTAMP,
                                       head_unit VARCHAR(100),
                                       head_anchor TIMESTAMP,
                                       head_name VARCHAR(400),
                                       head_external_name VARCHAR(400),
                                       head_external_id VARCHAR(400),
                                       head_trc_data_write BOOLEAN DEFAULT false NOT NULL,
                                       head_default_value VARCHAR(400),
                                       head_version BIGINT DEFAULT 0 NOT NULL
);

-- Shard the ts_head table using hash-based sharding on head_id
SELECT create_distributed_table('ts_head', 'head_id', 'hash');

-- Create the ts_data table
CREATE TABLE IF NOT EXISTS ts_data (
                                       data_block_start BIGINT NOT NULL,
                                       data_block_end BIGINT,
                                       data_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                       data_werte TEXT,
                                       PRIMARY KEY (data_head_id, data_block_start)
);

-- Shard the ts_data table using hash-based sharding on data_head_id
SELECT create_distributed_table('ts_data', 'data_head_id', 'hash');

-- Create the ts_formula table
CREATE TABLE IF NOT EXISTS ts_formula (
                                          form_id VARCHAR(36) PRIMARY KEY,
                                          form_type VARCHAR(50) NOT NULL,
                                          form_text OID NOT NULL,
                                          form_name VARCHAR(400),
                                          form_persistencestrategyid VARCHAR(36)
);

-- Shard the ts_formula table using hash-based sharding on form_id
SELECT create_distributed_table('ts_formula', 'form_id', 'hash');

-- Create the ts_formula_placeholder table
CREATE TABLE IF NOT EXISTS ts_formula_placeholder (
                                                      plch_form_id VARCHAR(36) NOT NULL REFERENCES ts_formula(form_id),
                                                      plch_placeholder VARCHAR(100) NOT NULL,
                                                      plch_dbname VARCHAR(100) NOT NULL,
                                                      plch_head_id VARCHAR(36) NOT NULL,
                                                      plch_valid_from TIMESTAMP,
                                                      plch_valid_to TIMESTAMP,
                                                      PRIMARY KEY (plch_form_id, plch_placeholder)
);

-- Shard the ts_formula_placeholder table using hash-based sharding on plch_form_id
SELECT create_distributed_table('ts_formula_placeholder', 'plch_form_id', 'hash');

-- Create the ts_formula_ver table (adjusted to include partition key in the primary key)
CREATE TABLE IF NOT EXISTS ts_formula_ver (
                                              form_family_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                              form_version BIGINT NOT NULL,
                                              form_id VARCHAR(36) NOT NULL,
                                              form_type VARCHAR(50) NOT NULL,
                                              form_text OID NOT NULL,
                                              form_name VARCHAR(400),
                                              form_valid_from TIMESTAMP,
                                              form_valid_to TIMESTAMP,
                                              PRIMARY KEY (form_id, form_family_id) -- Fixed: Include partition key in primary key
);

-- Shard the ts_formula_ver table using hash-based sharding on form_family_id
SELECT create_distributed_table('ts_formula_ver', 'form_family_id', 'hash');

-- Create the ts_data_write_trace table
CREATE TABLE IF NOT EXISTS ts_data_write_trace (
                                                   wtrc_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                   wtrc_interval_start BIGINT NOT NULL,
                                                   wtrc_interval_end BIGINT NOT NULL,
                                                   wtrc_timestamp BIGINT NOT NULL,
                                                   wtrc_ext_version TEXT,
                                                   PRIMARY KEY (wtrc_head_id, wtrc_interval_start, wtrc_interval_end, wtrc_timestamp)
);

-- Shard the ts_data_write_trace table using hash-based sharding on wtrc_head_id
SELECT create_distributed_table('ts_data_write_trace', 'wtrc_head_id', 'hash');

-- Create the ts_data_normalized table
CREATE TABLE IF NOT EXISTS ts_data_normalized (
                                                  norm_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                  norm_timestamp TIMESTAMP NOT NULL,
                                                  norm_value NUMERIC,
                                                  PRIMARY KEY (norm_head_id, norm_timestamp)
);

-- Shard the ts_data_normalized table using hash-based sharding on norm_head_id
SELECT create_distributed_table('ts_data_normalized', 'norm_head_id', 'hash');

-- Create the ts_attr_definition table as a reference table
CREATE TABLE IF NOT EXISTS ts_attr_definition (
                                                  atde_id VARCHAR(36) PRIMARY KEY,
                                                  atde_name VARCHAR(100) NOT NULL UNIQUE,
                                                  atde_valuerange VARCHAR(100),
                                                  atde_type VARCHAR(100) NOT NULL
);

-- Make ts_attr_definition a reference table (replicated across all nodes)
SELECT create_reference_table('ts_attr_definition');

-- Create the ts_attribute table
CREATE TABLE IF NOT EXISTS ts_attribute (
                                            attr_id VARCHAR(36),
                                            attr_atde_id VARCHAR(100) REFERENCES ts_attr_definition(atde_id),
                                            attr_head_id VARCHAR(100) REFERENCES ts_head(head_id),
                                            attr_value VARCHAR(100),
                                            attr_valid_from BIGINT,
                                            attr_valid_to BIGINT,
                                            PRIMARY KEY (attr_id, attr_head_id)
);

-- Shard the ts_attribute table using hash-based sharding on attr_head_id
SELECT create_distributed_table('ts_attribute', 'attr_head_id', 'hash');

-- Create the ts_readonly table
CREATE TABLE IF NOT EXISTS ts_readonly (
                                           roly_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                           roly_from TIMESTAMP NOT NULL,
                                           roly_to TIMESTAMP NOT NULL,
                                           PRIMARY KEY (roly_id, roly_from, roly_to)
);

-- Shard the ts_readonly table using hash-based sharding on roly_id
SELECT create_distributed_table('ts_readonly', 'roly_id', 'hash');

-- Create the ts_invalid_interval table
CREATE TABLE IF NOT EXISTS ts_invalid_interval (
                                                   inin_id BIGINT,
                                                   inin_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                   inin_from TIMESTAMP NOT NULL,
                                                   inin_to TIMESTAMP NOT NULL,
                                                   PRIMARY KEY (inin_id, inin_head_id)
);

-- Shard the ts_invalid_interval table using hash-based sharding on inin_head_id
SELECT create_distributed_table('ts_invalid_interval', 'inin_head_id', 'hash');

-- Create the ts_data_versioned_current table
CREATE TABLE IF NOT EXISTS ts_data_versioned_current (
                                                         data_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                         data_block_start BIGINT NOT NULL,
                                                         data_block_end BIGINT,
                                                         data_werte TEXT,
                                                         PRIMARY KEY (data_head_id, data_block_start)
);

-- Shard the ts_data_versioned_current table using hash-based sharding on data_head_id
SELECT create_distributed_table('ts_data_versioned_current', 'data_head_id', 'hash');

-- Create the ts_data_versioned_archive table
CREATE TABLE IF NOT EXISTS ts_data_versioned_archive (
                                                         data_row BIGSERIAL,
                                                         data_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                         data_block_start BIGINT NOT NULL,
                                                         data_block_end BIGINT,
                                                         data_version BIGINT NOT NULL,
                                                         data_werte TEXT,
                                                         PRIMARY KEY (data_head_id, data_block_start, data_version)
);

-- Shard the ts_data_versioned_archive table using hash-based sharding on data_head_id
SELECT create_distributed_table('ts_data_versioned_archive', 'data_head_id', 'hash');

-- Create the ts_checkpoint_versioned table
CREATE TABLE IF NOT EXISTS ts_checkpoint_versioned (
                                                       chkp_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                       chkp_version BIGINT NOT NULL,
                                                       chkp_rows OID,
                                                       PRIMARY KEY (chkp_head_id, chkp_version)
);

-- Shard the ts_checkpoint_versioned table using hash-based sharding on chkp_head_id
SELECT create_distributed_table('ts_checkpoint_versioned', 'chkp_head_id', 'hash');

-- Create the ts_data_int_ext_ver_curr table
CREATE TABLE IF NOT EXISTS ts_data_int_ext_ver_curr (
                                                        data_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                        data_block_start BIGINT NOT NULL,
                                                        data_block_end BIGINT,
                                                        data_ext_version TEXT NOT NULL,
                                                        data_werte TEXT,
                                                        PRIMARY KEY (data_head_id, data_block_start)
);

-- Shard the ts_data_int_ext_ver_curr table using hash-based sharding on data_head_id
SELECT create_distributed_table('ts_data_int_ext_ver_curr', 'data_head_id', 'hash');

-- Create the ts_data_int_ext_ver_archive table
CREATE TABLE IF NOT EXISTS ts_data_int_ext_ver_archive (
                                                           data_row BIGSERIAL,
                                                           data_head_id VARCHAR(36) NOT NULL REFERENCES ts_head(head_id),
                                                           data_block_start BIGINT NOT NULL,
                                                           data_block_end BIGINT,
                                                           data_version BIGINT NOT NULL,
                                                           data_ext_version TEXT NOT NULL,
                                                           data_werte TEXT,
                                                           PRIMARY KEY (data_head_id, data_version, data_block_start)
);

-- Shard the ts_data_int_ext_ver_archive table using hash-based sharding on data_head_id
SELECT create_distributed_table('ts_data_int_ext_ver_archive', 'data_head_id', 'hash');
