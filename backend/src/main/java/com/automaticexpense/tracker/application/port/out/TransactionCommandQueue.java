package com.automaticexpense.tracker.application.port.out;

import com.automaticexpense.tracker.domain.TransactionCommandReference;

public interface TransactionCommandQueue {
    void enqueue(TransactionCommandReference reference);
}
