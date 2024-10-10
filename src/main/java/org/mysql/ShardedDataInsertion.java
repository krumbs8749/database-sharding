package org.mysql;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.util.Random;

public class ShardedDataInsertion {
    
    private static final String URL = "jdbc:mysql://localhost:3306/test_keyspace";
    private static final String USER = "root";
    private static final String PASSWORD = "root";

    public static void main(String[] args) {
        try (Connection conn = DriverManager.getConnection(URL, USER, PASSWORD)) {
            conn.setAutoCommit(false);

            insertTbHead(conn);
            insertTbData(conn);

            conn.commit();
            System.out.println("Data insertion complete.");
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    private static void insertTbHead(Connection conn) throws SQLException {
        String insertHeadSQL = "INSERT INTO tb_head (head_id, head_name, head_type) VALUES (?, ?, ?)";
        try (PreparedStatement ps = conn.prepareStatement(insertHeadSQL)) {
            for (int i = 1; i <= 2000; i++) {
                ps.setInt(1, i);
                ps.setString(2, "Head " + i);
                ps.setString(3, "Type " + (i % 3 + 1));
                ps.addBatch();
            }
            ps.executeBatch();
        }
    }

    private static void insertTbData(Connection conn) throws SQLException {
        String insertDataSQL = "INSERT INTO tb_data (data_id, data_value, head_id) VALUES (?, ?, ?)";
        Random random = new Random();
        try (PreparedStatement ps = conn.prepareStatement(insertDataSQL)) {
            for (int i = 1; i <= 15000; i++) {
                ps.setInt(1, i); // Linking to random tb_head
                ps.setString(2, "Data write " + i);
                ps.setInt(3, random.nextInt(2000) + 1); // Random version
                ps.addBatch();
            }
            ps.executeBatch();
        }
    }
}
