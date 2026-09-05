package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.RecurringCommitment;

import java.util.List;
import java.util.Optional;

public interface RecurringCommitmentRepository {
    void save(RecurringCommitment commitment);

    Optional<RecurringCommitment> findById(String commitmentId);

    Optional<RecurringCommitment> findByCandidateKey(String candidateKey);

    List<RecurringCommitment> findAll();
}
