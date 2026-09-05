package com.automaticexpense.tracker.infrastructure.language;

import com.automaticexpense.tracker.application.port.out.LanguageModelCredentialPort;
import com.automaticexpense.tracker.application.port.out.LanguageModelPort;
import com.automaticexpense.tracker.application.port.out.LanguageModelUsageTelemetryPort;
import com.automaticexpense.tracker.domain.LanguageModelPlanningPrompt;
import com.automaticexpense.tracker.domain.LanguageModelPlanningResponse;
import com.automaticexpense.tracker.domain.LanguageModelUsage;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * Gemini's Developer API adapter is restricted to producing a query-plan schema.
 * It never receives ledger records or returns a user-facing answer.
 */
public final class GeminiDeveloperApiLanguageModelAdapter implements LanguageModelPort {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final String PROVIDER = "GEMINI";

    private final HttpClient client;
    private final LanguageModelCredentialPort credential;
    private final LanguageModelUsageTelemetryPort telemetry;
    private final String model;
    private final Duration timeout;
    private final int maxOutputTokens;

    public GeminiDeveloperApiLanguageModelAdapter(
        HttpClient client,
        LanguageModelCredentialPort credential,
        LanguageModelUsageTelemetryPort telemetry,
        String model,
        Duration timeout,
        int maxOutputTokens
    ) {
        this.client = Objects.requireNonNull(client, "client cannot be null");
        this.credential = Objects.requireNonNull(credential, "credential cannot be null");
        this.telemetry = Objects.requireNonNull(telemetry, "telemetry cannot be null");
        if (model == null || !model.matches("gemini-[0-9.]+-flash(?:-[a-z0-9-]+)?")) {
            throw new IllegalArgumentException("model must be a pinned Gemini Flash model");
        }
        if (timeout == null || timeout.isNegative() || timeout.isZero() || timeout.compareTo(Duration.ofSeconds(5)) > 0) {
            throw new IllegalArgumentException("timeout must be greater than zero and at most five seconds");
        }
        if (maxOutputTokens < 1 || maxOutputTokens > 256) {
            throw new IllegalArgumentException("maxOutputTokens must be between one and 256");
        }
        this.model = model;
        this.timeout = timeout;
        this.maxOutputTokens = maxOutputTokens;
    }

    @Override
    public LanguageModelPlanningResponse plan(LanguageModelPlanningPrompt prompt) {
        Instant started = Instant.now();
        LanguageModelPlanningResponse response = LanguageModelPlanningResponse.unavailable();
        int promptTokens = 0;
        int responseTokens = 0;
        try {
            String apiKey = credential.apiKey().orElse(null);
            if (apiKey == null || apiKey.isBlank()) {
                return response;
            }
            HttpRequest request = HttpRequest.newBuilder(endpoint(apiKey))
                .timeout(timeout)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(Map.of(
                    "contents", new Object[] {Map.of(
                        "role", "user",
                        "parts", new Object[] {Map.of("text", instruction(prompt))}
                    )},
                    "generationConfig", Map.of(
                        "temperature", 0,
                        "candidateCount", 1,
                        "maxOutputTokens", maxOutputTokens,
                        "responseMimeType", "application/json"
                    )
                ))))
                .build();
            HttpResponse<String> httpResponse = client.send(request, HttpResponse.BodyHandlers.ofString());
            if (httpResponse.statusCode() != 200) {
                return response;
            }
            JsonNode body = JSON.readTree(httpResponse.body());
            promptTokens = body.path("usageMetadata").path("promptTokenCount").asInt(0);
            responseTokens = body.path("usageMetadata").path("candidatesTokenCount").asInt(0);
            if (responseTokens > maxOutputTokens) {
                response = LanguageModelPlanningResponse.invalid();
            } else {
                response = parsePlan(body);
            }
            return response;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return response;
        } catch (Exception exception) {
            return response;
        } finally {
            record(response, started, promptTokens, responseTokens);
        }
    }

    private URI endpoint(String apiKey) {
        return URI.create(
            "https://generativelanguage.googleapis.com/v1beta/models/" + model
                + ":generateContent?key=" + URLEncoder.encode(apiKey, StandardCharsets.UTF_8)
        );
    }

    private String instruction(LanguageModelPlanningPrompt prompt) {
        return """
            Produce JSON only. Select one allowed capability and optional opaque aliases.
            Do not calculate money, explain, infer facts, or return any text outside JSON.
            Schema: {"capability":"allowed capability","period":"CURRENT_MONTH|PREVIOUS_MONTH|YYYY-MM",
            "merchantAlias":"optional opaque alias","categoryAlias":"optional opaque alias",
            "accountAlias":"optional opaque alias"}.
            Question: %s
            Allowed capabilities: %s
            Merchant aliases: %s
            Category aliases: %s
            Account aliases: %s
            """.formatted(
                prompt.sanitizedQuestion(), prompt.allowedCapabilities(), prompt.merchantAliases(),
                prompt.categoryAliases(), prompt.accountAliases()
            );
    }

    private LanguageModelPlanningResponse parsePlan(JsonNode body) {
        JsonNode candidates = body.path("candidates");
        if (!candidates.isArray() || candidates.size() != 1) {
            return LanguageModelPlanningResponse.invalid();
        }
        JsonNode parts = candidates.get(0).path("content").path("parts");
        if (!parts.isArray() || parts.size() != 1 || !parts.get(0).path("text").isTextual()) {
            return LanguageModelPlanningResponse.invalid();
        }
        try {
            JsonNode plan = JSON.readTree(parts.get(0).path("text").textValue());
            if (!plan.isObject() || plan.size() > 6 || !plan.path("capability").isTextual()
                || !plan.path("period").isTextual() || !hasOnlySchemaFields(plan)
                || !isOptionalText(plan, "merchantAlias") || !isOptionalText(plan, "categoryAlias")
                || !isOptionalText(plan, "accountAlias")) {
                return LanguageModelPlanningResponse.invalid();
            }
            return new LanguageModelPlanningResponse(
                LanguageModelPlanningResponse.Status.PLANNED,
                plan.path("capability").textValue(),
                plan.path("period").textValue(),
                nullableText(plan, "merchantAlias"),
                nullableText(plan, "categoryAlias"),
                nullableText(plan, "accountAlias")
            );
        } catch (Exception exception) {
            return LanguageModelPlanningResponse.invalid();
        }
    }

    private String nullableText(JsonNode plan, String field) {
        JsonNode value = plan.path(field);
        return value.isMissingNode() || value.isNull() ? null : value.isTextual() ? value.textValue() : null;
    }

    private boolean hasOnlySchemaFields(JsonNode plan) {
        Set<String> fields = Set.of(
            "capability", "period", "merchantAlias", "categoryAlias", "accountAlias"
        );
        java.util.Iterator<String> names = plan.fieldNames();
        while (names.hasNext()) {
            if (!fields.contains(names.next())) {
                return false;
            }
        }
        return true;
    }

    private boolean isOptionalText(JsonNode plan, String field) {
        JsonNode value = plan.path(field);
        return value.isMissingNode() || value.isNull() || value.isTextual();
    }

    private void record(LanguageModelPlanningResponse response, Instant started, int promptTokens, int responseTokens) {
        LanguageModelUsage.Outcome outcome = switch (response.status()) {
            case PLANNED -> LanguageModelUsage.Outcome.PLANNED;
            case INVALID -> LanguageModelUsage.Outcome.INVALID;
            case UNAVAILABLE -> LanguageModelUsage.Outcome.UNAVAILABLE;
        };
        try {
            telemetry.record(new LanguageModelUsage(
                PROVIDER, model, outcome, Duration.between(started, Instant.now()), promptTokens, responseTokens
            ));
        } catch (RuntimeException ignored) {
            // Telemetry is non-critical and must never make query planning fail.
        }
    }
}
