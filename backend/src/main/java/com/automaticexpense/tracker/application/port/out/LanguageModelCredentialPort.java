package com.automaticexpense.tracker.application.port.out;

import java.util.Optional;

/** Resolves provider credentials from managed secret storage. */
public interface LanguageModelCredentialPort {
    Optional<String> apiKey();
}
