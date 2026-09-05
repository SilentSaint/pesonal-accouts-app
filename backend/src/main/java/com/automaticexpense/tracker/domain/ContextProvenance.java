package com.automaticexpense.tracker.domain;

/** Only user-confirmed context can become authoritative financial context. */
public enum ContextProvenance {
    USER_DECLARED,
    USER_CONFIRMED,
    IMPORTED_USER_CONFIRMED
}
