### **MongoDB Sharded Cluster Setup Dokumentation**

---

## **Einleitung**

Diese Dokumentation beschreibt den Prozess der Einrichtung eines **sharded MongoDB Clusters** mithilfe von Docker. Alle
Schritte sind detailliert beschrieben, einschließlich der Begründungen für die durchgeführten Maßnahmen, um eine
bestmögliche Skalierbarkeit und Performance für eine produktionsreife Datenbankumgebung sicherzustellen. Dabei wird ein
realistisches Setup mit mehreren Shards und einem Mongos Router verwendet. Die Dokumentation umfasst zudem eine Abwägung
der Vor- und Nachteile von MongoDB Sharding im Vergleich zu anderen Datenbanksystemen.

---

### **Überblick über das Setup**

Unser Cluster besteht aus den folgenden Komponenten:

1. **Config Server**: Verwalten der Metadaten des Clusters und Koordination der Shard-Konfigurationen.
2. **Shards**: Hier werden die tatsächlichen Daten aufgeteilt und gespeichert.
3. **Mongos Router**: Leitet Anfragen der Clients an die passenden Shards weiter, basierend auf dem Sharding-Schlüssel.

Jeder Bestandteil wurde in einem separaten Docker-Container betrieben, und alle Komponenten sind miteinander über ein
eigenes Docker-Netzwerk verbunden.

---

## **Detaillierte Schritt-für-Schritt-Anleitung**

### 1. **Erstellen eines benutzerdefinierten Docker-Netzwerks**

**Warum**: Um sicherzustellen, dass alle MongoDB-Instanzen (Config Server, Shards und Mongos Router) sicher und isoliert
miteinander kommunizieren können, benötigen wir ein eigenes Docker-Netzwerk.

```bash
docker network create mongo-shard-network
```

Dies stellt sicher, dass alle MongoDB-Container im selben Netzwerk laufen und untereinander per DNS-Namen aufrufbar
sind.

### 2. **Konfiguration des Config Servers**

**Warum**: Der Config Server speichert die Metadaten der Sharding-Architektur und verwaltet die Zuweisung der Daten an
die einzelnen Shards. Er ist ein kritischer Bestandteil des Clusters, ohne den die Verteilung der Daten auf die Shards
nicht funktionieren würde.

```bash
docker run -d \
  --name mongo-configsvr \
  --net mongo-shard-network \
  -p 27019:27019 \
  -v "<volume-dir>/configsvr:/data/db" \
  mongo:latest mongod --configsvr --replSet rs0 --port 27019
```

- **`--configsvr`**: Konfiguriert diesen MongoDB-Server als Config Server.
- **`--replSet rs0`**: Konfiguriert diesen Server als Teil eines Replica Sets für Hochverfügbarkeit.

**Initialisierung des Replica Sets**:

```bash
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-configsvr --port 27019 --eval 'rs.initiate({
  _id: "rs0",
  configsvr: true,
  members: [{ _id: 0, host: "mongo-configsvr:27019" }]
})'
```

### 3. **Einrichten der Shards**

**Warum**: Die Shards speichern die tatsächlichen Daten und sind der Kern des Sharding-Prozesses. In unserem Fall haben
wir zwei Shards eingerichtet, um die Daten aufzuteilen.

#### **Einrichten von Shard 1**:

```bash
docker run -d \
  --name mongo-shard1 \
  --net mongo-shard-network \
  -p 27018:27018 \
  -v "<volume-dir>/shard1:/data/db" \
  mongo:latest mongod --shardsvr --replSet shard1 --port 27018
```

- **`--shardsvr`**: Kennzeichnet diesen Server als Shard.
- **`--replSet shard1`**: Konfiguriert diesen Server als Teil eines Replica Sets für Shard 1.

Initialisierung von Shard 1:

```bash
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-shard1 --port 27018 --eval 'rs.initiate({
  _id: "shard1",
  members: [{ _id: 0, host: "mongo-shard1:27018" }]
})'
```

#### **Einrichten von Shard 2**:

Analog zu Shard 1 wird Shard 2 wie folgt eingerichtet:

```bash
docker run -d \
  --name mongo-shard2 \
  --net mongo-shard-network \
  -p 27028:27018 \
  -v "<volume-dir>/shard2:/data/db" \
  mongo:latest mongod --shardsvr --replSet shard2 --port 27018
```

Initialisierung von Shard 2:

```bash
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-shard2 --port 27018 --eval 'rs.initiate({
  _id: "shard2",
  members: [{ _id: 0, host: "mongo-shard2:27018" }]
})'
```

### 4. **Einrichtung des Mongos Routers**

**Warum**: Der Mongos Router leitet Abfragen an die korrekten Shards weiter, basierend auf dem Shard-Schlüssel. Ohne ihn
könnten Clients nicht nahtlos auf die Shards zugreifen.

```bash
docker run -d \
  --name mongo-mongos \
  --net mongo-shard-network \
  -p 27017:27017 \
  mongo:latest mongos --configdb rs0/mongo-configsvr:27019 --bind_ip_all
```

### 5. **Hinzufügen der Shards zum Cluster**

Sobald die Shards konfiguriert und der Mongos Router läuft, müssen wir die Shards zum Cluster hinzufügen:

```bash
docker run --rm --net mongo-shard-network mongo:latest mongosh --host mongo-mongos --port 27017 --eval '
  sh.addShard("shard1/mongo-shard1:27018");
  sh.addShard("shard2/mongo-shard2:27018");
'
```

---

## **Test und Analyse**

### **Testen der Datenverteilung**

#### **Einrichten der Collections mit gehashtem Sharding**

Um zu überprüfen, ob die Daten gleichmäßig verteilt werden, haben wir das Sharding auf den Collections `tb_head`
und `tb_data` aktiviert, wobei wir **gehashtes Sharding** verwendet haben.

1. **Erstellen von Hashed Indizes**:
   Um die Collections zu sharden, haben wir auf den Feldern `head_id` und `data_id` gehashte Indizes erstellt:
   ```javascript
   db.tb_head.createIndex({ "head_id": "hashed" })
   db.tb_data.createIndex({ "data_id": "hashed" })
   ```

2. **Sharding der Collections**:
   Nachdem die Indizes erstellt wurden, haben wir das Sharding aktiviert:
   ```javascript
   sh.shardCollection("test_sharding.tb_head", { "head_id": "hashed" })
   sh.shardCollection("test_sharding.tb_data", { "data_id": "hashed" })
   ```

3. **Einfügen von Testdaten**:
   Um die Verteilung zu testen, haben wir über Java Daten in beide Collections eingefügt. Hier ein Beispiel
   für `tb_head`:
   ```java
   for (int i = 1001; i <= 100000; i++) {
       Document mockData = new Document()
               .append("head_id", i)
               .append("head_name", "HeadName" + i)
               .append("head_period", "2024-Q" + (i % 4 + 1))
               .append("head_revision", i % 10)
               .append("head_status", i % 2 == 0 ? "Active" : "Inactive");

       tbHeadCollection.insertOne(mockData);
   }
   ```

4. **Überprüfung der Verteilung**:
   Wir haben die Verteilung der Daten auf den Shards überprüft:

   Für `tb_head`:
   ```javascript
   db.tb_head.getShardDistribution()
   ```

   Für `tb_data`:
   ```javascript
   db.tb_data.getShardDistribution()
   ```

#### **Ergebnisse der Datenverteilung**

- **tb_head Verteilung**:
   ```javascript
   Shard shard1 at shard1/mongo-shard1:27018
   {
     data: '66KiB',
     docs: 519,
     chunks: 1,
     'estimated data per chunk': '66KiB',
     'estimated docs per chunk': 519
   }
   ---
   Shard shard2 at shard2/mongo-shard2:27018
   {
     data: '61KiB',
     docs: 480,
     chunks: 1,
     'estimated data per chunk': '61KiB',
     'estimated docs per chunk': 480
   }
   ```

- **tb_data Verteilung**:
   ```javascript
   Shard shard2 at shard2/mongo-shard2:27018
   {
     data: '255KiB',
     docs: 2475,
     chunks: 1,
     'estimated data per chunk': '255KiB',
     'estimated docs per chunk': 2475
   }
   ---
   Shard shard1 at shard1/mongo-shard1:27018
   {
     data: '260KiB',
     docs: 2525,
     chunks: 1,
     'estimated data per chunk': '260KiB',
     'estimated docs per chunk': 2525
  }
   ```

### **Analyse**

Durch den Einsatz von **gehashtem Sharding** wurde die Last gleichmäßig auf die beiden Shards verteilt, was die
gleichmäßige Aufteilung der Daten sicherstellt. Beide Shards zeigen eine nahezu identische Anzahl von Dokumenten und
eine ähnliche Datenmenge an, was auf eine erfolgreiche Verteilung hinweist.

### **Testen von Verwandten Daten (tb_head und tb_data)**

##### **Verwandte Daten richtig verteilen: Hashen von `tb_data` auf `head_id`**

Wenn wir sicherstellen möchten, dass die Daten in den Collections `tb_head` und `tb_data`, die über `head_id`
miteinander verknüpft sind, auf denselben Shards gespeichert werden, können wir **`tb_data` auf `head_id` hashen**.
Dadurch wird die gleiche Verteilungslogik wie bei `tb_head` angewendet. Da MongoDB bei gehashten Shard-Keys Daten
basierend auf den Hashwerten verteilt, wird sichergestellt, dass verwandte Dokumente auf denselben Shards gespeichert
werden.

#### **Vorteile des Hashing von `tb_data` auf `head_id`**:

- **Colocation von verwandten Daten**: Wenn sowohl `tb_head` als auch `tb_data` auf `head_id` gehasht werden, landen
  Dokumente mit dem gleichen `head_id` auf **dem gleichen Shard**. Dadurch wird die Performance von Abfragen verbessert,
  die beide Collections abfragen.
- **Effiziente Abfragen**: Bei Abfragen, die auf `head_id` basieren, wird nur ein Shard abgefragt, anstatt mehrere
  Shards durchsuchen zu müssen, was die Latenz reduziert und die Effizienz erhöht.

#### **Umsetzung von `head_id` als Shard-Key in `tb_data`**

1. **Erstellen eines Hashed-Indexes auf `head_id` in `tb_data`**:
   ```javascript
   db.tb_data.createIndex({ "head_id": "hashed" })
   ```

2. **Sharding von `tb_data` mit `head_id` als Shard-Key**:
   ```javascript
   sh.shardCollection("test_sharding.tb_data", { "head_id": "hashed" })
   ```

#### **Ergebnisse der Verteilung**:

1. **Verteilung von `tb_data` (gehasht auf `data_id`)**:
    - **Shard 1**: 50.49% der Daten, 50.5% der Dokumente
    - **Shard 2**: 49.5% der Daten, 49.5% der Dokumente
    - Diese Verteilung ist nahezu gleichmäßig, was durch das Hashen von `data_id` erreicht wurde. Allerdings werden
      damit verwandte Daten, die durch `head_id` verbunden sind, möglicherweise auf verschiedenen Shards gespeichert.

2. **Verteilung von `tb_head` (gehasht auf `head_id`)**:
    - **Shard 1**: 51.94% der Daten, 51.95% der Dokumente
    - **Shard 2**: 48.05% der Daten, 48.04% der Dokumente
    - Auch hier sehen wir eine gleichmäßige Verteilung der Daten. Da `head_id` als Shard-Schlüssel verwendet wird, sind
      die `tb_head`-Daten gut verteilt.

3. **Verteilung von `tb_data_hashed_on_head` (gehasht auf `head_id`)**:
    - **Shard 1**: 52.09% der Daten, 52.1% der Dokumente
    - **Shard 2**: 47.9% der Daten, 47.9% der Dokumente
    - Durch das Hashen von `tb_data` auf `head_id` sehen wir eine ähnliche Verteilung wie bei `tb_head`. Dies stellt
      sicher, dass verwandte Daten in beiden Collections auf denselben Shards gespeichert sind, was die Abfrageeffizienz
      verbessert.

#### **Analyse der Ergebnisse**:

- **Even Distribution**: Die Ergebnisse zeigen eine nahezu gleichmäßige Verteilung der Daten auf den beiden Shards für
  alle drei Collections, was auf die Effektivität des gehashten Shardings hinweist.
- **Verwandte Daten auf denselben Shards**: Durch das Hashen von `tb_data` auf `head_id` (wie in der
  Collection `tb_data_hashed_on_head`) werden verwandte Daten aus `tb_head` und `tb_data` auf denselben Shards
  gespeichert. Dies verbessert die Abfrageleistung bei Abfragen, die beide Collections betreffen, und minimiert die
  Anzahl der abgerufenen Shards.

Durch die Anwendung von **gehashtem Sharding auf `head_id`** in `tb_data_hashed_on_head` wird sichergestellt, dass
Daten, die auf `head_id` basieren, effizienter abgerufen werden können, da verwandte Daten auf denselben Shards liegen.

#### **Vorteile von MongoDB Sharding**

- **Gehashtes Sharding**: Verhindert Hotspots bei der Datenverteilung und sorgt dafür, dass Daten gleichmäßig auf die
  verfügbaren Shards verteilt werden.
- **Balancer**: Automatische Verteilung der Chunks über alle Shards hinweg, um eine gleichmäßige Lastverteilung zu
  gewährleisten.
- **Autosplit**: Automatische Aufteilung von Chunks, wenn sie eine bestimmte Größe erreichen, um sicherzustellen, dass
  die Datenbank skalierbar bleibt.
- **Skalierbarkeit**: MongoDB Sharding ermöglicht das Hinzufügen neuer Shards bei steigendem Datenvolumen, ohne dass die
  Anwendung modifiziert werden muss.

---

## **Fazit**

Durch die Implementierung eines **sharded MongoDB Clusters** mit Docker konnten wir eine leistungsfähige und skalierbare
Lösung zur Verteilung großer Datenmengen auf mehrere Server realisieren. **Gehashtes Sharding** hat sich als besonders
effizient erwiesen, um sicherzustellen, dass die Daten gleichmäßig verteilt und Leistungsengpässe vermieden werden.