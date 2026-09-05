package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.PeerDebtEntry;

import java.util.List;
import java.util.Optional;

public interface PeerDebtRepository {
    void save(PeerDebtEntry debtEntry);
    Optional<PeerDebtEntry> findDebtById(String id);
    List<PeerDebtEntry> findByContactName(String contactName);
    List<PeerDebtEntry> findAllUnsettled();
    List<PeerDebtEntry> findAllDebts();
}
