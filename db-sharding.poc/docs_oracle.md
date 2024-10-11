### Dokumentation des Oracle Sharding Setups und Analyse der Engpässe

#### Ziel des Setups:

Das Ziel des Projekts war die Einrichtung eines Oracle Sharding-Systems mit mehreren Shard-Datenbanken, einem
Shard-Katalog und einem Global Shard Manager (GSM) in einer containerisierten Umgebung unter Docker.

#### Step-by-Step Setup und Problemstellen:

---

### **1. Vorbereitung der Docker-Container**

Zunächst wurde eine Umgebung mit mehreren Docker-Containern vorbereitet, die die verschiedenen Datenbankkomponenten
hosten sollten.

**Schritte:**

- Bereitstellung der Docker-Container für:
    - Den Shard-Katalog (`oracle-shard-catalog`)
    - Die beiden Shards (`oracle-shard1`, `oracle-shard2`)
    - Den Global Shard Manager (`oracle-gsm1`)

**Ergebnis:**  
Alle Container wurden erfolgreich gestartet und waren betriebsbereit. Docker-Netzwerke waren korrekt eingerichtet, und
die Container waren über dieselbe virtuelle Netzwerkumgebung verbunden.

**Problem:**  
Hier gab es keine unmittelbaren Probleme.

---

### **2. Listener und TNS Konfiguration**

Um die Kommunikation zwischen den Containern sicherzustellen, mussten die `listener.ora` und `tnsnames.ora` Dateien in
den Containern angepasst werden.

**Schritte:**

- Konfiguration der `listener.ora` und `tnsnames.ora` in den entsprechenden Verzeichnissen der Oracle-Datenbanken.
- Verwenden von `tnsping`, um sicherzustellen, dass die Shard-Datenbanken und der Katalog korrekt kommunizieren.

**Ergebnis:**  
Die Listener und TNS-Konfiguration wurde erfolgreich abgeschlossen. Die `tnsping`-Befehle zeigten an, dass der
Shard-Katalog und die Shards ordnungsgemäß auf die Verbindungen antworteten.

**Problem:**  
Es traten keine größeren Probleme in diesem Schritt auf, aber kleinere Anpassungen der Konfigurationsdateien waren
notwendig, um sicherzustellen, dass die IP-Adressen und Ports korrekt waren.

---

### **3. Benutzerverwaltung und Berechtigungen (GSMCATUSER)**

Ein wiederkehrendes Problem betraf den `GSMCATUSER`-Benutzer, der für die Verwaltung des Shard-Katalogs verantwortlich
ist.

**Schritte:**

- Wiederholtes Entsperren des `GSMCATUSER`-Kontos in der Container-Datenbank (`oracle-shard-catalog`).
- Ändern des Passworts und sicherstellen, dass der Benutzer in allen Containern (CDB und PDB) entsperrt und korrekt
  eingerichtet ist.

```sql
ALTER
USER GSMCATUSER ACCOUNT UNLOCK;
ALTER
USER GSMCATUSER IDENTIFIED BY new_password ACCOUNT UNLOCK;
```

**Ergebnis:**  
Der Benutzer wurde erfolgreich entsperrt, und das Passwort wurde in der CDB und PDB aktualisiert.

**Problem:**  
Das Konto wurde mehrfach gesperrt, was den Fortschritt verzögerte. Es war notwendig, den Benutzer in mehreren Containern
und Umgebungen zu entsperren, was zusätzlichen Aufwand bedeutete. Dieses Problem trat wiederholt auf und sorgte für
signifikante Verzögerungen.

---

### **4. Einrichtung des Shard-Katalogs mit GDSCTL**

Die Verwendung von `GDSCTL` zur Einrichtung des Katalogs war der nächste Schritt. Hier traten jedoch mehrere Probleme
auf.

**Schritte:**

- Verbindung mit der Katalogdatenbank mit `GDSCTL` und Erstellung des Shard-Katalogs:
  ```bash
  GDSCTL> create catalog -database CATCDB;
  ```
- Registrierung des GSM mit dem Katalog:
  ```bash
  GDSCTL> add gsm -gsm sharddirector1 -listener 1522 -pwd new_password -catalog oshard-catalog-0:1521/CAT1PDB -region region1;
  ```

**Ergebnis:**  
Die Registrierung des Katalogs schlug fehl, da `GDSCTL` mehrmals meldete, dass der Katalog nicht korrekt konfiguriert
war, und SQL-Fehler auftraten.

**Problem:**

- **Fehlerhafte Katalogkonfiguration:** Die Fehler,
  wie `ORA-03739: The specified database is not configured to be a catalog`, zeigten an, dass die Katalogdatenbank nicht
  ordnungsgemäß als Shard-Katalog konfiguriert war. Dies verhinderte, dass der Katalog korrekt mit dem GSM verbunden
  wurde.
- **Doppelte Katalogerstellung:** Versuche, den Katalog erneut zu erstellen, führten zu Fehlern, die besagten, dass der
  Katalog bereits existierte, obwohl die Konfiguration fehlerhaft war.

---

### **5. Fehler beim Verwalten des Shard-Katalogs**

Trotz erfolgreicher Registrierung des `GSMCATUSER`-Benutzers konnte der Shard-Katalog nicht korrekt erstellt oder
verwaltet werden.

**Schritte:**

- Validierung des Katalogs über `GDSCTL`:
  ```bash
  GDSCTL> validate catalog;
  ```

**Ergebnis:**  
Die Validierung des Katalogs führte zu Fehlern wie `GSM-45035: GDS catalog exception`, was darauf hindeutete, dass der
Katalog nicht vollständig oder korrekt eingerichtet wurde.

**Problem:**

- **Katalogvalidierung schlug fehl:** Trotz erfolgreicher Verbindung des `GSMCATUSER`-Benutzers mit der Katalogdatenbank
  blieben die GDSCTL-Validierungsfehler bestehen.
- **Datenbankkonfiguration:** Die Fehler, die auf eine fehlerhafte Katalogkonfiguration hindeuteten, deuteten auf eine
  tiefere Konfigurationsinkonsistenz hin, die nicht leicht zu beheben war.

---

### **6. Schwierigkeiten bei der GSM-Registrierung**

Ein weiterer Engpass trat bei der Registrierung des Global Shard Managers (GSM) auf.

**Schritte:**

- Versuch, den GSM mit dem Katalog zu verbinden, um die Shard-Gruppen zu verwalten:
  ```bash
  GDSCTL> add gsm -gsm sharddirector1 -listener 1522 -pwd new_password -catalog oshard-catalog-0:1521/CAT1PDB -region region1;
  ```

**Ergebnis:**  
Die Registrierung des GSM schlug mit der
Fehlermeldung `ORA-03739: The specified database is not configured to be a catalog` fehl. Dies verhinderte die weitere
Verwaltung der Shards über den GSM.

**Problem:**

- **Ungültige Katalogverbindung:** Die GSM-Registrierung konnte nicht abgeschlossen werden, da der Shard-Katalog nicht
  ordnungsgemäß eingerichtet war. Die Shard-Gruppen konnten daher nicht korrekt verwaltet werden.

---

### Zusammenfassung der Engpässe:

1. **Benutzerprobleme (`GSMCATUSER`)**:
    - Wiederholte Sperrungen des `GSMCATUSER`-Benutzers führten zu Verzögerungen und erforderten manuelle Entsperrungen
      und Passwortänderungen. Dieses Problem trat mehrmals auf und unterbrach den Fortschritt.

2. **Fehlerhafte Katalogkonfiguration**:
    - Trotz mehrfacher Versuche konnte der Shard-Katalog nicht korrekt eingerichtet werden. Dies führte zu Fehlern bei
      der Verwendung von `GDSCTL`, insbesondere bei der Validierung und Registrierung des Katalogs.

3. **Probleme bei der Registrierung des Global Shard Managers (GSM)**:
    - Die fehlerhafte Katalogkonfiguration verhinderte, dass der GSM erfolgreich mit dem Katalog verbunden werden
      konnte. Dadurch konnte die Shard-Verwaltung nicht wie geplant erfolgen.

---

### Schlussfolgerung:

Das Oracle Sharding Setup stieß auf mehrere schwerwiegende Engpässe, die hauptsächlich auf Benutzerprobleme (Sperrungen
und Berechtigungen) und eine fehlerhafte Katalogkonfiguration zurückzuführen sind. Die Netzwerkkonfiguration und
Listener-Einstellungen funktionierten weitgehend, aber die korrekte Einrichtung des Shard-Katalogs bleibt der
Hauptbottleneck im gesamten Prozess.