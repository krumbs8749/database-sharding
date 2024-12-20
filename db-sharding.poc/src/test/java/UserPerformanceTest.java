
import com.google.common.collect.Iterables;
import entity.Order;
import entity.User;
import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityTransaction;
import jakarta.persistence.LockModeType;
import org.hibernate.Session;
import org.hibernate.SessionFactory;
import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.stream.Collectors;
import java.util.stream.IntStream;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.testng.AssertJUnit.assertNotNull;

public class UserPerformanceTest extends ShardingSpherePerformanceTest {

    /**
     * 10000 Data sequential test:
     * Shardingsphere performance in ms:
     *      write   : 5062
     *      read    :  320
     *      update  : 4701
     *      delete  : 3384
     * Single DB Postgres performance in ms:
     *       write   : 2961
     *       read    :  215
     *       update  : 2991
     *       delete  : 2696
     * <p>
     * 100000 Data sequential test hibernate, batch:
     * Shardingsphere performance in ms:
     *      write   : 34605
     *      read    :  369
     *      update  : 38346
     *      delete  : 40954
     * Single DB Postgres performance in ms:
     *       write   : 25658
     *       read    :   484
     *       update  : 27114
     *       delete  : 25918
     * <p>
     * 100.000 Data sequential test hibernate fetch=10000 batch=50, batch:
     * Shardingsphere performance in ms:
     *      write   : 4656
     *      read    :  395
     *      update  : 4867
     *      delete  : 2819
     * Single DB Postgres performance in ms:
     *       write   : 2088
     *       read    :  398
     *       update  : 2510
     *       delete  : 1723
     * <p>
     * 1.000.000 Data sequential test hibernate fetch=10000 batch=50, batch:
     * Shardingsphere performance in ms:
     *      write   : 23512
     *      read    :  1830
     *      update  : 37089
     *      delete  : 26228
     * Single DB Postgres performance in ms:
     *       write   : 15895
     *       read    :  1938
     *       update  : 387487
     *       delete  : 16112
     * <p>
     * 10.000.000 Data sequential test hibernate fetch=10000 batch=50, batch:
     * Shardingsphere performance in ms:
     *      write   : 216981
     *      read    :  16618
     *      update  : 387487
     *      delete  :    N/A
     * Single DB Postgres performance in ms:
     *       write   :   N/A
     *       read    :   N/A
     *       update  :   N/A
     *       delete  :   N/A
     */
    @Test
    public void testCRUDPerformance() {
        // Measure insert performance
        int n = 10;
        long insertStart = System.currentTimeMillis();
        em.getTransaction().begin();
        IntStream.range(0, n).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf(i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");
            em.persist(user);

        });
        em.getTransaction().commit();
        long insertEnd = System.currentTimeMillis();
        System.out.println("Insert Performance Time: " + (insertEnd - insertStart) + " ms");

        // Measure read performance: Select all users in a single query
        long readStartAll = System.currentTimeMillis();
        List<User> usersAll = IntStream.range(0, n)
                .mapToObj(i -> em.createQuery("SELECT u FROM User u WHERE u.id = :id", User.class)
                        .setParameter("id",  i)
                        .getSingleResult())
                .collect(Collectors.toList());

        long readEndAll = System.currentTimeMillis();
        System.out.println("Read Performance Time (Select one by one): " + (readEndAll - readStartAll) + " ms");
        assertEquals(n, usersAll.size());

        /*// Measure read performance: Targeting specific shards
        long readStart = System.currentTimeMillis();

        // Assuming your sharding algorithm is `id % numberOfShards`
        int numberOfShards = 2; // Adjust based on your configuration
        Map<Integer, List<Long>> idsByShard = new HashMap<>();

        for (long i = 0; i < n; i++) {
            int shard = (int) (i % numberOfShards);
            idsByShard.computeIfAbsent(shard, k -> new ArrayList<>()).add(i);
        }

        List<User> usersByShard = new ArrayList<>(n);

        em.getTransaction().begin();
        for (Map.Entry<Integer, List<Long>> entry : idsByShard.entrySet()) {
            List<Long> shardIds = entry.getValue();

            // Batch the shard-specific IDs
            int batchSize = 1000; // Adjust batch size as needed
            for (int i = 0; i < shardIds.size(); i += batchSize) {
                List<Long> batch = shardIds.subList(i, Math.min(i + batchSize, shardIds.size()));
                List<User> batchResult = em.createQuery("SELECT u FROM User u WHERE u.id IN :ids", User.class)
                        .setParameter("ids", batch)
                        .getResultList();
                usersByShard.addAll(batchResult);
            }
        }
        em.getTransaction().commit();

        long readEnd = System.currentTimeMillis();
        System.out.println("Read Performance Time (Shard Specific Queries): " + (readEnd - readStart) + " ms");
        assertEquals(n, usersByShard.size());

        // Measure update performance
        long updateStart = System.currentTimeMillis();
        em.getTransaction().begin();
        usersAll.forEach(user -> user.setEmail("updated_" + user.getEmail()));
        em.getTransaction().commit();
        long updateEnd = System.currentTimeMillis();
        System.out.println("Update Performance Time: " + (updateEnd - updateStart) + " ms");

        // Measure delete performance
        long deleteStart = System.currentTimeMillis();
        em.getTransaction().begin();
        usersAll.forEach(em::remove);
        em.getTransaction().commit();
        long deleteEnd = System.currentTimeMillis();
        System.out.println("Delete Performance Time: " + (deleteEnd - deleteStart) + " ms");
*/    }


    @Test
    public void testParallelBatchInsertHibernate() throws InterruptedException {
        int n = 100000;
        int batchSize = 1000; // Number of entities per batch
        int numberOfShards = 2; // ShardingSphere configuration
        int threadCount = numberOfShards; // 1 thread per shard

        // Group entities by shard
        Map<Integer, List<User>> usersByShard = new ConcurrentHashMap<>();
        IntStream.range(0, n).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");

            int shard = (int) (i % numberOfShards); // Sharding logic
            usersByShard.computeIfAbsent(shard, k -> new CopyOnWriteArrayList<>()).add(user);
        });

        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch latch = new CountDownLatch(threadCount);

        long insertStart = System.currentTimeMillis();

        // Process each shard in parallel
        for (Map.Entry<Integer, List<User>> entry : usersByShard.entrySet()) {
            executor.submit(() -> {
                EntityManager em = emf.createEntityManager();
                em.getTransaction().begin();

                try {
                    List<User> shardUsers = entry.getValue();
                    for (int i = 0; i < shardUsers.size(); i++) {
                        em.persist(shardUsers.get(i));

                        // Flush and clear after each batch
                        if (i > 0 && i % batchSize == 0) {
                            em.flush();
                            em.clear();
                        }
                    }

                    // Ensure remaining entities are flushed
                    em.flush();
                    em.clear();

                    em.getTransaction().commit();
                } catch (Exception e) {
                    e.printStackTrace();
                    em.getTransaction().rollback();
                } finally {
                    em.close();
                    latch.countDown();
                }
            });
        }

        latch.await();
        executor.shutdown();
        long insertEnd = System.currentTimeMillis();

        System.out.println("Insert Performance Time (Parallel Batch Insert): " + (insertEnd - insertStart) + " ms");
    }


    @Test
    public void testBatchInsertPerShard() {
        int n = 100000;
        int batchSize = 50; // Adjust based on your environment
        int numberOfShards = 2; // Adjust based on your configuration

        // Group records by shard
        Map<Integer, List<User>> usersByShard = new HashMap<>();
        IntStream.range(0, n).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");

            int shard = (int) (i % numberOfShards);
            usersByShard.computeIfAbsent(shard, k -> new ArrayList<>()).add(user);
        });

        // Insert records shard by shard
        long insertStart = System.currentTimeMillis();
        em.getTransaction().begin();
        for (Map.Entry<Integer, List<User>> entry : usersByShard.entrySet()) {
            List<User> shardUsers = entry.getValue();
            for (int i = 0; i < shardUsers.size(); i += batchSize) {
                List<User> batch = shardUsers.subList(i, Math.min(i + batchSize, shardUsers.size()));

                // Build the batch insert query
                StringBuilder queryBuilder = new StringBuilder("INSERT INTO t_user (id, username, email) VALUES ");
                for (int j = 0; j < batch.size(); j++) {
                    queryBuilder.append("(?, ?, ?)");
                    if (j < batch.size() - 1) {
                        queryBuilder.append(", ");
                    }
                }

                // Create and execute the query
                var query = em.createNativeQuery(queryBuilder.toString());
                int paramIndex = 1;
                for (User user : batch) {
                    query.setParameter(paramIndex++, user.getId());
                    query.setParameter(paramIndex++, user.getUsername());
                    query.setParameter(paramIndex++, user.getEmail());
                }
                query.executeUpdate();
            }
        }
        em.getTransaction().commit();
        long insertEnd = System.currentTimeMillis();

        System.out.println("Insert Performance Time (Batch Insert Per Shard): " + (insertEnd - insertStart) + " ms");
    }
    @Test
    public void testParallelBatchInsertPerShard() throws InterruptedException {
        int n = 100000;
        int batchSize = 50; // Adjust based on your environment
        int numberOfShards = 2; // Adjust based on your configuration

        // Group records by shard
        Map<Integer, List<User>> usersByShard = new HashMap<>();
        IntStream.range(0, n).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");

            int shard = (int) (i % numberOfShards);
            usersByShard.computeIfAbsent(shard, k -> new ArrayList<>()).add(user);
        });

        ExecutorService executor = Executors.newFixedThreadPool(numberOfShards);
        CountDownLatch latch = new CountDownLatch(numberOfShards);

        long insertStart = System.currentTimeMillis();

        // Insert records in parallel for each shard
        for (Map.Entry<Integer, List<User>> entry : usersByShard.entrySet()) {
            executor.submit(() -> {
                EntityManager em = emf.createEntityManager();
                em.getTransaction().begin();

                try {
                    List<User> shardUsers = entry.getValue();
                    for (int i = 0; i < shardUsers.size(); i += batchSize) {
                        List<User> batch = shardUsers.subList(i, Math.min(i + batchSize, shardUsers.size()));

                        // Build the batch insert query
                        StringBuilder queryBuilder = new StringBuilder("INSERT INTO t_user (id, username, email) VALUES ");
                        for (int j = 0; j < batch.size(); j++) {
                            queryBuilder.append("(?, ?, ?)");
                            if (j < batch.size() - 1) {
                                queryBuilder.append(", ");
                            }
                        }

                        // Create and execute the query
                        var query = em.createNativeQuery(queryBuilder.toString());
                        int paramIndex = 1;
                        for (User user : batch) {
                            query.setParameter(paramIndex++, user.getId());
                            query.setParameter(paramIndex++, user.getUsername());
                            query.setParameter(paramIndex++, user.getEmail());
                        }
                        query.executeUpdate();
                    }

                    em.getTransaction().commit();
                } catch (Exception e) {
                    e.printStackTrace();
                    em.getTransaction().rollback();
                } finally {
                    em.close();
                    latch.countDown();
                }
            });
        }

        latch.await();
        executor.shutdown();
        long insertEnd = System.currentTimeMillis();

        System.out.println("Insert Performance Time (Parallel Batch Insert Per Shard): " + (insertEnd - insertStart) + " ms");
    }

    @Test
    public void testBatchInsertWithPreparedStatement() {
        int n = 100000; // Number of records to insert
        int batchSize = 50; // Batch size for inserts

        long insertStart = System.currentTimeMillis();

        // Obtain a JDBC Connection from the Hibernate Session
        try (Session session = em.unwrap(Session.class)) {
            session.doWork(connection -> {
                try (PreparedStatement preparedStatement = connection.prepareStatement(
                        "INSERT INTO t_user (id, username, email) VALUES (?, ?, ?)")) {

                    connection.setAutoCommit(false); // Use manual transaction management for batch processing

                    for (int i = 0; i < n; i++) {
                        preparedStatement.setLong(1, i);
                        preparedStatement.setString(2, "User" + i);
                        preparedStatement.setString(3, "user" + i + "@example.com");
                        preparedStatement.addBatch();

                        if (i % batchSize == 0) {
                            preparedStatement.executeBatch(); // Execute the batch
                            connection.commit(); // Commit the transaction
                        }
                    }

                    // Execute the remaining batch
                    preparedStatement.executeBatch();
                    connection.commit();

                } catch (Exception e) {
                    e.printStackTrace();
                    throw new RuntimeException("Error during batch insert", e);
                }
            });
        }

        long insertEnd = System.currentTimeMillis();
        System.out.println("Insert Performance Time (Prepared Statement): " + (insertEnd - insertStart) + " ms");
    }

    @Test
    public void testParallelBatchInsertWithPreparedStatement() throws InterruptedException {
        int n = 100000; // Number of records to insert
        int batchSize = 50; // Batch size for inserts
        int numberOfShards = 2; // Number of shards (based on your ShardingSphere configuration)

        // Group records by shard
        Map<Integer, List<User>> usersByShard = new ConcurrentHashMap<>();
        IntStream.range(0, n).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");

            int shard = (int) (i % numberOfShards); // Sharding logic based on ID
            usersByShard.computeIfAbsent(shard, k -> new CopyOnWriteArrayList<>()).add(user);
        });

        ExecutorService executor = Executors.newFixedThreadPool(numberOfShards);
        CountDownLatch latch = new CountDownLatch(numberOfShards);

        long insertStart = System.currentTimeMillis();

        // Parallel execution for each shard
        for (Map.Entry<Integer, List<User>> entry : usersByShard.entrySet()) {
            executor.submit(() -> {
                EntityManager em = emf.createEntityManager();
                EntityTransaction transaction = em.getTransaction();
                try {
                    transaction.begin();
                    List<User> shardUsers = entry.getValue();
                    for (int i = 0; i < shardUsers.size(); i += batchSize) {
                        List<User> batch = shardUsers.subList(i, Math.min(i + batchSize, shardUsers.size()));

                        // Prepare and execute batch insert query
                        String sql = "INSERT INTO t_user (id, username, email) VALUES " +
                                batch.stream().map(u -> "(?, ?, ?)").collect(Collectors.joining(", "));
                        var preparedStatement = em.unwrap(Session.class).doReturningWork(connection -> connection.prepareStatement(sql));

                        int paramIndex = 1;
                        for (User user : batch) {
                            preparedStatement.setString(paramIndex++, user.getId());
                            preparedStatement.setString(paramIndex++, user.getUsername());
                            preparedStatement.setString(paramIndex++, user.getEmail());
                        }

                        preparedStatement.executeUpdate();
                    }

                    transaction.commit();
                } catch (Exception e) {
                    e.printStackTrace();
                    if (transaction.isActive()) {
                        transaction.rollback();
                    }
                } finally {
                    em.close();
                    latch.countDown();
                }
            });
        }

        latch.await();
        executor.shutdown();
        long insertEnd = System.currentTimeMillis();

        System.out.println("Insert Performance Time (Parallel Prepared Statement): " + (insertEnd - insertStart) + " ms");
    }



    @Test
    public void testBulkCRUDPerformanceWithWhereIn() {
        int totalRecords = 20; // Total number of records to process
        int batchSize = 5; // Batch size for WHERE IN and persistence

        List<User> existingUsers = new ArrayList<>();
        List<User> newUsers = new ArrayList<>();

        // Step 1: Generate and persist some existing users
        int existingUserCount = 5; // Half of the records already exist
        em.getTransaction().begin();
        for (int i = 0; i < existingUserCount; i++) {
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("ExistingUser" + i);
            user.setEmail("existing" + i + "@example.com");
            em.persist(user);
            existingUsers.add(user);

            if (i % batchSize == 0) {
                em.flush();
                em.clear();
            }
        }
        em.getTransaction().commit();
        System.out.println("Existing users persisted: " + existingUserCount);

        // Step 2: Prepare all records to process (both new and existing IDs)
        List<Long> allUserIds = new ArrayList<>();
        for (int i = 0; i < totalRecords; i++) {
            allUserIds.add((long) i);
        }

        // Step 3: Fetch Existing Records Using WHERE IN
        long fetchStart = System.currentTimeMillis();
        Map<String, User> existingUserMap = new HashMap<>();
        for (List<Long> idBatch : Iterables.partition(allUserIds, batchSize)) {
            List<User> fetchedUsers = em.createQuery(
                            "SELECT u FROM User u WHERE u.id IN :ids", User.class)
                    .setParameter("ids", idBatch)
                    .getResultList();

            fetchedUsers.forEach(user -> existingUserMap.put(user.getId(), user));
        }
        long fetchEnd = System.currentTimeMillis();
        System.out.println("Fetch Performance Time: " + (fetchEnd - fetchStart) + " ms");

        // Step 4: Identify and Insert New Users
        for (Long id : allUserIds) {
            if (!existingUserMap.containsKey(id)) {
                User user = new User();
                user.setId(String.valueOf(id));
                user.setUsername("NewUser" + id);
                user.setEmail("new" + id + "@example.com");
                newUsers.add(user);
            }
        }
        System.out.println("New users identified: " + newUsers.size());

        long insertStart = System.currentTimeMillis();
        em.getTransaction().begin();
        for (int i = 0; i < newUsers.size(); i++) {
            em.persist(newUsers.get(i));
            if (i % batchSize == 0) {
                em.flush();
                em.clear();
            }
        }
        em.getTransaction().commit();
        long insertEnd = System.currentTimeMillis();
        System.out.println("Insert Performance Time: " + (insertEnd - insertStart) + " ms");

        // Step 5: Read All Users in Batches
        long readStart = System.currentTimeMillis();
        int readCount = 0;
        for (int i = 0; i < totalRecords; i += batchSize) {
            List<User> users = em.createQuery(
                            "SELECT u FROM User u WHERE u.id BETWEEN :start AND :end", User.class)
                    .setParameter("start", (long) i)
                    .setParameter("end", (long) Math.min(i + batchSize - 1, totalRecords - 1))
                    .getResultList();
            readCount += users.size();
        }
        long readEnd = System.currentTimeMillis();
        System.out.println("Read Performance Time: " + (readEnd - readStart) + " ms");
        System.out.println("Total Users Read: " + readCount);

        // Step 6: Update Users in Batches
        long updateStart = System.currentTimeMillis();
        em.getTransaction().begin();
        for (int i = 0; i < totalRecords; i += batchSize) {
            em.createQuery("UPDATE User u SET u.email = CONCAT(u.email, '_updated') " +
                            "WHERE u.id BETWEEN :start AND :end")
                    .setParameter("start", (long) i)
                    .setParameter("end", (long) Math.min(i + batchSize - 1, totalRecords - 1))
                    .executeUpdate();
        }
        em.getTransaction().commit();
        long updateEnd = System.currentTimeMillis();
        System.out.println("Update Performance Time: " + (updateEnd - updateStart) + " ms");

        // Step 7: Delete Users in Batches
        long deleteStart = System.currentTimeMillis();
        em.getTransaction().begin();
        for (int i = 0; i < totalRecords; i += batchSize) {
            em.createQuery("DELETE FROM User u WHERE u.id BETWEEN :start AND :end")
                    .setParameter("start", (long) i)
                    .setParameter("end", (long) Math.min(i + batchSize - 1, totalRecords - 1))
                    .executeUpdate();
        }
        em.getTransaction().commit();
        long deleteEnd = System.currentTimeMillis();
        System.out.println("Delete Performance Time: " + (deleteEnd - deleteStart) + " ms");
    }

    @Test
    public void testHighConcurrencyCRUDWithPessimisticLockAndLogging() throws InterruptedException {
        int threadCount = 10; // Number of concurrent threads
        int operationsPerThread = 10; // Number of operations per thread
        int totalRecords = threadCount * operationsPerThread;

        System.out.println("Starting High-Concurrency CRUD Test");
        System.out.println("Threads: " + threadCount + ", Operations Per Thread: " + operationsPerThread + ", Total Records: " + totalRecords);

        // Step 1: Insert Initial Data
        System.out.println("Step 1: Inserting Initial Data...");
        long insertStart = System.currentTimeMillis();
        em.getTransaction().begin();
        IntStream.range(0, totalRecords).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf(i));
            user.setUsername("ConcurrentUser" + i);
            user.setEmail("user" + i + "@example.com");
            em.persist(user);

            // Batch flush and clear
            if (i % 500 == 0) {
                em.flush();
                em.clear();
                System.out.println("Inserted " + (i + 1) + " records so far...");
            }
        });
        em.getTransaction().commit();
        long insertEnd = System.currentTimeMillis();
        System.out.println("Initial Data Inserted: " + totalRecords + " records in " + (insertEnd - insertStart) + " ms");

        // Step 2: Concurrent Reads, Updates, and Deletes
        System.out.println("Step 2: Performing Concurrent CRUD Operations...");
        long crudStart = System.currentTimeMillis();
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        CountDownLatch latch = new CountDownLatch(threadCount);

        for (int t = 0; t < threadCount; t++) {
            int threadIndex = t;
            executor.submit(() -> {
                EntityManager threadEm = emf.createEntityManager(); // Thread-specific EntityManager
                threadEm.getTransaction().begin();

                System.out.println("Thread " + threadIndex + " started operations...");
                IntStream.range(0, operationsPerThread).forEach(i -> {
                    int id = (int) (Math.random() * totalRecords);

                    try {
                        // Concurrent Read with Pessimistic Locking
                        User user = threadEm.find(User.class, (long) id, LockModeType.PESSIMISTIC_WRITE);

                        if (user != null) {
                            // Log read operation
                            System.out.println("Thread " + threadIndex + " read user: " + user.getId());

                            // Concurrent Update
                            user.setEmail("updated_" + user.getEmail());
                            System.out.println("Thread " + threadIndex + " updated user: " + user.getId());

                            // Concurrent Delete (25% chance)
                            if (Math.random() < 0.25) {
                                threadEm.remove(user);
                                System.out.println("Thread " + threadIndex + " deleted user: " + user.getId());
                            }
                        }
                    } catch (Exception e) {
                        System.err.println("Thread " + threadIndex + " encountered error on ID " + id + ": " + e.getMessage());
                    }

                    // Commit transaction in batches
                    if (i % 100 == 0) {
                        threadEm.getTransaction().commit();
                        threadEm.getTransaction().begin();
                        System.out.println("Thread " + threadIndex + " committed batch of 100 operations...");
                    }
                });

                threadEm.getTransaction().commit();
                threadEm.close();
                System.out.println("Thread " + threadIndex + " completed all operations.");
                latch.countDown();
            });
        }

        latch.await();
        executor.shutdown();
        long crudEnd = System.currentTimeMillis();
        System.out.println("Concurrent CRUD Operations Completed in " + (crudEnd - crudStart) + " ms");

        // Step 3: Final Data Validation
        System.out.println("Step 3: Validating Remaining Data...");
        long validationStart = System.currentTimeMillis();
        long remainingCount = em.createQuery("SELECT COUNT(u) FROM User u", Long.class).getSingleResult();
        long validationEnd = System.currentTimeMillis();
        System.out.println("Remaining Records After High-Concurrency Test: " + remainingCount);
        System.out.println("Data Validation Completed in " + (validationEnd - validationStart) + " ms");
        System.out.println("High-Concurrency CRUD Test Completed Successfully.");
    }

    @Test
    public void testShardingsphereEqualityOrQueries() {
        // Step 1: Insert sample data for testing
        em.getTransaction().begin();

        IntStream.range(1, 10).forEach(i -> {
            // Insert Users
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");
            em.persist(user);

        });

        em.getTransaction().commit();

        // Step 2: Query Users with specific IDs
        List<Long> userIds =  List.of(1L, 4L, 3L);
        String userQuery = "SELECT u FROM User u WHERE u.id = :id1 OR u.id = :id2 OR u.id = :id3";
        List<User> users = em.createQuery(userQuery, User.class)
                .setParameter("id1", userIds.get(0))
                .setParameter("id2", userIds.get(1))
                .setParameter("id3", userIds.get(2))
                .getResultList();

        System.out.println("Users with IDs:");
        users.forEach(user -> System.out.println(user.getUsername()));



    }

    @Test
    public void testParallelShardedReads() throws InterruptedException {
        int n = 100000; // Total records
        int threadCount = 2; // Number of threads (matches shards)
        int shardCount = 2; // Number of shards
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);

        // Step 1: Insert data
        System.out.println("Step 1: Inserting data...");
        EntityManager em = emf.createEntityManager();
        em.getTransaction().begin();
        IntStream.range(0, n).forEach(i -> {
            User user = new User();
            user.setId(String.valueOf((long) i));
            user.setUsername("User" + i);
            user.setEmail("user" + i + "@example.com");
            em.persist(user);
            if (i % 2 == 0) { // Adjust batch size
                em.flush();
                em.clear();
            }

        });
        em.getTransaction().commit();
        em.getTransaction().commit();
        em.close();
        System.out.println("Data insertion completed.");

        // Step 2: Parallel reads
        System.out.println("Step 2: Executing parallel reads...");
        List<Future<Long>> readTasks = new ArrayList<>();
        long readStart = System.currentTimeMillis();

        for (int shard = 0; shard < shardCount; shard++) {
            final int shardId = shard;
            readTasks.add(executor.submit(() -> {
                EntityManager threadEm = emf.createEntityManager();
                long shardReadStart = System.currentTimeMillis();
                List<?> results = threadEm.createNativeQuery("SELECT * FROM t_user WHERE id % 2 = :shard")
                        .setParameter("shard", shardId)
                        .getResultList();
                threadEm.close();
                long shardReadEnd = System.currentTimeMillis();
                System.out.println("Shard " + shardId + " read time: " + (shardReadEnd - shardReadStart) + " ms, Records: " + results.size());
                return (shardReadEnd - shardReadStart);
            }));
        }

        executor.shutdown();
        executor.awaitTermination(10, TimeUnit.MINUTES);
        long readEnd = System.currentTimeMillis();

        // Aggregate results
        long totalReadTime = 0;
        for (Future<Long> task : readTasks) {
            try {
                totalReadTime += task.get();
            } catch (ExecutionException e) {
                e.printStackTrace();
            }
        }
        System.out.println("Parallel Sharded Reads Completed in " + (readEnd - readStart) + " ms");
        System.out.println("Total Shard Read Time: " + totalReadTime + " ms");
    }


    @Test
    public void testInsertAndQuery() {
        User user = new User();
        user.setId("0"); // Ensure ID matches the sharding key logic
        user.setUsername("User1");
        user.setEmail("test_email@example.com");
        em.getTransaction().begin();
        em.persist(user);
        em.flush();
        em.getTransaction().commit();

        // Query by username
        User queriedUser = em.createQuery(
                        "SELECT u FROM User u WHERE u.id = :username", User.class)
                .setParameter("username", "0")
                .getSingleResult();

        assertNotNull(queriedUser);
        assertEquals("User1", queriedUser.getUsername());
    }




}
