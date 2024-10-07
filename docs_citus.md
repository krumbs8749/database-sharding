## **Zusammenfassung: Sharding und Citus PostgreSQL Setup**

#### **Einleitung: PostgreSQL Citus**
Citus ist eine Erweiterung von PostgreSQL, die horizontale Skalierbarkeit durch Sharding und Parallelisierung ermöglicht. Dies erlaubt es, große Datenmengen auf mehrere Knoten (Nodes) zu verteilen, um Anfragen effizient zu verarbeiten. Mit Citus können Datenbanken in einem verteilten System verwendet werden, was sowohl die Leistung als auch die Verfügbarkeit der Datenbank verbessert.

### **1. Sharding in PostgreSQL mit Citus**

**Sharding** ist der Prozess, bei dem Daten einer Tabelle in kleinere, verwaltbare Teile (sogenannte **Shards**) aufgeteilt werden. Jeder Shard wird auf einem separaten **Worker-Knoten** gespeichert. Citus verwendet hauptsächlich **hash-basiertes Sharding** oder **range-basiertes Sharding**, um die Daten über diese Worker-Nodes zu verteilen.

- **Hash-basiertes Sharding (Single-Key Sharding)**: In unserem Projekt haben wir uns für **hash-basiertes Sharding** entschieden, bei dem der Sharding-Schlüssel (`head_id`) in eine Hash-Zahl umgewandelt wird. Die Hash-Zahl bestimmt, in welchem Shard die Daten gespeichert werden. Dies sorgt für eine gleichmäßige Verteilung der Daten und verbessert die Performance bei Point-Queries (Abfragen, die auf einzelne Zeilen zugreifen).

  **Vorteile von hash-basiertem Sharding**:
    - **Gleichmäßige Datenverteilung**: Hash-basiertes Sharding sorgt für eine ausgeglichene Verteilung der Daten über die Shards, was Lastspitzen vermeidet.
    - **Einfache Abfragen**: Es ist einfach, einzelne Zeilen zu finden, da der Hashwert die Zuordnung zu einem bestimmten Shard steuert.

- **Range-basiertes Sharding**: Bei diesem Ansatz werden Daten in Bereichsgruppen gespeichert. Dieser Ansatz ist jedoch weniger für unsere Anwendungsfälle geeignet, da wir eine gleichmäßige Verteilung ohne besondere Bereichslogik benötigen.

### **2. Rollen von Coordinator und Worker-Nodes**

Coordinator und Workers: Wie funktioniert die Verteilung?

- **Coordinator-Knoten**: Der Coordinator ist der zentrale Einstiegspunkt in den Citus-Cluster. Er empfängt alle SQL-Anfragen und plant deren Ausführung, indem er sie auf die Worker-Knoten verteilt. Der Coordinator selbst speichert keine Anwendungsdaten (nur Metadaten über die Shards und Worker).
    - **Aufgaben des Coordinators**:
        - Teilt Anfragen auf mehrere Worker auf.
        - Überwacht die Verteilung der Shards.
        - Koordiniert die parallele Verarbeitung von Abfragen.

- **Worker-Knoten**: Die Worker-Knoten speichern die tatsächlichen Daten, also die Shards der Tabellen. Wenn eine Anfrage vom Coordinator ankommt, führen die Worker die Operationen auf ihren Shards aus und geben die Ergebnisse zurück.
    - **Aufgaben der Worker**:
        - Speichern und verwalten von Shards.
        - Bearbeiten von Abfragen auf ihren lokalen Daten.
        - Kommunizieren mit dem Coordinator, um Ergebnisse bereitzustellen.

### **3. PostgreSQL Citus: Einrichtung des Clusters**

#### **Schritt-für-Schritt-Anleitung zur Cluster-Einrichtung**

1. **Docker-basierte Einrichtung**:
   Für dieses Setup verwenden wir Docker-Container, um einen Citus-Cluster mit einem Coordinator und zwei Worker-Nodes zu erstellen:

   ```bash
   # Citus Coordinator starten
   docker run -d --name citus-coordinator -p 5432:5432 -e POSTGRES_PASSWORD=citus citusdata/citus:12.1

   # Worker-Knoten starten
   docker run -d --name citus-worker-1 -p 5433:5432 -e POSTGRES_PASSWORD=citus citusdata/citus:12.1
   docker run -d --name citus-worker-2 -p 5434:5432 -e POSTGRES_PASSWORD=citus citusdata/citus:12.1

   # Nodes dem Citus-Coordinator hinzufügen
   docker exec -it citus-coordinator psql -U postgres -c "SELECT master_add_node('citus-worker-1', 5432);"
   docker exec -it citus-coordinator psql -U postgres -c "SELECT master_add_node('citus-worker-2', 5432);"
   ```

2. **Aktivieren der Citus-Erweiterung**:
   Nachdem der Cluster eingerichtet ist, aktivieren wir die Citus-Erweiterung in PostgreSQL:

   ```sql
   CREATE EXTENSION IF NOT EXISTS citus;
   ```

3. **Erstellen und Sharden der Tabellen**:
   In diesem Schritt erstellen wir die `ts_head`-Tabelle und sharden sie basierend auf der Spalte `head_id`.

   ```sql
   CREATE TABLE ts_head (
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

   -- Hash-basiertes Sharding auf der Spalte `head_id`
   SELECT create_distributed_table('ts_head', 'head_id', 'hash');
   ```

4. **Einfügen von Daten**:
   Nachdem die Tabelle erstellt und geshardet wurde, fügen wir Testdaten in die Tabelle ein.

   ```sql
   INSERT INTO ts_head (
       head_id, head_timeseriestype, head_valueplugin, head_persistencestrategyid,
       head_period, head_valid_from, head_valid_to, head_birth, head_trc_data_write,
       head_default_value, head_version
   ) VALUES 
   ('head1', 'time-series', NULL, 'strategy1', 'monthly', '2023-01-01', '2023-12-31',
   '2023-01-01', false, 'default1', 1),
   ('head2', 'time-series', NULL, 'strategy2', 'weekly', '2023-01-01', '2023-12-31',
   '2023-01-01', false, 'default2', 1);
   ```

### **4. Besonderheiten, Constraints und Einschränkungen**

Citus hat einige Einschränkungen bei der Verwendung von Constraints wie **Primärschlüsseln**, **Fremdschlüsseln** und **Unique-Constraints**:

- **Primärschlüssel**: Bei verteilten Tabellen muss der Primärschlüssel immer die Sharding-Spalte (z.B. `head_id`) enthalten, damit Citus die Eindeutigkeit innerhalb eines Shards garantieren kann.

- **Fremdschlüssel**: Fremdschlüssel können nur dann verwendet werden, wenn die Tabellen **co-located** sind, d.h., wenn sie auf der gleichen Spalte geshardet werden. Andernfalls kann die Konsistenz nicht gewährleistet werden.

  Beispiel:
  ```sql
  CREATE TABLE ts_attribute (
      attr_id VARCHAR(36) PRIMARY KEY,
      attr_head_id VARCHAR(100) REFERENCES ts_head(head_id), -- Co-located Fremdschlüssel
      attr_value VARCHAR(100),
      attr_valid_from BIGINT,
      attr_valid_to BIGINT
  );
  ```

- **Referenztabellen**: Kleine Tabellen, die oft in JOINs verwendet werden, können als Referenztabellen definiert werden, die auf allen Worker-Nodes repliziert werden.

  Beispiel:
  ```sql
  SELECT create_reference_table('ts_attr_definition');
  ```
- **Unique-Constraints** und **Exclude-Constraints** müssen ebenfalls den Sharding-Schlüssel enthalten, damit sie in einem verteilten Setup durchgesetzt werden können.

  **Beispiel**:
   ```sql
   CREATE TABLE ts_attribute (
       attr_id VARCHAR(36),
       attr_head_id VARCHAR(100) REFERENCES ts_head(head_id), -- Sharding-Schlüssel
       attr_value VARCHAR(100),
       PRIMARY KEY (attr_id, attr_head_id) -- Der Primärschlüssel muss den Sharding-Schlüssel enthalten
   );

- **Co-location (Zusammenarbeit von Shards)** stellt sicher, dass Tabellen, die miteinander verknüpft sind (z.B. durch Fremdschlüssel), auf denselben Worker-Knoten gespeichert werden. Dies geschieht durch Sharding nach derselben Spalte (z.B. `head_id`).

   ```sql
   -- Sharding der Tabelle `ts_attribute` basierend auf `attr_head_id`, um Co-location mit `ts_head` zu gewährleisten
   SELECT create_distributed_table('ts_attribute', 'attr_head_id', 'hash');
   ```

- **Transaktionen**: Verteilte Transaktionen sind möglich, aber sie sind teurer als Transaktionen auf einer einzelnen Node.
- **JOINs**: JOINs zwischen Tabellen sind effizienter, wenn die Tabellen co-located sind (d.h., auf der gleichen Spalte geshardet sind). Nicht co-located JOINs können zu Netzwerkoverhead führen.
- **Aggregation und GROUP BY**: Solche Operationen werden parallel auf den Worker-Nodes ausgeführt, wobei die Ergebnisse anschließend vom Coordinator aggregiert werden.


### **5. Verifikation und Tests**

1. **Überprüfen der Shard-Verteilung**:
   Mithilfe der folgenden Abfragen können Sie überprüfen, welche Shards für die Tabelle `ts_head` erstellt wurden:

   ```sql
   SELECT shardid, shardminvalue::bigint, shardmaxvalue::bigint
   FROM pg_dist_shard
   WHERE logicalrelid = 'ts_head'::regclass;
   ```

2. **Verteilen der Daten auf die Shards**:
   Um zu überprüfen, welcher Shard welche Daten speichert, verwenden wir:

   ```sql
   SELECT head_id, hashtext(head_id) AS hashed_value
   FROM ts_head;
   ```

3. **Verifizieren der Shard-Platzierung**:
   Um sicherzustellen, dass die Shards korrekt auf die Worker-Knoten verteilt sind, verwenden wir:

   ```sql
   SELECT
       pg_dist_shard_placement.shardid,
       pg_dist_shard.shardminvalue,
       pg_dist_shard.shardmaxvalue,
       pg_dist_shard_placement.nodename,
       pg_dist_shard_placement.nodeport
   FROM pg_dist_shard_placement
   JOIN pg_dist_shard ON pg_dist_shard_placement.shardid = pg_dist_shard.shardid
   WHERE pg_dist_shard.logicalrelid = 'ts_head'::regclass;
   ```

### **Zusammenfassung**
In unserem PostgreSQL-Citus-Projekt haben wir eine **hash-basierte Sharding-Strategie** verwendet, um die Daten effizient auf mehrere Worker-Knoten zu verteilen. Der Coordinator verwaltet alle Anfragen und verteilt sie an die Worker, die die Shards speichern. Mithilfe von Constraints wie Fremd- und Primärschlüsseln stellen wir sicher, dass die Konsistenz der Daten erhalten bleibt. Referenztabellen helfen dabei, häufig verwendete Daten über den gesamten Cluster zu replizieren.
Dieses Setup verbessert die Skalierbarkeit und Leistung bei der Arbeit mit großen Datenmengen.

