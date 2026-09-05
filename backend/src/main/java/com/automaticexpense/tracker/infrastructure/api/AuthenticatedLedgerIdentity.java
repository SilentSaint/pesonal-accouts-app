package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;

/**
 * Derives the user partition used by canonical transaction records from a verified email claim.
 * The derivation deliberately matches the established TransactionCommandHandler scheme.
 */
public final class AuthenticatedLedgerIdentity {
    private AuthenticatedLedgerIdentity() {
    }

    public static String ledgerScope(APIGatewayV2HTTPEvent request) {
        if (request == null || request.getRequestContext() == null
            || request.getRequestContext().getAuthorizer() == null
            || request.getRequestContext().getAuthorizer().getJwt() == null
            || request.getRequestContext().getAuthorizer().getJwt().getClaims() == null) {
            return null;
        }
        Map<String, String> claims = request.getRequestContext().getAuthorizer().getJwt().getClaims();
        if (!"true".equalsIgnoreCase(claims.get("email_verified"))) {
            return null;
        }
        String email = claims.get("email");
        return email == null || email.isBlank() ? null : scopeForVerifiedEmail(email);
    }

    public static String scopeForVerifiedEmail(String email) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                .digest(email.toLowerCase().trim().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest).substring(0, 32);
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to derive authenticated user scope", exception);
        }
    }
}
