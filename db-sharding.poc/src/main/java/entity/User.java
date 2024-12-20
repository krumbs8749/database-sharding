package entity;

import jakarta.persistence.*;
import lombok.Data;

@Entity
@Data
@Table(name = "t_user")
public class User {
    @Id
    private String id;

    private String username;
    private String email;

    // Getters and setters
}
