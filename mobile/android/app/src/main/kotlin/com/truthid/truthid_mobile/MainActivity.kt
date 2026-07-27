package com.truthid.truthid_mobile

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import androidx.annotation.RequiresApi
import com.truthid.truthid_mobile.autofill.TruthIdAutofillService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (não FlutterActivity) — exigência do plugin
// local_auth_android: o prompt biométrico usa androidx.biometric.BiometricPrompt,
// que precisa de uma FragmentActivity por baixo.
//
// Fase 15.5 — primeiro MethodChannel deste app. `TruthIdAutofillService`
// (SO) nunca toca no Vault: ele só detecta campos e abre esta Activity via
// PendingIntent de autenticação do próprio Android Autofill Framework. O
// canal `truthid/autofill` dá ao lado Dart (que já tem tudo — Vault,
// AppLockGate, o picker "1 de N" da Fase 15.4) um jeito de 1) ler os
// extras do pedido pendente e 2) devolver o resultado escolhido, que aqui
// vira o `Dataset` final embrulhado em `EXTRA_AUTHENTICATION_RESULT`.
class MainActivity : FlutterFragmentActivity() {

    // Intent mais recente com ACTION_AUTOFILL_AUTH — cold start (onCreate)
    // ou app já rodando (onNewIntent, launchMode="singleTop" reusa a mesma
    // instância). `readPendingRequest`/`submitAutofillResult` sempre leem
    // daqui, nunca de `intent` direto (que só reflete o launch original).
    private var pendingAutofillIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureAutofillIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureAutofillIntent(intent)
    }

    private fun captureAutofillIntent(candidate: Intent?) {
        if (candidate?.action == TruthIdAutofillService.ACTION_AUTOFILL_AUTH) {
            pendingAutofillIntent = candidate
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingAutofillRequest" -> result.success(readPendingRequest())
                    "submitAutofillResult" -> {
                        @Suppress("UNCHECKED_CAST")
                        val fields = call.arguments as? Map<String, String> ?: emptyMap()
                        submitAutofillResult(fields)
                        result.success(null)
                    }
                    "cancelAutofillRequest" -> {
                        cancelAutofillRequest()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readPendingRequest(): Map<String, Any?>? {
        val intent = pendingAutofillIntent ?: return null
        val entryType = intent.getStringExtra(TruthIdAutofillService.EXTRA_ENTRY_TYPE) ?: return null
        val requestingPackage =
            intent.getStringExtra(TruthIdAutofillService.EXTRA_REQUESTING_PACKAGE) ?: ""
        return mapOf("entryType" to entryType, "requestingPackage" to requestingPackage)
    }

    // `fields` vem do lado Dart já no vocabulário de `FieldRole.name` (ex:
    // "USERNAME", "STREET_ADDRESS", "CARD_NUMBER") — quem decide qual valor
    // do VaultEntry vai em qual papel é o Dart (autofill_bridge_service.dart),
    // não este Kotlin: ele só casa role -> AutofillId, nunca interpreta
    // semântica de Vault.
    @RequiresApi(Build.VERSION_CODES.O)
    @Suppress("DEPRECATION") // getParcelableArrayListExtra(String) — ver comentário no TruthIdAutofillService sobre manter compat com a API 26 mínima do framework.
    private fun submitAutofillResult(fields: Map<String, String>) {
        val intent = pendingAutofillIntent
        if (intent == null) {
            cancelAutofillRequest()
            return
        }
        val ids = intent.getParcelableArrayListExtra<AutofillId>(
            TruthIdAutofillService.EXTRA_AUTOFILL_IDS,
        ) ?: arrayListOf()
        val roles = intent.getStringArrayExtra(TruthIdAutofillService.EXTRA_FIELD_ROLES) ?: emptyArray()

        val datasetBuilder = Dataset.Builder()
        var filledAny = false
        for (i in ids.indices) {
            val role = roles.getOrNull(i) ?: continue
            val value = fields[role] ?: continue
            datasetBuilder.setValue(ids[i], AutofillValue.forText(value))
            filledAny = true
        }

        if (!filledAny) {
            cancelAutofillRequest()
            return
        }

        val resultIntent = Intent().apply {
            putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, datasetBuilder.build())
        }
        setResult(RESULT_OK, resultIntent)
        pendingAutofillIntent = null
        finish()
    }

    private fun cancelAutofillRequest() {
        setResult(RESULT_CANCELED)
        pendingAutofillIntent = null
        finish()
    }

    companion object {
        private const val CHANNEL = "truthid/autofill"
    }
}
