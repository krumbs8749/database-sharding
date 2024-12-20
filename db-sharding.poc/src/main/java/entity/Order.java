package entity;

import jakarta.persistence.*;
import lombok.Data;

@Entity
@Data
@Table(name = "t_order")
public class Order {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long user_id;
    private Double total_amount;

    // Getters and setters
}
