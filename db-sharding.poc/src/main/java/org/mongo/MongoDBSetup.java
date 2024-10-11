package org.mongo;

import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoDatabase;
import com.mongodb.client.MongoCollection;
import org.bson.Document;

public class MongoDBSetup {
    public static void main(String[] args) {
        // Connect to the MongoDB cluster
        MongoClient mongoClient = MongoClients.create("mongodb://localhost:27017");
        MongoDatabase database = mongoClient.getDatabase("test_sharding");

        // Create the tb_head collection
        MongoCollection<Document> tbHeadCollection = database.getCollection("tb_head");


        MongoCollection<Document> tbDataCollection = database.getCollection("tb_data");


        for (int i = 2; i <= 1000; i++) {
            Document mockData = new Document()
                    .append("head_id", i)
                    .append("head_name", "HeadName" + i)
                    .append("head_period", "2024-Q" + (i % 4 + 1))
                    .append("head_revision", i % 10)
                    .append("head_status", i % 2 == 0 ? "Active" : "Inactive");

            tbHeadCollection.insertOne(mockData);
        }

        for (int i = 1; i <= 5000; i++) {
            Document mockData = new Document()
                    .append("data_id", i)
                    .append("head_id", i % 1000) // Reference to tb_head
                    .append("data_block_start", "Block" + i)
                    .append("data_value", "Value" + i);

            tbDataCollection.insertOne(mockData);
        }



        System.out.println("Inserted document into tb_head.");
        mongoClient.close();
    }
}
