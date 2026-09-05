package com.automaticexpense.tracker.application;

public final class CommandRejectedException extends RuntimeException {
    public CommandRejectedException(String message, Throwable cause) {
        super(message, cause);
    }
}
