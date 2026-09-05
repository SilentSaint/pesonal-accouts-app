package com.automaticexpense.tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsBroadcastReceiver : BroadcastReceiver() {

    companion object {
        @Volatile
        var onCapturePersisted: (() -> Unit)? = null

        private val financialSenderPatterns = listOf(
            "HDFC", "SBI", "ICICI", "AXIS", "KOTAK", "CITI", "BOB", "PNB",
            "IDFC", "PAYTM", "AMEX", "INDUS", "RBL", "YESB", "CANARA", "UNIONB",
            "FEDERAL", "AUFIN", "BANDHAN", "HSBC", "STANCB", "CRED", "SLICE",
            "JUPITR", "FIMONEY", "PHONEPE", "GPAY", "BHIM", "AIRTEL", "AMZPAY"
        )

        private val financialBodyPatterns = listOf(
            "debited", "credited", "spent", "paid", "withdrawn", "deposited",
            "txn of", "vpa", "upi", "a/c", "acct", "ending", "card", "inr", "rs.", "rs "
        )

        fun isFinancialSender(sender: String?): Boolean {
            if (sender.isNullOrBlank()) return false
            val upper = sender.uppercase()
            return financialSenderPatterns.any { pattern -> upper.contains(pattern) }
        }

        fun isFinancialBody(body: String?): Boolean {
            if (body.isNullOrBlank()) return false
            val lower = body.lowercase()
            val matchesCurrency = lower.contains("rs") || lower.contains("inr") || lower.contains("₹")
            return matchesCurrency && financialBodyPatterns.any { pattern -> lower.contains(pattern) }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION ||
            !SmsCaptureStore(context).isCaptureEnabled()
        ) {
            return
        }

        // Multipart messages are delivered as one PDU per part. Persist only a
        // complete logical alert, before any Flutter process or network work.
        val groupedMessages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            .groupBy { "${it.displayOriginatingAddress.orEmpty()}\u0000${it.timestampMillis}" }
        val store = SmsCaptureStore(context)
        for (parts in groupedMessages.values) {
            val sender = parts.first().displayOriginatingAddress.orEmpty()
            val body = parts.joinToString(separator = "") { it.displayMessageBody.orEmpty() }
            if (isFinancialSender(sender) || isFinancialBody(body)) {
                if (store.record(sender, body, parts.first().timestampMillis)) {
                    onCapturePersisted?.invoke()
                }
            }
        }
    }
}
