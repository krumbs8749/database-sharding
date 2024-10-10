# Umfassende Dokumentation über Vitess und MySQL Cluster

## Einführung

In diesem Dokument wird ein detaillierter Überblick über Vitess und MySQL Cluster gegeben, zwei leistungsstarke Lösungen zur Verwaltung von großen MySQL-Datenbanken. Es wird die Architektur, die Verarbeitung von Anfragen und die Schritte beschrieben, die unternommen wurden, um MySQL Cluster in einer Docker-Umgebung einzurichten. Außerdem werden die Herausforderungen mit Vitess sowie die erfolgreiche Implementierung von MySQL Cluster behandelt.

## Vitess-Architektur

Vitess ist ein Datenbank-Cluster-System, das für das horizontale Skalieren von MySQL entwickelt wurde. Es fungiert als Middleware und bietet Sharding, Lastverteilung und Abfrageweiterleitung.

### Wichtige Komponenten von Vitess:
1. **vtgate**: Die Routing-Schicht, die SQL-Abfragen entgegennimmt und sie basierend auf einem Sharding-Schlüssel an das entsprechende Shard weiterleitet.
2. **vttablet**: Verwalten von einzelnen MySQL-Instanzen, die Replikation und Failover übernehmen. Jedes vttablet entspricht einem Shard.
3. **Topologie-Server**: Nutzt etcd oder Zookeeper zur Speicherung von Metadaten über Shards, was eine dynamische Skalierung ermöglicht.

### Sharding-Mechanismus:
Vitess verwendet einen hash-basierten oder range-basierten Sharding-Mechanismus, um Daten über mehrere MySQL-Instanzen zu verteilen. Die Daten werden in MySQL-Knoten gespeichert, wobei jeder Knoten für einen bestimmten Shard verantwortlich ist. Dies ermöglicht eine effiziente Verarbeitung großer Datenmengen und verbessert die Leistung durch die Aufteilung der Daten in handhabbare Teile.

### Herausforderung mit Vitess:
Bei der Installation von Vitess traten Probleme auf, da Docker-Container häufig abstürzten. Dies führte zu einer instabilen Umgebung, in der die Verwaltung der Knoten und die Verbindungen zwischen ihnen nicht zuverlässig waren.

## MySQL Cluster-Architektur

MySQL Cluster ist eine verteilte Datenbankarchitektur, die eine hohe Verfügbarkeit und Skalierbarkeit bietet. Es besteht aus mehreren Knoten, die zusammenarbeiten, um Daten zu speichern und Anfragen zu verarbeiten.

### Wichtige Komponenten von MySQL Cluster:
1. **Management Server (ndb_mgmd)**: Verwaltet die Clusterkonfiguration und -knoten. Dieser Server ist verantwortlich für das Hinzufügen und Entfernen von Knoten im Cluster.
2. **Datenknoten (ndbd)**: Speichern die Daten und sind für die Verarbeitung von Lese- und Schreiboperationen zuständig. Diese Knoten sind verantwortlich für die Speicherung von Daten in partitionierter Form.
3. **SQL-Knoten (mysqld)**: Bieten eine SQL-Schnittstelle für Anwendungen, um auf die im Cluster gespeicherten Daten zuzugreifen. Diese Knoten verarbeiten SQL-Anfragen und leiten sie an die entsprechenden Datenknoten weiter.

### Datenverarbeitungsschritte:
1. **Anfrage an SQL-Knoten**: Wenn eine Anwendung eine SQL-Anfrage stellt, wird sie an den SQL-Knoten weitergeleitet.
2. **Routing zu Datenknoten**: Der SQL-Knoten überprüft die Cluster-Metadaten, um herauszufinden, welche Datenknoten die relevanten Partitionen speichern.
3. **Datenoperation**: Der SQL-Knoten führt die Anfrage an die entsprechenden Datenknoten aus, die dann die Daten zurück an den SQL-Knoten senden.
4. **Antwort an die Anwendung**: Der SQL-Knoten gibt das Ergebnis der Anfrage an die Anwendung zurück.

## Schritte zur Einrichtung von MySQL Cluster

Die folgenden Schritte wurden unternommen, um MySQL Cluster erfolgreich in einer Docker-Umgebung einzurichten:

1. **Erstellen des Docker-Netzwerks**: Ein benutzerdefiniertes Docker-Netzwerk wurde mit der Subnetzmaske 192.168.0.0/16 erstellt.
   ```bash
   docker network create mysql-cluster --subnet=192.168.0.0/16
   ```

2. **Starten der Management-Server**: Der Management-Server (`mysql-mgm`) wurde mit einem konfigurierten Init-Skript gestartet, um die Cluster-Metadaten zu speichern.
   ```bash
   docker run -d --name mysql-mgm --net=mysql-cluster -e MYSQL_ROOT_PASSWORD=root mysql/mysql-cluster:8.0 ndb_mgmd
   ```

3. **Starten der Datenknoten**: Zwei Datenknoten (`mysql-ndb1` und `mysql-ndb2`) wurden erstellt, um die Daten zu speichern.
   ```bash
   docker run -d --net=mysql-cluster --name=mysql-ndb1 mysql/mysql-cluster:8.0 ndbd
   docker run -d --net=mysql-cluster --name=mysql-ndb2 mysql/mysql-cluster:8.0 ndbd
   ```

4. **Starten des SQL-Knotens**: Der SQL-Knoten (`mysql-sql`) wurde gestartet, um Anfragen von Anwendungen entgegenzunehmen.
   ```bash
   docker run -d --net=mysql-cluster --name=mysql-sql -e MYSQL_ROOT_PASSWORD=root mysql/mysql-cluster:8.0 mysqld
   ```

5. **Überprüfen der Clusterkonfiguration**: Die Konfiguration und der Status der Knoten wurden mithilfe des Befehls `ndb_mgm -e show` überprüft.

## Testergebnisse

Im Rahmen der Tests wurden 2000 Datensätze in die Tabelle `tb_head` und 15000 Datensätze in die Tabelle `tb_data` eingefügt. Die resultierenden Verteilungen zeigten, dass die Daten gleichmäßig auf die Partitionen verteilt waren, was die Leistung und Effizienz der Abfragen verbesserte. Der Speicherstatus der Knoten wurde mit dem Befehl `ndb_mgm> ALL REPORT MEMORYUSAGE` überprüft, um sicherzustellen, dass die Knoten optimal arbeiten.

### Beispiel für die Verteilung:
```plaintext
Node 2: Data usage is 2%(92 32K pages of total 3124)
Node 3: Data usage is 2%(93 32K pages of total 3124)
```

## Analyse der MySQL Cluster

Obwohl `ndb_desc` aufgrund von Verbindungsproblemen nicht erfolgreich ausgeführt werden konnte, konnten einige wichtige Informationen über die Tabellen und Partitionen abgerufen werden:

- Die Abfrage `SELECT partition_name, table_name, partition_ordinal_position, table_rows FROM INFORMATION_SCHEMA.PARTITIONS` lieferte Aufschluss darüber, wie viele Zeilen in den Partitionen der Tabellen `tb_head` und `tb_data` gespeichert sind.
- Die Abfrage `SELECT * FROM ndbinfo.memoryusage` lieferte Informationen über die Speichernutzung der Knoten.

## Fazit

In diesem Dokument haben wir die Herausforderungen und Erfolge bei der Implementierung von MySQL Cluster in einer Docker-Umgebung behandelt. Während Vitess bei der Einrichtung auf Probleme stieß, zeigte MySQL Cluster eine robuste Leistung und effektive Datenverarbeitung. Die durchgeführten Tests bestätigten die Verteilung und Effizienz der Daten. MySQL Cluster bietet eine flexible und skalierbare Lösung für datenintensive Anwendungen.