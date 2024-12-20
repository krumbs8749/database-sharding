
import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import jakarta.persistence.EntityTransaction;
import jakarta.persistence.Persistence;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.TestInstance;


@TestInstance(TestInstance.Lifecycle.PER_CLASS)
public abstract class BasePerformanceTest {

    protected EntityManagerFactory emf;
    protected EntityManager em;

    @BeforeAll
    public void setupEntityManagerFactory() {
        emf = Persistence.createEntityManagerFactory(getPersistenceUnitName());
    }

    @BeforeEach
    public void setupEntityManager() {
        em = emf.createEntityManager();
        deleteFromTables();
    }

    public void deleteFromTables() {
        EntityTransaction transaction = em.getTransaction();
        transaction.begin();

        // Delete from User table
        int deletedUsers = em.createQuery("DELETE FROM User").executeUpdate();
        System.out.println("Deleted " + deletedUsers + " users from User table.");

        // Add other entities if necessary
        // For example: em.createQuery("DELETE FROM Order").executeUpdate();

        transaction.commit();
    }

    protected abstract String getPersistenceUnitName();
}
