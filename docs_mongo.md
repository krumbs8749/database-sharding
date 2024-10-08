### MongoDB Sharded Cluster Setup Dokumentation

---

## **Einleitung**

Diese Dokumentation beschreibt den Prozess der Einrichtung eines **sharded MongoDB Clusters** mithilfe von Docker. Alle Schritte sind detailliert beschrieben, einschließlich der Begründungen für die durchgeführten Maßnahmen, um eine bestmögliche Skalierbarkeit und Performance für eine produktionsreife Datenbankumgebung sicherzustellen. Dabei wird ein realistisches Setup mit mehreren Shards und einem Mongos Router verwendet. Die Dokumentation umfasst zudem eine Abwägung der Vor- und Nachteile von MongoDB Sharding im Vergleich zu anderen Datenbanksystemen.

---

### **Überblick über das Setup**

Unser Cluster besteht aus den folgenden Komponenten:
1. **Config Server**: Verwalten der Metadaten des Clusters und Koordination der Shard-Konfigurationen.
2. **Shards**: Hier werden die tatsächlichen Daten aufgeteilt und gespeichert.
3. **Mongos Router**: Leitet Anfragen der Clients an die passenden Shards weiter, basierend auf dem Sharding-Schlüssel.

Jeder Bestandteil wurde in einem separaten Docker-Container betrieben, und alle Komponenten sind miteinander über ein eigenes Docker-Netzwerk verbunden.

---

## **Detaillierte Schritt-für-Schritt-Anleitung**

### 1. **Erstellen eines benutzerdefinierten Docker-Netzwerks**

**Warum**: Um sicherzustellen, dass alle MongoDB-Instanzen (Config Server, Shards und Mongos Router) sicher und isoliert miteinander kommunizieren können, benötigen wir ein eigenes Docker-Netzwerk.

```bash
docker network create mongo-shard-network
```

Dies stellt sicher, dass alle MongoDB-Container im selben Netzwerk laufen und untereinander per DNS-Namen aufrufbar sind.

### 2. **Konfiguration des Config Servers**

**Warum**: Der Config Server speichert die Metadaten der Sharding-Architektur und verwaltet die Zuweisung der Daten an die einzelnen Shards. Er ist ein kritischer Bestandteil des Clusters, ohne den die Verteilung der Daten auf die Shards nicht funktionieren würde.

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

**Warum**: Die Shards speichern die tatsächlichen Daten und sind der Kern des Sharding-Prozesses. In unserem Fall haben wir zwei Shards eingerichtet, um die Daten aufzuteilen.

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

**Warum**: Der Mongos Router leitet Abfragen an die korrekten Shards weiter, basierend auf dem Shard-Schlüssel. Ohne ihn könnten Clients nicht nahtlos auf die Shards zugreifen.

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

## **Überprüfung und Tests**

### 1. **Überprüfung des Sharding-Status**

Um sicherzustellen, dass das Cluster korrekt eingerichtet ist, prüfen wir den Status des Shardings:

```bash
docker exec -it mongo-mongos mongosh --eval "sh.status()"
```

Der Status zeigt die aktiven Shards, den Zustand des Balancers und die Datenverteilung zwischen den Shards.

### 2. **Testen der Datenverteilung**

Nach der Aktivierung des Shardings auf einer Datenbank kann die Datenverteilung getestet werden. Ein Beispiel für das Hinzufügen von Daten in eine gesharde Sammlung:

```javascript
use myShardedDB
sh.enableSharding("myShardedDB")
sh.shardCollection("myShardedDB.users", { "userId": "hashed" })

db.users.insert({ userId: 1, name: "Alice" })
db.users.insert({ userId: 2, name: "Bob" })
db.users.insert({ userId: 3, name: "Charlie" })
```

Die Verteilung der Daten auf die Shards kann anschließend überprüft werden:
```javascript
db.users.getShardDistribution()
```

---

## **Sicherheitskonfiguration**

**Warum**: MongoDB sollte standardmäßig nicht ohne Authentifizierung betrieben werden, um die Daten vor unbefugtem Zugriff zu schützen. In der Produktionsumgebung sollte Authentifizierung und Verschlüsselung implementiert werden.

### 1. **Einrichten von Benutzern**

Zunächst legen wir einen Admin-Benutzer an:
```javascript
use admin
db.createUser({
  user: "admin",
  pwd: "password",
  roles: [ { role: "root", db: "admin" } ]
})
```


## **Fazit**

Die Einrichtung eines MongoDB Sharded Clusters bietet eine leistungsstarke Lösung zur Skalierung großer Datenbanken. Durch die Verteilung der Daten über mehrere Shards wird die Last auf den Servern reduziert und die Verfügbarkeit

der Datenbank erhöht. Allerdings ist diese Architektur nicht ohne Herausforderungen, und es ist entscheidend, die richtige Konfiguration vorzunehmen, um Performance-Probleme und Dateninkonsistenzen zu vermeiden.

Durch die Implementierung der beschriebenen Sicherheitsmaßnahmen und die Wahl eines geeigneten Shard Keys kann ein robustes und skalierbares Datenbanksetup realisiert werden, das den Anforderungen moderner Anwendungen gerecht wird.

