package com.automaticexpense.tracker.infrastructure.api;

import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class AuthenticatedLedgerIdentityTest {

    @Test
    void derivesTheSameLedgerPartitionFromAVerifiedEmailAsTheTransactionCommandHandler() {
        APIGatewayV2HTTPEvent request = requestWithClaims(Map.of(
            "sub", "different-opaque-subject",
            "email", "User@Example.com",
            "email_verified", "true"
        ));

        assertThat(AuthenticatedLedgerIdentity.ledgerScope(request))
            .isEqualTo("b4c9a289323b21a01c3e940f150eb9b8");
    }

    @Test
    void rejectsAnUnverifiedEmailEvenWhenTheJwtContainsASubject() {
        assertThat(AuthenticatedLedgerIdentity.ledgerScope(requestWithClaims(Map.of(
            "sub", "opaque-subject", "email", "user@example.com", "email_verified", "false"
        )))).isNull();
    }

    private APIGatewayV2HTTPEvent requestWithClaims(Map<String, String> claims) {
        APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT jwt =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer.JWT();
        jwt.setClaims(claims);
        APIGatewayV2HTTPEvent.RequestContext.Authorizer authorizer =
            new APIGatewayV2HTTPEvent.RequestContext.Authorizer();
        authorizer.setJwt(jwt);
        APIGatewayV2HTTPEvent.RequestContext context = new APIGatewayV2HTTPEvent.RequestContext();
        context.setAuthorizer(authorizer);
        APIGatewayV2HTTPEvent request = new APIGatewayV2HTTPEvent();
        request.setRequestContext(context);
        return request;
    }
}
