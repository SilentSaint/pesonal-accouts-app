package com.automaticexpense.tracker

import android.content.Context
import java.security.MessageDigest
import org.json.JSONObject

/**
 * Stores only parsed transaction fields. The original SMS text is never logged,
 * persisted, or exposed to Flutter.
 */
class SmsCaptureStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun isCaptureEnabled(): Boolean = preferences.getBoolean(CAPTURE_ENABLED, false)

    fun setCaptureEnabled(enabled: Boolean) {
        preferences.edit().putBoolean(CAPTURE_ENABLED, enabled).commit()
        if (!enabled) clearPending()
    }

    fun record(sender: String, body: String, timestamp: Long): Boolean {
        val event = parse(sender, body, timestamp) ?: return false
        val key = eventKey(event.id)
        if (preferences.contains(key)) return true
        // commit() is intentional: BroadcastReceiver work must survive process
        // death before it returns and before Flutter/network delivery begins.
        return preferences.edit().putString(key, event.toJson().toString()).commit()
    }

    fun pendingEvents(): List<Map<String, Any>> {
        return preferences.all
            .asSequence()
            .filter { (key, value) -> key.startsWith(EVENT_PREFIX) && value is String }
            .mapNotNull { (_, value) -> parseStored(value as String) }
            .sortedBy { it["timestamp"] as Long }
            .toList()
    }

    fun acknowledge(id: String): Boolean = preferences.edit().remove(eventKey(id)).commit()

    private fun clearPending() {
        val editor = preferences.edit()
        preferences.all.keys
            .filter { it.startsWith(EVENT_PREFIX) }
            .forEach(editor::remove)
        editor.commit()
    }

    private fun parse(sender: String, body: String, timestamp: Long): CapturedSms? {
        val amountMatch = amountPattern.find(body) ?: return null
        val amount = amountMatch.groupValues[1].replace(",", "").toDoubleOrNull()
            ?.takeIf { it > 0 } ?: return null
        val accountLastFour = accountPattern.find(body)?.groupValues?.get(1) ?: return null
        val isCredit = creditPattern.containsMatchIn(body)
        val merchantMatch = merchantPattern.find(body)?.groupValues?.get(1)?.trim().orEmpty()
        val merchantName = cleanMerchantName(
            merchantMatch.ifBlank { cleanBankName(sender) }
        )
        return CapturedSms(
            id = "sms-${sha256("$sender\u0000$body\u0000$timestamp")}",
            amount = amount,
            type = if (isCredit) "CREDIT" else "DEBIT",
            merchantName = merchantName,
            bankName = cleanBankName(sender),
            accountLastFour = accountLastFour,
            categoryId = inferCategory(merchantName, body),
            timestamp = timestamp,
        )
    }

    private fun parseStored(value: String): Map<String, Any>? = try {
        val event = JSONObject(value)
        mapOf(
            "id" to event.getString("id"),
            "amount" to event.getDouble("amount"),
            "type" to event.getString("type"),
            "merchantName" to event.getString("merchantName"),
            "bankName" to event.getString("bankName"),
            "accountLastFour" to event.getString("accountLastFour"),
            "categoryId" to event.getString("categoryId"),
            "timestamp" to event.getLong("timestamp"),
        )
    } catch (_: Exception) {
        null
    }

    private data class CapturedSms(
        val id: String,
        val amount: Double,
        val type: String,
        val merchantName: String,
        val bankName: String,
        val accountLastFour: String,
        val categoryId: String,
        val timestamp: Long,
    ) {
        fun toJson() = JSONObject()
            .put("id", id)
            .put("amount", amount)
            .put("type", type)
            .put("merchantName", merchantName)
            .put("bankName", bankName)
            .put("accountLastFour", accountLastFour)
            .put("categoryId", categoryId)
            .put("timestamp", timestamp)
    }

    private fun cleanBankName(sender: String): String {
        val upper = sender.uppercase()
        return when {
            "HDFC" in upper -> "HDFC Bank"
            "SBI" in upper || "SBIN" in upper -> "State Bank of India"
            "ICICI" in upper -> "ICICI Bank"
            "AXIS" in upper -> "Axis Bank"
            "KOTAK" in upper -> "Kotak Mahindra"
            "IDFC" in upper -> "IDFC First"
            "PAYTM" in upper -> "Paytm Bank"
            "AMEX" in upper -> "American Express"
            else -> sender.replace(Regex("^[A-Za-z0-9]{2}-"), "")
        }
    }

    private fun cleanMerchantName(value: String): String {
        val withoutVpa = value.substringBefore("@")
            .replace(Regex("^(payto|upi|vpa|info|to|at)\\s*", RegexOption.IGNORE_CASE), "")
            .replace(Regex("[._-]+"), " ")
            .trim()
        return withoutVpa.ifBlank { "Merchant" }
            .split(Regex("\\s+"))
            .joinToString(" ") { it.lowercase().replaceFirstChar(Char::uppercase) }
    }

    private fun inferCategory(merchant: String, body: String): String {
        val text = "$merchant $body".lowercase()
        return when {
            listOf("swiggy", "zomato", "restaurant", "cafe", "food").any(text::contains) -> "Food & Dining"
            listOf("blinkit", "zepto", "instamart", "grocery", "supermarket").any(text::contains) -> "Groceries"
            listOf("uber", "ola", "rapido", "petrol", "fuel", "metro").any(text::contains) -> "Transport & Fuel"
            listOf("salary", "stipend", "bonus", "reimbursement").any(text::contains) -> "Income"
            listOf("amazon", "flipkart", "myntra", "shopping").any(text::contains) -> "Shopping"
            else -> "General Expenses"
        }
    }

    private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

    private fun eventKey(id: String) = "$EVENT_PREFIX$id"

    companion object {
        private const val PREFERENCES = "sms_capture_queue"
        private const val CAPTURE_ENABLED = "capture_enabled"
        private const val EVENT_PREFIX = "event."
        private val amountPattern = Regex("""(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d{1,2})?)""", RegexOption.IGNORE_CASE)
        private val creditPattern = Regex("""(?:credited|deposited|received|refund|cashback|inward)""", RegexOption.IGNORE_CASE)
        private val accountPattern = Regex("""(?:a/c|acct|account|card|ending with|ending in|ending|no\.?|xx|\*+)\s*(?:no\.?)?\s*(?:[xX*]+)?(\d{4})""", RegexOption.IGNORE_CASE)
        private val merchantPattern = Regex("""(?:to|at|vpa|info|merchant|towards)\s+([A-Za-z0-9\s&._@-]+?)(?:\.|\s+on|\s+ref|\s+avail|\s+bal|\s+upi|\s+avl|$)""", RegexOption.IGNORE_CASE)
    }
}
