package com.automaticexpense.tracker.domain;

public record EvidenceMetadata(int sourceCount, DrillDownReference drillDown) {
    public EvidenceMetadata {
        if (sourceCount < 0) {
            throw new IllegalArgumentException("sourceCount cannot be negative");
        }
    }
}
