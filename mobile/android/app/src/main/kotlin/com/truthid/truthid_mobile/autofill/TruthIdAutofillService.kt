package com.truthid.truthid_mobile.autofill

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillContext
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import com.truthid.truthid_mobile.MainActivity
import com.truthid.truthid_mobile.R

/**
 * `AutofillService` do SO (Fase 15.5) — deliberadamente leve: não toca no
 * Vault (chave/blob cifrados) aqui. Só detecta campos preenchíveis
 * ([collectFieldGroups]) e devolve um `Dataset` por grupo, cada um
 * "auth-gated" (`setAuthentication`) apontando pra `MainActivity` — o SO só
 * revela o valor de verdade depois que essa Activity Flutter (que já tem
 * acesso ao Vault, ao `AppLockGate`/biometria e ao mesmo picker "1 de N" da
 * Fase 15.4) devolve o resultado via `EXTRA_AUTHENTICATION_RESULT`. Ver
 * `project/PHASE.md` 15.5 pro desenho completo.
 *
 * `onSaveRequest` não é implementado de propósito — `onFillRequest` nunca
 * chama `FillResponse.Builder.setSaveInfo(...)`, então o SO nunca invoca
 * `onSaveRequest` (salvar credencial nova via autofill do sistema fica
 * fora desta fatia).
 */
@RequiresApi(Build.VERSION_CODES.O)
class TruthIdAutofillService : android.service.autofill.AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = latestStructure(request.fillContexts)
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val groups = collectFieldGroups(structure)
        if (groups.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val requestingPackage = structure.activityComponent?.packageName ?: packageName
        val responseBuilder = FillResponse.Builder()
        var requestCode = 0
        for ((entryType, fields) in groups) {
            responseBuilder.addDataset(
                buildAuthDataset(entryType, fields, requestingPackage, requestCode),
            )
            requestCode++
        }

        callback.onSuccess(responseBuilder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        callback.onFailure(getString(R.string.autofill_save_not_supported))
    }

    private fun latestStructure(contexts: List<FillContext>): AssistStructure? =
        contexts.lastOrNull()?.structure

    /**
     * Percorre a árvore de nós da `AssistStructure`, agrupando os
     * `AutofillId`s por `EntryType` — um `FillGroup` por tipo encontrado
     * (não por nó). Nós sem hint reconhecido (`classifyHints` devolve
     * `null`) são ignorados.
     */
    private fun collectFieldGroups(structure: AssistStructure): Map<String, MutableList<Pair<FieldRole, AutofillId>>> {
        val groups = LinkedHashMap<String, MutableList<Pair<FieldRole, AutofillId>>>()
        for (i in 0 until structure.windowNodeCount) {
            visitNode(structure.getWindowNodeAt(i).rootViewNode, groups)
        }
        return groups
    }

    private fun visitNode(
        node: AssistStructure.ViewNode,
        groups: MutableMap<String, MutableList<Pair<FieldRole, AutofillId>>>,
    ) {
        val autofillId = node.autofillId
        val hints = node.autofillHints
        if (autofillId != null && !hints.isNullOrEmpty()) {
            val role = classifyHints(hints.toList())
            if (role != null) {
                val entryType = entryTypeForRole(role)
                groups.getOrPut(entryType) { mutableListOf() }.add(role to autofillId)
            }
        }
        for (i in 0 until node.childCount) {
            visitNode(node.getChildAt(i), groups)
        }
    }

    /**
     * `Dataset` sem valores reais (`setValue(id, null)`) — só os
     * `AutofillId`s que este grupo cobre — gated por `setAuthentication`.
     * `Dataset.Builder(presentation)` (deprecado desde a API que introduziu
     * apresentação por campo) é usado de propósito: mantém compatibilidade
     * com a API 26 mínima do framework, sem precisar ramificar por versão
     * do SO só pra evitar 1 aviso de lint.
     */
    @Suppress("DEPRECATION")
    private fun buildAuthDataset(
        entryType: String,
        fields: List<Pair<FieldRole, AutofillId>>,
        requestingPackage: String,
        requestCode: Int,
    ): Dataset {
        val presentation = buildPresentation(entryType)
        val datasetBuilder = Dataset.Builder(presentation)
        for ((_, autofillId) in fields) {
            datasetBuilder.setValue(autofillId, null)
        }
        datasetBuilder.setAuthentication(
            buildAuthPendingIntent(entryType, fields, requestingPackage, requestCode).intentSender,
        )
        return datasetBuilder.build()
    }

    private fun buildPresentation(entryType: String): RemoteViews {
        val label = when (entryType) {
            ENTRY_TYPE_ADDRESS -> getString(R.string.autofill_presentation_address)
            ENTRY_TYPE_CREDIT_CARD -> getString(R.string.autofill_presentation_credit_card)
            else -> getString(R.string.autofill_presentation_credential)
        }
        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1)
        presentation.setTextViewText(android.R.id.text1, label)
        return presentation
    }

    private fun buildAuthPendingIntent(
        entryType: String,
        fields: List<Pair<FieldRole, AutofillId>>,
        requestingPackage: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_AUTOFILL_AUTH
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ENTRY_TYPE, entryType)
            putExtra(EXTRA_REQUESTING_PACKAGE, requestingPackage)
            putExtra(EXTRA_FIELD_ROLES, fields.map { it.first.name }.toTypedArray())
            putParcelableArrayListExtra(EXTRA_AUTOFILL_IDS, ArrayList(fields.map { it.second }))
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getActivity(this, requestCode, intent, flags)
    }

    companion object {
        const val ACTION_AUTOFILL_AUTH = "com.truthid.truthid_mobile.action.AUTOFILL_AUTH"
        const val EXTRA_ENTRY_TYPE = "com.truthid.truthid_mobile.extra.ENTRY_TYPE"
        const val EXTRA_REQUESTING_PACKAGE = "com.truthid.truthid_mobile.extra.REQUESTING_PACKAGE"
        const val EXTRA_FIELD_ROLES = "com.truthid.truthid_mobile.extra.FIELD_ROLES"
        const val EXTRA_AUTOFILL_IDS = "com.truthid.truthid_mobile.extra.AUTOFILL_IDS"
    }
}
