package sharding;

import org.apache.shardingsphere.sharding.api.sharding.complex.ComplexKeysShardingAlgorithm;
import org.apache.shardingsphere.sharding.api.sharding.complex.ComplexKeysShardingValue;

import java.util.Collection;
import java.util.Collections;

public class UserComplexShardingAlgorithm implements ComplexKeysShardingAlgorithm<String> {

    @Override
    public Collection<String> doSharding(Collection<String> availableTargetNames, ComplexKeysShardingValue<String> shardingValue) {
        String compositeKey = generateCompositeKey(shardingValue);
        int shardId = Math.abs(compositeKey.hashCode()) % availableTargetNames.size();
        String target = "ds_" + shardId;
        return Collections.singleton(target);
    }

    private String generateCompositeKey(ComplexKeysShardingValue<String> shardingValue) {
        StringBuilder keyBuilder = new StringBuilder();

        Collection<String> idValues = shardingValue.getColumnNameAndShardingValuesMap().get("id");
        if (idValues != null && !idValues.isEmpty()) {
            keyBuilder.append(idValues.iterator().next());
        }

        Collection<String> usernameValues = shardingValue.getColumnNameAndShardingValuesMap().get("username");
        if (usernameValues != null && !usernameValues.isEmpty()) {
            keyBuilder.append(usernameValues.iterator().next());
        }

        return keyBuilder.toString();
    }

}
