package org.mysql;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

public class ParallelRequestTest {
    private static final String URL = "jdbc:mysql://localhost:3306/test_keyspace";
    private static final String USER = "root";
    private static final String PASSWORD = "root";

    public static void main(String[] args) {
        // Simulate three parallel requests
        Thread t1 = new Thread(() -> queryHeadById(3));
        Thread t2 = new Thread(() -> queryHeadById(7728));
        Thread t3 = new Thread(() -> queryHeadById(1024));

        t1.start();
        t2.start();
        t3.start();
    }

    private static void queryHeadById(int headId) {
        try (Connection conn = DriverManager.getConnection(URL, USER, PASSWORD)) {
            String sql = "SELECT head_id, head_name FROM tb_head WHERE head_id = ?";
            try (PreparedStatement ps = conn.prepareStatement(sql)) {
                ps.setInt(1, headId);
                ResultSet rs = ps.executeQuery();
                while (rs.next()) {
                    System.out.println("Thread " + Thread.currentThread().getId() + ": head_id = " + rs.getInt("head_id") + ", head_name = " + rs.getString("head_name"));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
